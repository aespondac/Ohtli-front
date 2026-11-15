import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/utils/opening_hours.dart';

void main() {
  test('casos comunes del catálogo', () {
    expect(formatOpeningHours('Mo-Su 09:00-21:00'), 'Todos los días 9:00–21:00');
    expect(formatOpeningHours('Tu-Su 10:00-18:00'), 'Mar–Dom 10:00–18:00');
    expect(formatOpeningHours('24/7'), 'Abierto las 24 horas');
    expect(formatOpeningHours('sunrise-sunset'), 'Del amanecer al atardecer');
    expect(formatOpeningHours('09:00 - 18:00'), '9:00–18:00');
  });

  test('varias reglas, días cerrados y listas de días', () {
    expect(formatOpeningHours('Mo off; Tu-Su 10:00-17:00'), 'Lun cerrado · Mar–Dom 10:00–17:00');
    expect(
      formatOpeningHours('Fr-Sa 13:00-24:00, Su 12:00-22:00; Mo-Th 13:00-23:00'),
      'Vie–Sáb 13:00–24:00 · Dom 12:00–22:00 · Lun–Jue 13:00–23:00',
    );
    expect(formatOpeningHours('Mo, We, Th 15:00-22:00; Fr 15:00-23:00'), 'Lun, Mié y Jue 15:00–22:00 · Vie 15:00–23:00');
    expect(formatOpeningHours('Mo-Fr 17:00-01:30, Sa,Su 17:00-03:00'), 'Lun–Vie 17:00–1:30 · Sáb y Dom 17:00–3:00');
    expect(formatOpeningHours('Mo-Sa 08:00-11:00, 17:00-20:00'), 'Lun–Sáb 8:00–11:00, 17:00–20:00');
  });

  test('cierre a medianoche y datos raros', () {
    expect(formatOpeningHours('13:00-00:00'), '13:00–24:00');
    expect(formatOpeningHours('"Agenda tu cita"'), 'Agenda tu cita');
    expect(formatOpeningHours('5545260235'), '');
    expect(formatOpeningHours(''), '');
  });
}
