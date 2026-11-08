import 'dart:math';

import 'package:flutter/material.dart';

import '../engine/tools.dart';
import 'fx.dart';
import 'home.dart';
import 'theme.dart';

const _sky = Color(0xFF6FA8FF);
const _lilac = Color(0xFFA78BFF);
const _aqua = Color(0xFF3EE0B4);

Color _pc(double h) => h < .5 ? Color.lerp(_sky, _lilac, h * 2)! : Color.lerp(_lilac, _aqua, (h - .5) * 2)!;

class _P {
  const _P(this.r, this.a, this.spin, this.size, this.hue);
  final double r, a, spin, size, hue;
}

class Splash extends StatefulWidget {
  const Splash({super.key});

  @override
  State<Splash> createState() => _SplashState();
}

class _SplashState extends State<Splash> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3600));
  final _rnd = Random(11);
  late final List<_P> _ps = List.generate(
      110,
      (_) => _P(.35 + _rnd.nextDouble() * .65, _rnd.nextDouble() * 2 * pi,
          (_rnd.nextBool() ? 1 : -1) * (1.2 + _rnd.nextDouble() * 2.2), 1.4 + _rnd.nextDouble() * 3.2, _rnd.nextDouble()));
  late final List<_P> _sparks = List.generate(
      22, (i) => _P(.35 + _rnd.nextDouble() * .65, i / 22 * 2 * pi + _rnd.nextDouble() * .3, 0, 3 + _rnd.nextDouble() * 4, _rnd.nextDouble()));
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    Tools.init(); // detecta NVENC, Ghostscript y 7-Zip mientras corre la animación
    final reduce = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    if (reduce) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _next());
    } else {
      _c.forward().whenComplete(_next);
    }
  }

  void _next() {
    if (_gone || !mounted) return;
    _gone = true;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 500),
      pageBuilder: (_, __, ___) => const Home(),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.ink,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _next,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            final t = _c.value;
            final pop = Curves.elasticOut.transform(((t - .6) / .3).clamp(0.0, 1.0));
            final fade = ((t - .62) / .2).clamp(0.0, 1.0);
            return Stack(
              children: [
                Positioned.fill(child: CustomPaint(painter: _SplashPainter(t, _ps, _sparks))),
                Align(
                  alignment: const Alignment(0, .32),
                  child: Opacity(
                    opacity: fade,
                    child: Transform.scale(
                      scale: .6 + .4 * pop,
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Squeeze',
                              style: TextStyle(
                                  color: Colors.white, fontSize: 46, fontWeight: FontWeight.w800, letterSpacing: -1.2)),
                          SizedBox(height: 8),
                          Text('Menos peso. Misma calidad.', style: TextStyle(color: Colors.white70, fontSize: 15)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SplashPainter extends CustomPainter {
  _SplashPainter(this.t, this.ps, this.sparks);
  final double t;
  final List<_P> ps;
  final List<_P> sparks;
  static const _conv = .6; // momento en que todo colapsa al centro

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * .42);
    final maxR = min(max(size.shortestSide, 280.0), 700.0);
    final k = (t / _conv).clamp(0.0, 1.0);
    final e = Curves.easeInCubic.transform(k);
    final core = t < _conv ? 1.0 : 1 - ((t - _conv) / .3).clamp(0.0, 1.0);

    // núcleo luminoso que crece mientras las partículas se comprimen
    final cr = (8 + 40 * e) * 2.4;
    canvas.drawCircle(
      c,
      cr,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: .95 * (.2 + .8 * e) * core),
            _lilac.withValues(alpha: .45 * e * core),
            _lilac.withValues(alpha: 0),
          ],
          stops: const [0, .45, 1],
        ).createShader(Rect.fromCircle(center: c, radius: cr)),
    );

    // partículas en espiral hacia el centro
    if (k < 1) {
      final line = Paint()..strokeCap = StrokeCap.round;
      for (final p in ps) {
        final r = p.r * maxR * (1 - e);
        final a = p.a + e * p.spin;
        final pos = c + Offset(cos(a), sin(a)) * r;
        final da = .12 * p.spin.sign;
        final tail = c + Offset(cos(a - da), sin(a - da)) * (r * 1.08 + 6);
        final alpha = .25 + .75 * e;
        line
          ..color = _pc(p.hue).withValues(alpha: alpha * .5)
          ..strokeWidth = p.size * .7;
        canvas.drawLine(tail, pos, line);
        canvas.drawCircle(pos, p.size * (1 - .45 * e), Paint()..color = _pc(p.hue).withValues(alpha: alpha));
      }
    }

    if (t >= _conv) {
      // onda de choque
      final f = ((t - _conv) / .28).clamp(0.0, 1.0);
      canvas.drawCircle(
        c,
        20 + f * maxR * .6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5 * (1 - f) + .5
          ..color = Colors.white.withValues(alpha: (1 - f) * .8),
      );
      // destellos
      final bt = ((t - _conv) / .42).clamp(0.0, 1.0);
      final eo = Curves.easeOutCubic.transform(bt);
      for (final s in sparks) {
        final pos = c + Offset(cos(s.a), sin(s.a)) * (s.r * maxR * .7 * eo + 20);
        canvas.drawPath(
          sparklePath(pos, s.size * 3.2 * (1 - .4 * bt)),
          Paint()..color = _pc(s.hue).withValues(alpha: (1 - bt * bt).clamp(0.0, 1.0)),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_SplashPainter old) => old.t != t;
}
