// Vercel Serverless Function: Lists available YouTube caption tracks for a video.
// Uses the public timedtext list endpoint (no auth required).
// Returns: { langs: ['de','en','ro'], tracks: [{lang, name, kind}] }

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET');
  // Cache captions list for 1h — they rarely change once uploaded
  res.setHeader('Cache-Control', 's-maxage=3600, stale-while-revalidate=7200');

  const videoId = (req.query && req.query.videoId) || '';
  if (!videoId || !/^[A-Za-z0-9_-]{6,20}$/.test(videoId)) {
    res.status(400).json({ error: 'invalid videoId' });
    return;
  }

  try {
    const url = `https://video.google.com/timedtext?type=list&v=${encodeURIComponent(videoId)}`;
    const r = await fetch(url, {
      headers: { 'User-Agent': 'Mozilla/5.0 Tertius/1.0' },
    });
    if (!r.ok) {
      res.status(200).json({ langs: [], tracks: [] });
      return;
    }
    const xml = await r.text();

    // Parse <track lang_code="de" name="" lang_original="Deutsch" ...>
    const tracks = [];
    const re = /<track\s+([^>]+)\/>/g;
    let m;
    while ((m = re.exec(xml)) !== null) {
      const attrs = m[1];
      const lang = (attrs.match(/lang_code="([^"]+)"/) || [])[1];
      const name = (attrs.match(/name="([^"]*)"/) || [])[1] || '';
      const kind = (attrs.match(/kind="([^"]*)"/) || [])[1] || '';
      if (lang) tracks.push({ lang: lang.toLowerCase().split('-')[0], name, kind });
    }

    // Unique lang list preserving order
    const seen = new Set();
    const langs = [];
    for (const t of tracks) {
      if (!seen.has(t.lang)) { seen.add(t.lang); langs.push(t.lang); }
    }

    res.status(200).json({ langs, tracks });
  } catch (e) {
    res.status(200).json({ langs: [], tracks: [], error: e.message });
  }
}
