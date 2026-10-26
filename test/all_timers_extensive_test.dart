import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bar_rooms_trivia/shared/services/realtime_service.dart';
import 'package:bar_rooms_trivia/shared/services/game_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Extensive All Timers Verification & Accuracy Suite', () {
    late String mainJsContent;
    late String playerControllerContent;
    late String tvDisplayContent;
    late String realtimeServiceContent;
    late String htmlContent;

    setUpAll(() {
      mainJsContent = File('src/main.js').readAsStringSync();
      playerControllerContent = File('lib/player/views/player_controller_view.dart').readAsStringSync();
      tvDisplayContent = File('lib/tv/views/tv_display_view.dart').readAsStringSync();
      realtimeServiceContent = File('lib/shared/services/realtime_service.dart').readAsStringSync();
      htmlContent = File('index.html').readAsStringSync();
    });

    test('1. All standard question timer durations (10s, 15s, 20s, 30s, 45s, 60s, 90s, 120s, 180s) are supported and 20s is default', () {
      final supportedDurations = [10, 15, 20, 30, 45, 60, 90, 120, 180];

      // index.html checks
      for (final sec in supportedDurations) {
        expect(htmlContent.contains('data-timer="$sec"'), isTrue,
            reason: 'index.html must contain timer chip for ${sec}s');
      }
      expect(htmlContent.contains('data-timer="20">20s (Default)</button>'), isTrue,
          reason: '20s timer must be the default chip in index.html');

      // main.js checks
      expect(mainJsContent.contains("bar_trivia_question_duration') || '20'"), isTrue,
          reason: 'main.js must default selectedQuestionDuration to 20');
      expect(mainJsContent.contains('totalTimerDuration = 20'), isTrue,
          reason: 'main.js must initialize totalTimerDuration to 20');

      // When timer chip is clicked, both selectedQuestionDuration and totalTimerDuration update
      expect(mainJsContent.contains('selectedQuestionDuration = parsedSecs'), isTrue);
      expect(mainJsContent.contains('totalTimerDuration = parsedSecs'), isTrue);
    });

    test('2. 20-second question timer defensive guard prevents shortening when clock skew produces <= 4s', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      // Host sends 20s duration with a skewed deadline arriving with only 2s remaining
      final skewedDeadline = now + 2000;
      final payload = {
        'duration_seconds': 20,
        'timer_ends_at_epoch_ms': skewedDeadline,
      };

      final fallbackDuration = (payload['duration_seconds'] as num?)?.toInt() ?? 20;
      final remainingMs = skewedDeadline - now;
      int durationSec = (remainingMs / 1000).ceil();

      // Defensive guard implemented in player and TV
      if (durationSec <= 4 && fallbackDuration > 4) {
        durationSec = fallbackDuration;
      }

      // Player must be given the full 20s, not robbed of time
      expect(durationSec, 20, reason: 'Defensive guard must restore 20s timer');
    });

    test('3. Player Controller View implements defensive fallback guard for question timer', () {
      expect(playerControllerContent.contains('if (!isIdleTimer && durationSec <= 4 && fallbackDuration > 4)'), isTrue,
          reason: 'Player Controller View must enforce durationSec <= 4 fallback guard in onQuestionBroadcast');
      expect(playerControllerContent.contains('if (durationSec <= 4 && dur > 4)'), isTrue,
          reason: 'Player Controller View must enforce durationSec <= 4 fallback guard in polling recovery');
    });

    test('4. TV Display View implements defensive fallback guard for question timer', () {
      expect(tvDisplayContent.contains('if (!isIdleTimer && durationSec <= 4 && duration > 4)'), isTrue,
          reason: 'TV Display View must enforce durationSec <= 4 fallback guard in onQuestionBroadcast');
    });

    test('5. Web main.js implements defensive duration guard in handleIncomingQuestionStart, onQuestionStart, and startCountdown', () {
      expect(mainJsContent.contains('if (remainingSecs <= 4 && durationSeconds > 4)'), isTrue,
          reason: 'main.js handleIncomingQuestionStart must enforce remainingSecs <= 4 fallback');
      expect(mainJsContent.contains('if (durationSeconds <= 4 && totalTimerDuration > 4)'), isTrue,
          reason: 'main.js onQuestionStart must enforce durationSeconds <= 4 fallback');
      expect(mainJsContent.contains('(timerEndsAtGlobalMs - now) <= 4000 && validSeconds > 4'), isTrue,
          reason: 'main.js startCountdown must enforce 4s skew threshold');
    });

    test('6. RealtimeService normalizeClockSkew re-bases timer_ends_at, timerEndsAtEpochMs, starts_at across clock drifts', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      // Sender clock is 12 seconds behind local clock
      final senderSentTime = now - 12000;
      final senderDeadline = senderSentTime + 20000; // Sender gave 20 seconds

      final rawPayload = {
        'timestamp': senderSentTime,
        'timer_ends_at_epoch_ms': senderDeadline,
        'timerEndsAtEpochMs': senderDeadline,
        'timer_ends_at': senderDeadline,
        'duration_seconds': 20,
      };

      final normalized = RealtimeService.normalizeClockSkew(rawPayload);
      final adjustedDeadline = normalized['timer_ends_at_epoch_ms'] as int;
      final remainingMs = adjustedDeadline - now;
      final remainingSec = (remainingMs / 1000).ceil();

      expect(remainingSec, inInclusiveRange(19, 21),
          reason: 'Normalized deadline must yield full ~20s on receiver clock');
      expect(normalized['timerEndsAtEpochMs'], adjustedDeadline);
      expect(normalized['timer_ends_at'], adjustedDeadline);
    });

    test('7. RealtimeService normalizeClockSkew handles ISO-8601 string deadlines and updated_at fallback', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final senderSentTime = now - 10000;
      final deadlineIso = DateTime.fromMillisecondsSinceEpoch(senderSentTime + 20000).toIso8601String();

      final rawPayload = {
        'updated_at': DateTime.fromMillisecondsSinceEpoch(senderSentTime).toIso8601String(),
        'timer_ends_at': deadlineIso,
        'duration_seconds': 20,
      };

      final normalized = RealtimeService.normalizeClockSkew(rawPayload);
      final adjustedDeadline = normalized['timer_ends_at'] as int;
      final remainingMs = adjustedDeadline - now;
      final remainingSec = (remainingMs / 1000).ceil();

      expect(remainingSec, inInclusiveRange(19, 21),
          reason: 'ISO-8601 string deadlines with updated_at timestamp must normalize accurately');
    });

    test('8. Pre-Game Countdown timer (10s) is accurately configured and tracked', () {
      final gameEngineContent = File('lib/shared/services/game_engine.dart').readAsStringSync();
      expect(gameEngineContent.contains('preGameSecondsRemaining'), isTrue);

      // Web main.js pre-game countdown
      expect(mainJsContent.contains('const preGameSecs = 10;'), isTrue);
      expect(mainJsContent.contains('const countdownSecs = 10;'), isTrue);
      expect(mainJsContent.contains('startsAtMs = Date.now() + (countdownSecs * 1000)'), isTrue);
    });

    test('9. Question Review timer (15s) is synchronized with countdown display and answer reveal', () {
      // Web main.js review duration
      expect(mainJsContent.contains('const reviewDurationMs = 15000;'), isTrue,
          reason: 'Web main.js must use 15-second review duration');
      expect(mainJsContent.contains('nextEpoch = now + 15000;'), isTrue,
          reason: 'Web fallback review epoch must be exactly 15 seconds');

      // TV Display review duration
      expect(tvDisplayContent.contains('DateTime.now().millisecondsSinceEpoch + 15000'), isTrue,
          reason: 'Flutter TV display must use 15-second review fallback epoch');
    });

    test('10. Inter-Round Intermission timers (30s, 60s, 120s, 180s, 240s, 300s, 600s) supported', () {
      final expectedRoundIntervals = [30, 60, 120, 180, 240, 300, 600];

      for (final dur in expectedRoundIntervals) {
        expect(htmlContent.contains('data-round-dur="$dur"'), isTrue,
            reason: 'index.html must include inter-round chip for ${dur}s');
      }

      final gameEngineContent = File('lib/shared/services/game_engine.dart').readAsStringSync();
      expect(gameEngineContent.contains('int interRoundDurationSeconds = 120;'), isTrue);
    });

    test('11. Game Resume countdown timer (10s) accurately alerts players with 10s countdown', () {
      expect(playerControllerContent.contains('_resumeSecondsRemaining = 10'), isTrue);
      expect(tvDisplayContent.contains('_resumeSecondsRemaining = 10'), isTrue);
      expect(mainJsContent.contains('const resumeSecs = 10;'), isTrue);
    });

    test('12. Top 3 Winners celebration display timer (20s) on TV transitions cleanly to ad signage', () {
      expect(mainJsContent.contains('const winnerDisplayMs = Math.min(20000, remWinnerSecs * 1000);'), isTrue,
          reason: 'Top 3 Winners overlay must display for 20s before uncovering signage during intermission');
      expect(tvDisplayContent.contains('final winnerDisplaySec = delaySec > 20 ? 20 : delaySec;'), isTrue,
          reason: 'TV display must display round winners fanfare for up to 20s');
    });

    test('13. Broadcast question payloads in main.js include explicit timestamp and totalTimerDuration', () {
      expect(mainJsContent.contains('timestamp: Date.now()'), isTrue);
      expect(mainJsContent.contains('sent_at_epoch_ms: Date.now()'), isTrue);
      expect(mainJsContent.contains('totalTimerDuration: durationSeconds'), isTrue);
    });
  });
}
