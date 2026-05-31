import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../theme/colors.dart';

class MobileWelcomePage extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onLoginClick;
  final VoidCallback onJoinClick;

  const MobileWelcomePage({
    super.key,
    required this.onBack,
    required this.onLoginClick,
    required this.onJoinClick,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Imagen de fondo full screen
          Positioned.fill(
            child: Image.asset(
              'assets/bg.png',
              fit: BoxFit.cover,
              alignment: const Alignment(-0.4, 0.0),
            ),
          ),
          // Overlay oscuro
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.45),
            ),
          ),
          
          // Contenido scrollable y responsivo para evitar desbordamientos y asegurar accesibilidad
          Positioned.fill(
            child: SafeArea(
              child: CustomScrollView(
                slivers: [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Icono brújula superior izquierdo (tappable para volver)
                          GestureDetector(
                            onTap: onBack,
                            child: SvgPicture.asset(
                              'assets/icon_isologo.svg',
                              width: 52,
                              height: 52,
                              colorFilter: ColorFilter.mode(
                                OhtliColors.cloudDancer,
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                          
                          const Spacer(), // Empuja el contenido inferior hacia abajo si hay espacio suficiente
                          
                          // MÉXICO DESDE TU PROPIA VIBE
                          Text(
                            'MÉXICO DESDE\nTU PROPIA\nVIBE',
                            style: GoogleFonts.bebasNeue(
                              fontSize: 52,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              height: 1.05,
                              letterSpacing: 2.0,
                            ),
                          ),
                          const SizedBox(height: 48),

                          // BOTÓN: Unete al viaje
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: onJoinClick,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: OhtliColors.stormyTeal,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                              ),
                              child: Text(
                                'Unete al viaje',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // LINK: Iniciar sesión
                          Center(
                            child: TextButton(
                              onPressed: onLoginClick,
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                              ),
                              child: Text(
                                'Iniciar sesión',
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w400,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
