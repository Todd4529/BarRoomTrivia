import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bar_rooms_trivia/shared/models/question.dart';

void main() {
  group('Player View Next Question Progression & "Waiting for Next Question" Fix Tests', () {
    late String mainJs;
    late String indexHtml;
    late String playerControllerDart;

    setUpAll(() {
      mainJs = File('src/main.js').readAsStringSync();
      indexHtml = File('index.html').readAsStringSync();
      playerControllerDart = File('lib/player/views/player_controller_view.dart').readAsStringSync();
    });

    test('1. index.html defines initial player question text "Waiting for next question..." with 4 option buttons', () {
      expect(indexHtml.contains('id="player-question-text"'), isTrue);
      expect(indexHtml.contains('Waiting for next question...'), isTrue);
      expect(indexHtml.contains('class="player-question-card"'), isTrue);
      expect(indexHtml.contains('class="button-grid-2x2"'), isTrue);
      expect(indexHtml.contains('id="player-inter-question-screen"'), isTrue);
    });

    test('2. main.js handleIncomingQuestionStart dismisses overlays and checks isUiWaiting to prevent stuck state', () {
      expect(mainJs.contains('isUiWaiting'), isTrue);
      expect(mainJs.contains("playerQElem.textContent.includes('Waiting for next question')"), isTrue);
      expect(mainJs.contains("if (isSameQuestion && !isUiWaiting && playerChoiceSubmitted !== null)"), isTrue);
      expect(mainJs.contains("if (isSameQuestion && !isUiWaiting && (isCurrentQuestionScored || currentGameState === 'QUESTION_REVIEW'))"), isTrue);
      // Ensures that if UI is waiting, question start is NOT skipped
    });

    test('3. main.js handleIncomingQuestionStart only drops stale questions strictly from a past round', () {
      expect(mainJs.contains('incomingRound < currentRound'), isTrue);
      expect(mainJs.contains('incomingRound <= currentRound'), isFalse,
          reason: 'Must not drop round 2 question when currentRound was already incremented to 2');
    });

    test('4. main.js syncSessionFromSupabase supports active_reading and forces sync if player UI is waiting', () {
      expect(mainJs.contains("session.status === 'question_active' || session.status === 'active_reading'"), isTrue);
      expect(mainJs.contains('isUiWaiting'), isTrue);
      expect(mainJs.contains('isDifferentQ = !currentQuestionData ||'), isTrue);
      expect(mainJs.contains('cumulative_question_index: session.current_question_index || 1'), isTrue);
    });

    test('5. main.js switchView immediately renders active question when entering player view', () {
      expect(mainJs.contains("if (viewName === 'player') {"), isTrue);
      expect(mainJs.contains("currentGameState === 'QUESTION_ACTIVE' || currentGameState === 'QUESTION_READING'"), isTrue);
    });

    test('6. main.js hideInterQuestionCountdown explicitly restores question card display', () {
      expect(mainJs.contains("function hideInterQuestionCountdown()"), isTrue);
      expect(mainJs.contains("interQScreen.style.display = 'none'"), isTrue);
      expect(mainJs.contains("qCard.style.display = ''"), isTrue);
      expect(mainJs.contains("btnGrid.style.display = ''"), isTrue);
    });

    test('7. PlayerControllerView onQuestionBroadcast only drops stale questions strictly from past rounds', () {
      expect(playerControllerDart.contains('incomingRound < _currentRound'), isTrue);
      expect(playerControllerDart.contains('incomingRound <= _currentRound && isSameIndex'), isFalse,
          reason: 'Must not ignore round advancement to new question');
    });

    test('8. PlayerControllerView _startPlayerSessionPolling supports active_reading and transitions out of review phase', () {
      expect(playerControllerDart.contains("status == 'question_active' || status == 'active_reading'"), isTrue);
      expect(playerControllerDart.contains('_isInterQuestionPhase ||'), isTrue);
      expect(playerControllerDart.contains('_isReviewPhase ||'), isTrue);
    });

    test('9. Question JSON serialization and deserialization properly retains question text across devices', () {
      final q = Question(
        id: 'q_test_101',
        category: 'Pop Culture',
        difficulty: 'Standard',
        questionText: 'Who sang Bohemian Rhapsody?',
        optionA: 'Queen',
        optionB: 'The Beatles',
        optionC: 'Led Zeppelin',
        optionD: 'Pink Floyd',
        correctOption: 'A',
        timeLimitSeconds: 20,
      );

      final json = q.toJson();
      expect(json['id'], equals('q_test_101'));
      expect(json['text'], equals('Who sang Bohemian Rhapsody?'));
      expect(json['options']['A'], equals('Queen'));

      final restored = Question.fromJson(json);
      expect(restored.id, equals('q_test_101'));
      expect(restored.questionText, equals('Who sang Bohemian Rhapsody?'));
      expect(restored.optionA, equals('Queen'));
      expect(restored.correctOption, equals('A'));
    });
  });
}
