import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../theme/colors.dart';

class ApiLandingPage extends StatefulWidget {
  final VoidCallback onLoginRedirect;

  const ApiLandingPage({
    super.key,
    required this.onLoginRedirect,
  });

  @override
  State<ApiLandingPage> createState() => _ApiLandingPageState();
}

class _ApiLandingPageState extends State<ApiLandingPage> {
  bool _isHoveringCta = false;
  bool _isHoveringLogin = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 800;

    return Scaffold(
      backgroundColor: const Color(0xFFF0EEE9), // Light Mode forzado
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Main Content
          Positioned.fill(
            child: SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // Header Navbar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              SvgPicture.asset(
                                'assets/logo.svg',
                                height: 32,
                                colorFilter: ColorFilter.mode(OhtliColors.stormyTeal, BlendMode.srcIn),
                              ),
                            ],
                          ),
                          MouseRegion(
                            onEnter: (_) => setState(() => _isHoveringLogin = true),
                            onExit: (_) => setState(() => _isHoveringLogin = false),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              child: TextButton(
                                onPressed: widget.onLoginRedirect,
                                style: TextButton.styleFrom(
                                  foregroundColor: OhtliColors.stormyTeal,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                ),
                                child: Text(
                                  'Iniciar sesión',
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                    decoration: _isHoveringLogin ? TextDecoration.underline : TextDecoration.none,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Hero Section
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: isMobile ? 24 : 48, vertical: isMobile ? 80 : 160),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [

                          Text(
                            'La nueva forma de entender la ciudad',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(
                              fontSize: isMobile ? 40 : 64,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF0A090C),
                              letterSpacing: -1.0,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 40), // Mas espacio entre titulo y desc
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 800), // Ligeramente mas ancho
                            child: Text(
                              'Construye con inteligencia geoespacial. Despliega y escala rápido. Analiza la geografía de la CDMX y toma decisiones basadas en datos para logística y marketing. Comienza ahora con una cuenta empresarial.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(
                                fontSize: isMobile ? 18 : 22, // Ligeramente mas grande
                                fontWeight: FontWeight.w400,
                                color: const Color(0xFF0A090C).withValues(alpha: 0.7),
                                height: 1.8, // Mas interlineado
                              ),
                            ),
                          ),
                          const SizedBox(height: 120), // Mas espacio antes de las cards
                          
                          // Dark Feature Cards Carousel
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back_ios_rounded, color: Color(0xFF0A090C)),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  hoverColor: Colors.transparent,
                                  highlightColor: Colors.transparent,
                                ),
                                onPressed: () {
                                  _scrollController.animateTo(
                                    _scrollController.offset - 364, // 340 + 24 spacing
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeInOut,
                                  );
                                },
                              ),
                              Expanded(
                                child: SingleChildScrollView(
                                  controller: _scrollController,
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      _buildGcpFeatureCard(
                                        title: 'Ohtli Enhanced Places API',
                                        subtitle: 'Entrega lugares de la CDMX con información enriquecida por varias fuentes de datos.',
                                        label: 'PLACES',
                                        gradientColors: [OhtliColors.cempasuchil, OhtliColors.stormyTeal],
                                        icon: Icons.place_rounded,
                                      ),
                                      const SizedBox(width: 24),
                                      _buildGcpFeatureCard(
                                        title: 'Layers Weight API',
                                        subtitle: 'Da valores de peso para la toma de decisiones de un lugar como seguridad, costo e incluso tiempo de visita.',
                                        label: 'DECISION MAKING',
                                        gradientColors: [OhtliColors.xoconostle, OhtliColors.cempasuchil],
                                        icon: Icons.layers_rounded,
                                      ),
                                      const SizedBox(width: 24),
                                      _buildGcpFeatureCard(
                                        title: 'Honeyspots API',
                                        subtitle: 'Para un lugar objetivo que le entregas, te da posibles locaciones similares o ideales en la CDMX.',
                                        label: 'LOCATIONS',
                                        gradientColors: [OhtliColors.stormyTeal, OhtliColors.cantera],
                                        icon: Icons.hive_rounded,
                                      ),
                                      const SizedBox(width: 24),
                                      _buildGcpFeatureCard(
                                        title: 'Marketing API',
                                        subtitle: 'Búsqueda avanzada: entrégale una marca y busca el SoV, SoS, TrafficShare y otras métricas vitales.',
                                        label: 'MARKETING',
                                        gradientColors: [OhtliColors.cantera, OhtliColors.xoconostle],
                                        icon: Icons.storefront_rounded,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF0A090C)),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  hoverColor: Colors.transparent,
                                  highlightColor: Colors.transparent,
                                ),
                                onPressed: () {
                                  _scrollController.animateTo(
                                    _scrollController.offset + 364,
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeInOut,
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 64),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGcpFeatureCard({
    required String title,
    required String subtitle,
    required String label,
    required List<Color> gradientColors,
    required IconData icon,
  }) {
    return Container(
      width: 340,
      height: 380,
      decoration: BoxDecoration(
        color: const Color(0xFF0A090C), // Onyx explicitly
        borderRadius: BorderRadius.circular(24),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Graphic abstract background
          Positioned(
            top: 40,
            left: 20,
            right: 20,
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: gradientColors.map((c) => c.withValues(alpha: 0.5)).toList(),
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(100), // Pill shape abstract
                boxShadow: [
                  BoxShadow(
                    color: gradientColors[0].withValues(alpha: 0.3),
                    blurRadius: 40,
                    spreadRadius: 10,
                  )
                ]
              ),
              child: Center(
                child: Icon(icon, color: const Color(0xFFF0EEE9), size: 48),
              ),
            ),
          ),
          
          // Content
          Positioned(
            bottom: 32,
            left: 32,
            right: 32,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.outfit(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFF0EEE9).withValues(alpha: 0.7),
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFF0EEE9),
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  subtitle,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    color: const Color(0xFFF0EEE9).withValues(alpha: 0.6),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
