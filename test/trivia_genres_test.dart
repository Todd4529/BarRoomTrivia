import 'package:flutter_test/flutter_test.dart';
import 'package:bar_rooms_trivia/shared/data/trivia_genres.dart';
import 'package:bar_rooms_trivia/shared/data/trivia_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Trivia Question Genres - 500+ Unique Questions & Non-Repeating Verification', () {
    final specificGenres = TriviaGenres.allGenres
        .where((g) => g != 'Auto Select' && g != 'Random (Mixed)')
        .toList();

    for (final genre in specificGenres) {
      test('Genre "$genre" has at least 500 unique non-repeating questions', () {
        final questions = TriviaRepository.getQuestionsForCategory(genre);
        
        // 1. Verify count
        expect(questions.length, greaterThanOrEqualTo(500),
            reason: 'Genre $genre must contain at least 500 questions');

        // 2. Verify uniqueness of question text
        final seenTexts = <String>{};
        final duplicates = <String>[];

        for (final q in questions) {
          final text = q.questionText.trim().toLowerCase();
          if (seenTexts.contains(text)) {
            duplicates.add(q.questionText);
          }
          seenTexts.add(text);

          // Verify options exist
          expect(q.optionA.isNotEmpty, true);
          expect(q.optionB.isNotEmpty, true);
          expect(q.optionC.isNotEmpty, true);
          expect(q.optionD.isNotEmpty, true);
          expect(['A', 'B', 'C', 'D'].contains(q.correctOption), true);
        }

        expect(duplicates, isEmpty,
            reason: 'Found duplicate questions in genre $genre: $duplicates');
      });
    }

    test('TriviaRepository.getQuestionForGenres delivers non-repeating questions across games', () {
      TriviaRepository.resetSessionDecks();
      final servedQuestions = <String>{};

      // Draw 50 consecutive questions for a target genre
      for (int i = 0; i < 50; i++) {
        final q = TriviaRepository.getQuestionForGenres(['Homebrewing Beer'], i);
        expect(servedQuestions.contains(q.questionText), false,
            reason: 'Question repeated at index $i: "${q.questionText}"');
        servedQuestions.add(q.questionText);
      }

      expect(servedQuestions.length, 50);
    });
  });
}
