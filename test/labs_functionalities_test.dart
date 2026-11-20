import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/labs/lab_functionalities.dart';
import 'package:othli_front/labs/lab_sma_page.dart';
import 'package:othli_front/labs/research/lab_models.dart' show kPlatformProjectId, kTtProjectId;

void main() {
  test('el sistema multiagente son cuatro funcionalidades de la plataforma', () {
    expect(modulesOf(kPlatformProjectId).map((m) => m.id), ['sma_critico', 'sma_politicas', 'sma_curador', 'sma_mensajes']);
    expect(modulesOf(kTtProjectId), isEmpty);
    expect(kLabModules.map((m) => m.sma).toSet(), SmaModule.values.toSet());
    expect(kLabModules.map((m) => m.id).toSet(), hasLength(kLabModules.length));
  });

  test('cada parte consulta solo su endpoint', () {
    expect(SmaModule.values.map((m) => m.path).toSet(), hasLength(4));
    expect(moduleById('sma_curador')!.sma.path, '/v1/categories');
    expect(moduleById('nada'), isNull);
  });
}
