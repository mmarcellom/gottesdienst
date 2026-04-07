// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Manages frosted glass overlay divs INSIDE the YouTube player's DOM wrapper.
/// MUST be inside the wrapper for backdrop-filter to blur the iframe content.
class DomGlassOverlay {
  DomGlassOverlay._();
  static final DomGlassOverlay _instance = DomGlassOverlay._();
  factory DomGlassOverlay() => _instance;

  final Map<String, html.DivElement> _overlays = {};
  final Set<_GlassSyncState> _activeSyncs = {};
  html.Element? _host;

  // Scroll-driven frame callback — runs only during scroll
  bool _syncing = false;
  Timer? _stopTimer;
  bool _hidden = false; // immersive mode flag

  /// Wrapper top offset — calculated from Flutter, not read from DOM
  double _wrapperTop = 0;

  html.Element? _findHost() {
    if (_host != null && _host!.isConnected!) return _host;
    _host = html.document.querySelector('[data-yt-wrapper]');
    return _host;
  }

  /// Called from scroll handler with the current scroll offset
  void onScroll({double scrollOffset = 0}) {
    // Calculate wrapper position from Flutter's parallax formula
    _wrapperTop = -scrollOffset * 0.2;
    if (!_syncing) {
      _syncing = true;
      SchedulerBinding.instance.scheduleFrameCallback(_onFrame);
    }
    _stopTimer?.cancel();
    _stopTimer = Timer(const Duration(milliseconds: 200), () {
      _syncing = false;
      // Final sync to nail the position
      syncAll();
    });
  }

  void _onFrame(Duration timestamp) {
    if (!_syncing) return;
    syncAll();
    SchedulerBinding.instance.scheduleFrameCallback(_onFrame);
  }

  void syncAll() {
    for (final s in _activeSyncs) {
      s._syncPosition();
    }
  }

  void updateOverlay({
    required String id,
    required double top,
    required double left,
    required double width,
    required double height,
    double borderRadius = 20,
    double blur = 30,
  }) {
    final host = _findHost();
    if (host == null) return;

    var div = _overlays[id];
    if (div == null) {
      div = html.DivElement()
        ..id = 'glass-$id'
        ..style.position = 'absolute'
        ..style.pointerEvents = 'none'
        ..style.setProperty('-webkit-backdrop-filter', 'blur(${blur}px) saturate(180%)')
        ..style.setProperty('backdrop-filter', 'blur(${blur}px) saturate(180%)')
        ..style.background = 'transparent';
      host.append(div);
      _overlays[id] = div;
    }

    // Use Flutter-calculated wrapper offset — no DOM read, zero lag
    div.style
      ..top = '${top - _wrapperTop}px'
      ..left = '${left}px'
      ..width = '${width}px'
      ..height = '${height}px'
      ..borderRadius = '${borderRadius}px'
      ..opacity = '1';
  }

  void hideOverlay(String id) => _overlays[id]?.style.opacity = '0';
  void showOverlay(String id) => _overlays[id]?.style.opacity = '1';
  void hideAll() { _hidden = true; for (final d in _overlays.values) d.style.opacity = '0'; }
  void showAll() { _hidden = false; for (final d in _overlays.values) d.style.opacity = '1'; }
  void removeOverlay(String id) { _overlays[id]?.remove(); _overlays.remove(id); }
  void removeAll() { for (final d in _overlays.values) d.remove(); _overlays.clear(); }
}

/// Flutter widget that syncs its position to a DOM glass overlay.
class GlassSync extends StatefulWidget {
  final String overlayId;
  final double blur;
  final double borderRadius;
  final double opacity;
  final Widget child;

  const GlassSync({
    super.key,
    required this.overlayId,
    this.blur = 30,
    this.borderRadius = 20,
    this.opacity = 1.0,
    required this.child,
  });

  @override
  State<GlassSync> createState() => _GlassSyncState();
}

class _GlassSyncState extends State<GlassSync> {
  final GlobalKey _key = GlobalKey();
  final _glass = DomGlassOverlay();

  @override
  void initState() {
    super.initState();
    _glass._activeSyncs.add(this);
    for (final delay in [100, 300, 800, 1500, 3000]) {
      Future.delayed(Duration(milliseconds: delay), () {
        if (mounted) _syncPosition();
      });
    }
  }

  @override
  void dispose() {
    _glass._activeSyncs.remove(this);
    _glass.removeOverlay(widget.overlayId);
    super.dispose();
  }

  void _syncPosition() {
    if (_glass._hidden) return; // Don't sync in immersive mode

    final renderBox = _key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    if (widget.opacity <= 0.01) {
      _glass.hideOverlay(widget.overlayId);
      return;
    }

    _glass.updateOverlay(
      id: widget.overlayId,
      top: offset.dy,
      left: offset.dx,
      width: size.width,
      height: size.height,
      borderRadius: widget.borderRadius,
      blur: widget.blur,
    );
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncPosition();
    });

    return Container(
      key: _key,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        color: Colors.white.withOpacity(0.12),
        border: Border.all(color: Colors.white.withOpacity(0.25), width: 0.5),
      ),
      child: widget.child,
    );
  }
}
