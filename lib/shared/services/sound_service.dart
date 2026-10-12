import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// SoundService handles tailored, event-specific game audio
/// across Android TV / mobile (via native audio synthesis) and web.
class SoundService {
  static const MethodChannel _channel = MethodChannel('com.barroomstrivia/audio');

  /// Master toggle for game sound effects. When false, all audio playback is immediately muted.
  static bool isSoundEffectsEnabled = true;

  /// Play a tailored sound effect for a specific trivia game event:
  /// - 'question_start': Ascending game show chime announcing new question
  /// - 'tick' / 'tick_tock': Crisp ticking clock sound (param: remaining seconds 5..1)
  /// - 'buzz' / 'time_up': Authoritative game show time-expired buzzer
  /// - 'correct' / 'clapping_fanfare': Celebratory crowd clapping and cheering sound celebrating correct answer reveal
  /// - 'fanfare': Celebratory round victory clapping and cheering sound
  static Future<void> playSound(String type, [int param = 0]) async {
    if (!isSoundEffectsEnabled) return;
    try {
      await _channel.invokeMethod('playSound', {
        'type': type,
        'param': param,
      });
    } catch (e) {
      if (!isSoundEffectsEnabled) return;
      debugPrint('[SoundService] Audio playback fallback: $e');
      if (type == 'buzz' || type == 'time_up') {
        SystemSound.play(SystemSoundType.alert);
      } else {
        SystemSound.play(SystemSoundType.click);
        if (type == 'tick' || type == 'tick_tock' || type == 'ticktock') {
          Future.delayed(const Duration(milliseconds: 120), () {
            if (!isSoundEffectsEnabled) return;
            SystemSound.play(SystemSoundType.click);
          });
        }
      }
    }
  }
}
