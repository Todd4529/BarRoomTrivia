import 'package:flutter/material.dart';
import '../../shared/theme/app_theme.dart';

class TimerRing extends StatelessWidget {
  final double progress; // 0.0 to 1.0
  final int remainingSeconds;
  final String label;
  final Color? customColor;
  final double size;

  const TimerRing({
    super.key,
    required this.progress,
    required this.remainingSeconds,
    this.label = 'SECONDS',
    this.customColor,
    this.size = 58,
  });

  @override
  Widget build(BuildContext context) {
    final Color ringColor = customColor ??
        (remainingSeconds <= 5
            ? AppTheme.neonPink
            : remainingSeconds <= 10
                ? AppTheme.neonYellow
                : AppTheme.neonCyan);

    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            strokeWidth: (size * 0.08).clamp(3.5, 8.0),
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation<Color>(ringColor),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$remainingSeconds',
              style: TextStyle(
                fontSize: (size * 0.36).clamp(18.0, 36.0),
                fontWeight: FontWeight.bold,
                color: ringColor,
                height: 1.05,
              ),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: (size * 0.12).clamp(7.5, 10.0),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
