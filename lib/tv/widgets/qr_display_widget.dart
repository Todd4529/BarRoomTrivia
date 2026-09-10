import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../shared/theme/app_theme.dart';

class QrDisplayWidget extends StatelessWidget {
  final String roomCode;
  final String baseUrl;
  final bool showRoomCode;
  final bool compact;

  const QrDisplayWidget({
    super.key,
    required this.roomCode,
    this.baseUrl = 'https://todd4529.github.io/BarRoomTrivia',
    this.showRoomCode = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final cleanBase = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final playUrl = '$cleanBase/?view=player&room=$roomCode';

    return Container(
      padding: EdgeInsets.all(compact ? 10 : 20),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(compact ? 14 : 20),
        border: Border.all(color: AppTheme.neonCyan.withValues(alpha: 0.4), width: compact ? 1.5 : 2),
        boxShadow: [
          BoxShadow(
            color: AppTheme.neonCyan.withValues(alpha: 0.15),
            blurRadius: compact ? 12 : 20,
            spreadRadius: compact ? 1 : 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'SCAN TO PLAY',
            style: TextStyle(
              fontSize: compact ? 14 : 22,
              fontWeight: FontWeight.w900,
              letterSpacing: compact ? 1.2 : 2.0,
              color: AppTheme.neonCyan,
            ),
          ),
          SizedBox(height: compact ? 6 : 12),
          Container(
            padding: EdgeInsets.all(compact ? 8 : 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(compact ? 12 : 16),
            ),
            child: QrImageView(
              data: playUrl,
              version: QrVersions.auto,
              size: compact ? 110.0 : 180.0,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
              dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
            ),
          ),
          if (showRoomCode) ...[
            const SizedBox(height: 16),
            const Text(
              'ROOM CODE',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 2.0,
                color: Colors.white54,
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              roomCode,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                letterSpacing: 4.0,
                color: AppTheme.neonYellow,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
