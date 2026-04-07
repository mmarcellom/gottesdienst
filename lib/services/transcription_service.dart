import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/constants.dart';

/// Transcription modes
enum TranscriptionMode {
  vod,      // Pre-recorded video — pre-buffer for sync playback
  liveRemote, // Watching live stream from home
  liveInHall, // Sitting in the hall — text only, no video
}

/// Server-side transcription service.
/// All audio processing happens on Vercel — no YouTube audio on the client.
///
/// VOD:   Client sends videoId + timestamp → Server extracts audio → Whisper → translate → text
/// Live:  Client polls → Server gets latest HLS segment → Whisper → translate → text
class TranscriptionService extends ChangeNotifier {
  // State
  bool _isActive = false;
  String _targetLang = AppConstants.defaultLanguage;
  String? _currentVideoId;
  TranscriptionMode _mode = TranscriptionMode.vod;
  Timer? _pollTimer;
  bool _isProcessing = false;

  // VOD pre-buffer
  double _currentPlaybackSec = 0.0;
  double _preBufferAheadSec = 8.0; // How far ahead to transcribe
  double _lastTranscribedSec = 0.0;
  final Map<double, _TranscriptChunk> _vodBuffer = {};

  // YouTube captions (hybrid mode)
  bool _captionsLoaded = false;
  bool _captionsFailed = false;
  List<_CaptionSegment> _captionSegments = [];
  int _lastCaptionIndex = 0;

  // Transcript lines (displayed)
  final List<TranscriptLine> _lines = [];
  String _statusText = '';
  int _consecutiveErrors = 0;

  // Getters
  bool get isActive => _isActive;
  String get targetLang => _targetLang;
  TranscriptionMode get mode => _mode;
  List<TranscriptLine> get lines => List.unmodifiable(_lines);
  String get statusText => _statusText;

  /// Available languages
  static const availableLanguages = ['de', 'en', 'ru', 'zu', 'ro'];

  static const _langLabels = {
    'de': 'Deutsch',
    'en': 'English',
    'ru': 'Русский',
    'zu': 'isiZulu',
    'ro': 'Română',
  };

  static String langLabel(String code) => _langLabels[code] ?? code.toUpperCase();

  /// Set target language — notifies listeners so the player updates cc_lang_pref
  void setLanguage(String lang) {
    if (_targetLang == lang) return;
    _targetLang = lang;
    _lines.clear();
    _statusText = 'Sprache: ${langLabel(lang)}';
    notifyListeners();
  }

  /// Start VOD transcription — uses YouTube's native CC (shown in embed player)
  void startVod(String videoId) {
    if (_isActive && _currentVideoId == videoId && _mode == TranscriptionMode.vod) return;
    stop();

    _currentVideoId = videoId;
    _mode = TranscriptionMode.vod;
    _isActive = true;
    _lines.clear();
    _vodBuffer.clear();
    _captionsLoaded = false;
    _captionsFailed = false;
    _captionSegments = [];
    _lastCaptionIndex = 0;
    _lastTranscribedSec = _currentPlaybackSec;
    _consecutiveErrors = 0;
    // YouTube's native CC is enabled via the embed player
    // No server-side fetching needed — captions render directly in the iframe
    _statusText = 'YouTube Untertitel aktiviert';
    _captionsLoaded = true;  // Signal that we're using native CC
    notifyListeners();
  }

  /// Start live transcription (remote viewer or in-hall)
  void startLive(String videoId, {TranscriptionMode mode = TranscriptionMode.liveRemote}) {
    if (_isActive && _currentVideoId == videoId && _mode == mode) return;
    stop();

    _currentVideoId = videoId;
    _mode = mode;
    _isActive = true;
    _lines.clear();
    _consecutiveErrors = 0;
    _statusText = 'Verbinde mit Live-Stream...';
    notifyListeners();

    // Poll for new segments
    _fetchLiveChunk();
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: 3500),
      (_) => _fetchLiveChunk(),
    );
  }

  /// Update playback position (called by the player)
  void updatePlaybackPosition(double seconds) {
    _currentPlaybackSec = seconds;

    // Display captions or buffered Whisper text
    if (_captionsLoaded) {
      _displayCaptions();
    } else {
      _displayBufferedText();
    }
  }

  /// Stop transcription
  void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _isActive = false;
    _isProcessing = false;
    _currentVideoId = null;
    _consecutiveErrors = 0;
    _statusText = '';
    _vodBuffer.clear();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════
  //  YouTube Captions (Hybrid Mode)
  // ═══════════════════════════════════════════════════════

  /// Load YouTube auto-captions for the entire video. If unavailable, fall back to Whisper.
  Future<void> _loadYouTubeCaptions(String videoId) async {
    try {
      debugPrint('[Captions] Loading captions for $videoId lang=$_targetLang ...');
      _statusText = 'Lade YouTube Untertitel...';
      notifyListeners();

      // Route through Vercel serverless (avoids mixed content HTTPS→HTTP)
      final uri = Uri.parse('${AppConstants.baseUrl}/api/transcribe-captions');
      debugPrint('[Captions] POST $uri');

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'videoId': videoId,
          'lang': _targetLang,
          'targetLang': _targetLang,
        }),
      ).timeout(const Duration(seconds: 30));

      // Check if service was stopped while we were waiting
      if (!_isActive || _currentVideoId != videoId) {
        debugPrint('[Captions] Service stopped or video changed during fetch, aborting');
        return;
      }

      debugPrint('[Captions] Response: ${response.statusCode} (${response.body.length} bytes)');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final source = data['source'] as String? ?? '';
        final segments = (data['segments'] as List<dynamic>?) ?? [];

        debugPrint('[Captions] source=$source segments=${segments.length}');

        if (segments.isEmpty) {
          debugPrint('[Captions] No segments returned, fallback to Whisper');
          _statusText = 'Keine Untertitel verfügbar';
          notifyListeners();
          _fallbackToWhisper();
          return;
        }

        _captionSegments = segments.map((s) {
          final startSec = (s['startSec'] as num?)?.toDouble() ?? 0.0;
          final endSec = (s['endSec'] as num?)?.toDouble() ?? (startSec + 3.0);
          final text = (s['text'] as String?) ?? '';
          return _CaptionSegment(
            startSec: startSec,
            endSec: endSec,
            text: text,
          );
        }).where((s) => s.text.isNotEmpty).toList();

        if (_captionSegments.isEmpty) {
          debugPrint('[Captions] All segments empty after filtering');
          _fallbackToWhisper();
          return;
        }

        _captionsLoaded = true;
        _lastCaptionIndex = 0;
        _statusText = 'Untertitel geladen (${_captionSegments.length} Segmente)';
        notifyListeners();

        // Start polling to display captions in sync with playback
        _pollTimer?.cancel();
        _pollTimer = Timer.periodic(
          const Duration(milliseconds: 500),
          (_) => _displayCaptions(),
        );

        debugPrint('[Captions] ✓ Loaded ${_captionSegments.length} segments for $videoId');
      } else {
        final bodySnip = response.body.length > 150 ? response.body.substring(0, 150) : response.body;
        debugPrint('[Captions] HTTP ${response.statusCode}: $bodySnip');
        // Show details so user can report
        try {
          final errData = jsonDecode(response.body);
          final detail = errData['detail'] ?? errData['error'] ?? '';
          _statusText = 'Fehler ${response.statusCode}: $detail'.substring(0, 80);
        } catch (_) {
          _statusText = 'Untertitel-Fehler (${response.statusCode})';
        }
        notifyListeners();
        _fallbackToWhisper();
      }
    } catch (e) {
      debugPrint('[Captions] Exception: $e');
      _statusText = 'Untertitel-Fehler: ${e.toString().substring(0, e.toString().length.clamp(0, 80))}';
      notifyListeners();
      _fallbackToWhisper();
    }
  }

  /// Fall back to Whisper-based transcription
  void _fallbackToWhisper() {
    _captionsFailed = true;
    // Keep diagnostic error message visible if already set
    if (!_statusText.contains('Fehler')) {
      _statusText = 'Kein Untertitel — Whisper Fallback';
    }
    notifyListeners();

    // Start Whisper pre-buffering
    _preBufferVod();
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: 3000),
      (_) => _preBufferVod(),
    );
  }

  /// Display YouTube captions synchronized with playback position
  void _displayCaptions() {
    if (!_isActive || !_captionsLoaded || _captionSegments.isEmpty) return;

    bool changed = false;

    // Find segments that should be displayed at current playback position
    for (int i = _lastCaptionIndex; i < _captionSegments.length; i++) {
      final seg = _captionSegments[i];

      if (seg.startSec > _currentPlaybackSec + 1.0) break; // Not yet
      if (seg.endSec < _currentPlaybackSec - 2.0) {
        _lastCaptionIndex = i + 1;
        continue; // Already past
      }

      // This segment should be displayed now
      if (!seg.displayed && _currentPlaybackSec >= seg.startSec - 0.5) {
        seg.displayed = true;
        _lines.add(TranscriptLine(
          text: seg.text,
          detectedLang: _targetLang,
          timestamp: seg.startSec,
        ));

        while (_lines.length > AppConstants.maxTranscriptLines) {
          _lines.removeAt(0);
        }
        changed = true;
        _statusText = '';
      }
    }

    if (changed) notifyListeners();
  }

  // ═══════════════════════════════════════════════════════
  //  VOD Pre-Buffer (Whisper fallback)
  // ═══════════════════════════════════════════════════════

  Future<void> _preBufferVod() async {
    if (!_isActive || _isProcessing || _currentVideoId == null) return;
    if (_mode != TranscriptionMode.vod) return;

    // Don't buffer too far ahead
    final targetSec = _currentPlaybackSec + _preBufferAheadSec;
    if (_lastTranscribedSec >= targetSec) return;

    _isProcessing = true;

    try {
      final startSec = _lastTranscribedSec;
      const chunkDuration = 4.0;

      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/api/transcribe-vod'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'videoId': _currentVideoId,
          'startSec': startSec,
          'chunkDuration': chunkDuration,
          'targetLang': _targetLang,
        }),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = (data['translatedText'] as String?)?.trim() ??
            (data['text'] as String?)?.trim() ?? '';
        final detectedLang = data['detectedLang'] as String? ?? 'unknown';

        if (text.length > 2) {
          _vodBuffer[startSec] = _TranscriptChunk(
            startSec: startSec,
            endSec: startSec + chunkDuration,
            text: text,
            detectedLang: detectedLang,
          );
        }

        _lastTranscribedSec = startSec + chunkDuration;
        _consecutiveErrors = 0;
        _statusText = 'Transcribing...';

        // Try to display any newly available text
        _displayBufferedText();
      } else {
        _consecutiveErrors++;
        debugPrint('[VOD] Server error: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      _consecutiveErrors++;
      debugPrint('[VOD] Error: $e');

      if (_consecutiveErrors >= 10) {
        _statusText = 'Verbindung wird wiederhergestellt...';
        notifyListeners();
      }
    }

    _isProcessing = false;
  }

  /// Display buffered text that matches current playback position
  void _displayBufferedText() {
    final entries = _vodBuffer.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    bool changed = false;
    for (final entry in entries) {
      final chunk = entry.value;
      if (chunk.displayed) continue;

      // Show this chunk if playback has reached its start time
      if (_currentPlaybackSec >= chunk.startSec - 0.5) {
        chunk.displayed = true;
        _lines.add(TranscriptLine(
          text: chunk.text,
          detectedLang: chunk.detectedLang,
          timestamp: chunk.startSec,
        ));

        // Keep only the last N lines
        while (_lines.length > AppConstants.maxTranscriptLines) {
          _lines.removeAt(0);
        }
        changed = true;
      }
    }

    // Clean up old buffer entries
    _vodBuffer.removeWhere((k, v) => v.displayed && k < _currentPlaybackSec - 30);

    if (changed) notifyListeners();
  }

  // ═══════════════════════════════════════════════════════
  //  Live Transcription
  // ═══════════════════════════════════════════════════════

  Future<void> _fetchLiveChunk() async {
    if (!_isActive || _isProcessing || _currentVideoId == null) return;
    if (_mode != TranscriptionMode.liveRemote && _mode != TranscriptionMode.liveInHall) return;

    _isProcessing = true;

    try {
      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/api/transcribe-live'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'videoId': _currentVideoId,
          'targetLang': _targetLang,
        }),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = (data['translatedText'] as String?)?.trim() ??
            (data['text'] as String?)?.trim() ?? '';
        final detectedLang = data['detectedLang'] as String? ?? 'unknown';
        final cached = data['cached'] as bool? ?? false;

        // Only add non-cached, non-empty text
        if (text.length > 2 && !cached) {
          _lines.add(TranscriptLine(
            text: text,
            detectedLang: detectedLang,
            timestamp: DateTime.now().millisecondsSinceEpoch / 1000.0,
          ));

          while (_lines.length > AppConstants.maxTranscriptLines) {
            _lines.removeAt(0);
          }

          _statusText = 'Live Transcription...';
        } else if (cached) {
          // Same segment as before — no new audio yet
          _statusText = 'Warte auf neues Audio...';
        }

        _consecutiveErrors = 0;
        notifyListeners();
      } else if (response.statusCode == 400) {
        final data = jsonDecode(response.body);
        if (data['code'] == 'NOT_LIVE') {
          _statusText = 'Stream ist nicht live';
          notifyListeners();
        }
      } else {
        _consecutiveErrors++;
      }
    } catch (e) {
      _consecutiveErrors++;
      debugPrint('[Live] Error: $e');

      if (_consecutiveErrors >= 10) {
        _statusText = 'Verbindung gestört...';
        notifyListeners();
      }
    }

    _isProcessing = false;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}

/// A single transcript line with metadata
class TranscriptLine {
  final String text;
  final String detectedLang;
  final double timestamp;

  TranscriptLine({
    required this.text,
    required this.detectedLang,
    required this.timestamp,
  });
}

/// Internal: YouTube caption segment
class _CaptionSegment {
  final double startSec;
  final double endSec;
  final String text;
  bool displayed;

  _CaptionSegment({
    required this.startSec,
    required this.endSec,
    required this.text,
    this.displayed = false,
  });
}

/// Internal: buffered VOD chunk
class _TranscriptChunk {
  final double startSec;
  final double endSec;
  final String text;
  final String detectedLang;
  bool displayed;

  _TranscriptChunk({
    required this.startSec,
    required this.endSec,
    required this.text,
    required this.detectedLang,
    this.displayed = false,
  });
}
