import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/utils/friendly_errors.dart';

void main() {
  test('traduce errores de autenticación sin mostrar detalles técnicos', () {
    final msg = friendlyError(FirebaseAuthException(code: 'invalid-credential', message: '[firebase_auth/invalid-credential] raw'));
    expect(msg, 'Correo o contraseña incorrectos.');
    expect(msg.contains('firebase'), isFalse);
  });

  test('errores de red y tiempo de espera dan un mensaje de conexión', () {
    expect(friendlyError(FirebaseException(plugin: 'cloud_firestore', code: 'unavailable')), contains('conexión'));
    expect(friendlyError(TimeoutException('x')), contains('tardando'));
    expect(friendlyError(Exception('XMLHttpRequest error')), contains('internet'));
  });

  test('un error desconocido usa el texto de respaldo, no el error crudo', () {
    final msg = friendlyError(StateError('Bad state: null check'), fallback: 'No pudimos guardar.');
    expect(msg, 'No pudimos guardar.');
  });

  test('un solo punto de corte para móvil/escritorio', () {
    expect(ohtliIsMobileWidth(799), isTrue);
    expect(ohtliIsMobileWidth(800), isFalse);
  });
}
