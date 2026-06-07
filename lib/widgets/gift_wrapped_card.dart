import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/trip_model.dart';

enum PatternType { stripes, stars, dots, cross, grid }

class GiftWrapTheme {
  final Color paperColor;
  final Color patternColor;
  final PatternType patternType;
  final LinearGradient ribbonGradient;
  final Color tagBorderColor;
  final Color tagTextColor;
  final Color tagIconColor;
  final Color tagBgColor;
  final Color bowOutlineColor;

  GiftWrapTheme({
    required this.paperColor,
    required this.patternColor,
    required this.patternType,
    required this.ribbonGradient,
    required this.tagBorderColor,
    required this.tagTextColor,
    required this.tagIconColor,
    required this.tagBgColor,
    required this.bowOutlineColor,
  });
}

class GiftWrappedCard extends StatefulWidget {
  final bool isOpened;
  final String? addedByName;
  final Widget child; // The actual TripCard underneath
  final VoidCallback onRevealComplete;

  const GiftWrappedCard({
    super.key,
    required this.trip,
    required this.isLocked,
    required this.isOpened,
    required this.addedByName,
    required this.child,
    required this.onRevealComplete,
  });

  @override
  State<GiftWrappedCard> createState() => _GiftWrappedCardState();
}

class _GiftWrappedCardState extends State<GiftWrappedCard> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _paperOpacity;
  late Animation<double> _bowScale;
  late Animation<double> _horizontalRibbonOffset;
  late Animation<double> _verticalRibbonOffset;
  
  bool _isUnwrapping = false;
  bool _fullyRevealed = false;
  Offset _pointerOffset = Offset.zero;

  void _updatePointer(Offset localPosition, double width, double height) {
    if (_isUnwrapping || _fullyRevealed) return;
    final dx = (localPosition.dx / width) * 2 - 1.0;
    final dy = (localPosition.dy / height) * 2 - 1.0;
    setState(() {
      _pointerOffset = Offset(dx.clamp(-1.0, 1.0), dy.clamp(-1.0, 1.0));
    });
  }

  // Premium themes with multi-stop metallic gradients
  static final List<GiftWrapTheme> _themes = [
    // 0. Crimson Red & Gold (Rojo con Dorado)
    GiftWrapTheme(
      paperColor: const Color(0xFF8B0000), // Deep crimson red
      patternColor: const Color(0xFFFFD700).withValues(alpha: 0.15),
      patternType: PatternType.stripes,
      ribbonGradient: const LinearGradient(
        colors: [
          Color(0xFF7A5A0A), 
          Color(0xFFC59F2E), 
          Color(0xFFFFF1A8), 
          Color(0xFFD4AF37), 
          Color(0xFFAA8010), 
          Color(0xFF7A5A0A)
        ],
        stops: [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      tagBorderColor: const Color(0xFFD4AF37),
      tagTextColor: const Color(0xFF8B0000),
      tagIconColor: const Color(0xFF8B0000),
      tagBgColor: Colors.white,
      bowOutlineColor: const Color(0xFF5A4307),
    ),
    // 1. Royal Midnight Blue & Gold (Azul con Dorado)
    GiftWrapTheme(
      paperColor: const Color(0xFF0F1C2A), // Luxury Midnight Navy
      patternColor: const Color(0xFFFFD700).withValues(alpha: 0.15),
      patternType: PatternType.stars,
      ribbonGradient: const LinearGradient(
        colors: [
          Color(0xFF7A5A0A), 
          Color(0xFFC59F2E), 
          Color(0xFFFFF1A8), 
          Color(0xFFD4AF37), 
          Color(0xFFAA8010), 
          Color(0xFF7A5A0A)
        ],
        stops: [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      tagBorderColor: const Color(0xFFD4AF37),
      tagTextColor: const Color(0xFF0F1C2A),
      tagIconColor: const Color(0xFFD4AF37),
      tagBgColor: const Color(0xFFF0F4F8),
      bowOutlineColor: const Color(0xFF5A4307),
    ),
    // 2. Emerald Forest & Silver (Verde con Plateado)
    GiftWrapTheme(
      paperColor: const Color(0xFF063A2F), // Imperial Jade Green
      patternColor: const Color(0xFFE5E7EB).withValues(alpha: 0.12),
      patternType: PatternType.dots,
      ribbonGradient: const LinearGradient(
        colors: [
          Color(0xFF374151), 
          Color(0xFF9CA3AF), 
          Color(0xFFF3F4F6), 
          Color(0xFFD1D5DB), 
          Color(0xFF6B7280), 
          Color(0xFF374151)
        ],
        stops: [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      tagBorderColor: const Color(0xFF9CA3AF),
      tagTextColor: const Color(0xFF063A2F),
      tagIconColor: const Color(0xFF063A2F),
      tagBgColor: Colors.white,
      bowOutlineColor: const Color(0xFF4B5563),
    ),
    // 3. Velvet Purple & Gold (Morado con Dorado)
    GiftWrapTheme(
      paperColor: const Color(0xFF310E4E), // Deep Royal Velvet
      patternColor: const Color(0xFFFFD700).withValues(alpha: 0.15),
      patternType: PatternType.cross,
      ribbonGradient: const LinearGradient(
        colors: [
          Color(0xFF7A5A0A), 
          Color(0xFFC59F2E), 
          Color(0xFFFFF1A8), 
          Color(0xFFD4AF37), 
          Color(0xFFAA8010), 
          Color(0xFF7A5A0A)
        ],
        stops: [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      tagBorderColor: const Color(0xFFFFB300),
      tagTextColor: const Color(0xFF310E4E),
      tagIconColor: const Color(0xFF310E4E),
      tagBgColor: const Color(0xFFFAF7FC),
      bowOutlineColor: const Color(0xFF5A4307),
    ),
    // 4. Obsidian Black & Rose Gold (Negro con Oro Rosa)
    GiftWrapTheme(
      paperColor: const Color(0xFF161618), // Matte Obsidian Carbon
      patternColor: const Color(0xFFFDA4AF).withValues(alpha: 0.12),
      patternType: PatternType.grid,
      ribbonGradient: const LinearGradient(
        colors: [
          Color(0xFF5E2B2B), 
          Color(0xFFD29062), 
          Color(0xFFFFE4E6), 
          Color(0xFFFDA4AF), 
          Color(0xFF9F1239), 
          Color(0xFF5E2B2B)
        ],
        stops: [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      tagBorderColor: const Color(0xFFFDA4AF),
      tagTextColor: const Color(0xFF161618),
      tagIconColor: const Color(0xFF9F1239),
      tagBgColor: const Color(0xFFFFF5F5),
      bowOutlineColor: const Color(0xFF6B1D2F),
    ),
  ];

  GiftWrapTheme _getTheme() {
    final String tripId = widget.trip.id;
    int hash = 0;
    for (int i = 0; i < tripId.length; i++) {
      hash += tripId.codeUnitAt(i);
    }
    final index = hash % _themes.length;
    return _themes[index];
  }

  Widget _buildRibbonOverlay(double width, double height, GiftWrapTheme theme) {
    final String tripId = widget.trip.id;
    int hash = 0;
    for (int i = 0; i < tripId.length; i++) {
      hash += tripId.codeUnitAt(i);
    }
    int ribbonIndex = hash % 8;
    if (ribbonIndex == 1) ribbonIndex = 0; // Ribbon 1 eliminated, fallback to 0
    final themeIndex = hash % _themes.length;

    String variant = 'gold';
    if (themeIndex == 2) variant = 'silver';
    else if (themeIndex == 4) variant = 'rosegold';

    final asset = 'assets/ribbons/Ribbon_${ribbonIndex}_$variant.svg';

    final svgWidget = Transform.scale(
      scale: _bowScale.value,
      child: Opacity(
        opacity: math.max(0.0, 1.0 - _animController.value * 2.0),
        child: SvgPicture.asset(
          asset,
          fit: BoxFit.contain,
        ),
      ),
    );

    switch (ribbonIndex) {
      case 0:
        return Positioned(
          top: -18,
          left: -15,
          width: width + 25,
          child: svgWidget,
        );
      case 2:
      case 3:
      case 5:
      case 7:
        return Positioned(
          top: height * 0.33 - 50,
          left: 0,
          right: 0,
          child: svgWidget,
        );
      case 4:
      case 6:
        return Positioned(
          top: 0,
          bottom: 0,
          left: width * 0.5 - 55,
          child: svgWidget,
        );
      default:
        return Positioned.fill(child: svgWidget);
    }
  }

  String _getUnlockDateString() {
    if (widget.trip.surpriseUnlockDate != null) {
      final date = widget.trip.surpriseUnlockDate!;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final unlockDay = DateTime(date.year, date.month, date.day);
      if (today.isBefore(unlockDay)) {
        final months = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
        return "Disponible el ${date.day} ${months[date.month - 1]}";
      }
    }
    return "Ya disponible";
  }

  @override
  void initState() {
    super.initState();
    _fullyRevealed = widget.isOpened;
    
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _paperOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
      ),
    );

    _bowScale = Tween<double>(begin: 1.0, end: 1.8).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack),
      ),
    );

    _horizontalRibbonOffset = Tween<double>(begin: 0.0, end: 350.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.2, 0.8, curve: Curves.easeInOutCubic),
      ),
    );

    _verticalRibbonOffset = Tween<double>(begin: 0.0, end: -300.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.2, 0.8, curve: Curves.easeInOutCubic),
      ),
    );

    _animController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _fullyRevealed = true;
        });
        widget.onRevealComplete();
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _handleUnwrap() {
    if (widget.isLocked || _isUnwrapping || _fullyRevealed) return;
    setState(() {
      _isUnwrapping = true;
    });
    _animController.forward();
  }

  @override
  Widget build(BuildContext context) {
    if (_fullyRevealed) {
      return widget.child;
    }

    final theme = _getTheme();

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final double height = constraints.maxHeight;

        final String tripId = widget.trip.id;
        int hash = 0;
        for (int i = 0; i < tripId.length; i++) {
          hash += tripId.codeUnitAt(i);
        }
        int ribbonIndex = hash % 8;
        if (ribbonIndex == 1) ribbonIndex = 0;

        final bool isMobile = height < 200;
        final double tagWidth = 85.0;
        final double tagHeight = 130.0;
        
        // Tag is on left for web. For mobile, it's on right, EXCEPT if ribbon is 0.
        final bool tagIsOnLeft = isMobile ? (ribbonIndex == 0) : true;
        final double tagLeft = tagIsOnLeft ? width * 0.08 : width - tagWidth - (width * 0.08);
        final double tagBottom = height * 0.08;

        return Listener(
          onPointerMove: (e) => _updatePointer(e.localPosition, width, height),
          onPointerHover: (e) => _updatePointer(e.localPosition, width, height),
          onPointerUp: (_) => setState(() => _pointerOffset = Offset.zero),
          onPointerCancel: (_) => setState(() => _pointerOffset = Offset.zero),
          child: MouseRegion(
            cursor: widget.isLocked ? SystemMouseCursors.basic : SystemMouseCursors.click,
            onExit: (_) => setState(() => _pointerOffset = Offset.zero),
            child: TweenAnimationBuilder<Offset>(
              tween: Tween<Offset>(begin: Offset.zero, end: _pointerOffset),
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              builder: (context, pointer, _) {
                final matrix = Matrix4.identity()
                  ..setEntry(3, 2, 0.001)
                  ..rotateX(-pointer.dy * 0.1)
                  ..rotateY(pointer.dx * 0.1);

                return Transform(
                  transform: matrix,
                  alignment: Alignment.center,
                  child: Stack(
                    fit: StackFit.expand,
                    clipBehavior: Clip.none,
                    children: [
                      // 1. The actual TripCard revealed underneath (now it tilts too!)
                      Positioned.fill(child: widget.child),

                      // 2. The Gift Wrapping Overlay
                      AnimatedBuilder(
                        animation: _animController,
                        builder: (context, _) {
                          return Opacity(
                            opacity: _paperOpacity.value,
                            child: IgnorePointer(
                              ignoring: _fullyRevealed,
                              child: GestureDetector(
                                onTap: widget.isLocked ? null : _handleUnwrap,
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(24),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.2),
                                        blurRadius: 15,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    clipBehavior: Clip.none,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(24),
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            // Wrapping Paper Background Pattern
                                            Positioned.fill(
                                              child: CustomPaint(
                                                painter: WrappingPaperPainter(
                                                  paperColor: theme.paperColor,
                                                  patternColor: theme.patternColor,
                                                  patternType: theme.patternType,
                                                ),
                                              ),
                                            ),
                                            // 3D Radial Glare Effect Overlay
                                            Positioned.fill(
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  gradient: RadialGradient(
                                                    center: Alignment(-pointer.dx, -pointer.dy),
                                                    radius: 1.5,
                                                    colors: [
                                                      Colors.white.withValues(alpha: 0.15),
                                                      Colors.white.withValues(alpha: 0.05),
                                                      Colors.white.withValues(alpha: 0.0),
                                                    ],
                                                    stops: const [0.0, 0.5, 1.0],
                                                  ),
                                                ),
                                              ),
                                            ),
                                            // Shiny gold/silver outline border
                                            Positioned.fill(
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  borderRadius: BorderRadius.circular(24),
                                                  border: Border.all(
                                                    color: theme.tagBorderColor.withValues(alpha: 0.35),
                                                    width: 2.5,
                                                    style: BorderStyle.solid,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Dynamic SVG Ribbons
                                      _buildRibbonOverlay(constraints.maxWidth, constraints.maxHeight, theme),

                                      // Gift Tag
                                      Positioned(
                                        bottom: tagBottom,
                                        left: tagLeft,
                                        child: Transform.rotate(
                                          angle: 0.1,
                                          child: CustomPaint(
                                            painter: TagPainter(
                                              borderColor: theme.tagBorderColor,
                                              bgColor: theme.tagBgColor,
                                              isOnLeft: tagIsOnLeft,
                                            ),
                                            child: Container(
                                              width: tagWidth,
                                              height: tagHeight,
                                              padding: const EdgeInsets.only(left: 8, right: 8, top: 32, bottom: 8),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.center,
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    widget.isLocked ? Icons.lock_outline_rounded : Icons.card_giftcard_rounded,
                                                    size: 16,
                                                    color: theme.tagIconColor,
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Text(
                                                    _getUnlockDateString(),
                                                    style: GoogleFonts.outfit(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                      color: theme.tagTextColor,
                                                      height: 1.1,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  const Spacer(),
                                                  Container(
                                                    width: 30,
                                                    height: 1.5,
                                                    color: theme.tagBorderColor.withValues(alpha: 0.4),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    widget.addedByName != null ? "De:\n${widget.addedByName}" : "Para ti",
                                                    style: GoogleFonts.inter(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.w600,
                                                      color: Colors.black87,
                                                      height: 1.1,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class TagPainter extends CustomPainter {
  final Color borderColor;
  final Color bgColor;
  final bool isOnLeft;

  TagPainter({required this.borderColor, required this.bgColor, this.isOnLeft = false});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = bgColor
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final path = Path();
    final double clipX = size.width * 0.25;
    final double clipY = size.height * 0.15;
    
    // Luggage tag shape: hole at the top
    path.moveTo(clipX, 0);
    path.lineTo(size.width - clipX, 0);
    path.lineTo(size.width, clipY);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.lineTo(0, clipY);
    path.close();

    // Draw realistic shadow depending on position
    final shadowOffset = isOnLeft ? const Offset(4, 5) : const Offset(-4, 5);
    canvas.drawPath(
      path.shift(shadowOffset),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0),
    );

    canvas.drawPath(path, paint);
    canvas.drawPath(path, borderPaint);

    // Draw metal eyelet/rivet hole on the top center
    final holeCenter = Offset(size.width / 2, clipY * 0.85);
    final eyeletPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(holeCenter, 4.5, eyeletPaint);
    canvas.drawCircle(holeCenter, 2.0, Paint()..color = bgColor);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class TagStringPainter extends CustomPainter {
  final Offset start;
  final Offset end;
  final Color color;

  TagStringPainter({required this.start, required this.end, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final path = Path();
    path.moveTo(start.dx, start.dy);

    // Draw a natural sagging curved string using cubic bezier points
    final double controlX1 = start.dx + (end.dx - start.dx) * 0.1 - 20;
    final double controlY1 = start.dy + (end.dy - start.dy) * 0.4 + 10;
    final double controlX2 = start.dx + (end.dx - start.dx) * 0.6 - 15;
    final double controlY2 = start.dy + (end.dy - start.dy) * 0.9 + 5;

    path.cubicTo(controlX1, controlY1, controlX2, controlY2, end.dx, end.dy);

    // Subtle drop shadow for the string
    canvas.drawPath(
      path.shift(const Offset(1, 2)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}


class WrappingPaperPainter extends CustomPainter {
  final Color paperColor;
  final Color patternColor;
  final PatternType patternType;

  WrappingPaperPainter({
    required this.paperColor,
    required this.patternColor,
    required this.patternType,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw solid wrapping paper background
    final paint = Paint()
      ..color = paperColor
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    // 2. Draw pattern
    final patternPaint = Paint()
      ..color = patternColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    switch (patternType) {
      case PatternType.stripes:
        patternPaint.strokeWidth = 3.5;
        for (double i = -size.height; i < size.width; i += 28) {
          canvas.drawLine(Offset(i, 0), Offset(i + size.height, size.height), patternPaint);
        }
        break;

      case PatternType.stars:
        patternPaint.style = PaintingStyle.fill;
        final double spacing = 40.0;
        for (double x = 20; x < size.width; x += spacing) {
          for (double y = 20; y < size.height; y += spacing) {
            final double starSize = ((x + y) / spacing).round() % 2 == 0 ? 5.5 : 3.0;
            _drawSparkleStar(canvas, Offset(x, y), starSize, patternPaint);
          }
        }
        break;

      case PatternType.dots:
        patternPaint.style = PaintingStyle.fill;
        final double spacing = 30;
        for (double x = 15; x < size.width; x += spacing) {
          for (double y = 15; y < size.height; y += spacing) {
            final double r = ((x + y) / spacing).round() % 2 == 0 ? 2.5 : 1.2;
            canvas.drawCircle(Offset(x, y), r, patternPaint);
          }
        }
        break;

      case PatternType.cross:
        patternPaint.strokeWidth = 1.8;
        final double spacing = 35;
        for (double x = 20; x < size.width; x += spacing) {
          for (double y = 20; y < size.height; y += spacing) {
            const double len = 3.2;
            canvas.drawLine(Offset(x - len, y), Offset(x + len, y), patternPaint);
            canvas.drawLine(Offset(x, y - len), Offset(x, y + len), patternPaint);
          }
        }
        break;

      case PatternType.grid:
        patternPaint.strokeWidth = 1.2;
        for (double i = -size.height; i < size.width + size.height; i += 40) {
          canvas.drawLine(Offset(i, 0), Offset(i + size.height, size.height), patternPaint);
          canvas.drawLine(Offset(i, size.height), Offset(i + size.height, 0), patternPaint);
        }
        break;
    }

    // 3. Draw 3D lighting vignette overlay (creates depth by darkening outer edges)
    final vignettePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.4),
        ],
        stops: const [0.55, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), vignettePaint);
  }

  void _drawSparkleStar(Canvas canvas, Offset center, double size, Paint paint) {
    final path = Path();
    path.moveTo(center.dx, center.dy - size);
    path.quadraticBezierTo(center.dx, center.dy, center.dx + size, center.dy);
    path.quadraticBezierTo(center.dx, center.dy, center.dx, center.dy + size);
    path.quadraticBezierTo(center.dx, center.dy, center.dx - size, center.dy);
    path.quadraticBezierTo(center.dx, center.dy, center.dx, center.dy - size);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
