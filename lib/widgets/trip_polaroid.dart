import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/trip_model.dart';
import '../services/trip_service.dart';
import '../theme/cdmx_photos.dart';
import '../theme/colors.dart';

/// Fotos y paradas de un viaje para las tarjetas (portada + fotos de sus paradas).
class TripPhotoInfo {
  final List<String> photos;
  final int stops;
  const TripPhotoInfo(this.photos, this.stops);
}

/// Carga perezosa (y en caché) de las fotos de un viaje para las tarjetas tipo polaroid.
class TripPhotos {
  TripPhotos._();
  static final Map<String, Future<TripPhotoInfo>> _cache = {};

  static String _cover(Trip trip) => CdmxPhotos.tripCover(trip.coverUrl, trip.id.hashCode);

  /// Lo que se puede mostrar al instante (solo la portada), sin esperar al contenido.
  static TripPhotoInfo initial(Trip trip) => TripPhotoInfo([_cover(trip)], 0);

  static Future<TripPhotoInfo> load(Trip trip) {
    final key = '${trip.userId}/${trip.id}/${trip.updatedAt.millisecondsSinceEpoch}';
    return _cache[key] ??= _load(trip);
  }

  static Future<TripPhotoInfo> _load(Trip trip) async {
    final photos = <String>[_cover(trip)];
    var stops = 0;
    try {
      final content = await TripService().getTripContent(trip.userId, trip.id);
      for (final s in content?.sections ?? const <TripSection>[]) {
        String? url;
        if (s is PlaceSection) {
          stops++;
          // Solo fotos de la parada: una de referencia es de otro lugar (el Soumaya en un museo).
          url = (s.coverUrl?.isNotEmpty ?? false) ? s.coverUrl : (s.ownMainPhotoUrl.isNotEmpty ? s.ownMainPhotoUrl : null);
        } else if (s is TextImageSection && s.imageUrl.isNotEmpty) {
          url = s.imageUrl;
        }
        if (url != null && url.isNotEmpty && !photos.contains(url) && photos.length < 3) photos.add(url);
      }
    } catch (_) {
      // Sin permiso o sin conexión: basta con la portada
    }
    return TripPhotoInfo(photos, stops);
  }
}

/// Imagen que acepta URLs normales o `data:` (base64).
class OhtliPhoto extends StatelessWidget {
  final String url;
  final BoxFit fit;
  const OhtliPhoto(this.url, {super.key, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(color: OhtliColors.cantera.withValues(alpha: 0.35));
    if (url.isEmpty) return placeholder;
    if (url.startsWith('data:')) {
      try {
        return Image.memory(base64Decode(url.split(',').last), fit: fit, gaplessPlayback: true);
      } catch (_) {
        return placeholder;
      }
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 250),
      placeholder: (_, _) => placeholder,
      errorWidget: (_, _, _) => placeholder,
    );
  }
}

/// Una foto de la pila: esquinas redondeadas y sombra, como las fotos de las paradas del visor.
class PolaroidPrint extends StatelessWidget {
  final String? url;
  final double width;
  final double height;
  /// Boca abajo: se ve el reverso del papel (para regalos sin abrir).
  final bool faceDown;
  final Widget? overlay;

  const PolaroidPrint({super.key, this.url, required this.width, required this.height, this.faceDown = false, this.overlay});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: faceDown ? const Color(0xFFF4EEE3) : OhtliColors.cantera,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.16), blurRadius: 14, offset: const Offset(0, 6)),
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 2, offset: const Offset(0, 1)),
        ],
      ),
      child: faceDown
          ? Center(
              child: Opacity(
                opacity: 0.18,
                child: SvgPicture.asset(
                  'assets/icon_isologo.svg',
                  width: width * 0.32,
                  colorFilter: const ColorFilter.mode(OhtliColors.stormyTeal, BlendMode.srcIn),
                ),
              ),
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  OhtliPhoto(url ?? ''),
                  if (overlay != null) overlay!,
                ],
              ),
            ),
    );
  }
}

/// Pila de hasta 3 polaroids inclinadas como las fotos del visor: al pasar el cursor se abren en abanico.
class PolaroidStack extends StatelessWidget {
  final List<String> photos;
  final bool spread;
  final bool faceDown;
  /// Proporción de la foto frontal respecto al espacio disponible.
  final double scale;
  final Widget? frontOverlay;
  /// Posición vertical de la pila: -1 arriba, 0 centrada, 1 apoyada abajo.
  final double align;
  /// Ancho máximo de cada foto respecto al ancho disponible.
  final double maxWidthFraction;
  /// Si se indica, cada foto mide este ancho (fracción) y toda la altura disponible.
  final double? fillWidthFraction;

  const PolaroidStack({
    super.key,
    required this.photos,
    this.spread = false,
    this.faceDown = false,
    this.scale = 0.78,
    this.frontOverlay,
    this.align = 0,
    this.maxWidthFraction = 0.4,
    this.fillWidthFraction,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      // Tamaño que cabe completo (incluido el giro) dentro del recuadro
      final h = c.maxHeight * scale;
      final fill = fillWidthFraction;
      final w = fill != null ? c.maxWidth * fill : (h * 0.75).clamp(0.0, c.maxWidth * maxWidthFraction);
      final ph = fill != null ? h : w / 0.75;
      // Siempre se ven 3 hojas: si faltan fotos, las de atrás son papel en blanco
      final list = photos.isEmpty ? <String>[''] : photos.take(3).toList();
      final count = faceDown ? 3 : (list.length == 1 ? 2 : list.length);
      const back = [
        // (giro en vueltas, desplazamiento x relativo) cerrado / abierto
        [-0.018, -0.13, -0.028, -0.3],
        [0.016, 0.12, 0.026, 0.3],
      ];
      final children = <Widget>[];
      for (var i = count - 1; i >= 1; i--) {
        final cfg = back[(i - 1) % 2];
        final turns = spread ? cfg[2] : cfg[0];
        final dx = (spread ? cfg[3] : cfg[1]) * w;
        final url = i < list.length ? list[i] : null;
        children.add(AnimatedPositioned(
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutBack,
          left: (c.maxWidth - w) / 2 + dx,
          top: (c.maxHeight - ph) * (align + 1) / 2,
          child: AnimatedRotation(
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOutBack,
            turns: turns,
            child: PolaroidPrint(url: url, width: w, height: ph, faceDown: faceDown || url == null),
          ),
        ));
      }
      children.add(AnimatedPositioned(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutBack,
        left: (c.maxWidth - w) / 2,
        top: (c.maxHeight - ph) * (align + 1) / 2,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutBack,
          scale: spread ? 1.03 : 1.0,
          child: AnimatedRotation(
            duration: const Duration(milliseconds: 380),
            turns: spread ? 0 : -0.006,
            child: PolaroidPrint(url: list.first, width: w, height: ph, faceDown: faceDown, overlay: frontOverlay),
          ),
        ),
      ));
      return Stack(clipBehavior: Clip.none, children: children);
    });
  }
}

/// Fondo cálido tipo mesa sobre el que descansan las polaroids.
class PolaroidDesk extends StatelessWidget {
  final Widget child;
  final Color tint;
  final BorderRadius borderRadius;
  const PolaroidDesk({super.key, required this.child, this.tint = OhtliColors.stormyTeal, required this.borderRadius});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [tint.withValues(alpha: 0.10), tint.withValues(alpha: 0.03), OhtliColors.accent.withValues(alpha: 0.08)],
          ),
        ),
        child: child,
      ),
    );
  }
}
