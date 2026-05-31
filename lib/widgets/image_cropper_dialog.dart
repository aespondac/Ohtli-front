import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/colors.dart';

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

// Blazing-fast optimized raw camera image JPEG extraction
Uint8List? _extractEmbeddedJpeg(Uint8List rawBytes) {
  final int len = rawBytes.length;
  if (len < 100) return null;

  int bestStart = -1;
  int bestEnd = -1;
  int maxLen = 0;

  int i = 0;
  while (true) {
    // Highly optimized byte scanning using browser native TypedArray indexOf via Dart
    i = rawBytes.indexOf(0xFF, i);
    if (i == -1 || i > len - 4) {
      break;
    }

    // Check if we hit a JPEG SOI marker (0xFF, 0xD8, 0xFF)
    if (rawBytes[i + 1] == 0xD8 && rawBytes[i + 2] == 0xFF) {
      final int start = i;
      int end = -1;
      
      // Look ahead to find the EOI marker (0xFF, 0xD9)
      // Limit search to 30MB ahead to avoid infinite loops on corrupted data
      final int searchLimit = (start + 30 * 1024 * 1024).clamp(0, len);
      
      int j = start + 2;
      while (true) {
        j = rawBytes.indexOf(0xFF, j);
        if (j == -1 || j >= searchLimit - 1) {
          break;
        }
        if (rawBytes[j + 1] == 0xD9) {
          end = j + 2;
          break;
        }
        j++;
      }
      
      if (end != -1) {
        final int segmentLen = end - start;
        if (segmentLen > maxLen) {
          maxLen = segmentLen;
          bestStart = start;
          bestEnd = end;
        }
        // Jump past this JPEG segment in the outer loop
        i = end;
        continue;
      }
    }
    i++;
  }

  if (bestStart != -1 && bestEnd != -1 && maxLen > 40 * 1024) { // Filter out tiny thumbnails under 40KB
    return Uint8List.sublistView(rawBytes, bestStart, bestEnd);
  }
  return null;
}

Future<Uint8List> _convertImageToJpegWeb(Uint8List bytes) async {
  if (!kIsWeb) return bytes;

  final Completer<Uint8List> completer = Completer<Uint8List>();
  final String mimeType = _getMimeType(bytes);
  final html.Blob blob = html.Blob([bytes], mimeType);
  final String blobUrl = html.Url.createObjectUrlFromBlob(blob);

  final html.ImageElement imgElement = html.ImageElement();
  imgElement.src = blobUrl;

  imgElement.onLoad.listen((_) {
    try {
      final html.CanvasElement canvas = html.CanvasElement(
        width: imgElement.naturalWidth,
        height: imgElement.naturalHeight,
      );
      final html.CanvasRenderingContext2D ctx = canvas.context2D;
      ctx.drawImage(imgElement, 0, 0);

      // Export to high-quality JPEG (0.85)
      final String dataUrl = canvas.toDataUrl('image/jpeg', 0.85);
      html.Url.revokeObjectUrl(blobUrl);

      final String base64Data = dataUrl.split(',').last;
      completer.complete(base64Decode(base64Data));
    } catch (e) {
      html.Url.revokeObjectUrl(blobUrl);
      completer.completeError(e);
    }
  });

  imgElement.onError.listen((err) {
    html.Url.revokeObjectUrl(blobUrl);
    completer.completeError(Exception("Failed to decode image natively in browser. Format may not be supported by this browser."));
  });

  return completer.future;
}

Future<Uint8List> _preprocessImageBytesAsync(Uint8List bytes) async {
  final ImageFormat format = _detectFormat(bytes);

  // 1. Is it already a standard JPEG?
  if (format == ImageFormat.jpeg) {
    return bytes;
  }

  // 2. Scan for embedded JPEG preview in RAW / TIFF-based/Unknown files
  if (format == ImageFormat.tiff || format == ImageFormat.raf || format == ImageFormat.unknown) {
    final Uint8List? embeddedJpeg = _extractEmbeddedJpeg(bytes);
    if (embeddedJpeg != null) {
      // Return the extracted high-resolution JPEG preview
      return embeddedJpeg;
    }
  }

  // 3. Convert PNG, WEBP, BMP, GIF, HEIC (on Safari), or RAW without preview to JPG via Web Canvas
  if (kIsWeb) {
    try {
      return await _convertImageToJpegWeb(bytes);
    } catch (e) {
      print("Warning: Web Canvas conversion failed, falling back to original bytes. Error: $e");
    }
  }

  return bytes; // Fallback
}

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
  final GlobalKey _boundaryKey = GlobalKey();
  final TransformationController _transformationController = TransformationController();
  double _zoom = 1.0;
  bool _isSaving = false;
  bool _isProcessing = true;
  late Uint8List _processedBytes;

  @override
  void initState() {
    super.initState();
    _processImage();
  }

  Future<void> _processImage() async {
    try {
      final Uint8List processed = await _preprocessImageBytesAsync(widget.imageBytes);
      if (mounted) {
        setState(() {
          _processedBytes = processed;
          _isProcessing = false;
        });
      }
    } catch (e) {
      print("Error preprocessing image: $e");
      if (mounted) {
        setState(() {
          _processedBytes = widget.imageBytes;
          _isProcessing = false;
        });
      }
    }
  }

  void _onZoomChanged(double value, double cropperWidth, double cropperHeight) {
    setState(() {
      _zoom = value;
      // Calculate translations to keep zoom centered
      final double x = -((value - 1.0) * (cropperWidth / 2));
      final double y = -((value - 1.0) * (cropperHeight / 2));
      
      final Matrix4 translation = Matrix4.translationValues(x, y, 0.0);
      final Matrix4 scaling = Matrix4.diagonal3Values(value, value, 1.0);
      _transformationController.value = translation * scaling;
    });
  }

  Future<void> _cropAndSave() async {
    setState(() => _isSaving = true);
    try {
      // Delay slightly to allow Flutter's paint cycle to flush
      await Future.delayed(const Duration(milliseconds: 150));

      // Dynamically adjust export quality (pixelRatio) depending on the image's purpose:
      // - Cover Image (not circle and not 3:4): Best quality (pixelRatio: 2.8)
      // - Place photos / block images (3:4): Compressed/lightweight (pixelRatio: 0.65)
      // - Profile Photo (circle): Medium quality (pixelRatio: 1.2)
      double pixelRatio = 1.0;
      if (widget.isCircle) {
        pixelRatio = 1.2;
      } else if (widget.aspectRatio == 3 / 4) {
        pixelRatio = 0.65; // Highly compressed for blocks to avoid Firestore document limit issues
      } else {
        pixelRatio = 2.8; // High-res for visual crispness of Cover image
      }

      final boundary = _boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        final Uint8List croppedBytes = byteData.buffer.asUint8List();
        String base64String = 'data:image/png;base64,${base64.encode(croppedBytes)}';

        // Convert PNG to JPEG using Web Canvas to optimize size and standard compatibility
        if (kIsWeb) {
          try {
            final html.CanvasElement canvas = html.CanvasElement(
              width: image.width,
              height: image.height,
            );
            final html.CanvasRenderingContext2D ctx = canvas.context2D;
            
            final html.ImageElement imgElement = html.ImageElement();
            final Completer<void> completer = Completer<void>();
            imgElement.onLoad.listen((_) {
              ctx.drawImage(imgElement, 0, 0);
              completer.complete();
            });
            imgElement.onError.listen((err) {
              completer.completeError(err);
            });
            imgElement.src = base64String;
            await completer.future;
            
            // Export to JPEG with premium compressed quality (0.85)
            base64String = canvas.toDataUrl('image/jpeg', 0.85);
          } catch (e) {
            print("Error converting cropped image to JPEG: $e");
          }
        }

        widget.onCropped(base64String);
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al recortar la imagen: $e'),
            backgroundColor: OhtliColors.xoconostle,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final double dialogWidth = (screenSize.width * 0.9).clamp(280.0, 360.0);

    if (_isProcessing) {
      return Dialog(
        backgroundColor: OhtliColors.cloudDancer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Semantics(
          label: 'Procesando y optimizando imagen. Por favor espera.',
          container: true,
          child: Container(
            padding: const EdgeInsets.all(30),
            width: dialogWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    color: OhtliColors.stormyTeal,
                    strokeWidth: 3,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Procesando imagen...',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: OhtliColors.onyx,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Optimizando el archivo y convirtiendo al formato estándar JPEG de alta calidad.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: OhtliColors.onyx.withValues(alpha: 0.6),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Reduce cropper viewport dynamically for smaller mobile screens to avoid overflow
    final double cropperSize = (dialogWidth - 48).clamp(200.0, 250.0);

    final double cropperWidth = widget.isCircle
        ? cropperSize
        : widget.aspectRatio < 1.0
            ? (cropperSize * widget.aspectRatio)
            : (dialogWidth - 40);
    final double cropperHeight = widget.isCircle
        ? cropperSize
        : (cropperWidth / widget.aspectRatio);

    return Dialog(
      backgroundColor: OhtliColors.cloudDancer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(20),
        width: dialogWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.isCircle
                    ? 'Recortar foto de perfil'
                    : widget.aspectRatio == 3 / 4
                        ? 'Recortar imagen (3:4)'
                        : 'Recortar portada de viaje',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: OhtliColors.onyx,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.isCircle
                    ? 'Arrastra y haz zoom para ajustar tu foto dentro del círculo.'
                    : widget.aspectRatio == 3 / 4
                        ? 'Arrastra y haz zoom para ajustar tu imagen (3:4).'
                        : 'Arrastra y haz zoom para elegir la parte visible de tu portada (16:9).',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: OhtliColors.onyx.withValues(alpha: 0.6),
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 16),

              // Viewport de recorte con la máscara
              Center(
                child: Container(
                  width: cropperWidth,
                  height: cropperHeight,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: widget.isCircle ? OhtliColors.cantera : OhtliColors.stormyTeal,
                      width: widget.isCircle ? 1.0 : 1.5,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Stack(
                      children: [
                        // InteractiveViewer para arrastrar y zoom de la foto
                        Positioned.fill(
                          child: RepaintBoundary(
                            key: _boundaryKey,
                            child: InteractiveViewer(
                              transformationController: _transformationController,
                              minScale: 1.0,
                              maxScale: 4.0,
                              clipBehavior: Clip.hardEdge,
                              onInteractionUpdate: (details) {
                                final double scale = _transformationController.value.getMaxScaleOnAxis();
                                setState(() {
                                  _zoom = scale.clamp(1.0, 4.0);
                                });
                              },
                              child: Image.memory(
                                _processedBytes,
                                fit: BoxFit.cover,
                                width: cropperWidth,
                                height: cropperHeight,
                              ),
                            ),
                          ),
                        ),

                        // Máscara oscura circular superpuesta (solo para círculos)
                        if (widget.isCircle)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: CircularCropMaskPainter(),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Control de Zoom Slider
              Row(
                children: [
                  Icon(Icons.zoom_out, size: 16, color: OhtliColors.onyx.withValues(alpha: 0.5)),
                  Expanded(
                    child: Slider(
                      value: _zoom,
                      min: 1.0,
                      max: 4.0,
                      activeColor: OhtliColors.stormyTeal,
                      inactiveColor: OhtliColors.cantera,
                      onChanged: (val) => _onZoomChanged(val, cropperWidth, cropperHeight),
                    ),
                  ),
                  Icon(Icons.zoom_in, size: 16, color: OhtliColors.onyx.withValues(alpha: 0.5)),
                ],
              ),
              const SizedBox(height: 16),

              // Botones de acción
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: OhtliColors.onyx.withValues(alpha: 0.6),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      child: Text(
                        'Cancelar',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _cropAndSave,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: OhtliColors.stormyTeal,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 1.5),
                            )
                          : Text(
                              'Guardar',
                              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
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
