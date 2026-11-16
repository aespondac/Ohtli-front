import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/colors.dart';

/// Portada del teléfono sin sesión: la primera pantalla de Ohtli en móvil.
///
/// Mismo lenguaje que la portada de web (fondo crema, Outfit, collage de fotos de la
/// CDMX y botón cempasúchil), pero en una sola pantalla y con lo esencial: crear cuenta,
/// iniciar sesión o explorar lugares. Las fotos y la fuente vienen incluidas en la app
/// (assets/cover, assets/google_fonts) para que se vea completa en cuanto arranca.
class MobileWelcomePage extends StatelessWidget {
  final VoidCallback onLoginClick;
  final VoidCallback onJoinClick;
  final VoidCallback? onExplorePlaces;

  const MobileWelcomePage({
    super.key,
    required this.onLoginClick,
    required this.onJoinClick,
    this.onExplorePlaces,
  });

  static const String mainPhoto = 'assets/cover/bellas_artes.jpg';
  static const String secondaryPhoto = 'assets/cover/trajinera.jpg';

  /// Empieza a decodificar las fotos antes de mostrar la portada.
  static Future<void> precache(BuildContext context) => Future.wait([
        precacheImage(const AssetImage(mainPhoto), context),
        precacheImage(const AssetImage(secondaryPhoto), context),
      ]).then((_) {}, onError: (_) {});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            // El collage ocupa lo que sobre; en teléfonos bajos se encoge para que todo quepa
            // sin desplazarse (y si aun así no cabe, la pantalla se desplaza).
            final collageHeight = (c.maxHeight * 0.40).clamp(200.0, 360.0);
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: c.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        label: 'Ohtli',
                        child: SvgPicture.asset(
                          'assets/logo.svg',
                          height: 24,
                          colorFilter: const ColorFilter.mode(OhtliColors.stormyTeal, BlendMode.srcIn),
                        ),
                      ),
                      const SizedBox(height: 22),
                      _Collage(height: collageHeight),
                      const SizedBox(height: 28),
                      Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(text: 'Tu camino por la\nCiudad de México, '),
                            TextSpan(text: 'a tu medida.', style: TextStyle(color: OhtliColors.accentText)),
                          ],
                        ),
                        style: GoogleFonts.outfit(
                          fontSize: 33,
                          fontWeight: FontWeight.w800,
                          color: OhtliColors.onyx,
                          height: 1.04,
                          letterSpacing: -0.9,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Museos, cafés, cantinas y miradores convertidos en rutas según tu tiempo, '
                        'tu presupuesto y tus gustos.',
                        style: GoogleFonts.inter(fontSize: 15, color: OhtliColors.subtleText, height: 1.5),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: onJoinClick,
                          icon: const Icon(Icons.alt_route_rounded, size: 19),
                          label: const Text('Crea tu ruta gratis'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: OhtliColors.cempasuchil,
                            foregroundColor: const Color(0xFF1A120B),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 17),
                            shape: const StadiumBorder(),
                            textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: onLoginClick,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: OhtliColors.onyx,
                            padding: const EdgeInsets.symmetric(vertical: 17),
                            side: BorderSide(color: OhtliColors.onyx.withValues(alpha: 0.18)),
                            shape: const StadiumBorder(),
                            textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 16),
                          ),
                          child: const Text('Iniciar sesión'),
                        ),
                      ),
                      if (onExplorePlaces != null) ...[
                        const SizedBox(height: 6),
                        Center(
                          child: TextButton.icon(
                            onPressed: onExplorePlaces,
                            icon: const Icon(Icons.explore_rounded, size: 18),
                            label: const Text('Explorar lugares sin cuenta'),
                            style: TextButton.styleFrom(
                              foregroundColor: OhtliColors.accentText,
                              textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Collage de la portada de web en tamaño de teléfono: foto principal, una secundaria
/// con borde y dos etiquetas flotantes.
class _Collage extends StatelessWidget {
  final double height;
  const _Collage({required this.height});

  @override
  Widget build(BuildContext context) {
    final h = height;
    return SizedBox(
      height: h,
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: w * 0.16,
                top: 0,
                right: 0,
                bottom: h * 0.16,
                child: const _Photo(MobileWelcomePage.mainPhoto, radius: 30),
              ),
              Positioned(
                left: 0,
                bottom: 0,
                width: w * 0.46,
                height: h * 0.46,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: OhtliColors.cloudDancer, width: 5),
                  ),
                  child: const _Photo(MobileWelcomePage.secondaryPhoto, radius: 21),
                ),
              ),
              Positioned(
                left: w * 0.10,
                top: h * 0.07,
                child: const _Chip(
                  icon: Icons.auto_awesome_rounded,
                  title: 'Hecho para ti',
                  subtitle: 'Según tus gustos',
                  color: OhtliColors.stormyTeal,
                ),
              ),
              Positioned(
                right: 6,
                bottom: h * 0.04,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: math.max(150, w * 0.52)),
                  child: const _Chip(
                    icon: Icons.alt_route_rounded,
                    title: 'Ruta de 4 paradas',
                    subtitle: 'Centro Histórico · 5 h',
                    color: OhtliColors.cempasuchil,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Photo extends StatelessWidget {
  final String asset;
  final double radius;
  const _Photo(this.asset, {required this.radius});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: ColoredBox(
        color: OhtliColors.stormyTeal.withValues(alpha: 0.2),
        child: Image.asset(asset, fit: BoxFit.cover, width: double.infinity, height: double.infinity),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  const _Chip({required this.icon, required this.title, required this.subtitle, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 9, 14, 9),
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.16), blurRadius: 22, offset: const Offset(0, 9)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 9),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.w700, color: OhtliColors.onyx),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 11, color: OhtliColors.subtleText),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
