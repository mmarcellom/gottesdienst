// Vercel Serverless Function: Fetch latest videos from YouTube RSS feeds
// Returns the 6 most recent videos across all configured channels
// Sorted by logical time-of-day (morning → afternoon → evening) per date

const CHANNELS = [
  { id: 'UClwRpYWCJg4gjBN7jGS1YQg', name: 'MKSB Berlin' },
  { id: 'UCe5RLZXC8gLthqHDlfSEcQg', name: 'German Translation' },
  { id: 'UCT1daN9Wn27s2QnmCJfzj9g', name: 'KwaSizabantu Mission' },
  { id: 'UCfGfpoL_rXoPkkp6HH1y-2g', name: 'Kwasizabantu Romania' },
];

// ─── Language pairing groups ───
// Same service, different audio channels. Videos from these channels published
// within 3h of each other on the same service date will be merged into ONE card
// with an audio-language switcher.
const PAIR_GROUPS = [
  {
    id: 'kwasizabantu',
    langByChannel: {
      'KwaSizabantu Mission': 'en',
      'German Translation':   'de',
      'Kwasizabantu Romania': 'ro',
    },
    // First available lang wins as the primary (visible) card
    langPriority: ['de', 'en', 'ro'],
  },
];

function preferredLangsFromHeader(acceptLanguage) {
  // Parses "de-DE,de;q=0.9,en;q=0.8" and returns ordered list of lang codes
  if (!acceptLanguage) return null;
  const parts = acceptLanguage.split(',').map(s => {
    const [tag, qStr] = s.trim().split(';q=');
    const q = qStr ? parseFloat(qStr) : 1.0;
    const lang = tag.toLowerCase().split('-')[0];
    return { lang, q };
  });
  parts.sort((a,b)=>b.q-a.q);
  const seen = new Set();
  const out = [];
  for (const p of parts) {
    if (!seen.has(p.lang)) { seen.add(p.lang); out.push(p.lang); }
  }
  return out;
}

function buildPairings(videos, preferredLangs) {
  const pairMap = {}; // videoId -> { pairId, variants, primaryId }
  for (const group of PAIR_GROUPS) {
    // Reorder langPriority: preferred langs first, then fallback
    const priority = [];
    if (preferredLangs) {
      for (const l of preferredLangs) {
        if (group.langPriority.includes(l) && !priority.includes(l)) priority.push(l);
      }
    }
    for (const l of group.langPriority) {
      if (!priority.includes(l)) priority.push(l);
    }
    // Only consider videos whose date was EXTRACTED FROM THE TITLE — never
    // fall back to published date, otherwise unrelated videos get paired
    // just because they were uploaded on the same day.
    const groupVideos = videos.filter(v =>
      group.langByChannel[v.channelName] && v.titleServiceDate
    );
    const byDate = {};
    for (const v of groupVideos) {
      (byDate[v.titleServiceDate] = byDate[v.titleServiceDate] || []).push(v);
    }
    for (const dateKey in byDate) {
      const vids = byDate[dateKey].sort((a,b)=>new Date(a.published)-new Date(b.published));

      // Count videos per channel on this date. If every channel in this group
      // has AT MOST ONE video on this date, pairing is unambiguous → put them
      // all in one cluster regardless of upload-time gap (translations are
      // often uploaded hours or days later).
      const perChannelCount = {};
      for (const v of vids) {
        perChannelCount[v.channelName] = (perChannelCount[v.channelName] || 0) + 1;
      }
      const unambiguous = Object.values(perChannelCount).every(c => c <= 1);

      let clusters;
      if (unambiguous) {
        clusters = [vids];
      } else {
        // Ambiguous: multiple videos per channel same day → fall back to a
        // 4h time-window cluster so morning and evening services stay separate.
        clusters = [];
        for (const v of vids) {
          const t = new Date(v.published).getTime();
          let cluster = clusters.find(c =>
            c.some(x => Math.abs(new Date(x.published).getTime() - t) < 4 * 3600 * 1000)
          );
          if (cluster) cluster.push(v); else clusters.push([v]);
        }
      }
      for (const cluster of clusters) {
        if (cluster.length < 2) continue;
        const variants = {};
        const variantTitles = {};
        for (const v of cluster) {
          const lang = group.langByChannel[v.channelName];
          if (!variants[lang]) {
            variants[lang] = v.videoId;
            variantTitles[lang] = v.title;
          }
        }
        if (Object.keys(variants).length < 2) continue;
        let primaryId = null;
        let primaryLang = null;
        for (const lang of priority) {
          if (variants[lang]) { primaryId = variants[lang]; primaryLang = lang; break; }
        }
        for (const v of cluster) {
          pairMap[v.videoId] = { pairId: group.id, variants, variantTitles, primaryId, primaryLang };
        }
      }
    }
  }
  return pairMap;
}

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
// Note: also see getTitleServiceDate for strict title-only extraction (no fallback to published)
function getTitleServiceDate(title) {
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
  const m1 = title.match(/(\d{1,2})\.?\s+([A-Za-zäöü]+)\s+(\d{4})/);
  if (m1) {
    const month = months[m1[2].toLowerCase()];
    if (month) return `${m1[3]}-${month}-${String(m1[1]).padStart(2, '0')}`;
  }
  const m2 = title.match(/([A-Za-zäöü]+)\s+(\d{1,2}),?\s+(\d{4})/);
  if (m2) {
    const month = months[m2[1].toLowerCase()];
    if (month) return `${m2[3]}-${month}-${String(m2[2]).padStart(2, '0')}`;
  }
  // Numeric format: YYYYMMDD or YYYY-MM-DD
  const m3 = title.match(/(20\d{2})[-]?(\d{2})[-]?(\d{2})/);
  if (m3) return `${m3[1]}-${m3[2]}-${m3[3]}`;
  return null;
}

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
          // Strict title-only date for safe pairing (no fallback to published)
          titleServiceDate: getTitleServiceDate(title),
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

    // Build pair map BEFORE deduplication — uses Accept-Language for default primary lang
    const preferredLangs = preferredLangsFromHeader(req.headers['accept-language']);
    const pairMap = buildPairings(allVideos, preferredLangs);

    // Drop non-primary variants: if a video is part of a pair and NOT the primary, skip it
    const collapsed = allVideos.filter(v => {
      const p = pairMap[v.videoId];
      if (!p) return true;
      return p.primaryId === v.videoId;
    });

    // Guarantee at least 1 video per channel, then fill remaining slots with newest
    collapsed.sort((a, b) => new Date(b.published) - new Date(a.published));
    const recent = [];
    const usedIds = new Set();

    // Step 1: Pick the newest video from each channel (from the collapsed list).
    // For paired channels we use the primary only, so variant channels may appear empty —
    // that's fine because their content is now surfaced via audioVariants on the primary.
    for (const channel of CHANNELS) {
      const newest = collapsed.find(v => v.channelName === channel.name && !usedIds.has(v.videoId));
      if (newest) {
        recent.push(newest);
        usedIds.add(newest.videoId);
      }
    }

    // Step 2: Fill remaining slots (up to 6) with the newest videos overall
    for (const v of collapsed) {
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

    const latest = recent.map((v, i) => {
      const p = pairMap[v.videoId];
      return {
        videoId: v.videoId,
        title: v.title,
        published: v.published,
        channelName: v.channelName,
        thumbnail: v.thumbnail,
        cardColor: CARD_COLORS[i],
        // Language pairing info — only present when the video is part of a pair group
        audioVariants: p ? p.variants : null,          // {'de': 'id', 'en': 'id'}
        audioVariantTitles: p ? p.variantTitles : null,
        primaryLang: p ? p.primaryLang : null,
      };
    });

    res.status(200).json({ videos: latest, fetchedAt: new Date().toISOString() });
  } catch (e) {
    res.status(500).json({ error: 'Failed to fetch videos', message: e.message });
  }
}
