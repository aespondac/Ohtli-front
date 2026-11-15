import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/screens/login/auth_shell.dart';
import 'package:othli_front/screens/register/register_page.dart';

void main() {
  group('validateEmail', () {
    test('acepta correos normales', () {
      expect(validateEmail('ana@correo.com'), isNull);
      expect(validateEmail('  ana.perez+viajes@unam.mx '), isNull);
    });
    test('pide el correo si está vacío', () {
      expect(validateEmail(''), isNotNull);
      expect(validateEmail(null), isNotNull);
    });
    test('rechaza correos incompletos', () {
      expect(validateEmail('ana@correo'), isNotNull);
      expect(validateEmail('ana correo.com'), isNotNull);
      expect(validateEmail('@correo.com'), isNotNull);
    });
  });

  group('PasswordRules', () {
    test('cumple todo', () {
      expect(PasswordRules.meetsAll('Trajinera#2026'), isTrue);
      expect(PasswordRules.meetsAll('Ñandú.Coyoacán9'), isTrue);
    });
    test('falta un requisito', () {
      expect(PasswordRules.meetsAll('Tr#1a'), isFalse); // corta
      expect(PasswordRules.meetsAll('trajinera#2026'), isFalse); // sin mayúscula
      expect(PasswordRules.meetsAll('Trajinera#'), isFalse); // sin número
      expect(PasswordRules.meetsAll('Trajinera2026'), isFalse); // sin símbolo
    });
  });
}
