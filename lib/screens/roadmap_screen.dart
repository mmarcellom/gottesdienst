import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/theme.dart';

/// Tertius Roadmap — interactive progress tracker
class RoadmapScreen extends StatefulWidget {
  const RoadmapScreen({super.key});

  @override
  State<RoadmapScreen> createState() => _RoadmapScreenState();
}

class _RoadmapScreenState extends State<RoadmapScreen> with SingleTickerProviderStateMixin {
  static const _prefsKey = 'tertius_roadmap_v2';
  Map<String, bool> _taskState = {};
  final Set<String> _collapsedPhases = {};
  late AnimationController _fadeIn;

  @override
  void initState() {
    super.initState();
    _fadeIn = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _loadState();
  }

  @override
  void dispose() {
    _fadeIn.dispose();
    super.dispose();
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _taskState = decoded.map((k, v) => MapEntry(k, v as bool));
    }
    // Apply defaults for tasks not yet in saved state
    for (final phase in _phases) {
      for (final task in phase.tasks) {
        if (!_taskState.containsKey(task.id)) {
          _taskState[task.id] = task.defaultDone;
        }
      }
    }
    _saveState();
    setState(() {});
    _fadeIn.forward();
  }

  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(_taskState));
  }

  void _toggleTask(String id) {
    setState(() {
      _taskState[id] = !(_taskState[id] ?? false);
    });
    _saveState();
  }

  void _togglePhase(String id) {
    setState(() {
      if (_collapsedPhases.contains(id)) {
        _collapsedPhases.remove(id);
      } else {
        _collapsedPhases.add(id);
      }
    });
  }

  int get _totalTasks => _phases.fold(0, (sum, p) => sum + p.tasks.length);
  int get _doneTasks => _phases.fold(0, (sum, p) => sum + p.tasks.where((t) => _taskState[t.id] == true).length);

  @override
  Widget build(BuildContext context) {
    final pct = _totalTasks > 0 ? (_doneTasks / _totalTasks * 100).round() : 0;

    return Scaffold(
      backgroundColor: TertiusTheme.bg,
      body: FadeTransition(
        opacity: _fadeIn,
        child: CustomScrollView(
          slivers: [
            // --- App Bar ---
            SliverAppBar(
              backgroundColor: TertiusTheme.bg,
              pinned: true,
              expandedHeight: 140,
              leading: IconButton(
                icon: Icon(Icons.arrow_back_ios_new, size: 18, color: Colors.white.withOpacity(0.8)),
                onPressed: () => Navigator.pop(context),
              ),
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.only(left: 56, bottom: 16, right: 16),
                title: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Roadmap',
                      style: GoogleFonts.inter(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: TertiusTheme.text,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: TertiusTheme.yellow.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: TertiusTheme.yellow.withOpacity(0.3)),
                      ),
                      child: Text('$pct%',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: TertiusTheme.yellow,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // --- Progress Bar ---
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: TertiusTheme.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: _totalTasks > 0 ? _doneTasks / _totalTasks : 0,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [TertiusTheme.yellow, TertiusTheme.yellow.withOpacity(0.7)],
                            ),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text('$_doneTasks / $_totalTasks tasks',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.35),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // --- Phases ---
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final phase = _phases[index];
                    final collapsed = _collapsedPhases.contains(phase.id);
                    final phaseDone = phase.tasks.where((t) => _taskState[t.id] == true).length;
                    final phaseTotal = phase.tasks.length;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildPhaseCard(phase, collapsed, phaseDone, phaseTotal),
                    );
                  },
                  childCount: _phases.length,
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ),
      ),
    );
  }

  Widget _buildPhaseCard(_Phase phase, bool collapsed, int done, int total) {
    final allDone = done == total && total > 0;

    return Container(
      decoration: BoxDecoration(
        color: TertiusTheme.surface.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: allDone
              ? TertiusTheme.green.withOpacity(0.3)
              : TertiusTheme.border.withOpacity(0.5),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          GestureDetector(
            onTap: () => _togglePhase(phase.id),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: TertiusTheme.surface2.withOpacity(0.5),
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: phase.color.withOpacity(allDone ? 0.05 : 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: allDone
                        ? Icon(Icons.check, size: 14, color: TertiusTheme.green)
                        : Text(phase.num,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: phase.color,
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(phase.title,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: allDone ? Colors.white.withOpacity(0.5) : TertiusTheme.text,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: phase.color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: phase.color.withOpacity(0.2)),
                    ),
                    child: Text(phase.badge,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: phase.color,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('$done/$total',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: allDone ? TertiusTheme.green.withOpacity(0.6) : Colors.white.withOpacity(0.35),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: collapsed ? -0.25 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: Icon(Icons.expand_more, size: 18, color: Colors.white.withOpacity(0.35)),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 300),
            crossFadeState: collapsed ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: Column(
              children: phase.tasks.map((task) => _buildTaskRow(task, phase.color)).toList(),
            ),
            secondChild: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskRow(_Task task, Color phaseColor) {
    final done = _taskState[task.id] == true;

    return GestureDetector(
      onTap: () => _toggleTask(task.id),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: TertiusTheme.border.withOpacity(0.2)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 20,
              height: 20,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                color: done ? TertiusTheme.green : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: done ? TertiusTheme.green : TertiusTheme.border,
                  width: 1.5,
                ),
              ),
              child: done
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: done ? Colors.white.withOpacity(0.35) : TertiusTheme.text,
                      decoration: done ? TextDecoration.lineThrough : null,
                      decorationColor: Colors.white.withOpacity(0.25),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    task.desc,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: Colors.white.withOpacity(done ? 0.2 : 0.4),
                      fontWeight: FontWeight.w300,
                      height: 1.5,
                    ),
                  ),
                  if (task.tags.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: task.tags.map((tag) => _buildTag(tag)).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTag(String tag) {
    final colors = <String, Color>{
      'infra': TertiusTheme.yellow,
      'app': const Color(0xFF4F7CFF),
      'ai': const Color(0xFF7C4FFF),
      'ux': TertiusTheme.green,
      'integration': TertiusTheme.live,
    };
    final c = colors[tag] ?? Colors.white.withOpacity(0.5);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withOpacity(0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.withOpacity(0.15)),
      ),
      child: Text(tag,
        style: GoogleFonts.inter(
          fontSize: 9,
          fontWeight: FontWeight.w500,
          color: c.withOpacity(0.8),
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}


// =====================================================================
//  DATA
// =====================================================================

class _Phase {
  final String id, num, title, badge;
  final Color color;
  final List<_Task> tasks;
  const _Phase({required this.id, required this.num, required this.title, required this.badge, required this.color, required this.tasks});
}

class _Task {
  final String id, title, desc;
  final List<String> tags;
  final bool defaultDone;
  const _Task({required this.id, required this.title, required this.desc, required this.tags, this.defaultDone = false});
}

const _phases = <_Phase>[
  // ─────────────────────────────────────────────────
  //  PHASE 1 — Fundament stabilisieren
  // ─────────────────────────────────────────────────
  _Phase(
    id: 'p1', num: '01', title: 'Fundament stabilisieren', badge: 'Foundation',
    color: Color(0xFFF0C040),
    tasks: [
      // 1.1 — Audio-Pipeline (aufgeteilt)
      _Task(id: 't1_1a', title: 'Cloud Run Service deployen',
        desc: 'Python + yt-dlp + ffmpeg als Docker-Container auf Google Cloud Run. Gunicorn, Health-Endpoint, API-Key-Auth.',
        tags: ['infra'], defaultDone: true),
      _Task(id: 't1_1b', title: 'Residential Proxy (Decodo) einrichten',
        desc: 'Decodo/Smartproxy Residential Proxy mit Sticky Sessions konfigurieren. ID-Verifizierung abgeschlossen.',
        tags: ['infra'], defaultDone: true),
      _Task(id: 't1_1c', title: 'yt-dlp Audio-URL-Extraktion via Proxy',
        desc: 'yt-dlp extrahiert Audio-Stream-URLs (Format 140/m4a) durch Residential Proxy. Version 2025.10.14 gepinnt.',
        tags: ['infra', 'ai'], defaultDone: true),
      _Task(id: 't1_1d', title: 'Audio-Download vom YouTube CDN stabil machen',
        desc: 'googlevideo.com Media-Downloads bekommen 403 durch alle Proxy-Netzwerke. Lösung: BlackHole/direkter Mic-Input oder eigener VPS als Proxy.',
        tags: ['infra'], defaultDone: false),
      _Task(id: 't1_1e', title: 'ffmpeg Chunk-Extraktion (Cloud Run)',
        desc: 'ffmpeg extrahiert Zeitabschnitte aus heruntergeladenem Audio: -ss startSec -t duration, MP3 64k mono 16kHz Output.',
        tags: ['infra'], defaultDone: true),

      // 1.2 — Whisper (aufgeteilt)
      _Task(id: 't1_2a', title: 'Groq Whisper API Integration',
        desc: 'Whisper-large-v3-turbo via Groq API. FormData mit Audio-Blob, verbose_json Response, Prompt-Hints für Kirchenkontext.',
        tags: ['ai'], defaultDone: true),
      _Task(id: 't1_2b', title: 'Sprach-Auto-Erkennung (DE/EN/RU/RO/ZU)',
        desc: 'Whisper erkennt Sprache automatisch ohne language-Hint. normalizeLang() mapped Whisper-Output auf App-Sprachen.',
        tags: ['ai'], defaultDone: true),
      _Task(id: 't1_2c', title: 'End-to-End Transkription bewiesen',
        desc: 'Vollständige Pipeline: Cloud Run Audio-Chunk → Groq Whisper → korrekter deutscher Text aus Predigt bestätigt.',
        tags: ['ai', 'infra'], defaultDone: true),
      _Task(id: 't1_2d', title: 'Whisper Reconnect-Logik & 60+ Min Stabilität',
        desc: 'Automatisches Reconnect bei Groq-Timeouts. Consecutive-Error-Threshold, exponentielles Backoff, Session über volle Gottesdienst-Länge.',
        tags: ['ai'], defaultDone: false),

      // 1.3 — Übersetzung
      _Task(id: 't1_3a', title: 'DeepL Übersetzungs-API eingebunden',
        desc: 'Vercel Serverless Function /api/translate. Automatische Übersetzung wenn erkannte Sprache ≠ Zielsprache.',
        tags: ['ai', 'app'], defaultDone: true),

      // 1.4 — Vercel Serverless
      _Task(id: 't1_4a', title: 'Vercel transcribe-vod.js Serverless Function',
        desc: 'Orchestriert Pipeline: Cloud Run /audio-chunk → Groq Whisper → DeepL. Rate-Limiting, CORS, Error-Handling.',
        tags: ['infra', 'app'], defaultDone: true),

      // 1.5 — Supabase / BlackHole / OBS
      _Task(id: 't1_5a', title: 'Supabase Realtime Viewer-Bug fixen',
        desc: 'Text erscheint nicht stabil auf Viewer-Seite. Channel-Subscription und Event-Emitting debuggen.',
        tags: ['infra', 'app'], defaultDone: false),
      _Task(id: 't1_5b', title: 'BlackHole Audio-Routing einrichten',
        desc: 'Virtuelles Audio-Interface auf dem Broadcast-Mac: OBS-Mix → BlackHole → Transkriptions-App.',
        tags: ['infra'], defaultDone: false),
      _Task(id: 't1_5c', title: 'OBS Optimierungen abschließen',
        desc: 'Hardware-Encoding (Apple VideoToolbox), Keyframe-Interval 2s, Lower Third, Preview Grid cleanup.',
        tags: ['infra', 'ux'], defaultDone: false),
    ],
  ),

  // ─────────────────────────────────────────────────
  //  PHASE 1.5 — App UI (was wir gebaut haben)
  // ─────────────────────────────────────────────────
  _Phase(
    id: 'p1b', num: '▸', title: 'App UI & Player', badge: 'App',
    color: Color(0xFF4F7CFF),
    tasks: [
      _Task(id: 't1b_1', title: 'YouTube iFrame Player mit postMessage-Steuerung',
        desc: 'YouTube iframe mit JS-basiertem Event-Listener. Globale Vars window._ytCT/_ytDUR/_ytST für Progress, Duration, State.',
        tags: ['app'], defaultDone: true),
      _Task(id: 't1b_2', title: 'Progress-Bar, Play/Pause, Speed-Control',
        desc: 'Seekbar via video.currentTime, Play/Pause Toggle, Playback-Speed 0.5x–2.0x. Alles über postMessage.',
        tags: ['app', 'ux'], defaultDone: true),
      _Task(id: 't1b_3', title: 'Glasmorphism-Effekte (DomGlassOverlay)',
        desc: 'DOM-Divs mit CSS backdrop-filter:blur(30px) direkt im YouTube-Wrapper. GlassSync Widget für Flutter-Position-Sync.',
        tags: ['app', 'ux'], defaultDone: true),
      _Task(id: 't1b_4', title: 'Video Cross-Dissolve Transitions',
        desc: 'AnimationController 1800ms auto / 400ms user-tap. FadeTransition zwischen Videos, Thumbnail-Overlay während Ladezeit.',
        tags: ['app', 'ux'], defaultDone: true),
      _Task(id: 't1b_5', title: 'Parallax-Scrolling (0.2x Faktor)',
        desc: 'Video bewegt sich mit 0.2x der Scroll-Geschwindigkeit. Positioned statt AnimatedPositioned für lag-freies Scrolling.',
        tags: ['app', 'ux'], defaultDone: true),
      _Task(id: 't1b_6', title: 'Immersive Fullscreen-Modus',
        desc: 'Vollbild-Player mit Controls: Skip ±10s (Double-Tap), Seekbar, Mute/Unmute, Speed, Transkription-Toggle, Sprach-Auswahl.',
        tags: ['app', 'ux'], defaultDone: true),
      _Task(id: 't1b_7', title: 'Transkription-Overlay im Player',
        desc: 'Live-Untertitel unter dem Video im Immersive Mode. VOD Pre-Buffer-Modus, 3s Polling-Intervall.',
        tags: ['app', 'ai'], defaultDone: true),
      _Task(id: 't1b_8', title: 'Header Pills (Navigation + Clock/Profil)',
        desc: 'Zwei Glass-Pills oben: Links Discover/Upcoming/Watchlist, Rechts Search/Clock/Profil/Logout. Animiert bei Immersive.',
        tags: ['app', 'ux'], defaultDone: true),
      _Task(id: 't1b_9', title: 'Splash Screen & Auth (Supabase)',
        desc: 'Animated Splash mit Logo, Supabase Email/Password Auth, Session-Persistenz via localStorage.',
        tags: ['app', 'infra'], defaultDone: true),
      _Task(id: 't1b_10', title: 'Roadmap-Screen im App-Menü',
        desc: 'Interaktiver Fortschritts-Tracker mit klickbaren Tasks, Phase-Collapse, Progress-Bar. Zugang über Profil-Pill.',
        tags: ['app', 'ux'], defaultDone: true),
      _Task(id: 't1b_11', title: 'Sprach-Umschaltung im UI fixen',
        desc: 'Language-Selector im Immersive Mode schaltet Zielsprache um. Aktuell reagiert die Transkription nicht auf Sprachwechsel.',
        tags: ['app'], defaultDone: false),
    ],
  ),

  // ─────────────────────────────────────────────────
  //  PHASE 2 — RTMP-Ingest-Server
  // ─────────────────────────────────────────────────
  _Phase(
    id: 'p2', num: '02', title: 'Eigener RTMP-Ingest-Server', badge: 'Core Infra',
    color: Color(0xFF4F7CFF),
    tasks: [
      _Task(id: 't2_1', title: 'RTMP-Server aufsetzen (mediamtx oder SRS)',
        desc: 'Eigener Ingest-Punkt auf Hetzner VPS. Streams kommen hier rein bevor sie zu YouTube gehen.',
        tags: ['infra']),
      _Task(id: 't2_2', title: 'Stream-Weiterleitung zu YouTube konfigurieren',
        desc: 'RTMP Re-Streaming: Ingest-Server → YouTube RTMP-Endpunkt. Latenz messen und minimieren.',
        tags: ['infra', 'integration']),
      _Task(id: 't2_3', title: 'Multi-Audio-Track Handling',
        desc: 'Mehrere Audiospuren (Deutsch, Zulu, Englisch) am Ingest-Server empfangen und separat verwalten.',
        tags: ['infra', 'ai']),
      _Task(id: 't2_4', title: 'HLS-Output für eigenen Player',
        desc: 'Neben YouTube-Weiterleitung auch HLS-Stream generieren der direkt in der Tertius-App genutzt wird.',
        tags: ['infra', 'app']),
      _Task(id: 't2_5', title: 'Transkription auf eigenen Audio-Track umstellen',
        desc: 'Groq Whisper greift auf Audio-Track vom Ingest-Server zu — nicht mehr auf YouTube. Stabilität steigt dramatisch.',
        tags: ['ai', 'infra']),
    ],
  ),

  // ─────────────────────────────────────────────────
  //  PHASE 3 — App & Player ausbauen
  // ─────────────────────────────────────────────────
  _Phase(
    id: 'p3', num: '03', title: 'App & Player ausbauen', badge: 'Platform',
    color: Color(0xFF7C4FFF),
    tasks: [
      _Task(id: 't3_1', title: 'Multi-Audio-Umschaltung im Player',
        desc: 'User kann live zwischen Sprachspuren wechseln (Deutsch / Zulu / Englisch). UI: Sprach-Selector.',
        tags: ['app', 'ux']),
      _Task(id: 't3_2', title: 'Transkription Multi-Sprach-fähig machen',
        desc: 'Je nach Audiospur die passende Sprache transkribieren. Whisper-Modell per Track konfigurieren.',
        tags: ['ai', 'app']),
      _Task(id: 't3_3', title: 'Einbettbarer Player für externe Webseiten',
        desc: 'iFrame-kompatibler Embed ohne YouTube-Restrictions. Gemeinden können Streams auf ihrer Webseite einbetten.',
        tags: ['app', 'integration']),
      _Task(id: 't3_4', title: 'Saal-Modus (Großanzeige für Gehörlose)',
        desc: 'Separater Modus: nur Transkription groß anzeigen — für Tablet/Bildschirm vorne im Saal.',
        tags: ['ux', 'app']),
      _Task(id: 't3_5', title: 'Archiv & VOD-Verwaltung',
        desc: 'Aufzeichnungen zentral speichern, verschlagworten, abrufbar machen. Unabhängig von YouTube.',
        tags: ['app', 'infra']),
      _Task(id: 't3_6', title: 'Multi-Kanal-Management',
        desc: 'Mehrere Gemeinden/Kanäle (KwaSizabantu, Berlin, etc.) in einer Plattform verwalten.',
        tags: ['app']),
    ],
  ),

  // ─────────────────────────────────────────────────
  //  PHASE 4 — YouTube Multi-Audio
  // ─────────────────────────────────────────────────
  _Phase(
    id: 'p4', num: '04', title: 'YouTube Multi-Audio Integration', badge: 'Integration',
    color: Color(0xFF4F7CFF),
    tasks: [
      _Task(id: 't4_1', title: 'YouTube Live API Integration',
        desc: 'Live Streaming API statt reinem RTMP-Push. Ermöglicht Multi-Audio-Tracks.',
        tags: ['integration', 'infra']),
      _Task(id: 't4_2', title: 'Multi-Track Audio zu YouTube senden',
        desc: 'Mehrere Audiospuren an YouTube übergeben — Zuschauer können live die Sprache wechseln.',
        tags: ['integration', 'ai']),
      _Task(id: 't4_3', title: 'YouTube-Kanal-Konsolidierung',
        desc: 'Statt mehrerer Kanäle (DE/ZU/EN) einen Hauptkanal mit Sprachauswahl.',
        tags: ['integration', 'ux']),
    ],
  ),

  // ─────────────────────────────────────────────────
  //  PHASE 5 — Community
  // ─────────────────────────────────────────────────
  _Phase(
    id: 'p5', num: '05', title: 'Community & Gemeinde-Tools', badge: 'Community',
    color: Color(0xFF3DD68C),
    tasks: [
      _Task(id: 't5_1', title: 'Messenger integrieren',
        desc: 'Basis-Messaging für Gemeindeglieder. Shared Implementation mit Pitlane/Baulane.',
        tags: ['app', 'infra']),
      _Task(id: 't5_2', title: 'Gemeinde-Organisations-Tools',
        desc: 'Termine, Gruppen, Ankündigungen, Mitgliederverwaltung.',
        tags: ['app']),
      _Task(id: 't5_3', title: 'Benachrichtigungen (Push & Email)',
        desc: 'Livestream-Start, neue Aufzeichnungen, Termine. Native Push über PWA.',
        tags: ['app', 'ux']),
      _Task(id: 't5_4', title: 'Watchlist & persönliche Bibliothek',
        desc: 'Gottesdienste vormerken, Favoriten speichern, Wiedergabefortschritt merken.',
        tags: ['app', 'ux']),
    ],
  ),

  // ─────────────────────────────────────────────────
  //  PHASE 6 — Skalierung
  // ─────────────────────────────────────────────────
  _Phase(
    id: 'p6', num: '06', title: 'Skalierung & Partner-Onboarding', badge: 'Scale',
    color: Color(0xFFFF5C5C),
    tasks: [
      _Task(id: 't6_1', title: 'Onboarding-Flow für neue Gemeinden',
        desc: 'Einfacher Setup: Gemeinde registriert sich, bekommt RTMP-Zugangsdaten, richtet OBS um.',
        tags: ['ux', 'app']),
      _Task(id: 't6_2', title: 'KwaSizabantu Mission onboarden',
        desc: 'Erster externer Partner. Stream-Umleitung, Multi-Audio, Vorteile demonstrieren.',
        tags: ['integration']),
      _Task(id: 't6_3', title: 'CDN für Video-Auslieferung',
        desc: 'Cloudflare Stream oder R2 als CDN für VOD-Videos. Direkte Auslieferung ohne YouTube.',
        tags: ['infra']),
      _Task(id: 't6_4', title: 'Monitoring & Uptime Dashboard',
        desc: 'Welche Streams laufen, Transkriptions-Status, Fehler-Alerts.',
        tags: ['infra', 'app']),
      _Task(id: 't6_5', title: 'Tertius als eigenständige Plattform',
        desc: 'Vollständiger YouTube-Fallback: Eigene App, eigener Player, eigenes Archiv.',
        tags: ['infra', 'app']),
    ],
  ),
];
