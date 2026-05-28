import 'dart:async';
import 'dart:ui';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/colors.dart';

class ConstructionPage extends StatefulWidget {
  final VoidCallback onLoginClick;
  const ConstructionPage({super.key, required this.onLoginClick});

  @override
  State<ConstructionPage> createState() => _ConstructionPageState();
}

class _ConstructionPageState extends State<ConstructionPage> with SingleTickerProviderStateMixin {
  final List<String> _travelPhrases = [
    'el viaje empieza aquí',
    'estamos preparando todo',
    'trazando tus rutas ideales',
    'diseñando tu camino por la CDMX',
    'explorando nuevas perspectivas',
  ];

  int _currentPhraseIndex = 0;
  late Timer _phraseTimer;
  late AnimationController _fadeController;
  bool _isHoveringEnter = false;

  bool get _isOldDomain {
    try {
      final host = Uri.base.host.toLowerCase();
      final hasOldParam = Uri.base.queryParameters['old'] == 'true';
      final isFirebaseDomain = host.contains('web.app') || host.contains('firebaseapp.com');
      return ((host.contains('othli') && !host.contains('ohtli') && !isFirebaseDomain)) || hasOldParam;
    } catch (e) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward();

    _phraseTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (mounted) {
        setState(() {
          _currentPhraseIndex = (_currentPhraseIndex + 1) % _travelPhrases.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _phraseTimer.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 600;

    return Scaffold(
      body: FadeTransition(
        opacity: _fadeController,
        child: Stack(
          children: [
            // Líneas de mapa decorativas
            Positioned.fill(
              child: CustomPaint(
                painter: RouteBackgroundPainter(OhtliColors.cantera.withOpacity(0.95)),
              ),
            ),

            // Botón flotante superior de "Iniciar Sesión" (Solo si no es el dominio de desvío)
            if (!_isOldDomain)
              Positioned(
                top: 24,
                right: 24,
                child: MouseRegion(
                  onEnter: (_) => setState(() => _isHoveringEnter = true),
                  onExit: (_) => setState(() => _isHoveringEnter = false),
                  child: TextButton(
                    onPressed: widget.onLoginClick,
                    style: TextButton.styleFrom(
                      foregroundColor: _isHoveringEnter ? OhtliColors.xoconostle : OhtliColors.stormyTeal,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    child: Text(
                      'iniciar sesión',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 2.0,
                      ),
                    ),
                  ),
                ),
              ),

            // Contenido Central
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (_isOldDomain)
                      _buildRedirectView(isMobile)
                    else
                      _buildMainView(isMobile),
                  ],
                ),
              ),
            ),

            // Footer
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
                    color: OhtliColors.onyx.withOpacity(0.4),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainView(bool isMobile) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          constraints: const BoxConstraints(
            maxWidth: 280,
            maxHeight: 90,
          ),
          child: SvgPicture.asset(
            'assets/logo.svg',
            width: 240,
            fit: BoxFit.contain,
            placeholderBuilder: (BuildContext context) => _buildLogoFallback(OhtliColors.stormyTeal),
            errorBuilder: (context, error, stackTrace) => _buildLogoFallback(OhtliColors.stormyTeal),
          ),
        ),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 800),
          transitionBuilder: (Widget child, Animation<double> animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.0, 0.1),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: Container(
            key: ValueKey<int>(_currentPhraseIndex),
            child: Text(
              _travelPhrases[_currentPhraseIndex],
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: isMobile ? 22 : 28,
                fontWeight: FontWeight.w300,
                color: OhtliColors.onyx,
                letterSpacing: 2.0,
                height: 1.4,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRedirectView(bool isMobile) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Oh - tli!',
          style: GoogleFonts.caprasimo(
            fontSize: isMobile ? 72 : 110,
            color: OhtliColors.xoconostle,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '¡no te preocupes, a todos nos pasa!',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: isMobile ? 22 : 28,
            fontWeight: FontWeight.w300,
            color: OhtliColors.onyx,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Escribiste Othli en lugar de Ohtli (con la "h" antes de la "t"). En náhuatl, "ohtli" significa camino y el camino correcto te está esperando.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 14,
            height: 1.6,
            fontWeight: FontWeight.w300,
            color: OhtliColors.onyx.withOpacity(0.75),
          ),
        ),
        const SizedBox(height: 40),
        MouseRegion(
          onEnter: (_) => setState(() => _isHoveringEnter = true),
          onExit: (_) => setState(() => _isHoveringEnter = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 220,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              boxShadow: _isHoveringEnter
                  ? [
                      BoxShadow(
                        color: OhtliColors.stormyTeal.withOpacity(0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : [],
            ),
            child: ElevatedButton(
              onPressed: () {
                html.window.location.href = 'https://ohtli.quest';
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: OhtliColors.stormyTeal,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: Text(
                'seguir mi camino',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w400,
                  fontSize: 14,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLogoFallback(Color primaryColor) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: primaryColor.withOpacity(0.2),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(8),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: primaryColor.withOpacity(0.06),
          border: Border.all(
            color: primaryColor,
            width: 1.5,
          ),
        ),
        child: Icon(
          Icons.explore_outlined,
          color: primaryColor,
          size: 48,
        ),
      ),
    );
  }
}

// Pintor personalizado para dibujar líneas de ruta minimalistas
class RouteBackgroundPainter extends CustomPainter {
  final Color lineColor;

  RouteBackgroundPainter(this.lineColor);

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
