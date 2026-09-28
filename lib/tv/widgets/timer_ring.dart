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

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Stack(
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
            Text(
              '$remainingSeconds',
              style: TextStyle(
                fontSize: (size * 0.44).clamp(20.0, 36.0),
                fontWeight: FontWeight.w900,
                color: ringColor,
                height: 1.0,
              ),
            ),
          ],
        ),
        if (label.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: Colors.white70,
            ),
          ),
        ],
      ],
    );
  }
}
