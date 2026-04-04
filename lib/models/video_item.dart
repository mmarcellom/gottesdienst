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

  VideoItem({
    required this.videoId,
    required this.title,
    required this.channelName,
    this.published,
    String? thumbnailUrl,
    Color? cardColor,
    this.isLive = false,
  })  : thumbnailUrl = thumbnailUrl ?? 'https://img.youtube.com/vi/$videoId/hqdefault.jpg',
        cardColor = cardColor ?? TertiusTheme.cardColors[0];

  factory VideoItem.fromJson(Map<String, dynamic> json, int index) {
    return VideoItem(
      videoId: json['videoId'] as String,
      title: json['title'] as String,
      channelName: json['channelName'] as String,
      published: json['published'] as String?,
      thumbnailUrl: json['thumbnail'] as String?,
      cardColor: index < TertiusTheme.cardColors.length
          ? TertiusTheme.cardColors[index]
          : TertiusTheme.cardColors[index % TertiusTheme.cardColors.length],
    );
  }
}
