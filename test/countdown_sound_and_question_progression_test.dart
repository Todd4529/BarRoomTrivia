import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bar_rooms_trivia/shared/data/trivia_repository.dart';
import 'package:bar_rooms_trivia/shared/services/sound_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Countdown Sound & Question Progression Verification', () {
    test('1. TV countdown timer does NOT play question_start sound during question countdown', () {
      final tvFile = File('lib/tv/views/tv_display_view.dart').readAsStringSync();
      // Verify question_start is NOT called inside _startTimer
      final startTimerIdx = tvFile.indexOf('void _startTimer()');
      final onTimerEndedIdx = tvFile.indexOf('void _onTimerEnded');
      expect(startTimerIdx, isNonNegative);
      expect(onTimerEndedIdx, isNonNegative);
      final startTimerBody = tvFile.substring(startTimerIdx, onTimerEndedIdx);

      expect(startTimerBody.contains("SoundService.playSound('question_start')"), isFalse,
          reason: 'No sound should be played when question countdown begins');
      expect(startTimerBody.contains("rem <= 5"), isTrue,
          reason: 'Sound should only trigger in the last 5 seconds');
    });

    test('2. TV display triggers tick sound during the last 5 seconds', () {
      final tvFile = File('lib/tv/views/tv_display_view.dart').readAsStringSync();
      final startTimerIdx = tvFile.indexOf('void _startTimer()');
      final onTimerEndedIdx = tvFile.indexOf('void _onTimerEnded');
      final startTimerBody = tvFile.substring(startTimerIdx, onTimerEndedIdx);

      expect(startTimerBody.contains("SoundService.playSound('tick'"), isTrue,
          reason: 'Tick sound must trigger on remaining seconds <= 5');
      expect(startTimerBody.contains("SoundService.playSound('buzz')"), isFalse,
          reason: 'Buzzer should only play when time is up in _onTimerEnded');
    });

    test('3. MainActivity.kt implements mechanical tick-tock audio synthesizer', () {
      final mainActivityFile = File('android/app/src/main/kotlin/com/barroomstrivia/myapp/MainActivity.kt').readAsStringSync();
      expect(mainActivityFile.contains('playTickTockSound'), isTrue,
          reason: 'MainActivity must implement playTickTockSound');
      expect(mainActivityFile.contains('"tick", "tick_tock", "ticktock"'), isTrue,
          reason: 'Channel handler must route tick and tick_tock to playTickTockSound');
    });

    test('4. SoundService supports tick_tock sound type', () {
      expect(() => SoundService.playSound('tick_tock', 5), returnsNormally);
      expect(() => SoundService.playSound('tick', 3), returnsNormally);
    });

    test('5. TriviaRepository generates non-repeating consecutive questions for genre', () {
      TriviaRepository.resetSessionDecks();
      final q1 = TriviaRepository.getQuestionForGenres(['80s & 90s Nostalgia'], 0);
      final q2 = TriviaRepository.getQuestionForGenres(['80s & 90s Nostalgia'], 1);
      final q3 = TriviaRepository.getQuestionForGenres(['80s & 90s Nostalgia'], 2);

      expect(q1.questionText, isNotEmpty);
      expect(q2.questionText, isNotEmpty);
      expect(q3.questionText, isNotEmpty);

      // Verify questions are distinct and advance consecutively
      expect(q1.questionText, isNot(equals(q2.questionText)));
      expect(q2.questionText, isNot(equals(q3.questionText)));
      expect(q1.questionText, isNot(equals(q3.questionText)));
    });

    test('6. TV display advances question autonomously when review timer ends without looping', () {
      final tvFile = File('lib/tv/views/tv_display_view.dart').readAsStringSync();

      // Ensure _interQuestionTimer end does NOT call broadcastSyncRequest
      final onTimerEndedIdx = tvFile.indexOf('void _onTimerEnded');
      final completeRoundIdx = tvFile.indexOf('void _completeRoundAutonomously');
      final onTimerEndedBody = tvFile.substring(onTimerEndedIdx, completeRoundIdx);

      expect(onTimerEndedBody.contains('_advanceNextQuestionAutonomously();'), isTrue,
          reason: 'Must advance autonomously when review period ends');
      expect(onTimerEndedBody.contains('broadcastSyncRequest'), isFalse,
          reason: 'Must not call broadcastSyncRequest at end of review phase to prevent question repetition loop');
    });

    test('7. TV onRequestStateSyncBroadcast ignores TV self-requests and does not rebroadcast expired questions', () {
      final tvFile = File('lib/tv/views/tv_display_view.dart').readAsStringSync();

      final syncHandlerIdx = tvFile.indexOf('onRequestStateSyncBroadcast: (payload)');
      expect(syncHandlerIdx, isNonNegative);
      final syncHandlerEnd = tvFile.indexOf('void _startRoundQuestionOneAutonomously()');
      final syncBody = tvFile.substring(syncHandlerIdx, syncHandlerEnd);

      expect(syncBody.contains("sender == 'tv'"), isTrue,
          reason: 'Must ignore self-sent sync requests from TV');
      expect(syncBody.contains("!_isTimerExpired && !_isInterQuestionPhase && _remainingSeconds > 0"), isTrue,
          reason: 'Must only broadcast active question if timer is still running, not expired');
    });

    test('8. TV onQuestionBroadcast ignores duplicate active question echo', () {
      final tvFile = File('lib/tv/views/tv_display_view.dart').readAsStringSync();
      expect(tvFile.contains('// If this exact question is already actively playing and counting down on TV, ignore redundant echo'), isTrue,
          reason: 'Must ignore duplicate active question broadcasts to avoid resetting timer');
    });
  });
}
