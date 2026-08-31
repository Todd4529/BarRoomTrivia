import '../models/question.dart';
import 'genre_questions_engine.dart';

/// Specialized Question Generator and Data Bank for Science, Technology, History & Geography
class ScienceHistoryDatabase {
  static List<Question> generateQuestions() {
    final questions = <Question>[];
    questions.addAll(GenreQuestionsEngine.generateGenreQuestions('Science & Technology'));
    questions.addAll(GenreQuestionsEngine.generateGenreQuestions('World History'));
    questions.addAll(GenreQuestionsEngine.generateGenreQuestions('World Geography'));
    return questions;
  }
}
