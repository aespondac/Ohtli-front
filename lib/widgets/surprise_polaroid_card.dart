import 'dart:math' as math;

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

  const SurprisePolaroidCard({
    super.key,
    required this.trip,
    required this.isLocked,
    required this.unlockDate,
    required this.fromName,
    this.fromPhotoUrl,
    this.isHorizontal = false,
    required this.onOpen,
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

  Widget _ribbon(double t) {
    // Listón diagonal que se desliza y se desvanece al abrir
    return IgnorePointer(
      child: Opacity(
        opacity: (1 - t * 1.6).clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(t * 260, -t * 60),
          child: Transform.rotate(
            angle: -0.32,
            child: Center(
              child: Container(
                height: 26,
                width: 2000,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFE8892B), OhtliColors.cempasuchil, Color(0xFFE8892B)]),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 8, offset: const Offset(0, 3))],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tag({bool compact = false}) {
    final photo = widget.fromPhotoUrl;
    return Container(
      padding: EdgeInsets.fromLTRB(5, 5, compact ? 10 : 12, 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: OhtliColors.xoconostle.withValues(alpha: 0.25),
            backgroundImage: photo != null && photo.isNotEmpty ? NetworkImage(photo) : null,
            child: photo != null && photo.isNotEmpty
                ? null
                : Text(widget.fromName.isNotEmpty ? widget.fromName[0].toUpperCase() : '?',
                    style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: OhtliColors.xoconostle)),
          ),
          const SizedBox(width: 6),
          Text('De ${widget.fromName}', style: GoogleFonts.inter(fontSize: compact ? 11 : 12, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
        ],
      ),
    );
  }

  Widget _centerSeal() {
    final locked = widget.isLocked;
    return AnimatedScale(
      duration: const Duration(milliseconds: 260),
      scale: _hover && !locked ? 1.08 : 1,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: locked ? OhtliColors.onyx : OhtliColors.xoconostle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 14, offset: const Offset(0, 6))],
        ),
        child: Icon(locked ? Icons.lock_rounded : Icons.card_giftcard_rounded, color: Colors.white, size: 22),
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
          final flipped = t > 0.5;
          return FutureBuilder<TripPhotoInfo>(
            future: _photos,
            initialData: TripPhotos.initial(widget.trip),
            builder: (context, snap) {
              // Volteo: escala horizontal 1 → 0 → 1 cambiando de reverso a foto
              final sx = (math.cos(t * math.pi)).abs().clamp(0.02, 1.0);
              final wrapped = DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: widget.isLocked
                        ? [const Color(0xFF3A3F47), const Color(0xFF23262B)]
                        : [OhtliColors.xoconostle, const Color(0xFFB8325A)],
                  ),
                ),
                child: CustomPaint(painter: _ConfettiPainter(widget.trip.id.hashCode)),
              );
              return Stack(
                children: [
                  Positioned.fill(
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.diagonal3Values(sx, 1, 1),
                      child: flipped ? OhtliPhoto((snap.data?.photos ?? const ['']).first) : wrapped,
                    ),
                  ),
                  Positioned.fill(child: _ribbon(t)),
                  if (!flipped) Center(child: Opacity(opacity: (1 - t * 2).clamp(0.0, 1.0), child: _centerSeal())),
                  if (!compact) Positioned(top: 12, left: 12, child: _tag()),
                ],
              );
            },
          );
        },
      ),
    );
  }

  BoxDecoration get _decoration => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: widget.isLocked ? OhtliColors.cardBorder : OhtliColors.xoconostle.withValues(alpha: _hover ? 0.6 : 0.4),
          width: widget.isLocked ? 1 : 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: (_hover ? OhtliColors.xoconostle : Colors.black).withValues(alpha: _hover ? 0.16 : 0.05),
            blurRadius: _hover ? 30 : 14,
            spreadRadius: -4,
            offset: Offset(0, _hover ? 16 : 6),
          ),
        ],
      );

  Widget _statusPill() {
    final locked = widget.isLocked;
    final c = locked ? OhtliColors.onyx.withValues(alpha: 0.7) : OhtliColors.xoconostle;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(30)),
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

/// Papel de regalo: puntos y destellos suaves en posiciones fijas por viaje.
class _ConfettiPainter extends CustomPainter {
  final int seed;
  _ConfettiPainter(this.seed);

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.14);
    for (var i = 0; i < 26; i++) {
      final o = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
      canvas.drawCircle(o, 1.5 + rnd.nextDouble() * 3.5, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.seed != seed;
}
