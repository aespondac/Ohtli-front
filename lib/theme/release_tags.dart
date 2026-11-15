import 'package:flutter/material.dart';

import '../models/trip_model.dart';
import 'colors.dart';

/// Color e ícono de cada tipo de novedad en las notas de versión (ver [kReleaseTags]).
Color releaseTagColor(String? tag) => switch (tag) {
      'mejora' => OhtliColors.stormyTeal,
      // Xoconostle aclarado: el original casi no se ve sobre fondo oscuro.
      'correccion' => const Color(0xFFB4436C),
      _ => OhtliColors.cempasuchil,
    };

IconData releaseTagIcon(String? tag) => switch (tag) {
      'mejora' => Icons.trending_up_rounded,
      'correccion' => Icons.build_rounded,
      _ => Icons.auto_awesome_rounded,
    };

String releaseTagLabel(String? tag) => kReleaseTags[tag] ?? kReleaseTags['nuevo']!;
