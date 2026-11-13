import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import '../theme/colors.dart';
import '../models/trip_model.dart';
import '../services/trip_service.dart';
import '../services/pdf_export_service.dart';
import 'ohtli_markdown_renderer.dart';
import 'interactive_3d_card.dart';
import '../utils/friendly_errors.dart';

class TripCard extends StatefulWidget {
  final Trip trip;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback? onFeDeErratas;
  final bool isHorizontal;
  final String? addedByName;
  final String? addedByPhotoURL;
  final bool disable3D;

  const TripCard({
    super.key,
    required this.trip,
    required this.onDelete,
    required this.onEdit,
    this.onFeDeErratas,
    this.isHorizontal = false,
    this.addedByName,
    this.addedByPhotoURL,
    this.disable3D = false,
  });

  @override
  State<TripCard> createState() => _TripCardState();
}

class _TripCardState extends State<TripCard> {
  bool _isExportingPdf = false;

  String _formatSpanishDate(DateTime date) {
    final months = [
      'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
      'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'
    ];
    return '${date.day} de ${months[date.month - 1]} de ${date.year}';
  }

  void _handleShare(BuildContext context) {
    final String baseUrl = kIsWeb 
        ? "${Uri.base.scheme}://${Uri.base.host}${Uri.base.port != 80 && Uri.base.port != 443 && Uri.base.port != 0 ? ':${Uri.base.port}' : ''}/"
        : 'https://ohtli.quest/';
    final String tripUrl = '${baseUrl}viajes/${widget.trip.userId}/${widget.trip.id}';
    final String shareMessage = '¡Mira mi viaje "${widget.trip.title}" en Ohtli! $tripUrl';

    if (kIsWeb) {
      Clipboard.setData(ClipboardData(text: tripUrl)).then((_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Enlace del viaje copiado al portapapeles',
                style: GoogleFonts.inter(color: Colors.white),
              ),
              backgroundColor: OhtliColors.stormyTeal,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      });
    } else {
      Share.share(shareMessage);
    }
  }

  Future<void> _handlePdfExport(BuildContext context) async {
    if (_isExportingPdf) return;
    setState(() => _isExportingPdf = true);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Generando PDF editorial de "${widget.trip.title}"...',
                style: GoogleFonts.inter(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: OhtliColors.stormyTeal,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    try {
      // 1. Obtener contenido y secciones del viaje
      final tripContent = await TripService().getTripContent(widget.trip.userId, widget.trip.id);
      final sections = tripContent?.sections ?? [];

      if (!context.mounted) return;

      if (sections.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'El viaje no tiene paradas o secciones cargadas para exportar.',
              style: GoogleFonts.inter(color: Colors.white),
            ),
            backgroundColor: OhtliColors.xoconostle,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        setState(() => _isExportingPdf = false);
        return;
      }

      // 2. Determinar nombre del autor
      String authorName = widget.addedByName ?? '';
      if (authorName.isEmpty) {
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null && currentUser.uid == widget.trip.userId) {
          authorName = currentUser.displayName ?? 'Viajero Ohtli';
        } else {
          try {
            final authorDoc = await FirebaseFirestore.instance.collection('users').doc(widget.trip.userId).get();
            if (authorDoc.exists) {
              authorName = (authorDoc.data()?['displayName'] as String?) ?? 'Viajero Ohtli';
            }
          } catch (_) {}
        }
      }
      if (authorName.isEmpty) authorName = 'Viajero Ohtli';

      // 3. Base URL para QR
      final String baseUrl = kIsWeb
          ? "${Uri.base.scheme}://${Uri.base.host}${Uri.base.port != 80 && Uri.base.port != 443 && Uri.base.port != 0 ? ':${Uri.base.port}' : ''}/"
          : 'https://ohtli.quest/';
      final String qrBaseUrl = '${baseUrl}?tripId=${widget.trip.id}&authorId=${widget.trip.userId}';

      // 4. Descargar PDF interactivo con QR
      await PdfExportService.downloadTripPdf(
        trip: widget.trip,
        sections: sections,
        authorName: authorName,
        coAuthors: widget.trip.coAuthorNames,
        qrBaseUrl: qrBaseUrl,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '¡PDF de "${widget.trip.title}" descargado con éxito!',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: OhtliColors.stormyTeal,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              friendlyError(e, fallback: 'No pudimos exportar el viaje a PDF. Intenta de nuevo.'),
              style: GoogleFonts.inter(color: Colors.white),
            ),
            backgroundColor: OhtliColors.xoconostle,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExportingPdf = false);
      }
    }
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: OhtliColors.cloudDancer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(
            '¿Eliminar viaje?',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              color: OhtliColors.onyx,
            ),
          ),
          content: Text(
            'Esta acción no se puede deshacer. Se eliminarán permanentemente el viaje "${widget.trip.title}", todos sus planes y las fotos asociadas.',
            style: GoogleFonts.inter(
              color: OhtliColors.onyx.withValues(alpha: 0.8),
            ),
          ),
          actionsPadding: const EdgeInsets.only(right: 16, bottom: 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'Cancelar',
                style: GoogleFonts.inter(
                  color: OhtliColors.onyx.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                widget.onDelete();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: OhtliColors.xoconostle,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: Text(
                'Eliminar',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCoverImage({required bool isHorizontal}) {
    final bool hasCover = widget.trip.coverUrl.isNotEmpty;

    final border = isHorizontal
        ? const BorderRadius.horizontal(left: Radius.circular(24))
        : const BorderRadius.vertical(top: Radius.circular(24));

    Widget imageWidget;
    if (hasCover) {
      if (widget.trip.coverUrl.startsWith('data:image') || widget.trip.coverUrl.startsWith('data:')) {
        try {
          final String base64Data = widget.trip.coverUrl.split(',').last;
          imageWidget = Image.memory(
            base64Decode(base64Data),
            fit: BoxFit.cover,
          );
        } catch (e) {
          imageWidget = _buildCoverFallback();
        }
      } else {
        imageWidget = CachedNetworkImage(
          imageUrl: widget.trip.coverUrl,
          fit: BoxFit.cover,
          fadeInDuration: const Duration(milliseconds: 300),
          placeholder: (context, url) => Container(
            color: OhtliColors.cantera.withValues(alpha: 0.3),
            child: const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(OhtliColors.stormyTeal),
              ),
            ),
          ),
          errorWidget: (context, url, error) => _buildCoverFallback(),
        );
      }
    } else {
      imageWidget = _buildCoverFallback();
    }

    return ClipRRect(
      borderRadius: border,
      child: Stack(
        fit: StackFit.expand,
        children: [
          imageWidget,
          
          // Visibility Badge
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.trip.visibility == 'public'
                        ? Icons.public_rounded
                        : Icons.lock_outline_rounded,
                    color: Colors.white,
                    size: 11,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    widget.trip.visibility == 'public' ? 'Público' : 'Privado',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // "Añadido por" badge for co-authored trips
          if (widget.addedByName != null) 
            Positioned(
              bottom: 8,
              left: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.addedByPhotoURL != null && widget.addedByPhotoURL!.isNotEmpty)
                      CircleAvatar(
                        radius: 9,
                        backgroundImage: NetworkImage(widget.addedByPhotoURL!),
                        backgroundColor: OhtliColors.stormyTeal.withValues(alpha: 0.3),
                      )
                    else
                      CircleAvatar(
                        radius: 9,
                        backgroundColor: OhtliColors.stormyTeal.withValues(alpha: 0.5),
                        child: Text(
                          widget.addedByName!.isNotEmpty ? widget.addedByName![0].toUpperCase() : '?',
                          style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Añadido por ${widget.addedByName}',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCoverFallback() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            OhtliColors.stormyTeal.withValues(alpha: 0.8),
            OhtliColors.xoconostle.withValues(alpha: 0.7),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.landscape_rounded,
              color: Colors.white70,
              size: 40,
            ),
            const SizedBox(height: 6),
            Text(
              'Ohtli',
              style: GoogleFonts.inter(
                color: Colors.white70,
                fontSize: 12,
                letterSpacing: 2,
                fontWeight: FontWeight.w300,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerticalLayout(BuildContext context, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E22) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? const Color(0xFF2C2C32) : OhtliColors.cantera.withValues(alpha: 0.4),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: OhtliColors.onyx.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: _buildCoverImage(isHorizontal: false),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.trip.title,
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: OhtliColors.onyx,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      OhtliMarkdownText(
                        text: widget.trip.description.isNotEmpty 
                            ? widget.trip.description 
                            : 'Sin descripción del viaje.',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: OhtliColors.onyx.withValues(alpha: 0.6),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Creado: ${_formatSpanishDate(widget.trip.createdAt)}',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: OhtliColors.onyx.withValues(alpha: 0.4),
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Viaje: ${widget.trip.travelDate != null ? _formatSpanishDate(widget.trip.travelDate!) : "Sin fecha definida"}',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: OhtliColors.onyx.withValues(alpha: 0.65),
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'Generar PDF',
                        child: ElevatedButton.icon(
                          onPressed: _isExportingPdf ? null : () => _handlePdfExport(context),
                          icon: _isExportingPdf
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Icon(
                                  Icons.picture_as_pdf_rounded,
                                  size: 15,
                                ),
                          label: Text(
                            'Generar PDF',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: OhtliColors.stormyTeal,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      PopupMenuButton<String>(
                        icon: const Icon(
                          Icons.more_vert_rounded,
                          size: 20,
                        ),
                        iconColor: OhtliColors.stormyTeal,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        color: isDark ? const Color(0xFF25252A) : Colors.white,
                        onSelected: (value) {
                          if (value == 'edit') {
                            widget.onEdit();
                          } else if (value == 'pdf') {
                            _handlePdfExport(context);
                          } else if (value == 'share') {
                            _handleShare(context);
                          } else if (value == 'errata') {
                            if (widget.onFeDeErratas != null) {
                              widget.onFeDeErratas!();
                            }
                          } else if (value == 'delete') {
                            _showDeleteConfirmation(context);
                          }
                        },
                        itemBuilder: (BuildContext context) => [
                          PopupMenuItem<String>(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(
                                  widget.trip.status == 'published'
                                      ? Icons.visibility_rounded
                                      : Icons.edit_outlined,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  widget.trip.status == 'published' ? 'Ver' : 'Editar',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: OhtliColors.onyx,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'pdf',
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.picture_as_pdf_rounded,
                                  size: 18,
                                  color: OhtliColors.stormyTeal,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Generar PDF',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: OhtliColors.onyx,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (widget.trip.status == 'published')
                            PopupMenuItem<String>(
                              value: 'errata',
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.history_edu_rounded,
                                    size: 18,
                                    color: OhtliColors.xoconostle,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Fe de Erratas',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      color: OhtliColors.onyx,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          PopupMenuItem<String>(
                            value: 'share',
                            child: Row(
                              children: [
                                const Icon(Icons.share_outlined, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  'Compartir',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: OhtliColors.onyx,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const PopupMenuDivider(height: 1),
                          PopupMenuItem<String>(
                            value: 'delete',
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                  color: OhtliColors.xoconostle,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Eliminar',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: OhtliColors.xoconostle,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalLayout(BuildContext context, bool isDark) {
    return Container(
      height: 125,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E22) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? const Color(0xFF2C2C32) : OhtliColors.cantera.withValues(alpha: 0.4),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: OhtliColors.onyx.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          // Image on the left (aspect ratio 16/9, matching container height)
          SizedBox(
            width: 130,
            height: 125,
            child: _buildCoverImage(isHorizontal: true),
          ),
          
          // Details on the right
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.trip.title,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: OhtliColors.onyx,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      OhtliMarkdownText(
                        text: widget.trip.description.isNotEmpty 
                            ? widget.trip.description 
                            : 'Sin descripción del viaje.',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: OhtliColors.onyx.withValues(alpha: 0.6),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Creado: ${_formatSpanishDate(widget.trip.createdAt)}',
                              style: GoogleFonts.inter(
                                fontSize: 9,
                                color: OhtliColors.onyx.withValues(alpha: 0.4),
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'Viaje: ${widget.trip.travelDate != null ? _formatSpanishDate(widget.trip.travelDate!) : "Sin fecha definida"}',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: OhtliColors.onyx.withValues(alpha: 0.65),
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Tooltip(
                        message: 'Generar PDF',
                        child: ElevatedButton.icon(
                          onPressed: _isExportingPdf ? null : () => _handlePdfExport(context),
                          icon: _isExportingPdf
                              ? const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Icon(
                                  Icons.picture_as_pdf_rounded,
                                  size: 14,
                                ),
                          label: Text(
                            'Generar PDF',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: OhtliColors.stormyTeal,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      PopupMenuButton<String>(
                        icon: const Icon(
                          Icons.more_vert_rounded,
                          size: 18,
                        ),
                        iconColor: OhtliColors.stormyTeal,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        color: isDark ? const Color(0xFF25252A) : Colors.white,
                        onSelected: (value) {
                          if (value == 'edit') {
                            widget.onEdit();
                          } else if (value == 'pdf') {
                            _handlePdfExport(context);
                          } else if (value == 'share') {
                            _handleShare(context);
                          } else if (value == 'errata') {
                            if (widget.onFeDeErratas != null) {
                              widget.onFeDeErratas!();
                            }
                          } else if (value == 'delete') {
                            _showDeleteConfirmation(context);
                          }
                        },
                        itemBuilder: (BuildContext context) => [
                          PopupMenuItem<String>(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(
                                  widget.trip.status == 'published'
                                      ? Icons.visibility_rounded
                                      : Icons.edit_outlined,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  widget.trip.status == 'published' ? 'Ver' : 'Editar',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: OhtliColors.onyx,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'pdf',
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.picture_as_pdf_rounded,
                                  size: 16,
                                  color: OhtliColors.stormyTeal,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Generar PDF',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: OhtliColors.onyx,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (widget.trip.status == 'published')
                            PopupMenuItem<String>(
                              value: 'errata',
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.history_edu_rounded,
                                    size: 16,
                                    color: OhtliColors.xoconostle,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Fe de Erratas',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: OhtliColors.onyx,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          PopupMenuItem<String>(
                            value: 'share',
                            child: Row(
                              children: [
                                const Icon(Icons.share_outlined, size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  'Compartir',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: OhtliColors.onyx,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const PopupMenuDivider(height: 1),
                          PopupMenuItem<String>(
                            value: 'delete',
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 16,
                                  color: OhtliColors.xoconostle,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Eliminar',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: OhtliColors.xoconostle,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = OhtliSettings.instance.isDarkMode;
    final content = widget.isHorizontal
        ? _buildHorizontalLayout(context, isDark)
        : _buildVerticalLayout(context, isDark);
        
    if (widget.disable3D) {
      return GestureDetector(
        onTap: widget.onEdit,
        child: content,
      );
    }
    
    return Interactive3DCard(
      onTap: widget.onEdit,
      isDark: isDark,
      child: content,
    );
  }
}
