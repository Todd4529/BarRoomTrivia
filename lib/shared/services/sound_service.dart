import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// SoundService handles tailored, event-specific game audio
/// across Android TV / mobile (via native audio synthesis) and web.
class SoundService {
  static const MethodChannel _channel = MethodChannel('com.barroomstrivia/audio');

  /// Master toggle for game sound effects. Muted permanently per user request.
  static bool isSoundEffectsEnabled = false;

  /// Sounds deleted per user request - immediately returns without audio output
  static Future<void> playSound(String type, [int param = 0]) async {
    if (!isSoundEffectsEnabled) return;
    return;
  }
}
