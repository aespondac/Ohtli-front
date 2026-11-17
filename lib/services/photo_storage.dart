import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

/// Subida de fotos a Firebase Storage, igual para toda la app: JPEG ya recortado y comprimido
/// (ver `OhtliImageCropperDialog`), con caché larga y un reintento si la red falla.
///
/// Las rutas que usa la app tienen lectura pública en `storage.rules`, así que la URL se arma
/// sin token (y sin la consulta extra de `getDownloadURL`).
class PhotoStorage {
  PhotoStorage._();

  /// Un año en la caché del navegador y de la CDN. Cada foto nueva lleva un nombre propio o el
  /// parámetro `v` en la URL, así que nunca se sirve una versión vieja por esto.
  static const String cacheControl = 'public, max-age=31536000, immutable';

  /// Bytes de un data URI (`data:image/jpeg;base64,…`) o de un base64 sin prefijo.
  static Uint8List bytesOf(String dataUrl) {
    final raw = dataUrl.contains(',') ? dataUrl.substring(dataUrl.indexOf(',') + 1) : dataUrl;
    return Uint8List.fromList(base64Decode(raw));
  }

  /// URL pública de [path]. Con [version], la URL cambia aunque la ruta sea la misma (portadas y
  /// fotos de perfil que se reemplazan) para que el navegador no muestre la anterior.
  static String publicUrl(String path, {int? version}) {
    final bucket = FirebaseStorage.instance.app.options.storageBucket;
    final v = version == null ? '' : '&v=$version';
    return 'https://firebasestorage.googleapis.com/v0/b/$bucket/o/${Uri.encodeComponent(path)}?alt=media$v';
  }

  /// Sube [bytes] a [path] y devuelve su URL pública. [onProgress] recibe de 0 a 1.
  /// [replaces]: la ruta se sobrescribe (portada, perfil), así que la URL lleva versión.
  static Future<String> upload(
    String path,
    Uint8List bytes, {
    void Function(double progress)? onProgress,
    bool replaces = false,
  }) async {
    final ref = FirebaseStorage.instance.ref(path);
    final meta = SettableMetadata(contentType: 'image/jpeg', cacheControl: cacheControl);
    for (var attempt = 0;; attempt++) {
      final task = ref.putData(bytes, meta);
      final sub = onProgress == null
          ? null
          : task.snapshotEvents.listen((s) {
              if (s.totalBytes > 0) onProgress(s.bytesTransferred / s.totalBytes);
            }, onError: (_) {});
      try {
        await task;
        onProgress?.call(1);
        return publicUrl(path, version: replaces ? DateTime.now().millisecondsSinceEpoch : null);
      } on FirebaseException catch (e) {
        // Sin permiso o cancelada no se arregla reintentando; un corte de red, a veces sí.
        if (attempt >= 1 || !_retryable(e.code)) rethrow;
        await Future<void>.delayed(const Duration(seconds: 2));
      } finally {
        await sub?.cancel();
      }
    }
  }

  /// Igual que [upload], a partir del data URI que devuelve el recortador.
  static Future<String> uploadDataUrl(
    String path,
    String dataUrl, {
    void Function(double progress)? onProgress,
    bool replaces = false,
  }) =>
      upload(path, bytesOf(dataUrl), onProgress: onProgress, replaces: replaces);

  static bool _retryable(String code) => const {
        'unknown',
        'retry-limit-exceeded',
        'server-file-wrong-size',
        'internal-error',
        'network-request-failed',
      }.contains(code);
}
