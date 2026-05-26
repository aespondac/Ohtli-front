import 'dart:async';
import 'dart:html' as html;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';

void main() {
  runApp(const OhtliApp());
}

class OhtliApp extends StatelessWidget {
  const OhtliApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ohtli | El viaje empieza aquí',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF0EEE9), // Cloud Dancer
        textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
      ),
      home: const ConstructionPage(),
    );
  }
}

class ConstructionPage extends StatefulWidget {
  const ConstructionPage({super.key});

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
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitted = false;
  bool _isHoveringSubmit = false;

  bool get _isOldDomain {
    try {
      final host = Uri.base.host.toLowerCase();
      final hasOldParam = Uri.base.queryParameters['old'] == 'true';
      return (host.contains('othli') && !host.contains('ohtli')) || hasOldParam;
    } catch (e) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    
    // Controlador de opacidad inicial para cargar el sitio de forma elegante
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward();

    // Rotación periódica de frases con efecto fade
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
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 600;

    // Colores Oficiales
    const colorStormyTeal = Color(0xFF2C666E);
    const colorOnyx = Color(0xFF0A090C);
    const colorCantera = Color(0xFFD1CDC4);
    const colorXoconostle = Color(0xFF6C3953);
    const colorCempasuchil = Color(0xFFFFB800);

    return Scaffold(
      body: FadeTransition(
        opacity: _fadeController,
        child: Stack(
          children: [
            // Líneas decorativas en el fondo que simulan un mapa/trazos de caminos
            Positioned.fill(
              child: CustomPaint(
                painter: RouteBackgroundPainter(colorCantera.withOpacity(0.95)),
              ),
            ),

            // Contenido Central
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CenterPlayground.alignment,
                  children: [
                    if (_isOldDomain)
                      _buildRedirectView(colorStormyTeal, colorOnyx, colorXoconostle, isMobile)
                    else
                      _buildMainView(colorStormyTeal, colorOnyx, colorXoconostle, isMobile),
                  ],
                ),
              ),
            ),

            // Footer con branding sutil
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
                    color: colorOnyx.withOpacity(0.4),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Si el logo SVG aún no está en la carpeta de assets, se muestra esta versión estilizada.
  Widget _buildLogoFallback(Color primaryColor, Color accentColor) {
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

  Widget _buildMainView(Color colorStormyTeal, Color colorOnyx, Color colorXoconostle, bool isMobile) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // LOGO EN EL CENTRO
        Container(
          constraints: const BoxConstraints(
            maxWidth: 280,
            maxHeight: 90, // Limitamos el alto a 90 para eliminar el aire vertical del SVG
          ),
          child: SvgPicture.asset(
            'assets/logo.svg',
            width: 240,
            fit: BoxFit.contain,
            colorFilter: ColorFilter.mode(colorStormyTeal, BlendMode.srcIn),
            placeholderBuilder: (BuildContext context) => _buildLogoFallback(colorStormyTeal, colorXoconostle),
            errorBuilder: (context, error, stackTrace) => _buildLogoFallback(colorStormyTeal, colorXoconostle),
          ),
        ),
        const SizedBox(height: 16),

        // FRASE DE VIAJE ROTATIVA
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
                fontWeight: FontWeight.w300, // Light (w300)
                color: colorOnyx,
                letterSpacing: 2.0,
                height: 1.4,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRedirectView(Color colorStormyTeal, Color colorOnyx, Color colorXoconostle, bool isMobile) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Oh - tli! en fuente Caprasimo gigante
        Text(
          'Oh - tli!',
          style: GoogleFonts.caprasimo(
            fontSize: isMobile ? 72 : 110,
            color: colorXoconostle,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 16),

        // Título más amigable
        Text(
          '¡no te preocupes, a todos nos pasa!',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: isMobile ? 22 : 28,
            fontWeight: FontWeight.w300,
            color: colorOnyx,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 20),

        // Mensaje amigable
        Text(
          'Escribiste Othli en lugar de Ohtli (con la "h" antes de la "t"). En náhuatl, "ohtli" significa camino y el camino correcto te está esperando.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 14,
            height: 1.6,
            fontWeight: FontWeight.w300,
            color: colorOnyx.withOpacity(0.75),
          ),
        ),
        const SizedBox(height: 40),

        // Botón de redirección
        MouseRegion(
          onEnter: (_) => setState(() => _isHoveringSubmit = true),
          onExit: (_) => setState(() => _isHoveringSubmit = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 220,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              boxShadow: _isHoveringSubmit
                  ? [
                      BoxShadow(
                        color: colorStormyTeal.withOpacity(0.2),
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
                backgroundColor: colorStormyTeal,
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
}

// Pintor personalizado para dibujar líneas de ruta minimalistas (como caminos de un mapa urbano)
class RouteBackgroundPainter extends CustomPainter {
  final Color lineColor;

  RouteBackgroundPainter(this.lineColor);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8; // Aumentado el grosor para mayor visibilidad

    final path = Path();

    // Dibujar caminos o trazos de mapa estilizados
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

    // Dibujar el camino discontinuo (punteado/dashed)
    const double dashLength = 8.0; // Guión ligeramente más largo
    const double gapLength = 5.0; // Espaciado menor para mayor visibilidad

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

class CenterPlayground {
  static const alignment = CrossAxisAlignment.center;
}
