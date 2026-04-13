import 'package:flutter/material.dart';
import '../config/theme.dart';

class VideoItem {
  final String videoId;
  final String title;
  final String channelName;
  final String? published;
  final String thumbnailUrl;
  final Color cardColor;
  final bool isLive;

  /// Audio-language variants for the same service.
  /// E.g. `{'de': 'abc123', 'en': 'xyz456'}` — maps lang code → videoId.
  /// `null` if the video has no paired language variants.
  final Map<String, String>? audioVariants;

  /// Lang of the primary (default) video in the pair. e.g. 'de'
  final String? primaryLang;

  VideoItem({
    required this.videoId,
    required this.title,
    required this.channelName,
    this.published,
    String? thumbnailUrl,
    Color? cardColor,
    this.isLive = false,
    this.audioVariants,
    this.primaryLang,
  })  : thumbnailUrl = thumbnailUrl ?? 'https://img.youtube.com/vi/$videoId/hqdefault.jpg',
        cardColor = cardColor ?? TertiusTheme.cardColors[0];

  bool get hasLanguagePair =>
      audioVariants != null && audioVariants!.length > 1;

  factory VideoItem.fromJson(Map<String, dynamic> json, int index) {
    Map<String, String>? variants;
    final rawVariants = json['audioVariants'];
    if (rawVariants is Map) {
      variants = rawVariants.map((k, v) => MapEntry(k.toString(), v.toString()));
    }
    return VideoItem(
      videoId: json['videoId'] as String,
      title: json['title'] as String,
      channelName: json['channelName'] as String,
      published: json['published'] as String?,
      thumbnailUrl: json['thumbnail'] as String?,
      cardColor: index < TertiusTheme.cardColors.length
          ? TertiusTheme.cardColors[index]
          : TertiusTheme.cardColors[index % TertiusTheme.cardColors.length],
      audioVariants: variants,
      primaryLang: json['primaryLang'] as String?,
    );
  }
}
