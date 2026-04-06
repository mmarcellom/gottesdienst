// Vercel Serverless Function: Live Stream Transcription
// Fetches the latest HLS audio segment from a YouTube live stream,
// transcribes it via Groq Whisper, and optionally translates.
//
// For "Live Remote" (watching at home):
//   Client polls every ~3s: { videoId, targetLang }
//   Server grabs latest HLS segment → Whisper → translate → return text
//
// For "Live In-Hall" (sitting in the church):
//   Same API, but client shows FULL-SCREEN TEXT ONLY (no video)

import { Innertube } from 'youtubei.js';

export const config = {
  api: { bodyParser: true },
  maxDuration: 25,
};

// ─── Allowed Origins ───
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

// ─── HLS manifest cache ───
const hlsCache = new Map(); // videoId → { manifestUrl, lastSegmentUri, expires }
const HLS_CACHE_TTL = 2 * 60 * 1000; // 2 min (manifests update frequently for live)

// ─── Processed segment tracker (avoid re-transcribing same segment) ───
const processedSegments = new Map(); // segmentUri → { text, detectedLang, timestamp }
const MAX_PROCESSED = 100;

async function getHlsManifest(videoId) {
  const cached = hlsCache.get(videoId);
  if (cached && Date.now() < cached.expires) {
    return cached;
  }

  const yt = await Innertube.create({ retrieve_player: true });
  const info = await yt.getBasicInfo(videoId);

  // Check if this is actually a live stream
  if (!info.basic_info?.is_live) {
    throw new Error('NOT_LIVE');
  }

  const manifestUrl = info.streaming_data?.hls_manifest_url;
  if (!manifestUrl) {
    throw new Error('No HLS manifest available');
  }

  const result = { manifestUrl, expires: Date.now() + HLS_CACHE_TTL };
  hlsCache.set(videoId, result);
  return result;
}

async function getLatestAudioSegment(manifestUrl) {
  // Fetch the master manifest
  const masterRes = await fetch(manifestUrl);
  if (!masterRes.ok) throw new Error(`HLS master fetch failed: ${masterRes.status}`);
  const masterText = await masterRes.text();

  // Parse: find audio-only variant or lowest bandwidth (for speed)
  const lines = masterText.split('\n');
  let audioPlaylistUrl = null;

  // Look for audio-only playlist first
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].includes('TYPE=AUDIO') && lines[i].includes('URI=')) {
      const match = lines[i].match(/URI="([^"]+)"/);
      if (match) { audioPlaylistUrl = match[1]; break; }
    }
  }

  // Fallback: use the first media playlist (lowest bandwidth = fastest to download)
  if (!audioPlaylistUrl) {
    for (const line of lines) {
      if (line.trim() && !line.startsWith('#')) {
        audioPlaylistUrl = line.trim();
        break;
      }
    }
  }

  if (!audioPlaylistUrl) throw new Error('No audio playlist found in HLS manifest');

  // Make absolute URL
  if (!audioPlaylistUrl.startsWith('http')) {
    const base = manifestUrl.substring(0, manifestUrl.lastIndexOf('/') + 1);
    audioPlaylistUrl = base + audioPlaylistUrl;
  }

  // Fetch the media playlist
  const playlistRes = await fetch(audioPlaylistUrl);
  if (!playlistRes.ok) throw new Error(`HLS playlist fetch failed: ${playlistRes.status}`);
  const playlistText = await playlistRes.text();

  // Get the LAST segment (most recent audio)
  const segmentLines = playlistText.split('\n').filter(l => l.trim() && !l.startsWith('#'));
  if (segmentLines.length === 0) throw new Error('No segments in HLS playlist');

  let segmentUrl = segmentLines[segmentLines.length - 1].trim();

  // Make absolute URL
  if (!segmentUrl.startsWith('http')) {
    const base = audioPlaylistUrl.substring(0, audioPlaylistUrl.lastIndexOf('/') + 1);
    segmentUrl = base + segmentUrl;
  }

  return segmentUrl;
}

export default async function handler(req, res) {
  // CORS
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
    const { videoId, targetLang = 'de' } = req.body;

    if (!videoId) {
      return res.status(400).json({ error: 'videoId required' });
    }

    // 1. Get HLS manifest
    let hlsInfo;
    try {
      hlsInfo = await getHlsManifest(videoId);
    } catch (e) {
      if (e.message === 'NOT_LIVE') {
        return res.status(400).json({ error: 'Video is not a live stream', code: 'NOT_LIVE' });
      }
      throw e;
    }

    // 2. Get the latest audio segment
    const segmentUrl = await getLatestAudioSegment(hlsInfo.manifestUrl);

    // 3. Check if we already processed this segment
    const cached = processedSegments.get(segmentUrl);
    if (cached) {
      // Already transcribed — return cached result (possibly with new translation)
      let translatedText = cached.text;
      if (cached.detectedLang !== targetLang && cached.text.length > 2) {
        try {
          const baseUrl = `https://${req.headers.host}`;
          const translateRes = await fetch(`${baseUrl}/api/translate`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Origin': 'https://gottesdienst.vercel.app' },
            body: JSON.stringify({ text: cached.text, sourceLang: cached.detectedLang, targetLang }),
          });
          if (translateRes.ok) {
            const td = await translateRes.json();
            translatedText = td.translatedText || cached.text;
          }
        } catch (_) {}
      }
      return res.json({
        text: cached.text,
        detectedLang: cached.detectedLang,
        translatedText,
        targetLang,
        cached: true,
        timestamp: cached.timestamp,
      });
    }

    // 4. Download the segment
    const segRes = await fetch(segmentUrl);
    if (!segRes.ok) throw new Error(`Segment download failed: ${segRes.status}`);
    const segBuffer = Buffer.from(await segRes.arrayBuffer());

    if (segBuffer.length < 100) {
      return res.json({ text: '', detectedLang: 'unknown', translatedText: '', cached: false });
    }

    // 5. Send to Groq Whisper
    const formData = new FormData();
    formData.append('file', new Blob([segBuffer], { type: 'audio/mp2t' }), 'segment.ts');
    formData.append('model', 'whisper-large-v3-turbo');
    formData.append('response_format', 'verbose_json');

    const whisperRes = await fetch('https://api.groq.com/openai/v1/audio/transcriptions', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${GROQ_API_KEY}` },
      body: formData,
    });

    if (!whisperRes.ok) {
      const errText = await whisperRes.text();
      console.error('[Live] Whisper error:', errText);
      return res.status(502).json({ error: 'Transcription failed' });
    }

    const whisperData = await whisperRes.json();
    const text = (whisperData.text || '').trim();
    const detectedLang = normalizeLang(whisperData.language);

    // 6. Cache the result
    processedSegments.set(segmentUrl, { text, detectedLang, timestamp: Date.now() });
    // Prune cache
    if (processedSegments.size > MAX_PROCESSED) {
      const first = processedSegments.keys().next().value;
      processedSegments.delete(first);
    }

    // 7. Translate if needed
    let translatedText = text;
    if (text.length > 2 && detectedLang !== targetLang) {
      try {
        const baseUrl = `https://${req.headers.host}`;
        const translateRes = await fetch(`${baseUrl}/api/translate`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'Origin': 'https://gottesdienst.vercel.app' },
          body: JSON.stringify({ text, sourceLang: detectedLang, targetLang }),
        });
        if (translateRes.ok) {
          const td = await translateRes.json();
          translatedText = td.translatedText || text;
        }
      } catch (_) {}
    }

    res.status(200).json({
      text,
      detectedLang,
      translatedText,
      targetLang,
      cached: false,
      timestamp: Date.now(),
    });

  } catch (e) {
    console.error('[Live] Error:', e.message);
    res.status(500).json({ error: 'Live transcription failed', message: e.message });
  }
}

// ─── Language normalization ───
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
