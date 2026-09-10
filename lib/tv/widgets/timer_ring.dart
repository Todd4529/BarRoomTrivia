import 'package:flutter/material.dart';
import '../../shared/theme/app_theme.dart';

class TimerRing extends StatelessWidget {
  final double progress; // 0.0 to 1.0
  final int remainingSeconds;
  final String label;
  final Color? customColor;

  const TimerRing({
    super.key,
    required this.progress,
    required this.remainingSeconds,
    this.label = 'SECONDS',
    this.customColor,
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
          width: 140,
          height: 140,
          child: CircularProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            strokeWidth: 12,
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
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: ringColor,
              ),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
