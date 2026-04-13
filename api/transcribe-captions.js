// Vercel Serverless Function: YouTube Caption Extraction
// Fetches captions directly from YouTube by:
// 1. Loading the watch page HTML to extract caption track URLs
// 2. Fetching the actual timed text from those URLs
// No VPS needed, no cookies needed — just a consent cookie header

export const config = {
  api: { bodyParser: true },
  maxDuration: 25,
};

function isAllowedOrigin(origin) {
  if (!origin) return true;
  const allowed = ['https://gottesdienst.vercel.app', 'https://gottesdienst-', 'http://localhost', 'http://127.0.0.1'];
  return allowed.some(a => origin.startsWith(a));
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

  try {
    const { videoId, lang = 'de', targetLang = 'de' } = req.body;

    if (!videoId) {
      return res.status(400).json({ error: 'videoId required' });
    }

    console.log(`[Captions] Fetching for ${videoId} lang=${lang}`);

    // Step 1: Get caption track URL from YouTube watch page
    const trackUrl = await extractCaptionTrackUrl(videoId, lang);

    if (!trackUrl) {
      return res.status(404).json({
        error: 'No captions available',
        videoId,
      });
    }

    // Step 2: Fetch the actual captions
    const segments = await fetchCaptionSegments(trackUrl);

    if (!segments || segments.length === 0) {
      return res.status(404).json({
        error: 'Caption track empty',
        videoId,
      });
    }

    console.log(`[Captions] ✓ ${segments.length} segments for ${videoId}`);

    // Combine into text
    const text = segments.map(s => s.text).join(' ').trim();

    // Translate if needed
    let translatedText = text;
    if (text.length > 2 && lang !== targetLang) {
      try {
        const baseUrl = `https://${req.headers.host}`;
        const trRes = await fetch(`${baseUrl}/api/translate`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'Origin': 'https://gottesdienst.vercel.app' },
          body: JSON.stringify({ text: text.substring(0, 4000), sourceLang: lang, targetLang }),
        });
        if (trRes.ok) {
          const trData = await trRes.json();
          translatedText = trData.translatedText || text;
        }
      } catch (e) {
        console.error('[Captions] Translation error:', e.message);
      }
    }

    res.status(200).json({
      text,
      detectedLang: lang,
      translatedText,
      targetLang,
      source: 'youtube_captions',
      segmentCount: segments.length,
      segments,
    });

  } catch (e) {
    console.error('[Captions] Error:', e.message);
    res.status(500).json({ error: 'Caption fetch failed', message: e.message });
  }
}


/**
 * Extract caption track URL from YouTube watch page HTML.
 * The page contains captionTracks JSON with baseUrl for each language.
 */
async function extractCaptionTrackUrl(videoId, targetLang) {
  const headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    'Accept-Language': 'de-DE,de;q=0.9,en;q=0.8',
    'Cookie': 'CONSENT=YES+cb.20210328-17-p0.de+FX+123; SOCS=CAESEwgDEgk2MjcyMjc4MjQaAmRlIAEaBgiAo_a2Bg',
  };

  const pageRes = await fetch(`https://www.youtube.com/watch?v=${videoId}`, { headers });

  if (!pageRes.ok) {
    console.log(`[Captions] Page fetch failed: ${pageRes.status}`);
    return null;
  }

  const html = await pageRes.text();

  // Extract captionTracks from ytInitialPlayerResponse
  const match = html.match(/"captionTracks":\s*(\[.*?\])/);
  if (!match) {
    console.log('[Captions] No captionTracks in page');
    return null;
  }

  let tracks;
  try {
    // Unescape unicode
    const raw = match[1].replace(/\\u0026/g, '&').replace(/\\"/g, '"');
    tracks = JSON.parse(raw);
  } catch (e) {
    console.error('[Captions] Failed to parse captionTracks:', e.message);
    return null;
  }

  console.log(`[Captions] Found ${tracks.length} caption tracks`);

  // Find best track
  // Priority 1: exact language match
  let track = tracks.find(t => t.languageCode === targetLang);

  // Priority 2: language starts with target (e.g., 'de' matches 'de-DE')
  if (!track) {
    track = tracks.find(t => t.languageCode?.startsWith(targetLang));
  }

  // Priority 3: any auto-generated track (kind=asr), we'll translate via YouTube
  if (!track && tracks.length > 0) {
    const autoTrack = tracks.find(t => t.kind === 'asr') || tracks[0];
    // YouTube can translate captions — add tlang parameter
    let url = autoTrack.baseUrl;
    if (autoTrack.languageCode !== targetLang) {
      url += `&tlang=${targetLang}`;
    }
    console.log(`[Captions] Using ${autoTrack.languageCode} track, translating to ${targetLang}`);
    return url;
  }

  if (!track) {
    console.log('[Captions] No matching track found');
    return null;
  }

  console.log(`[Captions] Using track: ${track.languageCode} kind=${track.kind || 'manual'}`);
  return track.baseUrl;
}


/**
 * Fetch caption segments from a timedtext URL.
 * Tries json3 format first, falls back to srv3/xml.
 */
async function fetchCaptionSegments(baseUrl) {
  const headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
  };

  // Try JSON3 format
  const json3Url = baseUrl + '&fmt=json3';
  try {
    const res = await fetch(json3Url, { headers });
    if (res.ok) {
      const data = await res.json();
      const segments = parseJson3(data);
      if (segments && segments.length > 0) return segments;
    }
  } catch (e) {
    console.log('[Captions] json3 failed:', e.message);
  }

  // Fallback: try srv3 (XML) format
  const srv3Url = baseUrl + '&fmt=srv3';
  try {
    const res = await fetch(srv3Url, { headers });
    if (res.ok) {
      const xml = await res.text();
      return parseSrv3(xml);
    }
  } catch (e) {
    console.log('[Captions] srv3 failed:', e.message);
  }

  return null;
}


/**
 * Parse YouTube json3 caption format.
 */
function parseJson3(data) {
  const events = data.events || [];
  const segments = [];

  for (const ev of events) {
    const tStart = (ev.tStartMs || 0) / 1000.0;
    const tDur = (ev.dDurationMs || 0) / 1000.0;
    const segs = ev.segs || [];
    const text = segs.map(s => s.utf8 || '').join('').trim();

    if (!text || text.length < 2) continue;

    segments.push({
      startSec: Math.round(tStart * 100) / 100,
      endSec: Math.round((tStart + tDur) * 100) / 100,
      text,
    });
  }

  return segments.length > 0 ? segments : null;
}


/**
 * Parse YouTube srv3 (XML) caption format.
 */
function parseSrv3(xml) {
  const segments = [];
  // Simple XML parsing — srv3 format: <p t="startMs" d="durationMs">text</p>
  const regex = /<p\s+t="(\d+)"\s+d="(\d+)"[^>]*>([\s\S]*?)<\/p>/g;
  let m;

  while ((m = regex.exec(xml)) !== null) {
    const startMs = parseInt(m[1]);
    const durMs = parseInt(m[2]);
    // Remove HTML tags from text
    const text = m[3].replace(/<[^>]+>/g, '').trim();

    if (!text || text.length < 2) continue;

    segments.push({
      startSec: Math.round(startMs / 10) / 100,
      endSec: Math.round((startMs + durMs) / 10) / 100,
      text,
    });
  }

  return segments.length > 0 ? segments : null;
}
