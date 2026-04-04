import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:convert';
import '../config/constants.dart';
import 'youtube_service.dart';

/// Core transcription service — downloads audio from YouTube stream and sends to Groq Whisper.
/// Works on iOS without any special permissions (no mic, no screen capture needed).
///
/// Architecture:
/// 1. youtube_explode_dart gets the audio-only stream URL from YouTube
/// 2. We download small chunks (~4 seconds) of audio data via HTTP range requests
/// 3. Each chunk is sent to our Vercel proxy which forwards to Groq Whisper
/// 4. Whisper returns text + detected language
/// 5. We filter by target language and display matching text
class TranscriptionService extends ChangeNotifier {
  final YouTubeService _ytService = YouTubeService();

  // State
  bool _isActive = false;
  String _targetLang = AppConstants.defaultLanguage;
  String? _currentVideoId;
  String? _audioStreamUrl;
  Timer? _chunkTimer;
  bool _isProcessing = false;
  int _skipCount = 0;
  int _bytesDownloaded = 0;

  // Retry / resilience
  int _consecutiveErrors = 0;
  DateTime? _streamFetchedAt;
  static const _maxRetries = 3;
  static const _streamExpiryDuration = Duration(hours: 5, minutes: 30);

  // Transcript lines
  final List<String> _lines = [];
  String _statusText = '';

  // Getters
  bool get isActive => _isActive;
  String get targetLang => _targetLang;
  List<String> get lines => List.unmodifiable(_lines);
  String get statusText => _statusText;

  /// Language normalization map (same as web version)
  static const _langMap = {
    'de': 'de', 'german': 'de', 'deutsch': 'de',
    'en': 'en', 'english': 'en',
    'zu': 'zu', 'zulu': 'zu',
    'af': 'zu', // Afrikaans sometimes detected for Zulu
    'xh': 'zu', // Xhosa close to Zulu
    'st': 'zu', // Sotho group
  };

  String _normalizeLang(String? detected) {
    if (detected == null) return 'unknown';
    final d = detected.toLowerCase().trim();
    return _langMap[d] ?? d;
  }

  /// Set target language filter
  void setLanguage(String lang) {
    _targetLang = lang;
    _lines.clear();
    _skipCount = 0;
    _statusText = 'Transcribing (${lang.toUpperCase()})...';
    notifyListeners();
  }

  /// Start transcription for a video
  Future<void> start(String videoId) async {
    if (_isActive && _currentVideoId == videoId) return;

    // Stop any existing transcription
    stop();

    _currentVideoId = videoId;
    _isActive = true;
    _lines.clear();
    _skipCount = 0;
    _bytesDownloaded = 0;
    _consecutiveErrors = 0;
    _statusText = 'Verbinde mit Audio-Stream...';
    notifyListeners();

    try {
      await _refreshAudioStream();

      if (_audioStreamUrl == null) {
        _statusText = 'Kein Audio-Stream verfuegbar';
        notifyListeners();
        return;
      }

      _statusText = 'Transcribing...';
      notifyListeners();

      // Start periodic chunk downloads
      _downloadAndTranscribe(); // First chunk immediately
      _chunkTimer = Timer.periodic(
        const Duration(milliseconds: AppConstants.transcriptionIntervalMs),
        (_) => _downloadAndTranscribe(),
      );
    } catch (e) {
      _statusText = 'Fehler: $e';
      _isActive = false;
      notifyListeners();
    }
  }

  /// Stop transcription
  void stop() {
    _chunkTimer?.cancel();
    _chunkTimer = null;
    _isActive = false;
    _isProcessing = false;
    _audioStreamUrl = null;
    _currentVideoId = null;
    _consecutiveErrors = 0;
    _statusText = '';
    notifyListeners();
  }

  /// Refresh the audio stream URL (YouTube URLs expire after ~6 hours)
  Future<void> _refreshAudioStream() async {
    if (_currentVideoId == null) return;
    _audioStreamUrl = await _ytService.getAudioStreamUrl(_currentVideoId!);
    _streamFetchedAt = DateTime.now();
    _bytesDownloaded = 0;
  }

  /// Check if the stream URL is likely expired
  bool get _isStreamExpired {
    if (_streamFetchedAt == null) return true;
    return DateTime.now().difference(_streamFetchedAt!) > _streamExpiryDuration;
  }

  /// Exponential backoff delay for retries
  Duration _backoffDelay(int attempt) {
    // 1s, 2s, 4s
    return Duration(seconds: 1 << attempt.clamp(0, 3));
  }

  /// Download a chunk of audio and send to Whisper with retry logic
  Future<void> _downloadAndTranscribe() async {
    if (!_isActive || _isProcessing || _audioStreamUrl == null) return;
    _isProcessing = true;

    try {
      // Proactively refresh if stream is about to expire
      if (_isStreamExpired) {
        debugPrint('[Transcribe] Stream expired, refreshing...');
        _statusText = 'Stream wird erneuert...';
        notifyListeners();
        await _refreshAudioStream();
        if (_audioStreamUrl == null) {
          _statusText = 'Stream-Erneuerung fehlgeschlagen';
          _isProcessing = false;
          notifyListeners();
          return;
        }
      }

      // Download ~4 seconds of audio data via range request
      final chunkSize = 64 * 1024; // 64KB
      final rangeStart = _bytesDownloaded;
      final rangeEnd = rangeStart + chunkSize - 1;

      final audioRes = await _httpGetWithRetry(
        Uri.parse(_audioStreamUrl!),
        headers: {'Range': 'bytes=$rangeStart-$rangeEnd'},
      );

      if (audioRes == null) {
        // All retries failed — try refreshing the stream URL
        debugPrint('[Transcribe] Download failed, refreshing stream URL...');
        await _refreshAudioStream();
        _isProcessing = false;
        return;
      }

      if (audioRes.statusCode != 200 && audioRes.statusCode != 206) {
        // Stream might have expired, try to refresh
        debugPrint('[Transcribe] HTTP ${audioRes.statusCode}, refreshing stream...');
        await _refreshAudioStream();
        _isProcessing = false;
        return;
      }

      final audioData = audioRes.bodyBytes;
      _bytesDownloaded += audioData.length;
      _consecutiveErrors = 0; // Reset on success

      if (audioData.isEmpty) {
        _isProcessing = false;
        return;
      }

      // Send raw audio to Groq Whisper via our Vercel proxy
      final container = _ytService.lastAudioStreamContainer;
      final mimeType = _ytService.lastAudioStreamMimeType;

      final request = http.MultipartRequest('POST', Uri.parse(AppConstants.transcribeUrl));
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        audioData,
        filename: 'audio.$container',
        contentType: _parseMediaType(mimeType),
      ));
      request.fields['model'] = 'whisper-large-v3-turbo';
      request.fields['response_format'] = 'verbose_json';

      final streamedRes = await request.send().timeout(const Duration(seconds: 10));
      final resBody = await streamedRes.stream.bytesToString();

      if (streamedRes.statusCode != 200) {
        debugPrint('[Transcribe] API Error: $resBody');
        _isProcessing = false;
        return;
      }

      final data = jsonDecode(resBody);
      final text = (data['text'] as String?)?.trim() ?? '';
      final detectedLang = _normalizeLang(data['language'] as String?);

      debugPrint('[Transcribe] detected=$detectedLang target=$_targetLang text="${text.length > 50 ? text.substring(0, 50) : text}"');

      // Language filter
      if (detectedLang == _targetLang) {
        _skipCount = 0;
        if (text.length > 2) {
          _lines.add(text);
          if (_lines.length > AppConstants.maxTranscriptLines) {
            _lines.removeAt(0);
          }
          _statusText = 'Transcribing...';
          notifyListeners();
        }
      } else {
        _skipCount++;
        if (_skipCount >= 2) {
          _statusText = '${detectedLang.toUpperCase()} erkannt \u2014 warte auf ${_targetLang.toUpperCase()}...';
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('[Transcribe] Error: $e');
      _consecutiveErrors++;

      if (_consecutiveErrors >= 3) {
        // Try refreshing the stream after several consecutive errors
        debugPrint('[Transcribe] Too many errors, refreshing stream...');
        _statusText = 'Verbindung wird wiederhergestellt...';
        notifyListeners();
        try {
          await _refreshAudioStream();
          _consecutiveErrors = 0;
        } catch (_) {
          // Will retry on next timer tick
        }
      }
    }

    _isProcessing = false;
  }

  /// HTTP GET with exponential backoff retry
  Future<http.Response?> _httpGetWithRetry(Uri uri, {Map<String, String>? headers}) async {
    for (int attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        final response = await http.get(uri, headers: headers)
            .timeout(const Duration(seconds: 8));
        return response;
      } catch (e) {
        debugPrint('[Transcribe] Retry ${attempt + 1}/$_maxRetries: $e');
        if (attempt < _maxRetries - 1) {
          await Future.delayed(_backoffDelay(attempt));
        }
      }
    }
    return null;
  }

  /// Parse a MIME type string into a MediaType for http_parser
  MediaType _parseMediaType(String mimeType) {
    final parts = mimeType.split('/');
    if (parts.length == 2) {
      return MediaType(parts[0], parts[1]);
    }
    return MediaType('audio', 'webm');
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
