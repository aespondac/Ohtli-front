import 'dart:math';
import 'package:flutter/material.dart';
import '../../../theme/colors.dart';

class ParticlesBackground extends StatefulWidget {
  const ParticlesBackground({super.key});

  @override
  State<ParticlesBackground> createState() => _ParticlesBackgroundState();
}

class _ParticlesBackgroundState extends State<ParticlesBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  List<Particle> _particles = [];
  final int _particleCount = 100;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..addListener(() {
        _updateParticles();
        setState(() {});
      })..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_particles.isEmpty) {
      final size = MediaQuery.of(context).size;
      _initParticles(size);
    }
  }

  void _initParticles(Size size) {
    _particles = List.generate(_particleCount, (index) {
      return Particle(
        x: _random.nextDouble() * size.width,
        y: _random.nextDouble() * size.height,
        vx: (_random.nextDouble() - 0.5) * 1.5,
        vy: (_random.nextDouble() - 0.5) * 1.5,
        color: _getRandomOhtliColor(),
        radius: _random.nextDouble() * 3 + 2,
      );
    });
  }

  Color _getRandomOhtliColor() {
    final colors = [
      OhtliColors.stormyTeal,
      OhtliColors.xoconostle,
      OhtliColors.cempasuchil,
      OhtliColors.cantera,
    ];
    return colors[_random.nextInt(colors.length)];
  }

  void _updateParticles() {
    if (!mounted) return;
    final size = MediaQuery.of(context).size;
    for (var particle in _particles) {
      particle.x += particle.vx;
      particle.y += particle.vy;

      if (particle.x < 0 || particle.x > size.width) particle.vx *= -1;
      if (particle.y < 0 || particle.y > size.height) particle.vy *= -1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF0EEE9), // Blanco Ohtli forzado
      child: CustomPaint(
        painter: ParticlesPainter(particles: _particles),
        size: Size.infinite,
      ),
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
  final double connectionDistance = 150.0;

  ParticlesPainter({required this.particles});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Draw lines
    for (int i = 0; i < particles.length; i++) {
      for (int j = i + 1; j < particles.length; j++) {
        final p1 = particles[i];
        final p2 = particles[j];
        final dx = p1.x - p2.x;
        final dy = p1.y - p2.y;
        final distance = sqrt(dx * dx + dy * dy);

        if (distance < connectionDistance) {
          final opacity = 1.0 - (distance / connectionDistance);
          linePaint.color = p1.color.withValues(alpha: opacity * 0.4);
          canvas.drawLine(Offset(p1.x, p1.y), Offset(p2.x, p2.y), linePaint);
        }
      }
    }

    // Draw particles
    for (var particle in particles) {
      paint.color = particle.color.withValues(alpha: 0.8);
      canvas.drawCircle(Offset(particle.x, particle.y), particle.radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant ParticlesPainter oldDelegate) => true;
}
