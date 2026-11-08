import 'dart:io';

import 'package:flutter/material.dart';

import 'theme.dart';

/// Comparador deslizante: arrastra la barra para ver el antes (izquierda) y el después (derecha).
class BeforeAfter extends StatefulWidget {
  const BeforeAfter({super.key, required this.before, required this.after, this.height = 220});
  final String before;
  final String after;
  final double height;

  @override
  State<BeforeAfter> createState() => _BeforeAfterState();
}

class _LeftClip extends CustomClipper<Rect> {
  _LeftClip(this.f);
  final double f;
  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * f, size.height);
  @override
  bool shouldReclip(_LeftClip old) => old.f != f;
}

class _BeforeAfterState extends State<BeforeAfter> {
  double pos = .5;

  Widget _img(String path) => Image.file(
        File(path),
        fit: BoxFit.cover,
        cacheWidth: 1400,
        errorBuilder: (_, __, ___) => Container(color: C.line),
      );

  Widget _tag(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
        child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      return GestureDetector(
        onHorizontalDragUpdate: (d) => setState(() => pos = (pos + d.delta.dx / w).clamp(0.0, 1.0)),
        onTapDown: (d) => setState(() => pos = (d.localPosition.dx / w).clamp(0.0, 1.0)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: w,
            height: widget.height,
            child: Stack(fit: StackFit.expand, children: [
              _img(widget.after),
              ClipRect(clipper: _LeftClip(pos), child: _img(widget.before)),
              Positioned(left: w * pos - 1, top: 0, bottom: 0, child: Container(width: 2, color: Colors.white)),
              Positioned(
                left: w * pos - 17,
                top: widget.height / 2 - 17,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .25), blurRadius: 6)],
                  ),
                  child: const Icon(Icons.swap_horiz_rounded, color: C.blue, size: 22),
                ),
              ),
              Positioned(left: 8, top: 8, child: _tag('Antes')),
              Positioned(right: 8, top: 8, child: _tag('Después')),
            ]),
          ),
        ),
      );
    });
  }
}
