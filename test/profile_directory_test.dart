import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/services/profile_directory.dart';

void main() {
  test('teléfono: 10 dígitos de México con o sin lada y espacios', () {
    expect(ProfileDirectory.normalizePhone('55 1234 5678'), '+525512345678');
    expect(ProfileDirectory.normalizePhone('+52 (55) 1234-5678'), '+525512345678');
    expect(ProfileDirectory.normalizePhone('1234'), isNull);
  });

  test('correo en minúsculas y válido', () {
    expect(ProfileDirectory.normalizeEmail('  Ana@Ohtli.Quest '), 'ana@ohtli.quest');
    expect(ProfileDirectory.normalizeEmail('ana@'), isNull);
  });

  test('usertag: sin @, minúsculas y caracteres permitidos', () {
    expect(ProfileDirectory.normalizeTag('@Mariana.Lopez'), 'mariana.lopez');
    expect(ProfileDirectory.normalizeTag('ab'), isNull);
    expect(ProfileDirectory.normalizeTag('con espacio'), isNull);
  });

  test('clasifica lo que se busca', () {
    expect(ProfileDirectory.classify('@mariana')?.kind, 'tag');
    expect(ProfileDirectory.classify('ana@ohtli.quest')?.kind, 'email');
    expect(ProfileDirectory.classify('55 1234 5678')?.kind, 'phone');
    expect(ProfileDirectory.classify('Mariana López')?.kind, 'name');
  });

  test('el hash no contiene el dato y es estable', () {
    final h = ProfileDirectory.hashOf('phone', '+525512345678');
    expect(h, ProfileDirectory.hashOf('phone', '+525512345678'));
    expect(h.contains('5512345678'), isFalse);
    expect(h.length, 64);
  });

  test('el hash es el mismo que calcula la función contactDirectory', () {
    // node -e "require('./functions/directory.js').hashOf('phone','+525512345678')"
    expect(ProfileDirectory.hashOf('phone', '+525512345678'), '0913e7b6f8afd6c2119506c9f80202304bc301bfaee33f9f8f8fc753a91a8bd4');
  });

  test('usertags reservados y prohibidos', () {
    expect(ProfileDirectory.tagProblem('ohtli'), 'reserved');
    expect(ProfileDirectory.tagProblem('ohtli.oficial'), 'reserved');
    expect(ProfileDirectory.tagProblem('0htli'), 'reserved');
    expect(ProfileDirectory.tagProblem('soporte_mx'), 'reserved');
    expect(ProfileDirectory.tagProblem('cdmx'), 'reserved');
    expect(ProfileDirectory.tagProblem('pend3jo'), 'prohibited');
    expect(ProfileDirectory.tagProblem('n4rco.boss'), 'prohibited');
    expect(ProfileDirectory.tagProblem('mariana.lopez'), isNull);
    expect(ProfileDirectory.tagProblem('cdmx.viajero'), isNull);
    expect(ProfileDirectory.tagProblem('pedro'), isNull);
    expect(ProfileDirectory.tagProblem('isis.essex'), isNull);
    expect(ProfileDirectory.tagProblem('skill.method'), isNull);
  });
}
