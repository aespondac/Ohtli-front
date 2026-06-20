import 'package:flutter/material.dart';

class Interactive3DCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool isDark;

  const Interactive3DCard({
    super.key,
    required this.child,
    this.onTap,
    this.isDark = false,
  });

  @override
  State<Interactive3DCard> createState() => _Interactive3DCardState();
}

class _Interactive3DCardState extends State<Interactive3DCard> {
  Offset _pointerOffset = Offset.zero;

  void _updatePointer(Offset localPosition, double width, double height) {
    final dx = (localPosition.dx / width) * 2 - 1.0;
    final dy = (localPosition.dy / height) * 2 - 1.0;
    setState(() {
      _pointerOffset = Offset(dx.clamp(-1.0, 1.0), dy.clamp(-1.0, 1.0));
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth.isFinite ? constraints.maxWidth : 300;
        final double height = constraints.maxHeight.isFinite ? constraints.maxHeight : 300;

        return Listener(
          onPointerMove: (e) => _updatePointer(e.localPosition, width, height),
          onPointerHover: (e) => _updatePointer(e.localPosition, width, height),
          onPointerUp: (_) => setState(() => _pointerOffset = Offset.zero),
          onPointerCancel: (_) => setState(() => _pointerOffset = Offset.zero),
          child: MouseRegion(
            cursor: widget.onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
            onExit: (_) => setState(() => _pointerOffset = Offset.zero),
            child: GestureDetector(
              onTap: widget.onTap,
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
                      fit: StackFit.passthrough,
                      children: [
                        widget.child,
                        // Subtle 3D Glare Overlay
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(24),
                                gradient: RadialGradient(
                                  center: Alignment(-pointer.dx, -pointer.dy),
                                  radius: 1.5,
                                  colors: [
                                    Colors.white.withValues(alpha: widget.isDark ? 0.08 : 0.15),
                                    Colors.white.withValues(alpha: widget.isDark ? 0.02 : 0.05),
                                    Colors.white.withValues(alpha: 0.0),
                                  ],
                                  stops: const [0.0, 0.5, 1.0],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
