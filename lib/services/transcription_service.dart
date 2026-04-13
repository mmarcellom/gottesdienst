import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/constants.dart';

/// Transcription modes.
///
/// Strategy:
///   • VOD (already on YouTube)  → YouTube's native closed captions,
///     rendered directly inside the embed iframe. No server calls.
///   • Live (our own RTMP stream) → Whisper-based pipeline on our server,
///     polling `/api/transcribe-live`. Future work: wire this to our RTMP
///     ingest instead of yt-dlp, because YouTube does not expose live
///     captions we can consume.
enum TranscriptionMode {
  vod,        // Pre-recorded video → YouTube native CC
  liveRemote, // Watching our own live stream from home
  liveInHall, // In the hall — text only, no video
}

class TranscriptionService extends ChangeNotifier {
  bool _isActive = false;
  String _targetLang = AppConstants.defaultLanguage;
  String? _currentVideoId;
  TranscriptionMode _mode = TranscriptionMode.vod;
  Timer? _pollTimer;
  bool _isProcessing = false;
  int _consecutiveErrors = 0;

  // Displayed lines (used for live Whisper pipeline; VOD uses YouTube native CC
  // rendered inside the iframe, so _lines stays empty and the overlay is hidden)
  final List<TranscriptLine> _lines = [];
  String _statusText = '';

  bool get isActive => _isActive;
  String get targetLang => _targetLang;
  TranscriptionMode get mode => _mode;
  List<TranscriptLine> get lines => List.unmodifiable(_lines);
  String get statusText => _statusText;

  static const availableLanguages = ['de', 'en', 'ru', 'zu', 'ro'];

  static const _langLabels = {
    'de': 'Deutsch',
    'en': 'English',
    'ru': 'Русский',
    'zu': 'isiZulu',
    'ro': 'Română',
  };

  static String langLabel(String code) => _langLabels[code] ?? code.toUpperCase();

  /// Change target language. For VOD this re-triggers the iframe's
  /// `cc_lang_pref` via the player's `didUpdateWidget`.
  void setLanguage(String lang) {
    if (_targetLang == lang) return;
    _targetLang = lang;
    _lines.clear();
    _statusText = 'Sprache: ${langLabel(lang)}';
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════
  //  VOD — YouTube native CC (no server, no polling)
  // ═══════════════════════════════════════════════════════

  void startVod(String videoId) {
    if (_isActive && _currentVideoId == videoId && _mode == TranscriptionMode.vod) return;
    stop();

    _currentVideoId = videoId;
    _mode = TranscriptionMode.vod;
    _isActive = true;
    _lines.clear();
    _statusText = 'YouTube Untertitel aktiviert';
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════
  //  Live — Whisper pipeline on our server (future: RTMP ingest)
  // ═══════════════════════════════════════════════════════

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

    _fetchLiveChunk();
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: 3500),
      (_) => _fetchLiveChunk(),
    );
  }

  /// Called by the player on every progress tick. No-op for VOD (native CC
  /// handles sync internally), but kept so the player contract stays stable.
  void updatePlaybackPosition(double seconds) {}

  void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _isActive = false;
    _isProcessing = false;
    _currentVideoId = null;
    _consecutiveErrors = 0;
    _statusText = '';
    _lines.clear();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════
  //  Live fetch loop
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
        _statusText = 'Live-Transkription derzeit nicht verfügbar';
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
