import 'dart:math';

import 'package:flutter/material.dart';

import 'theme.dart';

/// Estrella de cuatro puntas (el "destello").
Path sparklePath(Offset c, double r) {
  final p = Path()..moveTo(c.dx, c.dy - r);
  p.quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy);
  p.quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r);
  p.quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy);
  p.quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r);
  return p..close();
}

class _Spark {
  const _Spark(this.angle, this.dist, this.size, this.hue);
  final double angle, dist, size, hue;
}

/// Explosión de destellos para celebrar un resultado. Cambia la `key` para repetirla.
class SparkleBurst extends StatefulWidget {
  const SparkleBurst({super.key, this.size = 300});
  final double size;

  @override
  State<SparkleBurst> createState() => _SparkleBurstState();
}

class _SparkleBurstState extends State<SparkleBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..forward();
  late final List<_Spark> _sparks = () {
    final r = Random(3);
    return List.generate(
        18, (i) => _Spark(i / 18 * 2 * pi + r.nextDouble() * .3, .35 + r.nextDouble() * .65, 5 + r.nextDouble() * 9, r.nextDouble()));
  }();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) => CustomPaint(painter: _BurstPainter(_c.value, _sparks)),
          ),
        ),
      );
}

class _BurstPainter extends CustomPainter {
  _BurstPainter(this.t, this.sparks);
  final double t;
  final List<_Spark> sparks;
  static const _cols = [C.blue, C.violet, C.mint, C.amber];

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final e = Curves.easeOutCubic.transform(t);
    for (final s in sparks) {
      final pos = c + Offset(cos(s.angle), sin(s.angle)) * (s.dist * size.width * .5 * e);
      final col = _cols[(s.hue * _cols.length).floor() % _cols.length].withValues(alpha: (1 - t).clamp(0.0, 1.0));
      canvas.drawPath(sparklePath(pos, s.size * (1 - t * .5)), Paint()..color = col);
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t;
}

class GradientButton extends StatelessWidget {
  const GradientButton({super.key, required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? .5 : 1,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [C.blue, C.violet]),
            borderRadius: BorderRadius.circular(40),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(40),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: Colors.white),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(label,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
