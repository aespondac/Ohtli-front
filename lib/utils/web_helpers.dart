import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Ayudas sobre `package:web` (la API del navegador que reemplaza a `dart:html`, que no
/// compila a WebAssembly) para los patrones que la app repite.

extension OhtliStorage on web.Storage {
  /// Lee y borra una clave en un paso (lo que hacía `storage.remove(key)` en dart:html).
  String? takeItem(String key) {
    final value = getItem(key);
    removeItem(key);
    return value;
  }
}

/// Agrega al `<head>` un `<script>` con [id] si todavía no existe. Con [src] lo descarga; con
/// [text], lo ejecuta en línea. Devuelve el elemento (nuevo o el que ya estaba).
web.HTMLScriptElement ensureScript({required String id, String? src, String? text, bool async = true}) {
  final existing = web.document.getElementById(id);
  if (existing != null) return existing as web.HTMLScriptElement;
  final script = web.HTMLScriptElement()
    ..id = id
    ..async = async;
  if (src != null) script.src = src;
  if (text != null) script.text = text;
  web.document.head?.append(script);
  return script;
}

/// Descarga [bytes] como un archivo llamado [fileName].
void downloadBytes(Uint8List bytes, String fileName, String mimeType) {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName;
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}

/// Archivo elegido por la persona: nombre, tipo MIME y contenido.
class PickedFile {
  PickedFile(this.name, this.mimeType, this.bytes);
  final String name;
  final String mimeType;
  final Uint8List bytes;
}

/// Abre el selector de archivos del navegador. Devuelve null si se cancela.
Future<PickedFile?> pickFile({String accept = '*/*'}) {
  final completer = Completer<PickedFile?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = accept;
  input.onchange = ((web.Event _) {
    final file = input.files?.item(0);
    if (file == null) {
      if (!completer.isCompleted) completer.complete(null);
      return;
    }
    final reader = web.FileReader();
    reader.onload = ((web.Event _) {
      final result = reader.result;
      final bytes = result == null ? Uint8List(0) : (result as JSArrayBuffer).toDart.asUint8List();
      if (!completer.isCompleted) completer.complete(PickedFile(file.name, file.type, bytes));
    }).toJS;
    reader.onerror = ((web.Event _) {
      if (!completer.isCompleted) completer.completeError(StateError('No se pudo leer el archivo'));
    }).toJS;
    reader.readAsArrayBuffer(file);
  }).toJS;
  // Si la persona cierra el selector sin elegir, algunos navegadores avisan con "cancel"
  input.addEventListener(
    'cancel',
    ((web.Event _) {
      if (!completer.isCompleted) completer.complete(null);
    }).toJS,
  );
  input.click();
  return completer.future;
}
