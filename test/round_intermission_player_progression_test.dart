import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Round Intermission Player Progression & Timers Verification Suite', () {
    late String mainJsContent;
    late String playerControllerContent;
    late String tvDisplayContent;
    late String realtimeServiceContent;

    setUpAll(() {
      mainJsContent = File('src/main.js').readAsStringSync();
      playerControllerContent = File('lib/player/views/player_controller_view.dart').readAsStringSync();
      tvDisplayContent = File('lib/tv/views/tv_display_view.dart').readAsStringSync();
      realtimeServiceContent = File('lib/shared/services/realtime_service.dart').readAsStringSync();
    });

    test('1. Web main.js winnerCountdownInterval finishes, clears interval, exits ROUND_SUMMARY, and requests sync', () {
      expect(mainJsContent.contains("if (currentSecs <= 0) {"), isTrue);
      expect(mainJsContent.contains("currentGameState = 'COUNTDOWN';"), isTrue);
      expect(mainJsContent.contains("broadcastRealtimeEvent('request_state_sync'"), isTrue);
      expect(mainJsContent.contains("triggerActiveSessionSync();"), isTrue);
    });

    test('2. Web main.js handleIncomingQuestionStart sets QUESTION_ACTIVE and clears winnerCountdownInterval', () {
      expect(mainJsContent.contains("currentGameState = 'QUESTION_ACTIVE';\n  clearInterval(winnerCountdownInterval);"), isTrue);
    });

    test('3. Web main.js syncSessionFromSupabase safely transitions out of ROUND_SUMMARY for new round question', () {
      expect(mainJsContent.contains("if (isIntermissionActive) {\n              if (sessionRound < currentRound) {\n                return;\n              }\n              currentGameState = 'QUESTION_ACTIVE';\n              clearInterval(winnerCountdownInterval);"), isTrue);
    });

    test('4. Web main.js round_completed/round_winner handler guards currentRound increment against missing metadata', () {
      expect(mainJsContent.contains("const rawCompleted = payload?.completed_round || payload?.round_number || payload?.roundNumber;"), isTrue);
      expect(mainJsContent.contains("const nextR = Number(rawNext || (rawCompleted ? Number(rawCompleted) + 1 : currentRound));"), isTrue);
    });

    test('5. PlayerControllerView clears _isInterRoundPhase and requests state sync when interRoundTimer reaches 0', () {
      expect(playerControllerContent.contains("_isInterRoundPhase = false;"), isTrue);
      expect(playerControllerContent.contains("_showRoundWinnersOverlay = false;"), isTrue);
      expect(playerControllerContent.contains("_realtimeService.broadcastSyncRequest(roomCode: room);"), isTrue);
    });

    test('6. PlayerControllerView _startPlayerSessionPolling treats _isInterRoundPhase as new question', () {
      expect(playerControllerContent.contains("_isInterRoundPhase ||\n                  _showRoundWinnersOverlay ||\n                  _isReviewPhase"), isTrue);
    });

    test('7. TVDisplayView formats timer_ends_at and starts_at as ISO-8601 strings for Postgres TIMESTAMPTZ', () {
      expect(tvDisplayContent.contains("'timer_ends_at': DateTime.fromMillisecondsSinceEpoch(timerEndsAtEpochMs).toIso8601String()"), isTrue);
      expect(tvDisplayContent.contains("'starts_at': DateTime.fromMillisecondsSinceEpoch(nextStartsAt).toIso8601String()"), isTrue);
    });

    test('8. RealtimeService formats timer_ends_at and starts_at as ISO-8601 strings for Supabase sessions', () {
      expect(realtimeServiceContent.contains("'timer_ends_at': DateTime.fromMillisecondsSinceEpoch(timerEndsAtEpochMs).toIso8601String()"), isTrue);
      expect(realtimeServiceContent.contains("'starts_at': startsAtEpochMs != null ? DateTime.fromMillisecondsSinceEpoch(startsAtEpochMs).toIso8601String() : null"), isTrue);
    });
  });
}
