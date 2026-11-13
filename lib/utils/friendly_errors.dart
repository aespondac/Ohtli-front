import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Ancho (px) a partir del cual la app usa el diseño de escritorio.
/// Un único valor para que todas las pantallas cambien de diseño al mismo tiempo.
const double kOhtliDesktopBreakpoint = 800;

bool ohtliIsMobileWidth(double width) => width < kOhtliDesktopBreakpoint;

/// Traduce cualquier excepción a un mensaje entendible para la persona usuaria.
/// El detalle técnico se escribe en consola (debug) y nunca se muestra en pantalla.
String friendlyError(Object error, {String fallback = 'Algo salió mal. Intenta de nuevo en un momento.'}) {
  debugPrint('[Ohtli] $error');

  if (error is TimeoutException) {
    return 'La conexión está tardando demasiado. Revisa tu internet e intenta de nuevo.';
  }

  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'invalid-email':
        return 'El correo no tiene un formato válido.';
      case 'user-disabled':
        return 'Esta cuenta está desactivada. Escríbenos si crees que es un error.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'INVALID_LOGIN_CREDENTIALS':
        return 'Correo o contraseña incorrectos.';
      case 'email-already-in-use':
        return 'Ya existe una cuenta con este correo. Intenta iniciar sesión.';
      case 'weak-password':
        return 'La contraseña es muy débil. Usa al menos 6 caracteres.';
      case 'too-many-requests':
        return 'Demasiados intentos. Espera unos minutos y vuelve a intentarlo.';
      case 'network-request-failed':
        return 'Sin conexión a internet. Revisa tu red e intenta de nuevo.';
      case 'popup-closed-by-user':
      case 'cancelled-popup-request':
        return 'Se cerró la ventana de Google antes de terminar.';
      case 'popup-blocked':
        return 'El navegador bloqueó la ventana de Google. Permite ventanas emergentes e intenta de nuevo.';
      case 'account-exists-with-different-credential':
        return 'Este correo ya está registrado con otro método de acceso.';
      case 'requires-recent-login':
        return 'Por seguridad, vuelve a iniciar sesión y repite esta acción.';
      case 'expired-action-code':
        return 'El enlace ya expiró. Solicita uno nuevo.';
      case 'invalid-action-code':
        return 'El enlace no es válido o ya se usó.';
    }
    return fallback;
  }

  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return 'No tienes permiso para realizar esta acción.';
      case 'unavailable':
      case 'deadline-exceeded':
        return 'Sin conexión con el servidor. Revisa tu internet e intenta de nuevo.';
      case 'not-found':
        return 'No encontramos la información que buscas.';
      case 'unauthenticated':
        return 'Tu sesión expiró. Vuelve a iniciar sesión.';
      case 'resource-exhausted':
        return 'El servicio está saturado. Intenta de nuevo en unos minutos.';
      case 'unauthorized':
      case 'canceled':
        return 'No se pudo subir el archivo. Intenta de nuevo.';
    }
    return fallback;
  }

  final text = error.toString().toLowerCase();
  if (text.contains('network') || text.contains('failed to fetch') || text.contains('socket') || text.contains('xmlhttprequest')) {
    return 'Sin conexión a internet. Revisa tu red e intenta de nuevo.';
  }
  return fallback;
}
