import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/labs/lab_runner.dart';

void main() {
  test('latencia con marcas del servidor: acuse + created_at → completed_at', () {
    final job = {'created_at': '2026-11-14 23:50:00.000000+00:00', 'completed_at': '2026-11-14 23:50:21.500000+00:00'};
    expect(serverE2eSeconds(300, job), closeTo(21.8, 1e-9));
  });

  test('sin marcas o incoherentes no se usa (queda la medida por sondeo)', () {
    expect(serverE2eSeconds(300, {}), isNull);
    expect(serverE2eSeconds(null, {'created_at': '2026-11-14T23:50:00Z', 'completed_at': '2026-11-14T23:50:10Z'}), isNull);
    expect(serverE2eSeconds(300, {'created_at': '2026-11-14T23:50:10Z', 'completed_at': '2026-11-14T23:50:00Z'}), isNull);
    expect(serverE2eSeconds(300, {'created_at': 'ayer', 'completed_at': 'hoy'}), isNull);
  });
}
