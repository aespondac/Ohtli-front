import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:web/web.dart' as web;

import '../theme/colors.dart';
import '../utils/friendly_errors.dart';
import '../utils/web_helpers.dart';

enum ImageFormat {
  jpeg,
  png,
  gif,
  webp,
  bmp,
  heic,
  tiff, // RAW formats like CR2, NEF, ARW, DNG
  raf,  // Fujifilm RAW
  unknown,
}

ImageFormat _detectFormat(Uint8List bytes) {
  if (bytes.length < 4) return ImageFormat.unknown;

  // JPEG
  if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
    return ImageFormat.jpeg;
  }

  // PNG
  if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
    return ImageFormat.png;
  }

  // GIF
  if (bytes.length >= 6 &&
      bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38) {
    return ImageFormat.gif;
  }

  // WEBP
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 && // 'RIFF'
      bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) { // 'WEBP'
    return ImageFormat.webp;
  }

  // BMP
  if (bytes[0] == 0x42 && bytes[1] == 0x4D) {
    return ImageFormat.bmp;
  }

  // TIFF (RAW formats like CR2, NEF, ARW, DNG)
  if ((bytes[0] == 0x49 && bytes[1] == 0x49 && bytes[2] == 0x2A && bytes[3] == 0x00) ||
      (bytes[0] == 0x4D && bytes[1] == 0x4D && bytes[2] == 0x00 && bytes[3] == 0x2A)) {
    return ImageFormat.tiff;
  }

  // Fujifilm RAF
  if (bytes.length >= 8 &&
      bytes[0] == 0x46 && bytes[1] == 0x55 && bytes[2] == 0x4A && bytes[3] == 0x49 &&
      bytes[4] == 0x46 && bytes[5] == 0x49 && bytes[6] == 0x4C && bytes[7] == 0x4D) {
    return ImageFormat.raf;
  }

  // HEIC/HEIF
  if (bytes.length >= 12 &&
      bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70) { // 'ftyp'
    try {
      final String subType = String.fromCharCodes(bytes.sublist(8, 12));
      if (subType.startsWith('he') || subType.startsWith('mi') || subType.startsWith('ms')) {
        return ImageFormat.heic;
      }
    } catch (_) {}
  }

  return ImageFormat.unknown;
}

String _getMimeType(Uint8List bytes) {
  final ImageFormat format = _detectFormat(bytes);
  switch (format) {
    case ImageFormat.jpeg:
      return 'image/jpeg';
    case ImageFormat.png:
      return 'image/png';
    case ImageFormat.gif:
      return 'image/gif';
    case ImageFormat.webp:
      return 'image/webp';
    case ImageFormat.bmp:
      return 'image/bmp';
    case ImageFormat.heic:
      return 'image/heic';
    case ImageFormat.tiff:
      return 'image/tiff';
    default:
      return 'image/octet-stream';
  }
}

int _readUint16(Uint8List bytes, int offset, bool isLittleEndian) {
  if (isLittleEndian) {
    return bytes[offset] | (bytes[offset + 1] << 8);
  } else {
    return (bytes[offset] << 8) | bytes[offset + 1];
  }
}

int _readUint32(Uint8List bytes, int offset, bool isLittleEndian) {
  if (isLittleEndian) {
    return bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24);
  } else {
    return (bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3];
  }
}

Uint8List? _extractEmbeddedJpegFromTiff(Uint8List bytes) {
  final int len = bytes.length;
  if (len < 64) return null;

  // 1. Determine byte order
  final bool isLittleEndian;
  if (bytes[0] == 0x49 && bytes[1] == 0x49) {
    isLittleEndian = true;
  } else if (bytes[0] == 0x4D && bytes[1] == 0x4D) {
    isLittleEndian = false;
  } else {
    return null; // Not a TIFF-based RAW file
  }

  // 2. Verify magic number (42 = standard TIFF)
  final int magic = _readUint16(bytes, 2, isLittleEndian);
  if (magic != 42 && magic != 0x4F52) {
    return null;
  }

  // 3. Find first IFD offset
  int firstIfdOffset = _readUint32(bytes, 4, isLittleEndian);
  if (firstIfdOffset <= 0 || firstIfdOffset >= len) return null;

  List<int> ifdQueue = [firstIfdOffset];
  Set<int> visitedIfds = {};
  
  int bestOffset = -1;
  int bestSize = -1;

  while (ifdQueue.isNotEmpty) {
    final int ifdOffset = ifdQueue.removeAt(0);
    if (visitedIfds.contains(ifdOffset) || ifdOffset <= 0 || ifdOffset >= len - 2) {
      continue;
    }
    visitedIfds.add(ifdOffset);

    try {
      final int numFields = _readUint16(bytes, ifdOffset, isLittleEndian);
      if (ifdOffset + 2 + numFields * 12 + 4 > len) continue;

      int? jpegOffset;
      int? jpegSize;
      int? stripOffset;
      int? stripSize;
      int? compression;

      for (int i = 0; i < numFields; i++) {
        final int entryPos = ifdOffset + 2 + i * 12;
        final int tagId = _readUint16(bytes, entryPos, isLittleEndian);
        _readUint16(bytes, entryPos + 2, isLittleEndian);
        final int count = _readUint32(bytes, entryPos + 4, isLittleEndian);
        final int valOffset = _readUint32(bytes, entryPos + 8, isLittleEndian);

        if (tagId == 0x0201) { // JPEGInterchangeFormat (JPEG offset)
          jpegOffset = valOffset;
        } else if (tagId == 0x0202) { // JPEGInterchangeFormatLength (JPEG size)
          jpegSize = valOffset;
        } else if (tagId == 0x0111) { // StripOffsets
          if (count == 1) {
            stripOffset = valOffset;
          } else if (count > 1 && valOffset < len - 4) {
            stripOffset = _readUint32(bytes, valOffset, isLittleEndian);
          }
        } else if (tagId == 0x0117) { // StripByteCounts
          if (count == 1) {
            stripSize = valOffset;
          } else if (count > 1 && valOffset < len - 4) {
            stripSize = _readUint32(bytes, valOffset, isLittleEndian);
          }
        } else if (tagId == 0x0103) { // Compression
          compression = valOffset;
        } else if (tagId == 0x014A) { // SubIFDs
          if (count == 1) {
            ifdQueue.add(valOffset);
          } else if (count > 1 && valOffset < len - (count * 4)) {
            for (int j = 0; j < count; j++) {
              final int subOffset = _readUint32(bytes, valOffset + j * 4, isLittleEndian);
              ifdQueue.add(subOffset);
            }
          }
        } else if (tagId == 0x8769) { // EXIFOffset
          ifdQueue.add(valOffset);
        }
      }

      // Prioritize JPEGInterchangeFormat (0x0201)
      if (jpegOffset != null && jpegSize != null && jpegOffset > 0 && jpegSize > 0) {
        if (jpegOffset + jpegSize <= len) {
          if (jpegSize > bestSize) {
            bestSize = jpegSize;
            bestOffset = jpegOffset;
          }
        }
      }
      // Fallback to StripOffsets (0x0111) if compression is JPEG (6 or 7)
      else if (stripOffset != null && stripSize != null && stripOffset > 0 && stripSize > 0) {
        if (stripOffset + stripSize <= len) {
          if (stripSize > bestSize && (compression == null || compression == 6 || compression == 7)) {
            bestSize = stripSize;
            bestOffset = stripOffset;
          }
        }
      }

      // Find next IFD offset in standard TIFF chain
      final int nextIfdOffsetPos = ifdOffset + 2 + numFields * 12;
      final int nextIfdOffset = _readUint32(bytes, nextIfdOffsetPos, isLittleEndian);
      if (nextIfdOffset > 0 && nextIfdOffset < len) {
        ifdQueue.add(nextIfdOffset);
      }
    } catch (_) {}
  }

  if (bestOffset > 0 && bestSize > 40 * 1024 && bestOffset + bestSize <= len) {
    return Uint8List.sublistView(bytes, bestOffset, bestOffset + bestSize);
  }
  return null;
}

Uint8List? _extractEmbeddedJpegFromRaf(Uint8List bytes) {
  final int len = bytes.length;
  if (len < 100) return null;
  
  // Fujifilm RAF files use Big Endian (Motorola) byte order.
  // The JPEG image offset is at byte 84 (0x54) and length is at byte 88 (0x58).
  final int jpegOffset = _readUint32(bytes, 84, false);
  final int jpegSize = _readUint32(bytes, 88, false);

  if (jpegOffset > 0 && jpegSize > 40 * 1024 && jpegOffset + jpegSize <= len) {
    return Uint8List.sublistView(bytes, jpegOffset, jpegOffset + jpegSize);
  }
  return null;
}

// Blazing-fast optimized raw camera image JPEG extraction
Uint8List? _extractEmbeddedJpeg(Uint8List rawBytes) {
  final ImageFormat format = _detectFormat(rawBytes);
  if (format == ImageFormat.tiff) {
    return _extractEmbeddedJpegFromTiff(rawBytes);
  }
  if (format == ImageFormat.raf) {
    return _extractEmbeddedJpegFromRaf(rawBytes);
  }
  if (format == ImageFormat.unknown) {
    // Attempt TIFF/RAF parser as fallbacks on unknown binary formats
    final tiffRes = _extractEmbeddedJpegFromTiff(rawBytes);
    if (tiffRes != null) return tiffRes;
    
    final rafRes = _extractEmbeddedJpegFromRaf(rawBytes);
    if (rafRes != null) return rafRes;
  }
  return null;
}

/// Lado mayor de la imagen con la que se trabaja en el recorte: deja acercar 1.5× sin perder
/// nitidez en la salida de 1600 px, y un celular la mueve sin trabarse (las fotos de 12 MP
/// del teléfono se decodificaban enteras).
const int _workMaxSide = 2400;

/// La foto no se pudo abrir en este navegador (HEIC fuera de Safari sin conversión, RAW sin
/// vista previa, archivo dañado…).
class UnsupportedImageException implements Exception {
  const UnsupportedImageException();
  @override
  String toString() =>
      'No pudimos abrir esta foto. Si es HEIC o RAW, conviértela a JPG o elige otra e inténtalo de nuevo.';
}

/// Decodifica con el propio navegador: así se respeta la orientación EXIF (las fotos verticales
/// del teléfono ya no salen acostadas) y Safari abre HEIC.
Future<web.HTMLImageElement> _decodeInBrowser(Uint8List bytes, String mimeType) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final img = web.HTMLImageElement();
  final done = Completer<void>();
  img.onload = ((web.Event _) {
    if (!done.isCompleted) done.complete();
  }).toJS;
  img.onerror = ((web.Event _) {
    if (!done.isCompleted) done.completeError(const UnsupportedImageException());
  }).toJS;
  img.src = url;
  try {
    await done.future;
    if (img.naturalWidth == 0 || img.naturalHeight == 0) throw const UnsupportedImageException();
    return img;
  } finally {
    web.URL.revokeObjectURL(url);
  }
}

@JS('heic2any')
external JSPromise<JSAny?> _heic2any(JSObject options);

/// HEIC del iPhone en Chrome, Firefox o Android (Safari ya lo abre): se convierte a JPEG con
/// heic2any, que solo se descarga la primera vez que hace falta.
Future<Uint8List> _heicToJpeg(Uint8List bytes) async {
  if (!globalContext.has('heic2any')) {
    final script = ensureScript(id: 'ohtli-heic2any', src: 'https://cdn.jsdelivr.net/npm/heic2any@0.0.4/dist/heic2any.min.js');
    final loaded = Completer<void>();
    script.addEventListener('load', ((web.Event _) {
      if (!loaded.isCompleted) loaded.complete();
    }).toJS);
    script.addEventListener('error', ((web.Event _) {
      if (!loaded.isCompleted) loaded.completeError(const UnsupportedImageException());
    }).toJS);
    // Por si ya estaba cargando desde otro intento
    if (globalContext.has('heic2any')) loaded.complete();
    await loaded.future.timeout(const Duration(seconds: 20));
  }
  final options = JSObject()
    ..['blob'] = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: 'image/heic'))
    ..['toType'] = 'image/jpeg'.toJS
    ..['quality'] = 0.92.toJS;
  JSAny? result = await _heic2any(options).toDart;
  // Con fotos "en vivo" devuelve una lista: la primera es la foto
  if (result != null && result.isA<JSArray>()) {
    final list = (result as JSArray<JSAny?>).toDart;
    result = list.isEmpty ? null : list.first;
  }
  if (result == null || !result.isA<web.Blob>()) throw const UnsupportedImageException();
  final buffer = await (result as web.Blob).arrayBuffer().toDart;
  return buffer.toDart.asUint8List();
}

/// Deja la foto lista para recortar: saca la vista previa de los RAW, la decodifica con la
/// orientación correcta y la reduce a [_workMaxSide].
Future<web.HTMLCanvasElement> _prepareCanvas(Uint8List bytes) async {
  var src = bytes;
  var format = _detectFormat(bytes);
  if (format == ImageFormat.tiff || format == ImageFormat.raf || format == ImageFormat.unknown) {
    final embedded = _extractEmbeddedJpeg(bytes);
    if (embedded != null) {
      src = embedded;
      format = ImageFormat.jpeg;
    }
  }
  web.HTMLImageElement img;
  try {
    img = await _decodeInBrowser(src, _getMimeType(src));
  } catch (_) {
    if (format != ImageFormat.heic) throw const UnsupportedImageException();
    try {
      img = await _decodeInBrowser(await _heicToJpeg(src), 'image/jpeg');
    } catch (_) {
      throw const UnsupportedImageException();
    }
  }
  final w = img.naturalWidth, h = img.naturalHeight;
  final scale = math.min(1.0, _workMaxSide / math.max(w, h));
  final canvas = web.HTMLCanvasElement()
    ..width = math.max(1, (w * scale).round())
    ..height = math.max(1, (h * scale).round());
  final ctx = canvas.context2D
    ..imageSmoothingEnabled = true
    ..imageSmoothingQuality = 'high';
  ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
  return canvas;
}

/// La misma imagen girada 90° a la derecha.
web.HTMLCanvasElement _rotateClockwise(web.HTMLCanvasElement source) {
  final out = web.HTMLCanvasElement()
    ..width = source.height
    ..height = source.width;
  out.context2D
    ..translate(out.width, 0)
    ..rotate(math.pi / 2)
    ..drawImage(source, 0, 0);
  return out;
}

Future<Uint8List> _canvasToJpeg(web.HTMLCanvasElement canvas, double quality) {
  final done = Completer<Uint8List>();
  canvas.toBlob(
    ((web.Blob? blob) {
      if (blob == null) {
        done.completeError(const UnsupportedImageException());
        return;
      }
      blob.arrayBuffer().toDart.then(
            (b) => done.complete(b.toDart.asUint8List()),
            onError: (Object e) => done.completeError(e),
          );
    }).toJS,
    'image/jpeg',
    quality.toJS,
  );
  return done.future;
}

/// Tamaño del contenido en el visor: la imagen escalada para cubrir [viewport] (como BoxFit.cover).
Size coverSize(Size image, Size viewport) {
  final s = math.max(viewport.width / image.width, viewport.height / image.height);
  return Size(image.width * s, image.height * s);
}

/// La parte de la imagen (en sus píxeles) que se ve en el visor con la transformación [m] del
/// InteractiveViewer, cuyo contenido mide [content] (ver [coverSize]).
Rect cropSourceRect({required Matrix4 m, required Size viewport, required Size content, required Size image}) {
  final z = m.getMaxScaleOnAxis();
  final t = m.getTranslation();
  final toImage = image.width / content.width;
  final rect = Rect.fromLTWH(-t.x / z * toImage, -t.y / z * toImage, viewport.width / z * toImage, viewport.height / z * toImage);
  return rect.intersect(Offset.zero & image);
}

/// Transformación con zoom [zoom] alrededor del centro del visor, sin dejar huecos.
Matrix4 zoomAroundCenter(Matrix4 m, double zoom, Size viewport, Size content) {
  final z = m.getMaxScaleOnAxis();
  final t = m.getTranslation();
  final cx = (viewport.width / 2 - t.x) / z, cy = (viewport.height / 2 - t.y) / z;
  final tx = (viewport.width / 2 - cx * zoom).clamp(viewport.width - content.width * zoom, 0.0);
  final ty = (viewport.height / 2 - cy * zoom).clamp(viewport.height - content.height * zoom, 0.0);
  return Matrix4.translationValues(tx, ty, 0)..multiply(Matrix4.diagonal3Values(zoom, zoom, 1));
}

/// Elige el encuadre de una foto (arrastrar, pellizcar o la barra de zoom, y girar) y devuelve
/// por [onCropped] un data URI JPEG: lado mayor de 1600 px (800 en la foto de perfil) al 85 %.
class OhtliImageCropperDialog extends StatefulWidget {
  final Uint8List imageBytes;
  final Function(String) onCropped;
  final bool isCircle;
  final double aspectRatio;

  const OhtliImageCropperDialog({
    super.key,
    required this.imageBytes,
    required this.onCropped,
    this.isCircle = true,
    this.aspectRatio = 16 / 9,
  });

  @override
  State<OhtliImageCropperDialog> createState() => _OhtliImageCropperDialogState();
}

class _OhtliImageCropperDialogState extends State<OhtliImageCropperDialog> {
  final TransformationController _transform = TransformationController();
  double _zoom = 1.0;
  bool _isSaving = false;
  bool _isProcessing = true;
  String? _error;
  web.HTMLCanvasElement? _canvas;
  Uint8List? _previewBytes;
  Size? _laidOutViewport;

  static const double _maxZoom = 5.0;

  double get _ratio => widget.isCircle ? 1.0 : widget.aspectRatio;
  Size get _imageSize => Size(_canvas!.width.toDouble(), _canvas!.height.toDouble());

  @override
  void initState() {
    super.initState();
    _processImage();
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  Future<void> _processImage() async {
    try {
      final canvas = await _prepareCanvas(widget.imageBytes);
      await _show(canvas);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _error = e is UnsupportedImageException
              ? e.toString()
              : friendlyError(e, fallback: 'No pudimos abrir esta foto. Intenta con otra.');
        });
      }
    }
  }

  /// Muestra [canvas] centrada y sin zoom.
  Future<void> _show(web.HTMLCanvasElement canvas) async {
    final preview = await _canvasToJpeg(canvas, 0.92);
    if (!mounted) return;
    setState(() {
      _canvas = canvas;
      _previewBytes = preview;
      _isProcessing = false;
      _laidOutViewport = null; // el build vuelve a centrar
    });
  }

  Future<void> _rotate() async {
    final c = _canvas;
    if (c == null || _isSaving) return;
    setState(() => _isProcessing = true);
    await _show(_rotateClockwise(c));
  }

  Size _viewport(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final dialogW = math.min(screen.width - 24, 460.0);
    var w = dialogW - 40;
    var h = w / _ratio;
    final maxH = math.max(200.0, screen.height * 0.5);
    if (h > maxH) {
      h = maxH;
      w = h * _ratio;
    }
    return Size(w, h);
  }

  void _center(Size viewport) {
    final content = coverSize(_imageSize, viewport);
    _transform.value = Matrix4.translationValues(-(content.width - viewport.width) / 2, -(content.height - viewport.height) / 2, 0);
    _zoom = 1.0;
  }

  void _onZoomChanged(double value, Size viewport) {
    setState(() {
      _zoom = value;
      _transform.value = zoomAroundCenter(_transform.value, value, viewport, coverSize(_imageSize, viewport));
    });
  }

  Future<void> _cropAndSave(Size viewport) async {
    final canvas = _canvas;
    if (canvas == null) return;
    setState(() => _isSaving = true);
    try {
      final src = cropSourceRect(m: _transform.value, viewport: viewport, content: coverSize(_imageSize, viewport), image: _imageSize);
      final maxSide = widget.isCircle ? 800 : 1600;
      final scale = math.min(1.0, maxSide / math.max(src.width, src.height));
      final out = web.HTMLCanvasElement()
        ..width = math.max(1, (src.width * scale).round())
        ..height = math.max(1, (src.height * scale).round());
      out.context2D
        ..imageSmoothingEnabled = true
        ..imageSmoothingQuality = 'high'
        ..drawImage(canvas, src.left, src.top, src.width, src.height, 0, 0, out.width, out.height);
      // JPEG al 85 %: sin diferencia visible y bastante más ligero que al 95 %
      final dataUrl = out.toDataURL('image/jpeg', 0.85.toJS);
      widget.onCropped(dataUrl);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e, fallback: 'No pudimos recortar la imagen. Intenta con otra foto.')),
            backgroundColor: OhtliColors.warning,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _frame({required double width, required Widget child}) => Dialog(
        backgroundColor: OhtliColors.cloudDancer,
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: SizedBox(width: width, child: child),
      );

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final double dialogWidth = math.min(screen.width - 24, 460.0);

    if (_error != null) {
      return _frame(
        width: dialogWidth,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.image_not_supported_outlined, color: OhtliColors.warning, size: 36),
              const SizedBox(height: 14),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.onyx, height: 1.4)),
              const SizedBox(height: 18),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(foregroundColor: OhtliColors.stormyTeal),
                child: Text('Entendido', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      );
    }

    if (_isProcessing || _previewBytes == null) {
      return _frame(
        width: dialogWidth,
        child: Semantics(
          label: 'Preparando la foto. Por favor espera.',
          container: true,
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(color: OhtliColors.stormyTeal, strokeWidth: 3),
                ),
                const SizedBox(height: 20),
                Text('Preparando la foto…',
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: OhtliColors.onyx)),
              ],
            ),
          ),
        ),
      );
    }

    final viewport = _viewport(context);
    final content = coverSize(_imageSize, viewport);
    if (_laidOutViewport != viewport) {
      final first = _laidOutViewport == null;
      _laidOutViewport = viewport;
      if (first) {
        _center(viewport);
      } else {
        // Giró el teléfono o cambió la ventana: se vuelve a centrar después de este cuadro
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _center(viewport));
        });
      }
    }

    final String title = widget.isCircle
        ? 'Recortar foto de perfil'
        : _ratio < 1
            ? 'Encuadrar foto'
            : 'Encuadrar portada';

    return _frame(
      width: dialogWidth,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: OhtliColors.onyx)),
            const SizedBox(height: 4),
            Text(
              'Arrastra para encuadrar; pellizca o usa la barra para acercar.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 11.5, color: OhtliColors.onyx.withValues(alpha: 0.6), height: 1.3),
            ),
            const SizedBox(height: 14),
            Semantics(
              label: 'Encuadre de la foto',
              child: Container(
                width: viewport.width,
                height: viewport.height,
                decoration: BoxDecoration(
                  border: Border.all(color: widget.isCircle ? OhtliColors.cantera : OhtliColors.stormyTeal, width: 1.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10.5),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: InteractiveViewer(
                          transformationController: _transform,
                          constrained: false,
                          minScale: 1.0,
                          maxScale: _maxZoom,
                          clipBehavior: Clip.hardEdge,
                          onInteractionUpdate: (_) {
                            final z = _transform.value.getMaxScaleOnAxis().clamp(1.0, _maxZoom);
                            if ((z - _zoom).abs() > 0.01) setState(() => _zoom = z);
                          },
                          child: SizedBox(
                            width: content.width,
                            height: content.height,
                            child: Image.memory(_previewBytes!, fit: BoxFit.fill, gaplessPlayback: true),
                          ),
                        ),
                      ),
                      if (widget.isCircle)
                        Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: CircularCropMaskPainter())))
                      else
                        Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _ThirdsGridPainter()))),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.zoom_out, size: 18, color: OhtliColors.onyx.withValues(alpha: 0.5)),
                Expanded(
                  child: Slider(
                    value: _zoom.clamp(1.0, _maxZoom),
                    min: 1.0,
                    max: _maxZoom,
                    activeColor: OhtliColors.stormyTeal,
                    inactiveColor: OhtliColors.cantera,
                    onChanged: (val) => _onZoomChanged(val, viewport),
                  ),
                ),
                Icon(Icons.zoom_in, size: 18, color: OhtliColors.onyx.withValues(alpha: 0.5)),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Girar',
                  onPressed: _isSaving ? null : _rotate,
                  icon: const Icon(Icons.rotate_right_rounded),
                  color: OhtliColors.stormyTeal,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: OhtliColors.onyx.withValues(alpha: 0.6),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('Cancelar', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : () => _cropAndSave(viewport),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: OhtliColors.stormyTeal,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 1.8))
                        : Text('Guardar', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Guías de tercios sobre el encuadre, para acomodar la foto.
class _ThirdsGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = size.width * i / 3, y = size.height * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Pintor personalizado para hacer una máscara circular oscura
class CircularCropMaskPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    // Crear un Path para toda la caja y restarle el círculo del centro
    final outerPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final innerPath = Path()
      ..addOval(Rect.fromCircle(
        center: Offset(size.width / 2, size.height / 2),
        radius: size.width / 2,
      ));

    // El Path resultante es la diferencia (máscara de anillo)
    final combinedPath = Path.combine(PathOperation.difference, outerPath, innerPath);

    canvas.drawPath(combinedPath, paint);

    // Dibujar un borde blanco sutil para delimitar el círculo de corte
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), size.width / 2, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
