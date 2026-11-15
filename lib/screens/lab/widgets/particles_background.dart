import 'dart:math';
import 'package:flutter/material.dart';
import '../../../theme/colors.dart';

/// Fondo de partículas conectadas de la portada de Labs.
///
/// - Usa el fondo del tema (antes forzaba un blanco claro aun en modo oscuro y el texto del hero
///   quedaba sobre gris).
/// - Solo repinta el lienzo en cada cuadro (CustomPainter con `repaint`), sin reconstruir widgets.
/// - Menos partículas en pantallas chicas, y quietas si la persona pidió reducir el movimiento.
/// - Al cambiar el tamaño de la ventana las partículas vuelven al área visible (antes podían
///   quedar atrapadas fuera, rebotando en cada cuadro).
class ParticlesBackground extends StatefulWidget {
  const ParticlesBackground({super.key});

  @override
  State<ParticlesBackground> createState() => _ParticlesBackgroundState();
}

class _ParticlesBackgroundState extends State<ParticlesBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final List<Particle> _particles = [];
  final Random _random = Random();
  Size _size = Size.zero;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 10))..addListener(_step);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  void _ensureParticles(Size size) {
    if (size.isEmpty) return;
    final target = size.width < 600 ? 40 : 90;
    if (_particles.length != target) {
      _particles
        ..clear()
        ..addAll(List.generate(target, (_) => _newParticle(size)));
    } else if (size != _size) {
      for (final p in _particles) {
        p.x = p.x.clamp(0, size.width);
        p.y = p.y.clamp(0, size.height);
      }
    }
    _size = size;
  }

  Particle _newParticle(Size size) => Particle(
        x: _random.nextDouble() * size.width,
        y: _random.nextDouble() * size.height,
        vx: (_random.nextDouble() - 0.5) * 1.5,
        vy: (_random.nextDouble() - 0.5) * 1.5,
        color: const [OhtliColors.stormyTeal, OhtliColors.xoconostle, OhtliColors.cempasuchil, OhtliColors.cantera][_random.nextInt(4)],
        radius: _random.nextDouble() * 3 + 2,
      );

  void _step() {
    if (_size.isEmpty) return;
    for (final p in _particles) {
      p.x += p.vx;
      p.y += p.vy;
      if (p.x < 0 || p.x > _size.width) {
        p.vx = -p.vx;
        p.x = p.x.clamp(0, _size.width);
      }
      if (p.y < 0 || p.y > _size.height) {
        p.vy = -p.vy;
        p.y = p.y.clamp(0, _size.height);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: OhtliColors.cloudDancer,
      child: LayoutBuilder(builder: (context, constraints) {
        _ensureParticles(constraints.biggest);
        return RepaintBoundary(
          child: CustomPaint(
            painter: ParticlesPainter(particles: _particles, repaint: _controller),
            size: Size.infinite,
          ),
        );
      }),
    );
  }
}

class Particle {
  double x;
  double y;
  double vx;
  double vy;
  Color color;
  double radius;

  Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.color,
    required this.radius,
  });
}

class ParticlesPainter extends CustomPainter {
  final List<Particle> particles;
  static const double connectionDistance = 150.0;

  ParticlesPainter({required this.particles, super.repaint});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    const maxD2 = connectionDistance * connectionDistance;

    for (int i = 0; i < particles.length; i++) {
      final p1 = particles[i];
      for (int j = i + 1; j < particles.length; j++) {
        final p2 = particles[j];
        final dx = p1.x - p2.x;
        if (dx.abs() > connectionDistance) continue;
        final dy = p1.y - p2.y;
        final d2 = dx * dx + dy * dy;
        if (d2 < maxD2) {
          final opacity = 1.0 - (sqrt(d2) / connectionDistance);
          linePaint.color = p1.color.withValues(alpha: opacity * 0.4);
          canvas.drawLine(Offset(p1.x, p1.y), Offset(p2.x, p2.y), linePaint);
        }
      }
    }

    for (final particle in particles) {
      paint.color = particle.color.withValues(alpha: 0.8);
      canvas.drawCircle(Offset(particle.x, particle.y), particle.radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant ParticlesPainter oldDelegate) => oldDelegate.particles != particles;
}
