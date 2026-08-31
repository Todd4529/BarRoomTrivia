import '../models/question.dart';
import 'genre_questions_engine.dart';

/// Specialized Question Generator and Data Bank for Movies, Music & Pop Culture
class PopCultureDatabase {
  static List<Question> generateQuestions() {
    final questions = <Question>[];
    questions.addAll(GenreQuestionsEngine.generateGenreQuestions('Movies & Hollywood'));
    questions.addAll(GenreQuestionsEngine.generateGenreQuestions('Pop Culture & Music'));
    questions.addAll(GenreQuestionsEngine.generateGenreQuestions('80s & 90s Nostalgia'));
    return questions;
  }
}
