import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
  final Trip trip;
  final bool isLocked;
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

  static final List<GiftWrapTheme> _themes = [
    // 0. Crimson Red & Gold (Rojo con Dorado)
    GiftWrapTheme(
      paperColor: const Color(0xFFB71C1C),
      patternColor: const Color(0xFFFFD700).withValues(alpha: 0.18),
      patternType: PatternType.stripes,
      ribbonGradient: const LinearGradient(
        colors: [Color(0xFFFFE082), Color(0xFFFFD54F), Color(0xFFFFC107), Color(0xFFFFB300), Color(0xFFFFA000)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      tagBorderColor: const Color(0xFFFFC107),
      tagTextColor: const Color(0xFFB71C1C),
      tagIconColor: const Color(0xFFB71C1C),
      tagBgColor: Colors.white,
      bowOutlineColor: const Color(0xFFB48A1F),
    ),
    // 1. Royal Midnight Blue & Gold (Azul con Dorado)
    GiftWrapTheme(
      paperColor: const Color(0xFF0F1B29),
      patternColor: const Color(0xFFFFD700).withValues(alpha: 0.16),
      patternType: PatternType.stars,
      ribbonGradient: const LinearGradient(
        colors: [Color(0xFFFFF9C4), Color(0xFFFBC02D), Color(0xFFF57F17)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      tagBorderColor: const Color(0xFFFBC02D),
      tagTextColor: const Color(0xFF0F1B29),
      tagIconColor: const Color(0xFFFBC02D),
      tagBgColor: const Color(0xFFF4F6F9),
      bowOutlineColor: const Color(0xFF9E7E0D),
    ),
    // 2. Deep Emerald Forest & Silver (Verde con Plateado)
    GiftWrapTheme(
      paperColor: const Color(0xFF064E3B),
      patternColor: const Color(0xFFE5E7EB).withValues(alpha: 0.15),
      patternType: PatternType.dots,
      ribbonGradient: const LinearGradient(
        colors: [Color(0xFFF3F4F6), Color(0xFFE5E7EB), Color(0xFFD1D5DB), Color(0xFF9CA3AF)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      tagBorderColor: const Color(0xFF9CA3AF),
      tagTextColor: const Color(0xFF064E3B),
      tagIconColor: const Color(0xFF064E3B),
      tagBgColor: Colors.white,
      bowOutlineColor: const Color(0xFF7B8390),
    ),
    // 3. Majestic Purple & Amber Gold (Morado con Dorado)
    GiftWrapTheme(
      paperColor: const Color(0xFF4C1D95),
      patternColor: const Color(0xFFFFD700).withValues(alpha: 0.18),
      patternType: PatternType.cross,
      ribbonGradient: const LinearGradient(
        colors: [Color(0xFFFFECB3), Color(0xFFFFD54F), Color(0xFFFFB300), Color(0xFFFFA000)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      tagBorderColor: const Color(0xFFFFB300),
      tagTextColor: const Color(0xFF4C1D95),
      tagIconColor: const Color(0xFF4C1D95),
      tagBgColor: const Color(0xFFFAFAFA),
      bowOutlineColor: const Color(0xFFB59110),
    ),
    // 4. Elegant Obsidian Black & Rose Gold (Negro con Oro Rosa)
    GiftWrapTheme(
      paperColor: const Color(0xFF111827),
      patternColor: const Color(0xFFFCA5A5).withValues(alpha: 0.12),
      patternType: PatternType.grid,
      ribbonGradient: const LinearGradient(
        colors: [Color(0xFFFFE4E6), Color(0xFFFECDD3), Color(0xFFFDA4AF), Color(0xFFF43F5E)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      tagBorderColor: const Color(0xFFFDA4AF),
      tagTextColor: const Color(0xFF111827),
      tagIconColor: const Color(0xFFF43F5E),
      tagBgColor: const Color(0xFFFFF1F2),
      bowOutlineColor: const Color(0xFFBE123C),
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

  String _getUnlockDateString() {
    if (!widget.isLocked) {
      return "Ya disponible";
    }
    if (widget.trip.surpriseUnlockDate == null) {
      return "Ya disponible";
    }
    final date = widget.trip.surpriseUnlockDate!;
    final months = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
    return "Disponible el ${date.day} ${months[date.month - 1]}";
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

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // 1. The actual TripCard revealed underneath
            Positioned.fill(child: widget.child),

            // 2. The Gift Wrapping Overlay
            AnimatedBuilder(
              animation: _animController,
              builder: (context, child) {
                return Opacity(
                  opacity: _paperOpacity.value,
                  child: IgnorePointer(
                    ignoring: _fullyRevealed,
                    child: GestureDetector(
                      onTap: widget.isLocked ? null : _handleUnwrap,
                      child: MouseRegion(
                        cursor: widget.isLocked ? SystemMouseCursors.basic : SystemMouseCursors.click,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Stack(
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

                                // Dotted border
                                Positioned.fill(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(
                                        color: theme.tagBorderColor.withValues(alpha: 0.4),
                                        width: 2,
                                        style: BorderStyle.solid,
                                      ),
                                    ),
                                  ),
                                ),

                                // Horizontal Ribbon
                                Transform.translate(
                                  offset: Offset(_horizontalRibbonOffset.value, 0),
                                  child: Align(
                                    alignment: Alignment.center,
                                    child: Container(
                                      height: 28,
                                      decoration: BoxDecoration(
                                        gradient: theme.ribbonGradient,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.15),
                                            blurRadius: 3,
                                            offset: const Offset(0, 1),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),

                                // Vertical Ribbon
                                Transform.translate(
                                  offset: Offset(0, _verticalRibbonOffset.value),
                                  child: Align(
                                    alignment: Alignment.center,
                                    child: Container(
                                      width: 28,
                                      decoration: BoxDecoration(
                                        gradient: theme.ribbonGradient,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.15),
                                            blurRadius: 3,
                                            offset: const Offset(1, 0),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),

                                // Gift Tag
                                Positioned(
                                  bottom: height * 0.15,
                                  left: width * 0.1,
                                  child: Transform.rotate(
                                    angle: -0.15,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: theme.tagBgColor,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: theme.tagBorderColor, width: 1.5),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.15),
                                            blurRadius: 5,
                                            offset: const Offset(2, 2),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              // Mini Rivet/Hole
                                              Container(
                                                width: 5,
                                                height: 5,
                                                margin: const EdgeInsets.only(right: 6),
                                                decoration: BoxDecoration(
                                                  color: theme.tagBorderColor,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                              Icon(
                                                widget.isLocked ? Icons.lock_outline_rounded : Icons.card_giftcard_rounded,
                                                size: 10,
                                                color: theme.tagIconColor,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                _getUnlockDateString(),
                                                style: GoogleFonts.outfit(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: theme.tagTextColor,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            widget.addedByName != null ? "De: ${widget.addedByName}" : "Para ti",
                                            style: GoogleFonts.inter(
                                              fontSize: 8.5,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.black87,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),

                                // Realistic Ribbon Bow in the Center
                                Align(
                                  alignment: Alignment.center,
                                  child: Transform.scale(
                                    scale: _bowScale.value,
                                    child: Opacity(
                                      opacity: math.max(0.0, 1.0 - _animController.value * 2.0),
                                      child: SizedBox(
                                        width: 80,
                                        height: 80,
                                        child: CustomPaint(
                                          painter: RealisticBowPainter(
                                            gradient: theme.ribbonGradient,
                                            outlineColor: theme.bowOutlineColor,
                                          ),
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
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class RealisticBowPainter extends CustomPainter {
  final LinearGradient gradient;
  final Color outlineColor;

  RealisticBowPainter({required this.gradient, required this.outlineColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0)
      ..style = PaintingStyle.fill;

    final outlinePaint = Paint()
      ..color = outlineColor.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // 1. Draw ribbon tails (underneath)
    final leftTail = Path();
    leftTail.moveTo(center.dx - 4, center.dy + 4);
    leftTail.cubicTo(
      center.dx - 12, center.dy + 15,
      center.dx - 22, center.dy + 25,
      center.dx - 22, center.dy + 35,
    );
    // V-cut at end
    leftTail.lineTo(center.dx - 14, center.dy + 30);
    leftTail.lineTo(center.dx - 8, center.dy + 32);
    leftTail.cubicTo(
      center.dx - 8, center.dy + 25,
      center.dx - 6, center.dy + 15,
      center.dx - 2, center.dy + 4,
    );
    leftTail.close();

    final rightTail = Path();
    rightTail.moveTo(center.dx + 4, center.dy + 4);
    rightTail.cubicTo(
      center.dx + 12, center.dy + 15,
      center.dx + 22, center.dy + 25,
      center.dx + 22, center.dy + 35,
    );
    // V-cut at end
    rightTail.lineTo(center.dx + 14, center.dy + 30);
    rightTail.lineTo(center.dx + 8, center.dy + 32);
    rightTail.cubicTo(
      center.dx + 8, center.dy + 25,
      center.dx + 6, center.dy + 15,
      center.dx + 2, center.dy + 4,
    );
    rightTail.close();

    // Draw tails shadow first
    canvas.drawPath(leftTail.shift(const Offset(1, 2)), shadowPaint);
    canvas.drawPath(rightTail.shift(const Offset(1, 2)), shadowPaint);

    // Draw tails
    canvas.drawPath(leftTail, paint);
    canvas.drawPath(leftTail, outlinePaint);
    canvas.drawPath(rightTail, paint);
    canvas.drawPath(rightTail, outlinePaint);

    // 2. Draw big outer loops (left & right)
    final leftLoop = Path();
    leftLoop.moveTo(center.dx, center.dy);
    // Outer curve
    leftLoop.cubicTo(
      center.dx - 25, center.dy - 25,
      center.dx - 45, center.dy - 10,
      center.dx - 40, center.dy + 5,
    );
    // Inner return curve
    leftLoop.cubicTo(
      center.dx - 35, center.dy + 15,
      center.dx - 15, center.dy + 5,
      center.dx, center.dy,
    );
    leftLoop.close();

    final rightLoop = Path();
    rightLoop.moveTo(center.dx, center.dy);
    // Outer curve
    rightLoop.cubicTo(
      center.dx + 25, center.dy - 25,
      center.dx + 45, center.dy - 10,
      center.dx + 40, center.dy + 5,
    );
    // Inner return curve
    rightLoop.cubicTo(
      center.dx + 35, center.dy + 15,
      center.dx + 15, center.dy + 5,
      center.dx, center.dy,
    );
    rightLoop.close();

    // Draw loop shadows
    canvas.drawPath(leftLoop.shift(const Offset(1, 3)), shadowPaint);
    canvas.drawPath(rightLoop.shift(const Offset(1, 3)), shadowPaint);

    // Draw loops
    canvas.drawPath(leftLoop, paint);
    canvas.drawPath(leftLoop, outlinePaint);
    canvas.drawPath(rightLoop, paint);
    canvas.drawPath(rightLoop, outlinePaint);

    // 3. Draw inner smaller loops for 3D depth
    final leftInner = Path();
    leftInner.moveTo(center.dx, center.dy);
    leftInner.cubicTo(
      center.dx - 15, center.dy - 12,
      center.dx - 25, center.dy - 5,
      center.dx - 22, center.dy + 2,
    );
    leftInner.cubicTo(
      center.dx - 18, center.dy + 8,
      center.dx - 8, center.dy + 3,
      center.dx, center.dy,
    );
    leftInner.close();

    final rightInner = Path();
    rightInner.moveTo(center.dx, center.dy);
    rightInner.cubicTo(
      center.dx + 15, center.dy - 12,
      center.dx + 25, center.dy - 5,
      center.dx + 22, center.dy + 2,
    );
    rightInner.cubicTo(
      center.dx + 18, center.dy + 8,
      center.dx + 8, center.dy + 3,
      center.dx, center.dy,
    );
    rightInner.close();

    // Paint inner loops
    canvas.drawPath(leftInner, paint);
    canvas.drawPath(leftInner, outlinePaint);
    canvas.drawPath(rightInner, paint);
    canvas.drawPath(rightInner, outlinePaint);

    // 4. Center knot (draw last)
    final knotPath = Path();
    knotPath.addOval(Rect.fromCircle(center: center, radius: 9));

    // Shadow
    canvas.drawPath(knotPath.shift(const Offset(0, 2)), shadowPaint);

    // Draw knot
    canvas.drawPath(knotPath, paint);
    canvas.drawPath(knotPath, outlinePaint);

    // Knot texture lines (fold lines) for realism
    final foldPaint = Paint()
      ..color = outlineColor.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawArc(
      Rect.fromCircle(center: center - const Offset(1, 0), radius: 6),
      0.5, 2.0, false, foldPaint
    );
    canvas.drawArc(
      Rect.fromCircle(center: center + const Offset(1, 0), radius: 6),
      3.5, 2.0, false, foldPaint
    );
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
    final paint = Paint()
      ..color = paperColor
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

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
            // Draw a sparkle star
            final double starSize = ((x + y) / spacing).round() % 2 == 0 ? 5.0 : 3.0;
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
            const double len = 3.0;
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
