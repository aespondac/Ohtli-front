import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/services/achievement_rarity.dart';

void main() {
  test('rareza por porcentaje de poseedores', () {
    expect(rarityOf(0), Rarity.legendario);
    expect(rarityOf(0.9), Rarity.legendario);
    expect(rarityOf(3), Rarity.epico);
    expect(rarityOf(7.7), Rarity.raro);
    expect(rarityOf(20), Rarity.pocoComun);
    expect(rarityOf(100), Rarity.comun);
  });

  test('porcentaje y texto', () {
    expect(holdersPercent(1, 13), closeTo(7.69, 0.01));
    expect(holdersPercent(1, 0), isNull);
    expect(holdersPercent(null, 10), isNull);
    expect(holdersText(0, 0), 'Nadie lo tiene todavía');
    expect(holdersText(1, 0.4), 'Lo tiene el <1 % de los viajeros');
    expect(holdersText(3, 23.1), 'Lo tiene el 23 % de los viajeros');
  });

  test('duración legible', () {
    expect(durationText(const Duration(hours: 5)), 'el mismo día');
    expect(durationText(const Duration(days: 1)), '1 día');
    expect(durationText(const Duration(days: 9)), '9 días');
    expect(durationText(const Duration(days: 21)), '3 semanas');
    expect(durationText(const Duration(days: 120)), '4 meses');
    expect(durationText(const Duration(days: 365)), '1 año');
    expect(durationText(const Duration(days: 430)), '1 año y 2 meses');
  });

  test('fecha corta', () {
    expect(shortDate(DateTime(2026, 11, 17)), '17 nov 2026');
  });
}
