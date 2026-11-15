import 'package:flutter/material.dart';
import '../models/poi_model.dart';
import '../screens/trips/trip_screens.dart' deferred as trips;

/// Wrapper de compatibilidad hacia atrás que redirige a la pantalla completa del planificador
/// (`TripPlannerPage`).
/// Garantiza que el onboarding y planeador de viaje nunca se abran como un modal.
class TripPlannerDialog {
  static Future<void> show(
    BuildContext context, {
    Poi? initialOriginPoi,
    VoidCallback? onManualPlanSelected,
    List<Map<String, dynamic>>? initialGeneratedOptions,
    String? initialActiveJobId,
    String? originName,
  }) async {
    // El planificador vive con las demás pantallas de viajes, en la parte diferida
    await trips.loadLibrary();
    if (!context.mounted) return;
    trips.TripPlannerPage.open(
      context,
      initialOriginPoi: initialOriginPoi,
      onManualPlanSelected: onManualPlanSelected,
      initialGeneratedOptions: initialGeneratedOptions,
      initialActiveJobId: initialActiveJobId,
      originName: originName,
    );
  }
}
