import 'package:flutter/material.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

/// A glass morphism container implemented as an HTML element.
/// Uses CSS `backdrop-filter: blur()` which works over Platform Views (iframes).
/// Flutter's BackdropFilter cannot blur through Platform Views on Web.
///
/// This widget places an HTML div with CSS backdrop-filter BEHIND the child.
/// Since both the YouTube iframe and this div live in the DOM layer,
/// the CSS blur actually works on the video content.
class HtmlGlass extends StatefulWidget {
  final double blur;
  final Color color;
  final double borderRadius;
  final double borderOpacity;
  final Widget? child;

  const HtmlGlass({
    super.key,
    this.blur = 30,
    this.color = const Color(0x1FFFFFFF), // white 12%
    this.borderRadius = 20,
    this.borderOpacity = 0.2,
    this.child,
  });

  @override
  State<HtmlGlass> createState() => _HtmlGlassState();
}

class _HtmlGlassState extends State<HtmlGlass> {
  late String _viewId;

  @override
  void initState() {
    super.initState();
    _viewId = 'html-glass-${identityHashCode(this)}-${DateTime.now().millisecondsSinceEpoch}';
    _registerView();
  }

  void _registerView() {
    ui_web.platformViewRegistry.registerViewFactory(_viewId, (int viewId) {
      final r = widget.color.red;
      final g = widget.color.green;
      final b = widget.color.blue;
      final a = widget.color.opacity;

      final blurVal = 'blur(${widget.blur}px) saturate(180%)';
      final div = html.DivElement()
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.borderRadius = '${widget.borderRadius}px'
        ..style.setProperty('-webkit-backdrop-filter', blurVal)
        ..style.setProperty('backdrop-filter', blurVal)
        ..style.background = 'rgba($r,$g,$b,$a)'
        ..style.border = '1px solid rgba(255,255,255,${widget.borderOpacity})'
        ..style.boxShadow = '0 8px 32px rgba(0,0,0,0.18), inset 0 1px 0 rgba(255,255,255,0.12)'
        ..style.pointerEvents = 'none';

      return div;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        // HTML glass layer (blurs the iframe beneath via CSS backdrop-filter)
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: HtmlElementView(viewType: _viewId),
          ),
        ),
        // Flutter child on top (renders on canvas layer, above DOM layer)
        if (widget.child != null) widget.child!,
      ],
    );
  }
}
