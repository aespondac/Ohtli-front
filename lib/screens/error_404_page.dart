import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/colors.dart';

class Error404Page extends StatefulWidget {
  final VoidCallback onExploreHome;

  const Error404Page({
    super.key,
    required this.onExploreHome,
  });

  @override
  State<Error404Page> createState() => _Error404PageState();
}

class _Error404PageState extends State<Error404Page> {
  bool _isHoveringBtn = false;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 600;
    final bool isDark = OhtliSettings.instance.isDarkMode;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121214) : OhtliColors.cloudDancer,
      body: Stack(
        children: [
          // Background map lines
          Positioned.fill(
            child: CustomPaint(
              painter: _RouteBackgroundPainter(
                isDark 
                    ? const Color(0xFF222226) 
                    : OhtliColors.cantera.withValues(alpha: 0.95)
              ),
            ),
          ),

          // Central content
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Icon
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: OhtliColors.xoconostle.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.explore_off_outlined,
                      size: 44,
                      color: OhtliColors.xoconostle,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Huge 404 Title
                  Text(
                    '404',
                    style: GoogleFonts.caprasimo(
                      fontSize: isMobile ? 80 : 110,
                      color: OhtliColors.xoconostle,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Subtitle / Heading
                  Text(
                    'Este viaje ha tomado otro rumbo.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 18 : 22,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : OhtliColors.onyx,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Message description
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Text(
                      'No logramos encontrar la bitácora que buscas. Puede que el enlace esté roto o que el viaje haya sido eliminado por su autor.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: isDark ? Colors.white60 : OhtliColors.onyx.withValues(alpha: 0.65),
                        height: 1.5,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                  const SizedBox(height: 36),
                  // Action button with subtle hover feedback
                  MouseRegion(
                    onEnter: (_) => setState(() => _isHoveringBtn = true),
                    onExit: (_) => setState(() => _isHoveringBtn = false),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: _isHoveringBtn
                            ? [
                                BoxShadow(
                                  color: OhtliColors.stormyTeal.withValues(alpha: 0.25),
                                  blurRadius: 12,
                                  offset: const Offset(0, 5),
                                )
                              ]
                            : [],
                      ),
                      child: ElevatedButton(
                        onPressed: widget.onExploreHome,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: OhtliColors.stormyTeal,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: Text(
                          'explorar inicio',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            letterSpacing: 2.0,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Footer branding
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'ohtli  •  cdmx',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 4.0,
                  color: isDark ? Colors.white30 : OhtliColors.onyx.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteBackgroundPainter extends CustomPainter {
  final Color lineColor;

  _RouteBackgroundPainter(this.lineColor);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    final path = Path();

    path.moveTo(0, size.height * 0.25);
    path.quadraticBezierTo(
      size.width * 0.35,
      size.height * 0.2,
      size.width * 0.5,
      size.height * 0.45,
    );
    path.quadraticBezierTo(
      size.width * 0.65,
      size.height * 0.7,
      size.width,
      size.height * 0.65,
    );

    path.moveTo(size.width * 0.2, size.height);
    path.lineTo(size.width * 0.8, 0);

    const double dashLength = 8.0;
    const double gapLength = 5.0;

    for (final PathMetric metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final double nextDistance = distance + dashLength;
        final Path extract = metric.extractPath(distance, nextDistance);
        canvas.drawPath(extract, paint);
        distance = nextDistance + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
