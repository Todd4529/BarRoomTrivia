import '../models/question.dart';

/// Specialized Question Generator and Data Bank for Science, Technology, History & Geography
class ScienceHistoryDatabase {
  static List<Question> generateQuestions() {
    final questions = <Question>[];
    questions.addAll(_curatedScienceQuestions);
    questions.addAll(_curatedHistoryQuestions);
    questions.addAll(_curatedGeographyQuestions);
    return questions;
  }

  static final List<Question> _curatedScienceQuestions = [
    Question(
      id: 'sci-01',
      category: 'Science & Technology',
      difficulty: 'Standard',
      questionText: 'What element on the periodic table has the chemical symbol "Au"?',
      optionA: 'Gold',
      optionB: 'Silver',
      optionC: 'Copper',
      optionD: 'Aluminum',
      correctOption: 'A',
    ),
    Question(
      id: 'sci-02',
      category: 'Science & Technology',
      difficulty: 'Standard',
      questionText: 'What is the speed of light in a vacuum approximately equal to?',
      optionA: '300,000 km/s (186,000 miles/s)',
      optionB: '150,000 km/s',
      optionC: '500,000 km/s',
      optionD: '1,000,000 km/s',
      correctOption: 'A',
    ),
    Question(
      id: 'sci-03',
      category: 'Astronomy & Space',
      difficulty: 'Standard',
      questionText: 'Which planet in our solar system is known as the "Red Planet" due to iron oxide on its surface?',
      optionA: 'Mars',
      optionB: 'Venus',
      optionC: 'Jupiter',
      optionD: 'Saturn',
      correctOption: 'A',
    ),
    Question(
      id: 'sci-04',
      category: 'Astronomy & Space',
      difficulty: 'Standard',
      questionText: 'What Apollo mission successfully landed the first humans on the Moon in July 1969?',
      optionA: 'Apollo 11',
      optionB: 'Apollo 13',
      optionC: 'Apollo 8',
      optionD: 'Apollo 17',
      correctOption: 'A',
    ),
  ];

  static final List<Question> _curatedHistoryQuestions = [
    Question(
      id: 'hist-01',
      category: 'World History',
      difficulty: 'Standard',
      questionText: 'In what year did the Declaration of Independence get signed in Philadelphia?',
      optionA: '1776',
      optionB: '1789',
      optionC: '1812',
      optionD: '1754',
      correctOption: 'A',
    ),
    Question(
      id: 'hist-02',
      category: 'World History',
      difficulty: 'Standard',
      questionText: 'Which ancient civilization constructed the Great Pyramid of Giza?',
      optionA: 'Ancient Egyptians',
      optionB: 'Mesopotamians',
      optionC: 'Romans',
      optionD: 'Greeks',
      correctOption: 'A',
    ),
    Question(
      id: 'hist-03',
      category: 'World History',
      difficulty: 'Standard',
      questionText: 'What wall erected in 1961 dividing a major European city fell on November 9, 1989?',
      optionA: 'The Berlin Wall',
      optionB: 'Hadrian\'s Wall',
      optionC: 'The Great Wall',
      optionD: 'The Iron Curtain Wall',
      correctOption: 'A',
    ),
  ];

  static final List<Question> _curatedGeographyQuestions = [
    Question(
      id: 'geo-01',
      category: 'World Geography',
      difficulty: 'Standard',
      questionText: 'What is the largest ocean on Earth by surface area?',
      optionA: 'Pacific Ocean',
      optionB: 'Atlantic Ocean',
      optionC: 'Indian Ocean',
      optionD: 'Arctic Ocean',
      correctOption: 'A',
    ),
    Question(
      id: 'geo-02',
      category: 'World Geography',
      difficulty: 'Standard',
      questionText: 'What is the capital city of Australia?',
      optionA: 'Canberra',
      optionB: 'Sydney',
      optionC: 'Melbourne',
      optionD: 'Brisbane',
      correctOption: 'A',
    ),
    Question(
      id: 'geo-03',
      category: 'World Geography',
      difficulty: 'Standard',
      questionText: 'Which continent contains the Amazon Rainforest and the Andes mountain range?',
      optionA: 'South America',
      optionB: 'Africa',
      optionC: 'Asia',
      optionD: 'North America',
      correctOption: 'A',
    ),
  ];
}
