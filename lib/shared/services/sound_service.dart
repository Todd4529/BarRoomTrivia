import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// SoundService handles tailored, event-specific game audio
/// across Android TV / mobile (via native audio synthesis) and web.
class SoundService {
  static const MethodChannel _channel = MethodChannel('com.barroomstrivia/audio');

  /// Play a tailored sound effect for a specific trivia game event:
  /// - 'question_start': Ascending game show chime announcing new question
  /// - 'tick': Crisp tension tick (param: remaining seconds 5..1 for pitch escalation)
  /// - 'buzz' / 'time_up': Authoritative game show time-expired buzzer
  /// - 'correct': Sparkling victory chime
  /// - 'fanfare': Celebratory round victory fanfare
  static Future<void> playSound(String type, [int param = 0]) async {
    try {
      await _channel.invokeMethod('playSound', {
        'type': type,
        'param': param,
      });
    } catch (e) {
      debugPrint('[SoundService] Audio playback fallback: $e');
      if (type == 'buzz' || type == 'time_up') {
        SystemSound.play(SystemSoundType.alert);
      } else {
        SystemSound.play(SystemSoundType.click);
      }
    }
  }
}
