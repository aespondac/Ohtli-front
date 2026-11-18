import 'package:flutter/material.dart';

import '../theme/colors.dart';

/// Rareza de un título según el porcentaje de cuentas que lo tienen (como en las plataformas de
/// juegos): los poseedores (`titles/{id}.holders`) y el total (`app_config/achievements.totalUsers`)
/// los recuenta el motor.
enum Rarity { legendario, epico, raro, pocoComun, comun }

extension RarityX on Rarity {
  String get label => switch (this) {
        Rarity.legendario => 'Legendario',
        Rarity.epico => 'Épico',
        Rarity.raro => 'Raro',
        Rarity.pocoComun => 'Poco común',
        Rarity.comun => 'Común',
      };

  /// Sin cempasúchil: ese color es solo para estrellas, advertencias y borrar.
  Color get color => switch (this) {
        Rarity.legendario => const Color(0xFFB86BFF),
        Rarity.epico => const Color(0xFF6C5CE7),
        Rarity.raro => OhtliColors.accent,
        Rarity.pocoComun => tealText,
        Rarity.comun => OhtliColors.subtleText,
      };
}

/// Turquesa legible en ambos temas (el stormyTeal se pierde sobre fondo oscuro).
Color get tealText => OhtliSettings.instance.isDarkMode ? const Color(0xFF7CC4CC) : OhtliColors.stormyTeal;

/// Porcentaje de cuentas con el título (0–100); null si aún no hay recuento.
double? holdersPercent(int? holders, int? total) {
  if (holders == null || total == null || total <= 0) return null;
  return (holders / total * 100).clamp(0, 100).toDouble();
}

Rarity rarityOf(double percent) {
  if (percent < 1) return Rarity.legendario;
  if (percent < 5) return Rarity.epico;
  if (percent < 15) return Rarity.raro;
  if (percent < 40) return Rarity.pocoComun;
  return Rarity.comun;
}

/// "Lo tiene el 8 % de los viajeros" / "Nadie lo tiene todavía".
String holdersText(int holders, double percent) {
  if (holders == 0) return 'Nadie lo tiene todavía';
  final p = percent < 1 ? '<1' : percent.round().toString();
  return 'Lo tiene el $p % de los viajeros';
}

const _kMonths = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

String shortDate(DateTime d) => '${d.day} ${_kMonths[d.month - 1]} ${d.year}';

/// Cuánto tardó en completarlo: "el mismo día", "3 días", "2 semanas", "4 meses", "1 año y 2 meses".
String durationText(Duration d) {
  final days = d.inDays;
  if (days < 1) return 'el mismo día';
  if (days < 14) return days == 1 ? '1 día' : '$days días';
  if (days < 60) {
    final w = (days / 7).round();
    return w == 1 ? '1 semana' : '$w semanas';
  }
  if (days < 365) {
    final m = (days / 30.4).round();
    return m == 1 ? '1 mes' : '$m meses';
  }
  final y = days ~/ 365;
  final m = ((days - y * 365) / 30.4).round();
  final ys = y == 1 ? '1 año' : '$y años';
  return m == 0 ? ys : '$ys y ${m == 1 ? '1 mes' : '$m meses'}';
}
