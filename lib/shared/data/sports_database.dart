import '../models/question.dart';
import 'genre_questions_engine.dart';

/// Specialized Question Generator and Data Bank for Sports & Stadiums
class SportsDatabase {
  static List<Question> generateQuestions() {
    return GenreQuestionsEngine.generateGenreQuestions('Sports & Stadiums');
  }
}
