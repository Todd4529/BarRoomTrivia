import 'dart:math';
import 'package:flutter/material.dart';
import '../../shared/theme/app_theme.dart';

/// Realistic Animated Hourglass Widget with Draining Sand and 180-Degree Flip
class RealHourglassWidget extends StatefulWidget {
  final double size;
  const RealHourglassWidget({super.key, this.size = 84});

  @override
  State<RealHourglassWidget> createState() => _RealHourglassWidgetState();
}

class _RealHourglassWidgetState extends State<RealHourglassWidget>
    with TickerProviderStateMixin {
  late AnimationController _sandController;
  late AnimationController _flipController;
  int _flipCount = 0;

  @override
  void initState() {
    super.initState();
    _sandController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );

    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    _sandController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _flipController.forward(from: 0.0).then((_) {
          if (mounted) {
            setState(() {
              _flipCount++;
            });
            _sandController.forward(from: 0.0);
          }
        });
      }
    });

    _sandController.forward();
  }

  @override
  void dispose() {
    _sandController.dispose();
    _flipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_sandController, _flipController]),
      builder: (context, child) {
        final flipCurve = CurvedAnimation(
          parent: _flipController,
          curve: Curves.easeInOutBack,
        );
        final flipRotation = (_flipCount * pi) + (flipCurve.value * pi);
        final sandProgress = _sandController.value;

        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()..rotateZ(flipRotation),
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: CustomPaint(
              painter: _HourglassPainter(
                sandProgress: sandProgress,
                isFlipping: _flipController.isAnimating,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HourglassPainter extends CustomPainter {
  final double sandProgress;
  final bool isFlipping;

  _HourglassPainter({
    required this.sandProgress,
    required this.isFlipping,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;

    // Paints
    final framePaint = Paint()
      ..color = const Color(0xFFD97706) // Warm Brass / Gold Frame
      ..style = PaintingStyle.fill;

    final frameBorderPaint = Paint()
      ..color = Colors.white38
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final glassBorderPaint = Paint()
      ..color = AppTheme.neonCyan.withOpacity(0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final glassFillPaint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..style = PaintingStyle.fill;

    final sandPaint = Paint()
      ..color = const Color(0xFFF59E0B) // Rich Golden Sand
      ..style = PaintingStyle.fill;

    final sandStreamPaint = Paint()
      ..color = const Color(0xFFFBBF24)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;

    // 1. Draw Wooden / Brass Base & Top Cap
    final capHeight = h * 0.08;
    final capRadius = Radius.circular(capHeight / 2);

    // Top Cap
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.1, 0, w * 0.8, capHeight), capRadius),
      framePaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.1, 0, w * 0.8, capHeight), capRadius),
      frameBorderPaint,
    );

    // Bottom Cap
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.1, h - capHeight, w * 0.8, capHeight), capRadius),
      framePaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.1, h - capHeight, w * 0.8, capHeight), capRadius),
      frameBorderPaint,
    );

    // Side Pillars
    final pillarWidth = w * 0.05;
    canvas.drawRect(Rect.fromLTWH(w * 0.12, capHeight, pillarWidth, h - (capHeight * 2)), framePaint);
    canvas.drawRect(Rect.fromLTWH(w * 0.88 - pillarWidth, capHeight, pillarWidth, h - (capHeight * 2)), framePaint);

    // 2. Glass Bulb Path (Hourglass Outline)
    final glassPath = Path();
    final topY = capHeight;
    final botY = h - capHeight;
    final neckWidth = w * 0.14;

    glassPath.moveTo(w * 0.2, topY);
    // Upper bulb curve to neck
    glassPath.cubicTo(
      w * 0.2, cy * 0.6,
      cx - neckWidth, cy,
      cx - neckWidth / 2, cy,
    );
    // Neck to lower bulb curve
    glassPath.cubicTo(
      cx - neckWidth, cy,
      w * 0.2, cy * 1.4,
      w * 0.2, botY,
    );
    // Bottom edge
    glassPath.lineTo(w * 0.8, botY);
    // Right lower bulb to neck
    glassPath.cubicTo(
      w * 0.8, cy * 1.4,
      cx + neckWidth, cy,
      cx + neckWidth / 2, cy,
    );
    // Right neck to upper bulb
    glassPath.cubicTo(
      cx + neckWidth, cy,
      w * 0.8, cy * 0.6,
      w * 0.8, topY,
    );
    glassPath.close();

    // Draw Glass Background Fill
    canvas.drawPath(glassPath, glassFillPaint);

    // 3. Draw Top Sand (Draining)
    if (sandProgress < 1.0) {
      final currentTopY = topY + ((cy - topY) * sandProgress);
      final topSandRect = Rect.fromLTRB(w * 0.15, currentTopY, w * 0.85, cy);

      canvas.save();
      canvas.clipPath(glassPath);
      canvas.drawRect(topSandRect, sandPaint);
      canvas.restore();
    }

    // 4. Draw Bottom Sand (Filling)
    if (sandProgress > 0.0) {
      final botSandHeight = (botY - cy) * sandProgress;
      final currentBotY = botY - botSandHeight;
      final botSandRect = Rect.fromLTRB(w * 0.15, currentBotY, w * 0.85, botY);

      canvas.save();
      canvas.clipPath(glassPath);
      canvas.drawRect(botSandRect, sandPaint);
      canvas.restore();
    }

    // 5. Draw Falling Sand Stream
    if (sandProgress < 0.98 && !isFlipping) {
      final streamPath = Path();
      streamPath.moveTo(cx, cy);
      streamPath.lineTo(cx, botY - ((botY - cy) * sandProgress));
      canvas.drawPath(streamPath, sandStreamPaint);
    }

    // 6. Draw Glass Border Outline & Specular Reflection
    canvas.drawPath(glassPath, glassBorderPaint);

    final sheenPath = Path();
    sheenPath.moveTo(w * 0.28, topY + 4);
    sheenPath.quadraticBezierTo(w * 0.32, cy * 0.6, cx - 4, cy - 4);
    final sheenPaint = Paint()
      ..color = Colors.white.withOpacity(0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawPath(sheenPath, sheenPaint);
  }

  @override
  bool shouldRepaint(covariant _HourglassPainter oldDelegate) {
    return oldDelegate.sandProgress != sandProgress || oldDelegate.isFlipping != isFlipping;
  }
}
