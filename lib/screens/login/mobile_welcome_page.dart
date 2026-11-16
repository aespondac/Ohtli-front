import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/colors.dart';

/// Portada del teléfono sin sesión: la primera pantalla de Ohtli en móvil.
///
/// Foto de la ciudad a toda la pantalla con el lema y las dos acciones abajo, con la
/// estética de la tarjeta de foto de web (AuthShell): esquinas redondeadas sobre el fondo
/// crema, degradado oscuro, Outfit en blanco y "a tu medida." en xoconostle. La foto viene
/// incluida en la app (assets/cover, recortada en vertical) para que se vea al instante.
class MobileWelcomePage extends StatelessWidget {
  final VoidCallback onLoginClick;
  final VoidCallback onJoinClick;

  const MobileWelcomePage({
    super.key,
    required this.onLoginClick,
    required this.onJoinClick,
  });

  static const String photo = 'assets/cover/bellas_artes.jpg';

  /// Empieza a decodificar la foto antes de mostrar la portada.
  static Future<void> precache(BuildContext context) =>
      precacheImage(const AssetImage(photo), context).then((_) {}, onError: (_) {});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(color: OhtliColors.stormyTeal.withValues(alpha: 0.35)),
                Image.asset(
                  photo,
                  fit: BoxFit.cover,
                  alignment: const Alignment(0, -0.2),
                  excludeFromSemantics: true,
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0, 0.45, 1],
                      colors: [
                        Colors.black.withValues(alpha: 0.18),
                        Colors.black.withValues(alpha: 0.30),
                        Colors.black.withValues(alpha: 0.82),
                      ],
                    ),
                  ),
                ),
                // Contenido: se desplaza si el teléfono es muy bajo o la letra es grande
                LayoutBuilder(
                  builder: (context, c) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: c.maxHeight),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(26, 28, 26, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            SvgPicture.asset(
                              'assets/logo.svg',
                              height: 30,
                              colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                              semanticsLabel: 'Ohtli',
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 48),
                                Text.rich(
                                  const TextSpan(
                                    children: [
                                      TextSpan(text: 'Tu camino por la Ciudad de México, '),
                                      TextSpan(
                                        text: 'a tu medida.',
                                        style: TextStyle(color: OhtliColors.accentLight),
                                      ),
                                    ],
                                  ),
                                  style: GoogleFonts.outfit(
                                    fontSize: 40,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    height: 1.04,
                                    letterSpacing: -1.2,
                                  ),
                                ),
                                const SizedBox(height: 28),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: onJoinClick,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: OhtliColors.accentFill,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(vertical: 17),
                                      shape: const StadiumBorder(),
                                      textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 16.5),
                                    ),
                                    child: const Text('Únete al viaje'),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                SizedBox(
                                  width: double.infinity,
                                  child: TextButton(
                                    onPressed: onLoginClick,
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 15),
                                      shape: const StadiumBorder(),
                                      textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
                                    ),
                                    child: const Text('Iniciar sesión'),
                                  ),
                                ),
                              ],
                            ),
                          ],
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
    );
  }
}
