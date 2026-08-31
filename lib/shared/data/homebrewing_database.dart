import '../models/question.dart';
import 'genre_questions_engine.dart';

/// Authentic 500+ Homebrewing Beer Trivia Question Generator for Flutter Monorepo
class HomebrewingDatabase {
  /// Generates a randomized list of 500+ unique Homebrewing questions with zero repeats
  static List<Question> generate500Questions() {
    return GenreQuestionsEngine.generateGenreQuestions('Homebrewing Beer');
  }
}
