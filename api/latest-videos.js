// Vercel Serverless Function: Fetch latest videos from YouTube RSS feeds
// Returns the 6 most recent videos across all configured channels
// Sorted by logical time-of-day (morning → afternoon → evening) per date

const CHANNELS = [
  { id: 'UClwRpYWCJg4gjBN7jGS1YQg', name: 'MKSB Berlin' },
  { id: 'UCe5RLZXC8gLthqHDlfSEcQg', name: 'German Translation' },
  { id: 'UCT1daN9Wn27s2QnmCJfzj9g', name: 'KwaSizabantu Mission' },
  { id: 'UCfGfpoL_rXoPkkp6HH1y-2g', name: 'Kwasizabantu Romania' },
];

const CARD_COLORS = [
  'rgba(139,92,246,0.82)',
  'rgba(236,72,153,0.82)',
  'rgba(14,165,233,0.82)',
  'rgba(245,158,11,0.82)',
  'rgba(16,185,129,0.82)',
  'rgba(220,38,38,0.82)',
];

// ─── Time-of-day parser ───
// Extracts the logical service time from the video title.
// Returns a numeric weight: 0 = early morning, 1 = morning, 2 = afternoon, 3 = evening/night
// This handles German, English, Zulu, and Romanian title patterns.
function getTimeOfDayWeight(title) {
  const t = title.toLowerCase();

  // Early morning / dawn
  if (/früh|early|dawn|dimineata|dimineață|kusasa/.test(t)) return 0;

  // Morning
  if (/morgen[^s]|morning|vormittag|ekuseni/.test(t)) return 1;
  // "Morgens" also morning
  if (/morgens/.test(t)) return 1;

  // Midday / afternoon
  if (/mittag|nachmittag|afternoon|noon|prânz|după-amiaz|emini/.test(t)) return 2;

  // Evening / night
  if (/abend|evening|night|nacht|seara|sear[aă]|ebusuku|freitagabend/.test(t)) return 3;

  // Fallback: use the upload timestamp hour as rough hint
  return 1.5; // neutral middle — won't displace known slots
}

// ─── Date parser ───
// Tries to extract the service date from the title (e.g. "3. April 2026" or "3 April 2026")
// Returns a YYYY-MM-DD string or null
function getServiceDate(title, published) {
  const months = {
    jan: '01', januar: '01', january: '01', ianuarie: '01',
    feb: '02', februar: '02', february: '02', februarie: '02',
    mär: '03', märz: '03', march: '03', mar: '03', martie: '03',
    apr: '04', april: '04', aprilie: '04',
    mai: '05', may: '05',
    jun: '06', juni: '06', june: '06', iunie: '06',
    jul: '07', juli: '07', july: '07', iulie: '07',
    aug: '08', august: '08',
    sep: '09', sept: '09', september: '09', septembrie: '09',
    okt: '10', oktober: '10', october: '10', oct: '10', octombrie: '10',
    nov: '11', november: '11', noiembrie: '11',
    dez: '12', dezember: '12', december: '12', dec: '12', decembrie: '12',
  };

  // Pattern: "3. April 2026" or "3 April 2026" or "April 3, 2026"
  const m1 = title.match(/(\d{1,2})\.?\s+([A-Za-zäöü]+)\s+(\d{4})/);
  if (m1) {
    const month = months[m1[2].toLowerCase()];
    if (month) return `${m1[3]}-${month}-${String(m1[1]).padStart(2, '0')}`;
  }

  // Pattern: "April 3, 2026"
  const m2 = title.match(/([A-Za-zäöü]+)\s+(\d{1,2}),?\s+(\d{4})/);
  if (m2) {
    const month = months[m2[1].toLowerCase()];
    if (month) return `${m2[3]}-${month}-${String(m2[2]).padStart(2, '0')}`;
  }

  // Fallback: use the published date's calendar day
  if (published) {
    return published.substring(0, 10);
  }
  return null;
}

async function fetchChannelFeed(channel) {
  const url = `https://www.youtube.com/feeds/videos.xml?channel_id=${channel.id}`;
  try {
    const res = await fetch(url);
    if (!res.ok) return [];
    const xml = await res.text();

    // Parse XML entries manually (no DOMParser in Node)
    const entries = [];
    const entryRegex = /<entry>([\s\S]*?)<\/entry>/g;
    let match;
    while ((match = entryRegex.exec(xml)) !== null) {
      const entry = match[1];
      const videoId = entry.match(/<yt:videoId>([^<]+)<\/yt:videoId>/)?.[1];
      const title = entry.match(/<title>([^<]+)<\/title>/)?.[1];
      const published = entry.match(/<published>([^<]+)<\/published>/)?.[1];
      if (videoId && title) {
        entries.push({
          videoId,
          title,
          published,
          channelName: channel.name,
          thumbnail: `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`,
          // Pre-compute sort keys
          serviceDate: getServiceDate(title, published),
          timeWeight: getTimeOfDayWeight(title),
        });
      }
    }
    return entries;
  } catch (e) {
    console.error(`Failed to fetch feed for ${channel.name}:`, e);
    return [];
  }
}

export default async function handler(req, res) {
  // CORS headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET');
  // Cache for 30 minutes
  res.setHeader('Cache-Control', 's-maxage=1800, stale-while-revalidate=3600');

  try {
    // Fetch all channel feeds in parallel
    const allFeeds = await Promise.all(CHANNELS.map(fetchChannelFeed));
    const allVideos = allFeeds.flat();

    // Guarantee at least 1 video per channel, then fill remaining slots with newest
    allVideos.sort((a, b) => new Date(b.published) - new Date(a.published));
    const recent = [];
    const usedIds = new Set();

    // Step 1: Pick the newest video from each channel
    for (const channel of CHANNELS) {
      const newest = allVideos.find(v => v.channelName === channel.name && !usedIds.has(v.videoId));
      if (newest) {
        recent.push(newest);
        usedIds.add(newest.videoId);
      }
    }

    // Step 2: Fill remaining slots (up to 6) with the newest videos overall
    for (const v of allVideos) {
      if (recent.length >= 6) break;
      if (!usedIds.has(v.videoId)) {
        recent.push(v);
        usedIds.add(v.videoId);
      }
    }

    // Sort: newest first (left) → oldest last (right)
    recent.sort((a, b) => {
      // Primary: service date descending (newest day first)
      if (a.serviceDate && b.serviceDate && a.serviceDate !== b.serviceDate) {
        return b.serviceDate.localeCompare(a.serviceDate);
      }
      // Secondary: time-of-day weight descending (evening before morning on same day)
      return b.timeWeight - a.timeWeight;
    });

    const latest = recent.map((v, i) => ({
      videoId: v.videoId,
      title: v.title,
      published: v.published,
      channelName: v.channelName,
      thumbnail: v.thumbnail,
      cardColor: CARD_COLORS[i],
    }));

    res.status(200).json({ videos: latest, fetchedAt: new Date().toISOString() });
  } catch (e) {
    res.status(500).json({ error: 'Failed to fetch videos', message: e.message });
  }
}
