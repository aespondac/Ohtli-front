import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/trip_model.dart';
import '../theme/colors.dart';
import 'trip_polaroid.dart';

/// Plan sorpresa que un amigo preparó para ti: polaroids boca abajo atadas con un
/// listón. Bloqueado muestra cuándo se abre; desbloqueado se abre con un toque
/// (el listón se suelta y las fotos se voltean) y luego llama a [onOpen].
class SurprisePolaroidCard extends StatefulWidget {
  final Trip trip;
  final bool isLocked;
  final DateTime? unlockDate;
  final String fromName;
  final String? fromPhotoUrl;
  final bool isHorizontal;
  final VoidCallback onOpen;

  /// Quitar la sorpresa de tus planes (solo para ti).
  final VoidCallback? onRemove;

  const SurprisePolaroidCard({
    super.key,
    required this.trip,
    required this.isLocked,
    required this.unlockDate,
    required this.fromName,
    this.fromPhotoUrl,
    this.isHorizontal = false,
    required this.onOpen,
    this.onRemove,
  });

  @override
  State<SurprisePolaroidCard> createState() => _SurprisePolaroidCardState();
}

class _SurprisePolaroidCardState extends State<SurprisePolaroidCard> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  late final Future<TripPhotoInfo> _photos = TripPhotos.load(widget.trip);
  bool _hover = false;
  bool _opening = false;

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  String get _unlockText {
    final d = widget.unlockDate;
    if (widget.trip.unlockOnPublish && widget.trip.status != 'published') return 'Se abre cuando lo publique';
    if (d != null && widget.isLocked) {
      const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
      final today = DateTime.now();
      final days = DateTime(d.year, d.month, d.day).difference(DateTime(today.year, today.month, today.day)).inDays;
      final when = '${d.day} ${months[d.month - 1]}';
      return days == 1 ? 'Se abre mañana · $when' : 'Se abre en $days días · $when';
    }
    return 'Ya puedes abrirlo';
  }

  Future<void> _tap() async {
    if (widget.isLocked) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Todavía no: ${_unlockText.toLowerCase()}.', style: GoogleFonts.inter()),
        behavior: SnackBarBehavior.floating,
        backgroundColor: OhtliColors.onyx,
      ));
      return;
    }
    if (_opening) return;
    setState(() => _opening = true);
    await _anim.forward();
    if (mounted) widget.onOpen();
  }

  Widget _tag({bool compact = false}) {
    final photo = widget.fromPhotoUrl;
    return Container(
      padding: EdgeInsets.fromLTRB(5, 5, compact ? 10 : 12, 5),
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: OhtliColors.accent.withValues(alpha: 0.25),
            backgroundImage: photo != null && photo.isNotEmpty ? NetworkImage(photo) : null,
            child: photo != null && photo.isNotEmpty
                ? null
                : Text(widget.fromName.isNotEmpty ? widget.fromName[0].toUpperCase() : '?',
                    style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: OhtliColors.accent)),
          ),
          const SizedBox(width: 6),
          Text('De ${widget.fromName}', style: GoogleFonts.inter(fontSize: compact ? 11 : 12, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
        ],
      ),
    );
  }

  Widget _desk({required bool compact}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, _) {
          final t = Curves.easeInOutCubic.transform(_anim.value);
          return FutureBuilder<TripPhotoInfo>(
            future: _photos,
            initialData: TripPhotos.initial(widget.trip),
            builder: (context, snap) {
              final photo = (snap.data?.photos ?? const ['']).first;
              // Cerrada: portada muy difuminada; al abrir se va enfocando
              final blur = (1 - t) * 26 + 0.01;
              final veil = (1 - t).clamp(0.0, 1.0);
              final locked = widget.isLocked;
              return Stack(
                children: [
                  Positioned.fill(
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur, tileMode: TileMode.clamp),
                      child: Transform.scale(scale: 1.15 - t * 0.15, child: OhtliPhoto(photo)),
                    ),
                  ),
                  // Velo de color para que no se adivine la foto
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: locked
                                ? [const Color(0xFF2E3238).withValues(alpha: 0.72 * veil), const Color(0xFF15171A).withValues(alpha: 0.82 * veil)]
                                : [OhtliColors.accent.withValues(alpha: 0.55 * veil), const Color(0xFF6E1F45).withValues(alpha: 0.70 * veil)],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Ícono limpio en un círculo esmerilado
                  if (t < 0.6)
                    Center(
                      child: Opacity(
                        opacity: (1 - t * 1.8).clamp(0.0, 1.0),
                        child: AnimatedScale(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutBack,
                          scale: _hover && !locked ? 1.08 : 1.0,
                          child: Container(
                            width: compact ? 40 : 58,
                            height: compact ? 40 : 58,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.16),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.45), width: 1.2),
                            ),
                            child: Icon(
                              locked ? Icons.lock_rounded : Icons.redeem_rounded,
                              color: Colors.white,
                              size: compact ? 18 : 26,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (!compact) Positioned(bottom: 10, left: 10, child: _tag()),
                  if (widget.onRemove != null && t == 0)
                    Positioned(top: compact ? 4 : 8, right: compact ? 4 : 8, child: _removeButton(compact)),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmRemove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OhtliColors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('¿Quitar la sorpresa de tus planes?',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 20, color: OhtliColors.onyx)),
        content: Text(
          'Dejarás de verla aquí. Es de ${widget.fromName}, así que no se borra para nadie más.',
          style: GoogleFonts.inter(color: OhtliColors.subtleText, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancelar', style: GoogleFonts.inter(color: OhtliColors.subtleText, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: OhtliColors.accentFill,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Quitar', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok == true) widget.onRemove?.call();
  }

  Widget _removeButton(bool compact) {
    return Tooltip(
      message: 'Quitar de mis planes',
      child: Material(
        color: Colors.black.withValues(alpha: 0.38),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _confirmRemove,
          child: SizedBox(
            width: compact ? 24 : 30,
            height: compact ? 24 : 30,
            child: Icon(Icons.close_rounded, size: compact ? 14 : 17, color: Colors.white),
          ),
        ),
      ),
    );
  }

  BoxDecoration get _decoration => BoxDecoration(
        color: OhtliColors.cardBg,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: widget.isLocked ? OhtliColors.cardBorder : OhtliColors.accent.withValues(alpha: _hover ? 0.6 : 0.4),
          width: widget.isLocked ? 1 : 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: (_hover ? OhtliColors.accent : Colors.black).withValues(alpha: _hover ? 0.16 : 0.05),
            blurRadius: _hover ? 30 : 14,
            spreadRadius: -4,
            offset: Offset(0, _hover ? 16 : 6),
          ),
        ],
      );

  Widget _statusPill() {
    final locked = widget.isLocked;
    final c = locked ? OhtliColors.onyx.withValues(alpha: 0.8) : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: locked ? OhtliColors.innerCardBg : null,
        gradient: locked ? null : LinearGradient(colors: [OhtliColors.accent, Color(0xFFB8325A)]),
        borderRadius: BorderRadius.circular(30),
        border: locked ? Border.all(color: OhtliColors.cardBorder) : null,
        boxShadow: locked ? null : [BoxShadow(color: OhtliColors.accent.withValues(alpha: _hover ? 0.45 : 0.25), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(locked ? Icons.schedule_rounded : Icons.touch_app_rounded, size: 13, color: c),
          const SizedBox(width: 5),
          Flexible(
            child: Text(locked ? _unlockText : 'Toca para abrir',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: c)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.isHorizontal ? _horizontal() : _vertical();
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(onTap: _tap, child: card),
    );
  }

  Widget _vertical() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      transform: Matrix4.translationValues(0, _hover ? -4 : 0, 0),
      decoration: _decoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(6, 6, 6, 0), child: _desk(compact: false))),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Un viaje sorpresa',
                    style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800, color: OhtliColors.onyx, letterSpacing: -0.2)),
                const SizedBox(height: 2),
                Text('${widget.fromName} preparó este recorrido para ti.',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: OhtliColors.subtleText)),
                const SizedBox(height: 8),
                _statusPill(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _horizontal() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      height: 112,
      decoration: _decoration,
      child: Row(
        children: [
          Padding(padding: const EdgeInsets.all(6), child: SizedBox(width: 100, child: _desk(compact: true))),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Un viaje sorpresa', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
                      const SizedBox(height: 6),
                      _tag(compact: true),
                    ],
                  ),
                  _statusPill(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
