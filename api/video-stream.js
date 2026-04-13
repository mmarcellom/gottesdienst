// Vercel Serverless Function: Get direct video stream URL
// Uses youtubei.js Innertube

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Cache-Control', 'public, max-age=3600');
  if (req.method === 'OPTIONS') return res.status(200).end();

  const { videoId, debug } = req.query;
  if (!videoId) {
    return res.status(400).json({ error: 'Missing videoId parameter' });
  }

  try {
    const { Innertube } = await import('youtubei.js');
    const yt = await Innertube.create({ retrieve_player: true });

    // Try getInfo first (has more data), fallback to getBasicInfo
    let info;
    try {
      info = await yt.getInfo(videoId);
    } catch (e) {
      console.error('getInfo failed, trying getBasicInfo:', e.message);
      info = await yt.getBasicInfo(videoId);
    }

    const streamingData = info.streaming_data;
    if (!streamingData || (!streamingData.formats?.length && !streamingData.adaptive_formats?.length)) {
      return res.status(404).json({
        error: 'No streaming data',
        streamingDataType: typeof streamingData,
        streamingDataKeys: streamingData ? Object.keys(streamingData).slice(0, 10) : [],
        formatsCount: streamingData?.formats?.length || 0,
        adaptiveCount: streamingData?.adaptive_formats?.length || 0,
        playability: info?.playability_status?.status,
        playabilityReason: info?.playability_status?.reason,
        title: info?.basic_info?.title,
      });
    }

    // Use adaptive_formats (more reliable) + formats (muxed)
    const formats = [
      ...(streamingData.formats || []),
      ...(streamingData.adaptive_formats || []),
    ];

    if (debug) {
      // Debug mode: show format structure
      const debugFormats = formats.map(f => ({
        itag: f.itag,
        mime: f.mime_type?.toString(),
        height: f.height,
        hasUrl: !!f.url,
        urlType: typeof f.url,
        urlValue: f.url?.toString?.()?.substring(0, 100),
      }));
      return res.status(200).json({ formatsCount: formats.length, formats: debugFormats });
    }

    // Find best mp4 muxed format ≤720p (prefer muxed for <video> playback)
    let best = null;
    for (const fmt of formats) {
      const mime = fmt.mime_type?.toString() || '';
      const h = fmt.height || 0;
      // Only muxed video+audio MP4 formats (not adaptive audio-only or video-only)
      if (mime.includes('video/mp4') && h <= 720 && h > 0) {
        if (!best || h > (best.height || 0)) best = fmt;
      }
    }
    // Fallback: any video format
    if (!best) {
      for (const fmt of formats) {
        const mime = fmt.mime_type?.toString() || '';
        if (mime.includes('video/') && (fmt.height || 0) > 0) {
          if (!best || (fmt.height || 0) > (best.height || 0)) best = fmt;
          if ((best.height || 0) >= 720) break;
        }
      }
    }
    if (!best && formats.length > 0) best = formats[0];

    if (!best) {
      return res.status(404).json({ error: 'No format found', formatsCount: formats.length });
    }

    // Extract URL via decipher (same approach as transcribe-vod.js)
    let streamUrl = null;
    try {
      streamUrl = best.decipher(yt.session.player);
      if (streamUrl && typeof streamUrl === 'object') {
        streamUrl = streamUrl.toString();
      }
    } catch (e) {
      console.error('Decipher error:', e.message);
    }

    // Fallback: direct url property
    if (!streamUrl && best.url) {
      streamUrl = typeof best.url === 'string' ? best.url : best.url.toString();
    }

    if (!streamUrl || streamUrl === '[object Object]') {
      return res.status(404).json({
        error: 'Could not extract URL',
        hasDecipher: !!best.decipher,
      });
    }

    return res.status(200).json({
      streamUrl,
      quality: `${best.height || '?'}p`,
      mimeType: best.mime_type?.toString() || 'video/mp4',
    });
  } catch (err) {
    console.error('video-stream error:', err);
    return res.status(500).json({ error: err.message || 'Unknown error' });
  }
}
