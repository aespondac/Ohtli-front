import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/colors.dart';

class OhtliImageCropperDialog extends StatefulWidget {
  final Uint8List imageBytes;
  final Function(String) onCropped;
  final bool isCircle;

  const OhtliImageCropperDialog({
    super.key,
    required this.imageBytes,
    required this.onCropped,
    this.isCircle = true,
  });

  @override
  State<OhtliImageCropperDialog> createState() => _OhtliImageCropperDialogState();
}

class _OhtliImageCropperDialogState extends State<OhtliImageCropperDialog> {
  final GlobalKey _boundaryKey = GlobalKey();
  final TransformationController _transformationController = TransformationController();
  double _zoom = 1.0;
  bool _isSaving = false;

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

      final boundary = _boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(pixelRatio: 1.5); // 1.5x optimized for low size/cost
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        final Uint8List croppedBytes = byteData.buffer.asUint8List();
        final String base64String = 'data:image/png;base64,${base64.encode(croppedBytes)}';
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
    // Reduce cropper viewport dynamically for smaller mobile screens to avoid overflow
    final double cropperSize = (dialogWidth - 48).clamp(200.0, 250.0);

    final double cropperWidth = widget.isCircle ? cropperSize : (dialogWidth - 40);
    final double cropperHeight = widget.isCircle ? cropperSize : (cropperWidth * 9 / 16);

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
                widget.isCircle ? 'Recortar foto de perfil' : 'Recortar portada de viaje',
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
                    : 'Arrastra y haz zoom para elegir la parte visible de tu portada (16:9).',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: OhtliColors.onyx.withOpacity(0.6),
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
                                widget.imageBytes,
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
                  Icon(Icons.zoom_out, size: 16, color: OhtliColors.onyx.withOpacity(0.5)),
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
                  Icon(Icons.zoom_in, size: 16, color: OhtliColors.onyx.withOpacity(0.5)),
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
                        foregroundColor: OhtliColors.onyx.withOpacity(0.6),
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
      ..color = Colors.black.withOpacity(0.5)
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
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), size.width / 2, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
