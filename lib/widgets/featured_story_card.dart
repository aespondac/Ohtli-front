import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'grow_route.dart';
import 'ohtli_ui.dart';
import 'trip_polaroid.dart';

/// Crónica destacada de Explorar: la foto ocupa toda la tarjeta, con un degradado para
/// leer el texto encima. Al tocarla, la tarjeta crece hasta convertirse en el visor.
class FeaturedStoryCard extends StatefulWidget {
  const FeaturedStoryCard({
    super.key,
    required this.photoUrl,
    required this.title,
    required this.description,
    required this.badgeText,
    required this.badgeIcon,
    required this.accent,
    required this.author,
    required this.buttonLabel,
    required this.pageBuilder,
    this.highlightButton = true,
    this.isMobile = false,
    this.background = Colors.black,
  });

  final String photoUrl;
  final String title;

  /// Texto plano o markdown sencillo (se le quitan las marcas).
  final String description;
  final String badgeText;
  final IconData badgeIcon;
  final Color accent;

  /// Avatar, nombre y título de quien escribe (en blanco).
  final Widget author;
  final String buttonLabel;
  final bool highlightButton;

  /// La página que se abre (el visor).
  final WidgetBuilder pageBuilder;
  final bool isMobile;

  /// Color de fondo mientras crece (el de la página que se abre).
  final Color background;

  static const double radius = 28;

  @override
  State<FeaturedStoryCard> createState() => _FeaturedStoryCardState();
}

class _FeaturedStoryCardState extends State<FeaturedStoryCard> {
  bool _hovered = false;

  void _open(BuildContext cardContext) {
    final rect = GrowPageRoute.rectOf(cardContext);
    Navigator.of(cardContext).push(
      rect == null
          ? MaterialPageRoute(builder: widget.pageBuilder)
          : GrowPageRoute(
              from: rect,
              radius: FeaturedStoryCard.radius,
              background: widget.background,
              closed: _face(hovered: false, onOpen: () {}),
              builder: widget.pageBuilder,
            ),
    );
  }

  Widget _text(VoidCallback onOpen) {
    final bool m = widget.isMobile;
    final String desc = widget.description.replaceAll(RegExp(r'\[![A-Z]+\]'), '').replaceAll(RegExp(r'[*_`#>~]'), '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: widget.accent.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(30)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.badgeIcon, color: Colors.white, size: 13),
              const SizedBox(width: 6),
              Text(widget.badgeText,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
            ],
          ),
        ),
        SizedBox(height: m ? 12 : 16),
        Text(
          widget.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontSize: m ? 27 : 40,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            height: 1.04,
            shadows: [Shadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 16)],
          ),
        ),
        if (desc.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            desc,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(color: Colors.white.withValues(alpha: 0.88), fontSize: m ? 14 : 15.5, height: 1.45),
          ),
        ],
        SizedBox(height: m ? 14 : 20),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: widget.author),
            if (!m) ...[
              const SizedBox(width: 20),
              OhtliPrimaryButton(
                label: widget.buttonLabel,
                icon: Icons.arrow_forward_rounded,
                highlight: widget.highlightButton,
                onPressed: onOpen,
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _face({required bool hovered, required VoidCallback onOpen}) {
    final bool m = widget.isMobile;
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedScale(
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          scale: hovered ? 1.05 : 1.0,
          child: OhtliPhoto(widget.photoUrl),
        ),
        // Oscuro abajo (y a la izquierda en escritorio) para que el texto se lea sobre cualquier foto.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, 0.38, 1],
              colors: [Colors.black.withValues(alpha: 0.18), Colors.black.withValues(alpha: 0.08), Colors.black.withValues(alpha: 0.86)],
            ),
          ),
        ),
        if (!m)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                stops: const [0, 0.55, 1],
                colors: [Colors.black.withValues(alpha: 0.55), Colors.black.withValues(alpha: 0.12), Colors.transparent],
              ),
            ),
          ),
        Positioned(
          left: m ? 20 : 40,
          right: m ? 20 : 40,
          bottom: m ? 20 : 34,
          child: Align(
            alignment: Alignment.bottomLeft,
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: _text(onOpen)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Este contexto es la tarjeta: de aquí crece el visor.
    return Builder(
      builder: (cardContext) {
        void open() => _open(cardContext);
        return MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: open,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(FeaturedStoryCard.radius),
                boxShadow: OhtliUi.softShadow(color: _hovered ? widget.accent : null, raised: _hovered),
              ),
              child: _face(hovered: _hovered, onOpen: open),
            ),
          ),
        );
      },
    );
  }
}
