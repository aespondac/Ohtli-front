import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/trip_model.dart';

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

    final ribbonGradient = const LinearGradient(
      colors: [
        Color(0xFFF9D976),
        Color(0xFFE9B646),
        Color(0xFFD4AF37),
        Color(0xFFB48A1F),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

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
                                      paperColor: const Color(0xFFB71C1C), // Deep festive red
                                      patternColor: const Color(0xFFFFD700).withValues(alpha: 0.18), // Gold lines
                                    ),
                                  ),
                                ),

                                // Dotted border
                                Positioned.fill(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(
                                        color: const Color(0xFFFFD700).withValues(alpha: 0.4),
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
                                        gradient: ribbonGradient,
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
                                        gradient: ribbonGradient,
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
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: const Color(0xFFD4AF37), width: 1.5),
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
                                              Icon(
                                                widget.isLocked ? Icons.lock_outline_rounded : Icons.card_giftcard_rounded,
                                                size: 10,
                                                color: const Color(0xFFB71C1C),
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                widget.isLocked ? "CERRADO" : "SORPRESA",
                                                style: GoogleFonts.outfit(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: const Color(0xFFB71C1C),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            widget.isLocked 
                                                ? "Abre: ${widget.trip.surpriseUnlockDate!.day}/${widget.trip.surpriseUnlockDate!.month}"
                                                : (widget.addedByName != null ? "De: ${widget.addedByName}" : "Para ti"),
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

                                // Ribbon Bow in the Center
                                Align(
                                  alignment: Alignment.center,
                                  child: Transform.scale(
                                    scale: _bowScale.value,
                                    child: Opacity(
                                      opacity: math.max(0.0, 1.0 - _animController.value * 2.0),
                                      child: _buildBow(ribbonGradient),
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

  Widget _buildBow(LinearGradient ribbonGradient) {
    return SizedBox(
      width: 70,
      height: 70,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Left loop
          Positioned(
            left: 10,
            top: 18,
            child: Transform.rotate(
              angle: -0.4,
              child: Container(
                width: 28,
                height: 18,
                decoration: BoxDecoration(
                  gradient: ribbonGradient,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: const Color(0xFFB48A1F), width: 0.8),
                ),
              ),
            ),
          ),
          // Right loop
          Positioned(
            right: 10,
            top: 18,
            child: Transform.rotate(
              angle: 0.4,
              child: Container(
                width: 28,
                height: 18,
                decoration: BoxDecoration(
                  gradient: ribbonGradient,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: const Color(0xFFB48A1F), width: 0.8),
                ),
              ),
            ),
          ),
          // Left tail
          Positioned(
            left: 18,
            bottom: 12,
            child: Transform.rotate(
              angle: 0.4,
              child: Container(
                width: 9,
                height: 22,
                decoration: BoxDecoration(
                  gradient: ribbonGradient,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(4),
                    bottomRight: Radius.circular(4),
                  ),
                ),
              ),
            ),
          ),
          // Right tail
          Positioned(
            right: 18,
            bottom: 12,
            child: Transform.rotate(
              angle: -0.4,
              child: Container(
                width: 9,
                height: 22,
                decoration: BoxDecoration(
                  gradient: ribbonGradient,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(4),
                    bottomRight: Radius.circular(4),
                  ),
                ),
              ),
            ),
          ),
          // Center knot
          Container(
            width: 17,
            height: 17,
            decoration: BoxDecoration(
              gradient: ribbonGradient,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFB48A1F), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class WrappingPaperPainter extends CustomPainter {
  final Color paperColor;
  final Color patternColor;

  WrappingPaperPainter({required this.paperColor, required this.patternColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = paperColor
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    final stripePaint = Paint()
      ..color = patternColor
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke;

    // Draw festive diagonal gold stripes
    for (double i = -size.height; i < size.width; i += 28) {
      canvas.drawLine(Offset(i, 0), Offset(i + size.height, size.height), stripePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
