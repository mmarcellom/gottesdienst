import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/video_item.dart';

/// Fan-style card carousel matching the web version's fan layout
/// with swipe gesture support for mobile navigation
class FanCarousel extends StatefulWidget {
  final List<VideoItem> videos;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  const FanCarousel({
    super.key,
    required this.videos,
    required this.currentIndex,
    required this.onSelect,
  });

  @override
  State<FanCarousel> createState() => _FanCarouselState();
}

class _FanCarouselState extends State<FanCarousel> {
  double _dragOffset = 0;
  bool _isDragging = false;

  void _onHorizontalDragStart(DragStartDetails details) {
    _isDragging = true;
    _dragOffset = 0;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.primaryDelta ?? 0;
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final threshold = 40.0;

    if (_dragOffset < -threshold || velocity < -300) {
      // Swipe left = next
      final next = (widget.currentIndex + 1).clamp(0, widget.videos.length - 1);
      if (next != widget.currentIndex) widget.onSelect(next);
    } else if (_dragOffset > threshold || velocity > 300) {
      // Swipe right = previous
      final prev = (widget.currentIndex - 1).clamp(0, widget.videos.length - 1);
      if (prev != widget.currentIndex) widget.onSelect(prev);
    }

    setState(() {
      _isDragging = false;
      _dragOffset = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.videos.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 114,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 600;

          if (isWide) {
            // Desktop: horizontal row
            return ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: widget.videos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 30),
              itemBuilder: (context, i) => _buildCard(context, i, 200, 114),
            );
          }

          // Mobile: stacked fan layout with swipe gestures
          return GestureDetector(
            onHorizontalDragStart: _onHorizontalDragStart,
            onHorizontalDragUpdate: _onHorizontalDragUpdate,
            onHorizontalDragEnd: _onHorizontalDragEnd,
            behavior: HitTestBehavior.opaque,
            child: Stack(
              alignment: Alignment.center,
              children: List.generate(widget.videos.length, (i) {
                return _buildFanCard(context, i, constraints.maxWidth);
              }),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFanCard(BuildContext context, int index, double parentWidth) {
    final isCenter = index == widget.currentIndex;
    final diff = index - widget.currentIndex;

    double left;
    double scale;
    double opacity;

    if (isCenter) {
      left = parentWidth * 0.5 - 55;
      scale = 1.0;
      opacity = 1.0;
    } else if (diff == -1 || (diff > 2 && widget.currentIndex == 0)) {
      left = parentWidth * 0.1;
      scale = 0.85;
      opacity = 0.6;
    } else if (diff == 1 || (diff < -2 && widget.currentIndex == widget.videos.length - 1)) {
      left = parentWidth * 0.9 - 110;
      scale = 0.85;
      opacity = 0.6;
    } else {
      left = diff < 0 ? -100 : parentWidth;
      scale = 0.7;
      opacity = 0.0;
    }

    // Apply drag offset to the center card for visual feedback
    if (_isDragging && isCenter) {
      left += _dragOffset * 0.3;
    }

    return AnimatedPositioned(
      duration: _isDragging ? Duration.zero : const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      left: left,
      top: 0,
      child: GestureDetector(
        onTap: () => widget.onSelect(index),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 400),
          opacity: opacity,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 400),
            scale: scale,
            child: _buildCard(context, index, 200, 114),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context, int index, double width, double height) {
    final video = widget.videos[index];
    final isActive = index == widget.currentIndex;

    return GestureDetector(
      onTap: () => widget.onSelect(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          border: isActive
              ? Border.all(color: Colors.white.withValues(alpha: 0.6), width: 2)
              : Border.all(color: Colors.white.withValues(alpha: 0.1)),
          boxShadow: isActive
              ? [BoxShadow(color: video.cardColor.withValues(alpha: 0.4), blurRadius: 16, spreadRadius: -2)]
              : [],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Thumbnail — use mqdefault (320×180, no letterbox) instead of hqdefault (480×360, has black bars)
            CachedNetworkImage(
              imageUrl: video.thumbnailUrl.replaceAll('hqdefault', 'mqdefault'),
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: video.cardColor.withValues(alpha: 0.3)),
              errorWidget: (_, __, ___) => CachedNetworkImage(
                imageUrl: video.thumbnailUrl,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(color: video.cardColor.withValues(alpha: 0.3)),
              ),
            ),
            // Overlay
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, video.cardColor],
                ),
              ),
            ),
            // Text
            Positioned(
              left: 8, right: 8, bottom: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    video.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                  Text(
                    video.channelName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 8, color: Colors.white.withValues(alpha: 0.7)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
