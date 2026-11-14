import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/colors.dart';
import '../models/trip_model.dart';
import '../services/trip_service.dart';
import '../services/pdf_export_service.dart';
import 'ohtli_markdown_renderer.dart';
import 'trip_polaroid.dart';
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
  /// Hay algo nuevo (p. ej. un comentario) desde tu última visita.
  final bool hasNews;
  final String newsLabel;

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
    this.hasNews = false,
    this.newsLabel = 'Nuevo',
  });

  @override
  State<TripCard> createState() => _TripCardState();
}

class _TripCardState extends State<TripCard> {
  bool _isExportingPdf = false;
  bool _hover = false;
  late Future<TripPhotoInfo> _photos;

  @override
  void initState() {
    super.initState();
    _photos = TripPhotos.load(widget.trip);
  }

  @override
  void didUpdateWidget(covariant TripCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trip.id != widget.trip.id || oldWidget.trip.updatedAt != widget.trip.updatedAt) {
      _photos = TripPhotos.load(widget.trip);
    }
  }

  String _formatShortDate(DateTime date) {
    const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    final now = DateTime.now();
    final base = '${date.day} ${months[date.month - 1]}';
    return date.year == now.year ? base : '$base ${date.year}';
  }

  bool get _isPublished => widget.trip.status == 'published';

  Widget _buildStatusChip() {
    final published = _isPublished;
    final color = published ? OhtliColors.stormyTeal : OhtliColors.cempasuchil;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(published ? Icons.check_circle_rounded : Icons.edit_note_rounded, size: 13, color: published ? OhtliColors.accentText : const Color(0xFFB4690E)),
          const SizedBox(width: 5),
          Text(
            published ? 'Publicado' : 'Borrador',
            style: GoogleFonts.inter(color: published ? OhtliColors.accentText : const Color(0xFFB4690E), fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildTravelDate({double fontSize = 12}) {
    final date = widget.trip.travelDate;
    final muted = OhtliColors.onyx.withValues(alpha: 0.55);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(date != null ? Icons.event_rounded : Icons.event_busy_rounded, size: fontSize + 3, color: date != null ? OhtliColors.stormyTeal : muted),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            date != null ? _formatShortDate(date) : 'Sin fecha',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: date != null ? OhtliColors.onyx.withValues(alpha: 0.8) : muted,
            ),
          ),
        ),
      ],
    );
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

  // ───────────── Piezas ─────────────

  Widget _pill({required IconData icon, required String label, Color? color}) {
    final c = color ?? OhtliColors.onyx.withValues(alpha: 0.75);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: OhtliColors.innerCardBg,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: OhtliColors.cardBorder, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color ?? OhtliColors.accentText),
          const SizedBox(width: 5),
          Text(label, style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: c)),
        ],
      ),
    );
  }

  // ───────────── Sorpresas ─────────────

  bool get _isSurprise => widget.trip.isSurprise;
  bool get _isOwnSurprise => _isSurprise && widget.trip.userId == FirebaseAuth.instance.currentUser?.uid;

  String get _surpriseFor {
    final names = widget.trip.surpriseTargetNames.where((n) => n.trim().isNotEmpty).toList();
    if (names.isEmpty) return 'Para un amigo';
    final first = names.first.split(' ').first;
    return names.length == 1 ? 'Para $first' : 'Para $first +${names.length - 1}';
  }

  String get _surpriseWhen {
    if (widget.trip.unlockOnPublish) return widget.trip.status == 'published' ? 'Ya se puede abrir' : 'Se abre al publicar';
    final dates = widget.trip.surpriseUnlockDates.values.toList()..sort();
    if (dates.isEmpty) return 'Ya se puede abrir';
    final d = dates.first;
    final now = DateTime.now();
    if (!DateTime(now.year, now.month, now.day).isBefore(DateTime(d.year, d.month, d.day))) return 'Ya se puede abrir';
    return 'Se abre el ${_formatShortDate(d)}';
  }

  Widget _surpriseChipOnPhoto() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [OhtliColors.xoconostle, Color(0xFFB8325A)]),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: OhtliColors.xoconostle.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.card_giftcard_rounded, size: 12, color: Colors.white),
          const SizedBox(width: 5),
          Text(_isOwnSurprise ? 'Sorpresa · ${_isPublished ? 'Publicada' : 'Borrador'}' : 'Sorpresa',
              style: GoogleFonts.inter(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  /// Listón diagonal en la esquina de la foto de una sorpresa.
  Widget _ribbonCorner() {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomRight,
        child: Transform.translate(
          offset: const Offset(26, -14),
          child: Transform.rotate(
            angle: -0.75,
            child: Container(
              width: 130,
              height: 16,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFE8892B), OhtliColors.cempasuchil, Color(0xFFE8892B)]),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 6, offset: const Offset(0, 2))],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChipOnPhoto() {
    if (_isSurprise) return _surpriseChipOnPhoto();
    final published = _isPublished;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(published ? Icons.check_circle_rounded : Icons.edit_note_rounded, size: 12, color: published ? Colors.white : OhtliColors.cempasuchil),
          const SizedBox(width: 5),
          Text(published ? 'Publicado' : 'Borrador', style: GoogleFonts.inter(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _newsBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: OhtliColors.xoconostle,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: OhtliColors.xoconostle.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.chat_bubble_rounded, size: 11, color: Colors.white),
          const SizedBox(width: 5),
          Text(widget.newsLabel, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
        ],
      ),
    );
  }

  Widget _visibilityBadge({bool compact = false}) {
    final public = widget.trip.visibility == 'public';
    return Container(
      padding: compact ? const EdgeInsets.all(6) : const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(public ? Icons.public_rounded : Icons.lock_outline_rounded, color: OhtliColors.onyx.withValues(alpha: 0.7), size: 12),
          if (!compact) ...[
            const SizedBox(width: 4),
            Text(public ? 'Público' : 'Privado',
                style: GoogleFonts.inter(color: OhtliColors.onyx.withValues(alpha: 0.75), fontSize: 10.5, fontWeight: FontWeight.w700)),
          ],
        ],
      ),
    );
  }

  Widget _addedBy() {
    final name = widget.addedByName ?? '';
    final photo = widget.addedByPhotoURL;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 9,
          backgroundColor: OhtliColors.stormyTeal.withValues(alpha: 0.4),
          backgroundImage: photo != null && photo.isNotEmpty ? NetworkImage(photo) : null,
          child: photo != null && photo.isNotEmpty
              ? null
              : Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white)),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(_isSurprise ? 'Sorpresa de $name' : 'Con $name',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: OhtliColors.subtleText)),
        ),
      ],
    );
  }

  Widget _photosArea({required bool compact}) {
    return AnimatedScale(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      scale: _hover ? 1.05 : 1.0,
      child: OhtliPhoto(TripPhotos.initial(widget.trip).photos.first),
    );
  }

  Widget _stopsPill() {
    return FutureBuilder<TripPhotoInfo>(
      future: _photos,
      builder: (context, snap) {
        final n = snap.data?.stops ?? 0;
        if (n == 0) return const SizedBox.shrink();
        return _pill(icon: Icons.place_rounded, label: '$n ${n == 1 ? 'parada' : 'paradas'}');
      },
    );
  }

  void _onMenu(String value, BuildContext context) {
    if (value == 'edit') {
      widget.onEdit();
    } else if (value == 'pdf') {
      _handlePdfExport(context);
    } else if (value == 'share') {
      _handleShare(context);
    } else if (value == 'errata') {
      widget.onFeDeErratas?.call();
    } else if (value == 'delete') {
      _showDeleteConfirmation(context);
    }
  }

  Widget _menu(BuildContext context, bool isDark) {
    PopupMenuItem<String> item(String value, IconData icon, String label, {Color? color}) => PopupMenuItem<String>(
          value: value,
          child: Row(
            children: [
              Icon(icon, size: 18, color: color ?? OhtliColors.onyx.withValues(alpha: 0.75)),
              const SizedBox(width: 10),
              Text(label, style: GoogleFonts.inter(fontSize: 13, color: color ?? OhtliColors.onyx, fontWeight: color != null ? FontWeight.w600 : FontWeight.w500)),
            ],
          ),
        );
    final published = widget.trip.status == 'published';
    return PopupMenuButton<String>(
      tooltip: 'Más opciones',
      icon: Icon(Icons.more_horiz_rounded, size: 20, color: OhtliColors.onyx.withValues(alpha: 0.6)),
      style: IconButton.styleFrom(backgroundColor: OhtliColors.innerCardBg, shape: const CircleBorder()),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      color: isDark ? const Color(0xFF25252A) : Colors.white,
      onSelected: (v) => _onMenu(v, context),
      itemBuilder: (_) => [
        item('edit', published ? Icons.visibility_rounded : Icons.edit_outlined, published ? 'Ver' : 'Editar'),
        item('pdf', Icons.picture_as_pdf_rounded, 'Generar PDF'),
        if (published && widget.onFeDeErratas != null) item('errata', Icons.history_edu_rounded, 'Fe de erratas'),
        item('share', Icons.ios_share_rounded, 'Compartir'),
        const PopupMenuDivider(height: 1),
        item('delete', Icons.delete_outline_rounded, 'Eliminar', color: OhtliColors.xoconostle),
      ],
    );
  }

  BoxDecoration _cardDecoration(bool isDark) => BoxDecoration(
        color: isDark ? const Color(0xFF1E1E22) : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: widget.hasNews || _isSurprise
              ? OhtliColors.xoconostle.withValues(alpha: widget.hasNews ? 0.55 : 0.35)
              : (_hover ? OhtliColors.stormyTeal.withValues(alpha: 0.35) : OhtliColors.cardBorder),
          width: widget.hasNews || _isSurprise ? 1.4 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: (_hover ? OhtliColors.stormyTeal : Colors.black).withValues(alpha: _hover ? 0.16 : 0.05),
            blurRadius: _hover ? 30 : 14,
            spreadRadius: -4,
            offset: Offset(0, _hover ? 16 : 6),
          ),
        ],
      );

  String get _description => widget.trip.description.isNotEmpty ? widget.trip.description : 'Sin descripción del viaje.';

  // ───────────── Diseños ─────────────

  Widget _buildVerticalLayout(BuildContext context, bool isDark) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      transform: Matrix4.translationValues(0, _hover ? -4 : 0, 0),
      decoration: _cardDecoration(isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Portada del viaje
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  children: [
                    Positioned.fill(child: _photosArea(compact: false)),
                    if (_isSurprise) Positioned.fill(child: _ribbonCorner()),
                    Positioned(top: 10, left: 10, child: _buildStatusChipOnPhoto()),
                    Positioned(top: 10, right: 10, child: widget.hasNews ? _newsBadge() : _visibilityBadge(compact: true)),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.trip.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800, color: OhtliColors.onyx, letterSpacing: -0.2, height: 1.15),
                ),
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: OhtliMarkdownText(
                    text: _description,
                    style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: OhtliColors.subtleText),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: widget.addedByName != null
                          ? _addedBy()
                          : SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: _isOwnSurprise
                                  ? Row(children: [
                                      _pill(icon: Icons.card_giftcard_rounded, label: _surpriseFor, color: OhtliColors.xoconostle),
                                      const SizedBox(width: 6),
                                      _pill(icon: Icons.schedule_rounded, label: _surpriseWhen),
                                    ])
                                  : Row(children: [
                                _pill(icon: widget.trip.travelDate != null ? Icons.event_rounded : Icons.event_busy_rounded,
                                    label: widget.trip.travelDate != null ? _formatShortDate(widget.trip.travelDate!) : 'Sin fecha'),
                                const SizedBox(width: 6),
                                _stopsPill(),
                              ]),
                            ),
                    ),
                    _menu(context, isDark),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalLayout(BuildContext context, bool isDark) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      height: 112,
      decoration: _cardDecoration(isDark),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.all(6),
            child: SizedBox(
              width: 100,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(children: [Positioned.fill(child: _photosArea(compact: true)), if (_isSurprise) Positioned.fill(child: _ribbonCorner())]),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 4, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.trip.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: OhtliColors.onyx, height: 1.15),
                            ),
                          ),
                          if (widget.hasNews) ...[
                            const SizedBox(width: 6),
                            Container(width: 9, height: 9, decoration: const BoxDecoration(color: OhtliColors.xoconostle, shape: BoxShape.circle)),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      OhtliMarkdownText(
                        text: _description,
                        style: GoogleFonts.inter(fontSize: 12, height: 1.4, color: OhtliColors.subtleText),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      _isSurprise ? _surpriseChipOnPhoto() : _buildStatusChip(),
                      const SizedBox(width: 6),
                      Expanded(
                        child: widget.addedByName != null
                            ? _addedBy()
                            : (_isOwnSurprise
                                ? Text('${_surpriseFor} · ${_surpriseWhen.toLowerCase()}',
                                    maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: OhtliColors.subtleText))
                                : _buildTravelDate(fontSize: 11.5)),
                      ),
                      _menu(context, isDark),
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
    final content = widget.isHorizontal ? _buildHorizontalLayout(context, isDark) : _buildVerticalLayout(context, isDark);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onEdit,
        onLongPressStart: (_) => setState(() => _hover = true),
        onLongPressEnd: (_) => setState(() => _hover = false),
        child: content,
      ),
    );
  }
}
