// Vercel Serverless Function: VOD Transcription
// 1. Gets audio URL from Python yt-dlp function (handles YouTube auth)
// 2. Downloads audio byte range for the requested timestamp
// 3. Sends to Groq Whisper for transcription
// 4. Optionally translates via DeepL/Google

export const config = {
  api: { bodyParser: true },
  maxDuration: 30,
};

// ─── Rate Limiter ───
const rateMap = new Map();
function isRateLimited(ip) {
  const now = Date.now();
  let entry = rateMap.get(ip);
  if (!entry || now > entry.resetAt) {
    entry = { count: 0, resetAt: now + 60000 };
    rateMap.set(ip, entry);
  }
  entry.count++;
  return entry.count > 30;
}

const ALLOWED_ORIGINS = [
  'https://gottesdienst.vercel.app',
  'https://gottesdienst-',
  'http://localhost',
  'http://127.0.0.1',
];

function isAllowedOrigin(origin) {
  if (!origin) return true; // Same-origin requests are allowed
  return ALLOWED_ORIGINS.some(a => origin.startsWith(a));
}


export default async function handler(req, res) {
  if (req.method === 'OPTIONS') {
    res.setHeader('Access-Control-Allow-Origin', req.headers.origin || '*');
    res.setHeader('Access-Control-Allow-Methods', 'POST');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
    return res.status(200).end();
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const origin = req.headers.origin || req.headers.referer || '';
  if (!isAllowedOrigin(origin)) {
    return res.status(403).json({ error: 'Forbidden' });
  }
  res.setHeader('Access-Control-Allow-Origin', req.headers.origin || '*');

  const ip = req.headers['x-forwarded-for']?.split(',')[0]?.trim() || 'unknown';
  if (isRateLimited(ip)) {
    return res.status(429).json({ error: 'Too many requests' });
  }

  const GROQ_API_KEY = process.env.GROQ_API_KEY;
  if (!GROQ_API_KEY) {
    return res.status(500).json({ error: 'Groq not configured' });
  }

  try {
    const { videoId, startSec = 0, chunkDuration = 4, targetLang = 'de' } = req.body;

    if (!videoId) {
      return res.status(400).json({ error: 'videoId required' });
    }

    // 1. Download audio chunk via Cloud Run (residential proxy handles YouTube)
    const serviceUrl = process.env.YT_AUDIO_SERVICE_URL;
    const apiKey = process.env.YT_AUDIO_API_KEY;

    if (!serviceUrl || !apiKey) {
      return res.status(500).json({ error: 'YT Audio Service not configured' });
    }

    const audioRes = await fetch(
      `${serviceUrl}/audio-chunk?videoId=${videoId}&startSec=${startSec}&duration=${chunkDuration}&key=${apiKey}`
    );

    if (!audioRes.ok) {
      const err = await audioRes.json().catch(() => ({}));
      return res.status(502).json({ error: err.error || 'Audio download failed' });
    }

    const audioBuffer = Buffer.from(await audioRes.arrayBuffer());

    console.log('[VOD] Audio chunk received:', audioBuffer.length, 'bytes, ext:', audioRes.headers.get('x-audio-ext'));

    if (audioBuffer.length < 100) {
      return res.json({ text: '', detectedLang: 'unknown', translatedText: '' });
    }

    // 4. Send to Groq Whisper
    const formData = new FormData();
    formData.append('file', new Blob([audioBuffer], { type: 'audio/mpeg' }), 'audio.mp3');
    formData.append('model', 'whisper-large-v3-turbo');
    formData.append('response_format', 'verbose_json');
    // Let Whisper auto-detect language (don't force targetLang — that's for translation)
    formData.append('prompt', 'Gottesdienst, Predigt, Bibel, Gemeinde');

    const whisperRes = await fetch('https://api.groq.com/openai/v1/audio/transcriptions', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${GROQ_API_KEY}` },
      body: formData,
    });

    console.log('[VOD] Whisper response status:', whisperRes.status);
    if (!whisperRes.ok) {
      const errText = await whisperRes.text();
      console.error('[VOD] Whisper error:', errText);
      return res.status(502).json({ error: 'Whisper transcription failed', details: errText.substring(0, 200) });
    }

    const whisperData = await whisperRes.json();
    const text = (whisperData.text || '').trim();
    const detectedLang = normalizeLang(whisperData.language);

    // 5. Translate if needed
    let translatedText = text;
    if (text.length > 2 && detectedLang !== targetLang) {
      try {
        const baseUrl = `https://${req.headers.host}`;
        const translateRes = await fetch(`${baseUrl}/api/translate`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Origin': 'https://gottesdienst.vercel.app',
          },
          body: JSON.stringify({ text, sourceLang: detectedLang, targetLang }),
        });
        if (translateRes.ok) {
          const translateData = await translateRes.json();
          translatedText = translateData.translatedText || text;
        }
      } catch (e) {
        console.error('[VOD] Translation error:', e.message);
      }
    }

    res.status(200).json({
      text,
      detectedLang,
      translatedText,
      targetLang,
      startSec,
      endSec: startSec + chunkDuration,
    });

  } catch (e) {
    console.error('[VOD] Error:', e.message);
    res.status(500).json({ error: 'Transcription failed', message: e.message, stack: e.stack?.split('\n')[1]?.trim() });
  }
}

const LANG_MAP = {
  de: 'de', german: 'de', deutsch: 'de',
  en: 'en', english: 'en',
  ru: 'ru', russian: 'ru',
  zu: 'zu', zulu: 'zu', af: 'zu', xh: 'zu', st: 'zu',
  ro: 'ro', romanian: 'ro',
};

function normalizeLang(detected) {
  if (!detected) return 'unknown';
  const d = detected.toLowerCase().trim();
  return LANG_MAP[d] || d;
}
