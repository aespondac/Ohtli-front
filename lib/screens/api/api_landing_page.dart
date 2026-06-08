import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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

class _ApiLandingPageState extends State<ApiLandingPage> with SingleTickerProviderStateMixin {
  late AnimationController _bgController;
  bool _isHoveringLogin = false;
  bool _isHoveringCta = false;

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 25),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _bgController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 800;
    final isDark = OhtliSettings.instance.isDarkMode;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0A0C) : const Color(0xFFEFEFEF),
      body: Stack(
        children: [
          // Animated Background Elements (Geometric for API)
          AnimatedBuilder(
            animation: _bgController,
            builder: (context, child) {
              return Stack(
                children: [
                  Positioned(
                    top: -150 - (30 * _bgController.value),
                    right: -100 + (80 * _bgController.value),
                    child: Transform.rotate(
                      angle: _bgController.value * 0.5,
                      child: Container(
                        width: 700,
                        height: 700,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(100),
                          color: const Color(0xFF2B5B84).withValues(alpha: 0.1), // Corporate Blue touch
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -250 + (60 * _bgController.value),
                    left: -150 - (40 * _bgController.value),
                    child: Container(
                      width: 600,
                      height: 600,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: OhtliColors.stormyTeal.withValues(alpha: 0.15),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          
          // Glassmorphism overlay
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
              child: Container(color: Colors.transparent),
            ),
          ),

          // Main Content
          SafeArea(
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
                          Icon(Icons.data_object_rounded, size: 32, color: OhtliColors.stormyTeal),
                          const SizedBox(width: 12),
                          Text(
                            'Ohtli API',
                            style: GoogleFonts.outfit(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white : OhtliColors.onyx,
                              letterSpacing: -0.5,
                            ),
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
                                ? [BoxShadow(color: OhtliColors.stormyTeal.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))]
                                : [],
                          ),
                          child: ElevatedButton(
                            onPressed: widget.onLoginRedirect,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isDark ? Colors.white : OhtliColors.onyx,
                              foregroundColor: isDark ? OhtliColors.onyx : Colors.white,
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
                                  style: GoogleFonts.inter(fontWeight: FontWeight.w600, letterSpacing: 0.5),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(horizontal: isMobile ? 24 : 48, vertical: 40),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2B5B84).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFF2B5B84).withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              'SOLUCIONES PARA EMPRESAS',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF3A7CA5), // Brighter blue
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Inteligencia Geográfica\npara tu Negocio.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.caprasimo(
                              fontSize: isMobile ? 42 : 76,
                              color: isDark ? Colors.white : OhtliColors.onyx,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 24),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 700),
                            child: Text(
                              'Consume las APIs de Ohtli para obtener insights comerciales invaluables basados en la geografía y el comportamiento turístico en la CDMX. Transforma datos en estrategias.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 16 : 20,
                                color: isDark ? Colors.white70 : OhtliColors.onyx.withValues(alpha: 0.7),
                                height: 1.6,
                              ),
                            ),
                          ),
                          const SizedBox(height: 48),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 24,
                            runSpacing: 24,
                            children: [
                              _buildFeatureCard(
                                icon: Icons.insights_rounded,
                                title: 'Business Insights',
                                desc: 'Descubre patrones de movilidad y puntos calientes turísticos.',
                                isDark: isDark,
                              ),
                              _buildFeatureCard(
                                icon: Icons.map_rounded,
                                title: 'Geografía CDMX',
                                desc: 'Mapeo detallado y actualizado de la Ciudad de México.',
                                isDark: isDark,
                              ),
                              _buildFeatureCard(
                                icon: Icons.account_balance_wallet_rounded,
                                title: 'Créditos Flexibles',
                                desc: 'Inicia sesión para convertir tu cuenta y agregar créditos según tu uso.',
                                isDark: isDark,
                              ),
                            ],
                          ),
                          const SizedBox(height: 64),
                          MouseRegion(
                            onEnter: (_) => setState(() => _isHoveringCta = true),
                            onExit: (_) => setState(() => _isHoveringCta = false),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              transform: Matrix4.identity()..scale(_isHoveringCta ? 1.05 : 1.0),
                              child: ElevatedButton(
                                onPressed: widget.onLoginRedirect,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: OhtliColors.stormyTeal,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
                                ),
                                child: Text(
                                  'Convertir a Cuenta Empresarial',
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
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

  Widget _buildFeatureCard({required IconData icon, required String title, required String desc, required bool isDark}) {
    return Container(
      width: 280,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.white,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.1) : OhtliColors.onyx.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: isDark ? Colors.white : OhtliColors.onyx, size: 28),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : OhtliColors.onyx,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            desc,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: isDark ? Colors.white60 : OhtliColors.onyx.withValues(alpha: 0.6),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
