import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/contribution_titles.dart';
import '../services/place_feedback_service.dart';
import 'place_report_page.dart';
import '../models/poi_model.dart';
import '../theme/colors.dart';
import '../utils/friendly_errors.dart';
import 'ohtli_ui.dart';

/// Si el lugar del catálogo ya tiene foto.
Future<bool> placeHasCatalogPhoto(String poiId) async {
  try {
    final d = (await FirebaseFirestore.instance.collection('pois').doc(poiId).get()).data() ?? const {};
    final url = (d['photo_url'] ?? d['image_url'] ?? d['photo'] ?? '').toString();
    if (url.isNotEmpty) return true;
    final photos = d['photos'];
    return photos is List && photos.isNotEmpty;
  } catch (_) {
    return true; // si no se sabe, se pregunta
  }
}

/// Antes de elegir la foto de un lugar del catálogo: si el lugar no tiene foto, se dona sola
/// (true); si ya tiene, se pregunta Subir o Subir y donar. null si se cancela.
Future<bool?> decidePhotoDonation(BuildContext context, {required String poiId, required String poiName}) async {
  if (poiId.isEmpty) return false;
  if (!await placeHasCatalogPhoto(poiId)) return true;
  if (!context.mounted) return null;
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: OhtliColors.cardBg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text('Foto de $poiName', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Este lugar ya tiene foto en Ohtli. Si donas la tuya y la aprobamos, la reemplaza para todos.',
                  style: OhtliUi.body(size: 13)),
            ),
            ListTile(
              leading: Icon(Icons.add_photo_alternate_outlined, color: OhtliColors.accentText),
              title: Text('Subir', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: OhtliColors.onyx)),
              subtitle: Text('Solo para tu viaje', style: OhtliUi.body(size: 12.5)),
              onTap: () => Navigator.pop(ctx, false),
            ),
            ListTile(
              leading: const Icon(Icons.volunteer_activism_rounded, color: OhtliColors.stormyTeal),
              title: Text('Subir y donar', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: OhtliColors.onyx)),
              subtitle: Text('Para tu viaje y, si la aprobamos, como foto del lugar', style: OhtliUi.body(size: 12.5)),
              onTap: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Dona la foto ya recortada (sin preguntar: la decisión se tomó antes de elegirla).
Future<void> donatePhotoNow(
  ScaffoldMessengerState messenger, {
  required String poiId,
  required String poiName,
  required String dataUrl,
  String? tripId,
}) async {
  try {
    final newTitle = await PlaceFeedbackService.donatePhoto(poiId: poiId, poiName: poiName, dataUrl: dataUrl, tripId: tripId);
    messenger.showSnackBar(SnackBar(
      content: Text(newTitle
          ? 'Donaste tu foto a $poiName y ganaste el título ${kTitleDonor.name}. Si la aprobamos, ganas ${kTitleDonorApproved.name}.'
          : 'Donaste tu foto a $poiName. Te avisamos cuando la revisemos.'),
    ));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(e, fallback: 'No se pudo donar tu foto. Quedó solo en tu viaje.'))));
  }
}

/// Reportar un lugar: pantalla con un paso por cada dato marcado (place_report_page.dart).
Future<void> showReportPlaceSheet(BuildContext context, {required Poi poi}) {
  return Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlaceReportPage(poi: poi), fullscreenDialog: true));
}
