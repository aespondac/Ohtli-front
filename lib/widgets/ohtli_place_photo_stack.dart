import 'package:flutter/material.dart';

class OhtliPlacePhotoStack extends StatefulWidget {
  final List<Map<String, dynamic>> drawOrderSlots;
  final bool isDark;
  final Widget Function(Map<String, dynamic> slot, int index) slotBuilder;

  const OhtliPlacePhotoStack({
    super.key,
    required this.drawOrderSlots,
    required this.isDark,
    required this.slotBuilder,
  });

  @override
  State<OhtliPlacePhotoStack> createState() => _OhtliPlacePhotoStackState();
}

class _OhtliPlacePhotoStackState extends State<OhtliPlacePhotoStack> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final int count = widget.drawOrderSlots.length;
    
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isHovered = true),
        onTapUp: (_) => setState(() => _isHovered = false),
        onTapCancel: () => setState(() => _isHovered = false),
        child: SizedBox(
          width: 160,
          height: 195,
          child: Stack(
            clipBehavior: Clip.none,
            children: List.generate(count, (displayIndex) {
              final displaySlot = widget.drawOrderSlots[displayIndex];
              final String type = displaySlot['type'] as String;

              double rotation = 0.0;
              double offsetX = 0.0;
              double offsetY = 0.0;
              double scale = 1.0;

              if (count == 3) {
                if (type == 'place_sec_1') { // back card
                  rotation = _isHovered ? -0.15 : -0.06;
                  offsetX = _isHovered ? -26.0 : -10.0;
                  offsetY = _isHovered ? -8.0 : -6.0;
                } else if (type == 'place_sec_0') { // middle card
                  rotation = _isHovered ? 0.12 : 0.05;
                  offsetX = _isHovered ? 24.0 : 8.0;
                  offsetY = _isHovered ? -5.0 : -3.0;
                } else if (type == 'place_main') { // front card
                  rotation = 0.0;
                  offsetX = 0.0;
                  offsetY = 0.0;
                  scale = _isHovered ? 1.05 : 1.0;
                }
              } else if (count == 2) {
                if (type != 'place_main') { // back card
                  rotation = _isHovered ? -0.12 : -0.05;
                  offsetX = _isHovered ? -20.0 : -8.0;
                  offsetY = _isHovered ? -6.0 : -4.0;
                } else { // front card
                  rotation = 0.0;
                  offsetX = 0.0;
                  offsetY = 0.0;
                  scale = _isHovered ? 1.05 : 1.0;
                }
              }

              return AnimatedPositioned(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutBack, // Premium spring curve
                left: 15 + offsetX,
                top: 10 + offsetY,
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutBack,
                  scale: scale,
                  child: AnimatedRotation(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutBack,
                    turns: rotation / (2 * 3.14159265),
                    child: SizedBox(
                      width: 120,
                      height: 160,
                      child: widget.slotBuilder(displaySlot, displayIndex),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
