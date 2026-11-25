import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/models/poi_model.dart';

void main() {
  Map<String, dynamic> base() => {'name': 'Rico Club', 'category': 'bar', 'location': {'lat': 19.42, 'lng': -99.16}};

  test('un reporte aprobado de cerrado cuenta como cerrado definitivamente y no se lista', () {
    final open = Poi.fromMap(base(), 'p1');
    final closed = Poi.fromMap({...base(), 'permanently_closed': true}, 'p1');
    final google = Poi.fromMap({...base(), 'operational_status': 'closed_permanently'}, 'p1');
    expect(closed.isClosedPermanently, isTrue);
    expect(google.isClosedPermanently, isTrue);
    expect(closed.isValidCulturalPlace, isFalse);
    expect(open.isClosedPermanently, isFalse);
  });
}
