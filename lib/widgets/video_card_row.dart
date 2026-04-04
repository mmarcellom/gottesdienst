import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/video_item.dart';
import '../config/theme.dart';

/// Horizontal scrollable row of video cards (Card 2, 3, etc.)
class VideoCardRow extends StatelessWidget {
  final List<VideoItem> videos;

  const VideoCardRow({super.key, required this.videos});

  @override
  Widget build(BuildContext context) {
    if (videos.isEmpty) {
      return SizedBox(
        height: 120,
        child: Center(
          child: Text('Keine Videos', style: TextStyle(color: TertiusTheme.textMuted)),
        ),
      );
    }

    return SizedBox(
      height: 140,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: videos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final video = videos[i];
          return SizedBox(
            width: 180,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thumbnail
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: video.thumbnailUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(color: video.cardColor.withValues(alpha: 0.2)),
                          errorWidget: (_, __, ___) => Container(color: video.cardColor.withValues(alpha: 0.2)),
                        ),
                        // Color overlay
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, video.cardColor.withValues(alpha: 0.7)],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                // Title
                Text(
                  video.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: TertiusTheme.text),
                ),
                // Channel
                Text(
                  video.channelName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: TertiusTheme.textMuted),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
