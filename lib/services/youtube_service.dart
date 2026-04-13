import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../config/constants.dart';
import '../models/video_item.dart';
import '../config/theme.dart';

/// Fetches latest videos from YouTube channels and provides stream URLs
class YouTubeService {
  static final YouTubeService _instance = YouTubeService._();
  factory YouTubeService() => _instance;
  YouTubeService._();

  final _yt = YoutubeExplode();
  List<VideoItem> _cachedVideos = [];
  DateTime? _lastFetch;

  List<VideoItem> get cachedVideos => _cachedVideos;

  /// Fetch latest videos — tries Vercel API first, falls back to youtube_explode
  Future<List<VideoItem>> fetchLatestVideos({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _cachedVideos.isNotEmpty &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!).inMinutes < 30) {
      return _cachedVideos;
    }

    try {
      // Try Vercel API first (already has smart sorting)
      final res = await http.get(
        Uri.parse('https://gottesdienst.vercel.app/api/latest-videos'),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final videos = (data['videos'] as List)
            .asMap()
            .entries
            .map((e) => VideoItem.fromJson(e.value as Map<String, dynamic>, e.key))
            .toList();
        _cachedVideos = videos;
        _lastFetch = DateTime.now();
        return videos;
      }
    } catch (_) {}

    // Fallback: fetch directly via youtube_explode
    try {
      final allVideos = <VideoItem>[];
      for (final channel in AppConstants.channels) {
        try {
          // Use channel uploads
          final uploads = _yt.channels.getUploads(ChannelId.fromString('UC${channel.id.substring(2)}'));
          await for (final video in uploads.take(3)) {
            allVideos.add(VideoItem(
              videoId: video.id.value,
              title: video.title,
              channelName: channel.name,
              published: video.uploadDate?.toString(),
              cardColor: TertiusTheme.cardColors[allVideos.length % TertiusTheme.cardColors.length],
            ));
          }
        } catch (_) {}
      }

      // Guarantee at least 1 per channel, then fill to 6
      final result = <VideoItem>[];
      final used = <String>{};

      for (final channel in AppConstants.channels) {
        final vid = allVideos.firstWhere(
          (v) => v.channelName == channel.name && !used.contains(v.videoId),
          orElse: () => allVideos.first,
        );
        result.add(vid);
        used.add(vid.videoId);
      }

      for (final v in allVideos) {
        if (result.length >= 6) break;
        if (!used.contains(v.videoId)) {
          result.add(v);
          used.add(v.videoId);
        }
      }

      _cachedVideos = result;
      _lastFetch = DateTime.now();
      return result;
    } catch (e) {
      return _cachedVideos.isNotEmpty ? _cachedVideos : _defaultVideos();
    }
  }

  /// Cached info about the last resolved audio stream
  AudioOnlyStreamInfo? _lastAudioStreamInfo;

  /// Get the audio-only stream URL for a video (for transcription)
  Future<String?> getAudioStreamUrl(String videoId) async {
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(VideoId(videoId));
      // Get the best audio-only stream
      final audioStreams = manifest.audioOnly.sortByBitrate();
      if (audioStreams.isNotEmpty) {
        _lastAudioStreamInfo = audioStreams.last;
        return audioStreams.last.url.toString();
      }
    } catch (e) {
      // For live streams, try HLS
      try {
        _lastAudioStreamInfo = null;
        final url = await _yt.videos.streamsClient.getHttpLiveStreamUrl(VideoId(videoId));
        return url;
      } catch (_) {}
    }
    return null;
  }

  /// Get the container name of the last resolved audio stream (e.g. "webm", "mp4")
  String get lastAudioStreamContainer {
    final info = _lastAudioStreamInfo;
    if (info == null) return 'webm';
    // AudioStreamInfo.container.name gives e.g. "webm", "mp4"
    return info.container.name;
  }

  /// Get the MIME type of the last resolved audio stream
  String get lastAudioStreamMimeType {
    final info = _lastAudioStreamInfo;
    if (info == null) return 'audio/webm';
    // Use the codec info to build a proper MIME type
    final container = info.container.name;
    switch (container) {
      case 'webm':
        return 'audio/webm';
      case 'mp4':
      case 'm4a':
        return 'audio/mp4';
      default:
        return 'audio/$container';
    }
  }

  /// Get video info including whether it's live
  Future<bool> isLiveStream(String videoId) async {
    try {
      final video = await _yt.videos.get(VideoId(videoId));
      return video.isLive;
    } catch (_) {
      return false;
    }
  }

  /// Default fallback videos
  List<VideoItem> _defaultVideos() {
    return [
      VideoItem(videoId: 'cK8CT7e_CuU', title: 'Andacht', channelName: 'MKSB Berlin', cardColor: TertiusTheme.cardColors[0]),
      VideoItem(videoId: 'hncfNy8xCus', title: 'Mustard Seed', channelName: 'KwaSizabantu Mission', cardColor: TertiusTheme.cardColors[1]),
      VideoItem(videoId: 'Q5aiihMB_sY', title: 'Senfkoerner', channelName: 'German Translation', cardColor: TertiusTheme.cardColors[2]),
      VideoItem(videoId: 'Nityj0W5dp8', title: 'Am auzit', channelName: 'Kwasizabantu Romania', cardColor: TertiusTheme.cardColors[3]),
      VideoItem(videoId: 'rcbqC_94tUg', title: 'Mary vom Leuchtturm', channelName: 'German Translation', cardColor: TertiusTheme.cardColors[4]),
      VideoItem(videoId: 'GyeOjz9E2uo', title: 'Mary of the Lighthouse', channelName: 'KwaSizabantu Mission', cardColor: TertiusTheme.cardColors[5]),
    ];
  }

  void dispose() {
    _yt.close();
  }
}
