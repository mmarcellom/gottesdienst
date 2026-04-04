// Vercel Serverless Function: Secure Proxy for Groq Whisper API
// API key stays server-side — never exposed to the client
//
// Security layers:
// 1. Origin check — only allows requests from our own domain
// 2. Rate limiting — max 20 requests per minute per IP
// 3. Body size limit — max 2MB per request (4s audio chunk ≈ 128KB)
// 4. Method lock — POST only
// 5. HMAC token — frontend sends a time-based token to verify it's our app

import { createHmac } from 'crypto';

export const config = {
  api: {
    bodyParser: false,
  },
};

// ─── Rate Limiter (in-memory, per-instance) ───
const rateMap = new Map(); // ip → { count, resetAt }
const RATE_LIMIT = 20;     // requests per window
const RATE_WINDOW = 60000; // 1 minute

function isRateLimited(ip) {
  const now = Date.now();
  let entry = rateMap.get(ip);
  if (!entry || now > entry.resetAt) {
    entry = { count: 0, resetAt: now + RATE_WINDOW };
    rateMap.set(ip, entry);
  }
  entry.count++;
  return entry.count > RATE_LIMIT;
}

// ─── HMAC Token Verification ───
// Frontend generates: HMAC-SHA256(secret, timestamp) where timestamp = floor(Date.now() / 30000)
// Token is valid for current + previous window (60s tolerance)
function verifyToken(token, secret) {
  if (!token || !secret) return false;
  const now = Math.floor(Date.now() / 30000);
  for (let i = 0; i <= 1; i++) {
    const expected = createHmac('sha256', secret)
      .update(String(now - i))
      .digest('hex')
      .substring(0, 16); // short hash is sufficient
    if (token === expected) return true;
  }
  return false;
}

// ─── Allowed Origins ───
const ALLOWED_ORIGINS = [
  'https://gottesdienst.vercel.app',
  'https://gottesdienst-',  // Vercel preview deployments
  'http://localhost',
  'http://127.0.0.1',
];

function isAllowedOrigin(origin) {
  if (!origin) return false;
  return ALLOWED_ORIGINS.some(allowed => origin.startsWith(allowed));
}

export default async function handler(req, res) {
  // ─── 1. Method check ───
  if (req.method === 'OPTIONS') {
    res.setHeader('Access-Control-Allow-Origin', req.headers.origin || '*');
    res.setHeader('Access-Control-Allow-Methods', 'POST');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, X-Tertius-Token');
    return res.status(200).end();
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  // ─── 2. Origin check ───
  const origin = req.headers.origin || req.headers.referer || '';
  if (!isAllowedOrigin(origin)) {
    console.warn(`[Transcribe] Blocked origin: ${origin}`);
    return res.status(403).json({ error: 'Forbidden' });
  }

  // Set CORS for allowed origin
  res.setHeader('Access-Control-Allow-Origin', req.headers.origin || '*');

  // ─── 3. Rate limiting ───
  const ip = req.headers['x-forwarded-for']?.split(',')[0]?.trim() || req.socket?.remoteAddress || 'unknown';
  if (isRateLimited(ip)) {
    console.warn(`[Transcribe] Rate limited: ${ip}`);
    return res.status(429).json({ error: 'Too many requests. Try again in a minute.' });
  }

  // ─── 4. HMAC Token check ───
  const TOKEN_SECRET = process.env.TERTIUS_TOKEN_SECRET;
  const token = req.headers['x-tertius-token'];
  if (TOKEN_SECRET && !verifyToken(token, TOKEN_SECRET)) {
    console.warn(`[Transcribe] Invalid token from ${ip}`);
    return res.status(403).json({ error: 'Invalid token' });
  }

  // ─── 5. API Key check ───
  const GROQ_API_KEY = process.env.GROQ_API_KEY;
  if (!GROQ_API_KEY) {
    return res.status(500).json({ error: 'Service not configured' });
  }

  try {
    // ─── 6. Body size limit (2MB) ───
    const MAX_SIZE = 2 * 1024 * 1024;
    const chunks = [];
    let totalSize = 0;

    for await (const chunk of req) {
      totalSize += chunk.length;
      if (totalSize > MAX_SIZE) {
        return res.status(413).json({ error: 'Request too large' });
      }
      chunks.push(chunk);
    }
    const body = Buffer.concat(chunks);

    // ─── 7. Forward to Groq (key stays server-side) ───
    const groqRes = await fetch('https://api.groq.com/openai/v1/audio/transcriptions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${GROQ_API_KEY}`,
        'Content-Type': req.headers['content-type'],
      },
      body: body,
    });

    const data = await groqRes.text();
    res.status(groqRes.status).setHeader('Content-Type', 'application/json').send(data);
  } catch (e) {
    console.error('[Transcribe] Proxy error:', e);
    res.status(500).json({ error: 'Transcription failed' });
  }
}
