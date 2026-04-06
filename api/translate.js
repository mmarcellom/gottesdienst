// Vercel Serverless Function: Translation Service
// Routes to DeepL (best for EU languages) or Google Translate (Zulu + fallback)
//
// Supported languages: DE, EN, RU, RO (DeepL) + ZU (Google Translate)
// DeepL Free: 500,000 chars/month — more than enough

export const config = {
  maxDuration: 10,
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
  return entry.count > 60; // 60 translations/min
}

// ─── DeepL language codes ───
// Note: DeepL requires regional variants for some target languages
const DEEPL_SOURCE_LANGS = {
  de: 'DE', en: 'EN', ru: 'RU', ro: 'RO',
};
const DEEPL_TARGET_LANGS = {
  de: 'DE', en: 'EN-US', ru: 'RU', ro: 'RO',
};

// Languages DeepL supports (no Zulu)
const DEEPL_SUPPORTED = new Set(['de', 'en', 'ru', 'ro']);

// ─── Google Translate (free endpoint, no API key needed) ───
async function googleTranslate(text, sourceLang, targetLang) {
  // Google language codes
  const googleLangs = { de: 'de', en: 'en', ru: 'ru', ro: 'ro', zu: 'zu' };
  const sl = googleLangs[sourceLang] || sourceLang;
  const tl = googleLangs[targetLang] || targetLang;

  const url = `https://translate.googleapis.com/translate_a/single?client=gtx&sl=${sl}&tl=${tl}&dt=t&q=${encodeURIComponent(text)}`;

  const res = await fetch(url);
  if (!res.ok) throw new Error(`Google Translate HTTP ${res.status}`);

  const data = await res.json();
  // Response format: [[["translated text","original text",null,null,10]],null,"de"]
  if (Array.isArray(data) && Array.isArray(data[0])) {
    return data[0].map(s => s[0]).join('');
  }
  throw new Error('Unexpected Google Translate response format');
}

// ─── DeepL Translation ───
async function deeplTranslate(text, sourceLang, targetLang) {
  const DEEPL_KEY = process.env.DEEPL_API_KEY;
  if (!DEEPL_KEY) throw new Error('DeepL not configured');

  const params = new URLSearchParams();
  params.append('text', text);
  params.append('source_lang', DEEPL_SOURCE_LANGS[sourceLang] || sourceLang.toUpperCase());
  params.append('target_lang', DEEPL_TARGET_LANGS[targetLang] || targetLang.toUpperCase());

  // DeepL Free uses api-free.deepl.com (key contains ":fx")
  const isFree = DEEPL_KEY.includes(':fx');
  const baseUrl = isFree
    ? 'https://api-free.deepl.com'
    : 'https://api.deepl.com';
  console.log('[Translate] DeepL base:', baseUrl, 'isFree:', isFree);

  const res = await fetch(`${baseUrl}/v2/translate`, {
    method: 'POST',
    headers: {
      'Authorization': `DeepL-Auth-Key ${DEEPL_KEY}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: params.toString(),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`DeepL HTTP ${res.status}: ${errText}`);
  }

  const data = await res.json();
  return data.translations?.[0]?.text || text;
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

  try {
    const { text, sourceLang, targetLang } = req.body;

    if (!text || !targetLang) {
      return res.status(400).json({ error: 'text and targetLang required' });
    }

    // Same language = no translation needed
    if (sourceLang === targetLang) {
      return res.json({ translatedText: text, service: 'none' });
    }

    let translatedText;
    let service;

    // Route to the best service
    const canUseDeepL = DEEPL_SUPPORTED.has(sourceLang) && DEEPL_SUPPORTED.has(targetLang);

    if (canUseDeepL && process.env.DEEPL_API_KEY) {
      // DeepL for EU language pairs (best quality)
      try {
        console.log('[Translate] Using DeepL, key present:', !!process.env.DEEPL_API_KEY, 'key ends with:', process.env.DEEPL_API_KEY?.slice(-5));
        translatedText = await deeplTranslate(text, sourceLang, targetLang);
        service = 'deepl';
      } catch (e) {
        console.warn('[Translate] DeepL failed, falling back to Google:', e.message);
        translatedText = await googleTranslate(text, sourceLang, targetLang);
        service = `google (deepl-error: ${e.message})`;
      }
    } else {
      // Google Translate for Zulu and other unsupported DeepL pairs
      translatedText = await googleTranslate(text, sourceLang, targetLang);
      service = 'google';
    }

    res.status(200).json({ translatedText, service, sourceLang, targetLang });

  } catch (e) {
    console.error('[Translate] Error:', e.message);
    res.status(500).json({ error: 'Translation failed', message: e.message });
  }
}
