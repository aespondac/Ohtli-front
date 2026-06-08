import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../theme/colors.dart';
import 'widgets/particles_background.dart';

class LabLandingPage extends StatefulWidget {
  final VoidCallback onLoginRedirect;

  const LabLandingPage({
    super.key,
    required this.onLoginRedirect,
  });

  @override
  State<LabLandingPage> createState() => _LabLandingPageState();
}

class _LabLandingPageState extends State<LabLandingPage> {
  bool _isHoveringLogin = false;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 800;

    return Scaffold(
      // Forzamos un tema claro para esta página
      backgroundColor: const Color(0xFFF0EEE9), // Blanco Ohtli forzado
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Fondo animado de partículas
          Positioned.fill(
            child: ParticlesBackground(),
          ),

          // Main Content
          Positioned.fill(
            child: SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              SvgPicture.asset(
                                'assets/logo.svg',
                                height: 32,
                                colorFilter: const ColorFilter.mode(Color(0xFF0A090C), BlendMode.srcIn),
                              ),
                            ],
                          ),
                          MouseRegion(
                            onEnter: (_) => setState(() => _isHoveringLogin = true),
                            onExit: (_) => setState(() => _isHoveringLogin = false),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(30),
                                boxShadow: _isHoveringLogin
                                    ? [BoxShadow(color: const Color(0xFF0A090C).withValues(alpha: 0.2), blurRadius: 12, offset: const Offset(0, 4))]
                                    : null,
                              ),
                              child: ElevatedButton(
                                onPressed: widget.onLoginRedirect,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0A090C),
                                  foregroundColor: const Color(0xFFF0EEE9),
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.login_rounded, size: 16),
                                    const SizedBox(width: 8),
                                    Text(
                                      'iniciar sesión',
                                      style: GoogleFonts.outfit(fontWeight: FontWeight.w600, letterSpacing: 0.5),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Hero Section
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: isMobile ? 24 : 48, vertical: 80),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            'Creemos el futuro,\njuntos.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(
                              fontSize: isMobile ? 48 : 84,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0A090C),
                              height: 1.1,
                              letterSpacing: -1.5,
                            ),
                          ),
                          const SizedBox(height: 24),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 600),
                            child: Text(
                              'Ohtli Labs es nuestro espacio de creación e innovación. Prueba las funcionalidades en las que estamos trabajando antes que nadie, ayúdanos a mejorarlas y desbloquea medallas exclusivas en tu perfil.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(
                                fontSize: isMobile ? 18 : 22,
                                fontWeight: FontWeight.w400,
                                color: const Color(0xFF0A090C).withValues(alpha: 0.8),
                                height: 1.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 80),
                        ],
                      ),
                    ),

                    // Experimentos Section (Dark Container)
                    Container(
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        color: OhtliColors.cantera, // Bottom section in Cantera
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(40),
                          topRight: Radius.circular(40),
                        ),
                      ),
                      padding: EdgeInsets.symmetric(horizontal: isMobile ? 24 : 64, vertical: 64),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Nuevos experimentos',
                            style: GoogleFonts.outfit(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF0A090C), // Onyx explicitly
                            ),
                          ),
                          const SizedBox(height: 40),
                          Wrap(
                            spacing: 24,
                            runSpacing: 24,
                            alignment: WrapAlignment.center,
                            children: [
                              _buildExperimentCard(
                                title: 'Caza Lugares',
                                desc: 'Dada una dirección específica, consolida información de lugares a través de múltiples fuentes de datos.',
                                imageColor: OhtliColors.stormyTeal,
                                icon: Icons.travel_explore_rounded,
                              ),
                              _buildExperimentCard(
                                title: 'Descubre tu Vibe',
                                desc: 'A través de diversas preguntas, te develamos tu "vibe" y los lugares en la ciudad que te podrían gustar.',
                                imageColor: OhtliColors.xoconostle,
                                icon: Icons.auto_awesome_rounded,
                              ),
                              _buildExperimentCard(
                                title: 'Logros Únicos',
                                desc: 'Gana medallas exclusivas por tu participación en los experimentos y betas de Ohtli.',
                                imageColor: OhtliColors.cempasuchil,
                                icon: Icons.emoji_events_rounded,
                              ),
                            ],
                          ),
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

  Widget _buildExperimentCard({
    required String title,
    required String desc,
    required Color imageColor,
    required IconData icon,
  }) {
    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: const Color(0xFFF0EEE9), // Card background in CloudDancer (white/cream)
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF0A090C).withValues(alpha: 0.1)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Imagen Placeholder
          Container(
            height: 160,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  imageColor.withValues(alpha: 0.8),
                  imageColor.withValues(alpha: 0.4),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Center(
              child: Icon(icon, size: 64, color: const Color(0xFF0A090C).withValues(alpha: 0.5)),
            ),
          ),
          // Contenido
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0A090C),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  desc,
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    color: const Color(0xFF0A090C).withValues(alpha: 0.7),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: widget.onLoginRedirect,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0A090C),
                      side: BorderSide(color: const Color(0xFF0A090C).withValues(alpha: 0.2)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text(
                      'Unirse al experimento',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
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
