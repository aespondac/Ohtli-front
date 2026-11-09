import 'package:flutter/material.dart';
import '../models/poi_model.dart';
import '../screens/trips/trip_planner_page.dart';

/// Wrapper de compatibilidad hacia atrás que redirige a la pantalla completa [TripPlannerPage].
/// Garantiza que el onboarding y planeador de viaje nunca se abran como un modal.
class TripPlannerDialog {
  static void show(
    BuildContext context, {
    Poi? initialOriginPoi,
    VoidCallback? onManualPlanSelected,
    List<Map<String, dynamic>>? initialGeneratedOptions,
    String? initialActiveJobId,
    String? originName,
  }) {
    TripPlannerPage.open(
      context,
      initialOriginPoi: initialOriginPoi,
      onManualPlanSelected: onManualPlanSelected,
      initialGeneratedOptions: initialGeneratedOptions,
      initialActiveJobId: initialActiveJobId,
      originName: originName,
    );
  }
}
