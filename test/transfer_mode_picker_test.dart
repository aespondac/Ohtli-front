import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/services/trip_transfers.dart';
import 'package:othli_front/widgets/transfer_mode_picker.dart';

void main() {
  test('los grupos del selector incluyen cada modo una sola vez', () {
    final grouped = [for (final g in kTransferModeGroups) ...g.$2];
    expect(grouped.toSet().length, grouped.length, reason: 'sin repetidos');
    expect(grouped.toSet(), kTransferModes.map((m) => m.id).toSet(), reason: 'ningún modo se queda fuera');
  });
}
