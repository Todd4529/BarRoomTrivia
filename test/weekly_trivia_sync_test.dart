import 'package:flutter_test/flutter_test.dart';
import 'package:bar_rooms_trivia/shared/data/trivia_repository.dart';
import 'package:bar_rooms_trivia/shared/models/question.dart';

void main() {
  group('Weekly Trivia Ingestion and Injection Tests', () {
    test('Injecting dynamic weekly questions enhances category question pool', () {
      final initialQuestions = TriviaRepository.getQuestionsForCategory('Sports & Stadiums');
      expect(initialQuestions.isNotEmpty, isTrue);

      final dynamicQ1 = Question(
        id: 'dyn-sports-001',
        category: 'Sports & Stadiums',
        difficulty: 'Standard',
        questionText: 'Which ancient venue hosted the first modern Olympic Games in 1896 in Athens?',
        optionA: 'Panathenaic Stadium',
        optionB: 'Wembley Stadium',
        optionC: 'Colosseum',
        optionD: 'Maracana',
        correctOption: 'A',
      );

      TriviaRepository.injectQuestions([dynamicQ1]);

      final updatedQuestions = TriviaRepository.getQuestionsForCategory('Sports & Stadiums');
      expect(updatedQuestions.any((q) => q.questionText.contains('Athens')), isTrue);
    });

    test('Injecting duplicate questions does not duplicate entries', () {
      final dynamicQ = Question(
        id: 'dyn-unique-002',
        category: 'World History',
        difficulty: 'Standard',
        questionText: 'Which legendary empire built the lost city of Machu Picchu in 1450?',
        optionA: 'Inca Empire',
        optionB: 'Aztec Empire',
        optionC: 'Maya Civilization',
        optionD: 'Olmec Empire',
        correctOption: 'A',
      );

      // Inject twice
      TriviaRepository.injectQuestions([dynamicQ]);
      TriviaRepository.injectQuestions([dynamicQ]);

      final historyQuestions = TriviaRepository.getQuestionsForCategory('World History');
      final matches = historyQuestions.where((q) => q.questionText.contains('Machu Picchu in 1450')).toList();
      expect(matches.length, equals(1));
    });
  });
}
