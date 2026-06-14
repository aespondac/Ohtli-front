import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/colors.dart';

class Error403Page extends StatefulWidget {
  final VoidCallback onExploreHome;
  final VoidCallback onLoginRedirect;

  const Error403Page({
    super.key,
    required this.onExploreHome,
    required this.onLoginRedirect,
  });

  @override
  State<Error403Page> createState() => _Error403PageState();
}

class _Error403PageState extends State<Error403Page> {
  bool _isHoveringPrimary = false;
  bool _isHoveringSecondary = false;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 600;
    final bool isDark = OhtliSettings.instance.isDarkMode;
    final bool isGuest = FirebaseAuth.instance.currentUser == null;

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
                      color: OhtliColors.stormyTeal.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock_outline_rounded,
                      size: 44,
                      color: OhtliColors.stormyTeal,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Huge 403 Title
                  Text(
                    '403',
                    style: GoogleFonts.caprasimo(
                      fontSize: isMobile ? 80 : 110,
                      color: OhtliColors.stormyTeal,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Subtitle / Heading
                  Text(
                    'Bitácora restringida.',
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
                      'El aventurero ha decidido mantener esta bitácora bajo llave. Si eres co-autor o el destinatario de esta sorpresa, inicia sesión para acceder.',
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
                  // Action buttons
                  if (isGuest) ...[
                    // Show "Iniciar Sesión" (Primary) and "Explorar Inicio" (Secondary)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Iniciar Sesión button
                        MouseRegion(
                          onEnter: (_) => setState(() => _isHoveringPrimary = true),
                          onExit: (_) => setState(() => _isHoveringPrimary = false),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(30),
                              boxShadow: _isHoveringPrimary
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
                              onPressed: widget.onLoginRedirect,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: OhtliColors.stormyTeal,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                              ),
                              child: Text(
                                'iniciar sesión',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12.5,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Explorar Inicio button
                        MouseRegion(
                          onEnter: (_) => setState(() => _isHoveringSecondary = true),
                          onExit: (_) => setState(() => _isHoveringSecondary = false),
                          child: OutlinedButton(
                            onPressed: widget.onExploreHome,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: OhtliColors.stormyTeal,
                              side: const BorderSide(color: OhtliColors.stormyTeal, width: 1.5),
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                            child: Text(
                              'explorar inicio',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                fontSize: 12.5,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    // Already logged in but restricted: Just show "Explorar Inicio" (Primary)
                    MouseRegion(
                      onEnter: (_) => setState(() => _isHoveringPrimary = true),
                      onExit: (_) => setState(() => _isHoveringPrimary = false),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: _isHoveringPrimary
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
