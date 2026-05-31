import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:convert';
import '../theme/colors.dart';
import '../models/trip_model.dart';
import 'ohtli_markdown_renderer.dart';

class TripCard extends StatelessWidget {
  final Trip trip;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback? onFeDeErratas;
  final bool isHorizontal;

  const TripCard({
    super.key,
    required this.trip,
    required this.onDelete,
    required this.onEdit,
    this.onFeDeErratas,
    this.isHorizontal = false,
  });

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
    final String tripUrl = '$baseUrl?tripId=${trip.id}&authorId=${trip.userId}';
    final String shareMessage = '¡Mira mi viaje "${trip.title}" en Ohtli! $tripUrl';

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
            'Esta acción no se puede deshacer. Se eliminarán permanentemente el viaje "${trip.title}", todos sus planes y las fotos asociadas.',
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
                onDelete();
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
    final bool hasCover = trip.coverUrl.isNotEmpty;

    final border = isHorizontal
        ? const BorderRadius.horizontal(left: Radius.circular(24))
        : const BorderRadius.vertical(top: Radius.circular(24));

    Widget imageWidget;
    if (hasCover) {
      if (trip.coverUrl.startsWith('data:image') || trip.coverUrl.startsWith('data:')) {
        try {
          final String base64Data = trip.coverUrl.split(',').last;
          imageWidget = Image.memory(
            base64Decode(base64Data),
            fit: BoxFit.cover,
          );
        } catch (e) {
          imageWidget = _buildCoverFallback();
        }
      } else {
        imageWidget = CachedNetworkImage(
          imageUrl: trip.coverUrl,
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
                    trip.visibility == 'public'
                        ? Icons.public_rounded
                        : Icons.lock_outline_rounded,
                    color: Colors.white,
                    size: 11,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    trip.visibility == 'public' ? 'Público' : 'Privado',
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
                        trip.title,
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
                        text: trip.description.isNotEmpty 
                            ? trip.description 
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
                              'Creado: ${_formatSpanishDate(trip.createdAt)}',
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
                              'Viaje: ${trip.travelDate != null ? _formatSpanishDate(trip.travelDate!) : "Sin fecha definida"}',
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
                            onEdit();
                          } else if (value == 'share') {
                            _handleShare(context);
                          } else if (value == 'errata') {
                            if (onFeDeErratas != null) {
                              onFeDeErratas!();
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
                                  trip.status == 'published'
                                      ? Icons.visibility_rounded
                                      : Icons.edit_outlined,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  trip.status == 'published' ? 'Ver' : 'Editar',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: OhtliColors.onyx,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (trip.status == 'published')
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
                        trip.title,
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
                        text: trip.description.isNotEmpty 
                            ? trip.description 
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
                              'Creado: ${_formatSpanishDate(trip.createdAt)}',
                              style: GoogleFonts.inter(
                                fontSize: 9,
                                color: OhtliColors.onyx.withValues(alpha: 0.4),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              'Viaje: ${trip.travelDate != null ? _formatSpanishDate(trip.travelDate!) : "Sin fecha definida"}',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: OhtliColors.onyx.withValues(alpha: 0.65),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
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
                            onEdit();
                          } else if (value == 'share') {
                            _handleShare(context);
                          } else if (value == 'errata') {
                            if (onFeDeErratas != null) {
                              onFeDeErratas!();
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
                                  trip.status == 'published'
                                      ? Icons.visibility_rounded
                                      : Icons.edit_outlined,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  trip.status == 'published' ? 'Ver' : 'Editar',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: OhtliColors.onyx,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (trip.status == 'published')
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
    return GestureDetector(
      onTap: onEdit,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: isHorizontal
            ? _buildHorizontalLayout(context, isDark)
            : _buildVerticalLayout(context, isDark),
      ),
    );
  }
}
