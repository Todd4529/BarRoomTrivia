import '../models/question.dart';

/// Specialized Question Generator and Data Bank for Movies, Music & Pop Culture
class PopCultureDatabase {
  static List<Question> generateQuestions() {
    final questions = <Question>[];
    questions.addAll(_curatedMovieQuestions);
    questions.addAll(_curatedMusicQuestions);
    questions.addAll(_curated80s90sQuestions);
    return questions;
  }

  static final List<Question> _curatedMovieQuestions = [
    Question(
      id: 'mov-01',
      category: 'Movies & Hollywood',
      difficulty: 'Standard',
      questionText: 'Which 1994 film won 6 Academy Awards including Best Picture, Best Director, and Best Actor for Tom Hanks?',
      optionA: 'Forrest Gump',
      optionB: 'Pulp Fiction',
      optionC: 'The Shawshank Redemption',
      optionD: 'Jurassic Park',
      correctOption: 'A',
    ),
    Question(
      id: 'mov-02',
      category: 'Movies & Hollywood',
      difficulty: 'Standard',
      questionText: 'In the Star Wars franchise, what is the iconic name of Han Solo’s starship?',
      optionA: 'Millennium Falcon',
      optionB: 'Star Destroyer',
      optionC: 'X-Wing Fighter',
      optionD: 'Tie Interceptor',
      correctOption: 'A',
    ),
    Question(
      id: 'mov-03',
      category: 'Movies & Hollywood',
      difficulty: 'Standard',
      questionText: 'What actor famously uttered the quote "I\'ll be back" in the 1984 sci-fi classic The Terminator?',
      optionA: 'Arnold Schwarzenegger',
      optionB: 'Sylvester Stallone',
      optionC: 'Bruce Willis',
      optionD: 'Jean-Claude Van Damme',
      correctOption: 'A',
    ),
    Question(
      id: 'mov-04',
      category: 'Movies & Hollywood',
      difficulty: 'Standard',
      questionText: 'Which director directed Jaws, E.T. the Extra-Terrestrial, Jurassic Park, and Indiana Jones?',
      optionA: 'Steven Spielberg',
      optionB: 'George Lucas',
      optionC: 'James Cameron',
      optionD: 'Christopher Nolan',
      correctOption: 'A',
    ),
  ];

  static final List<Question> _curatedMusicQuestions = [
    Question(
      id: 'mus-01',
      category: 'Pop Culture & Music',
      difficulty: 'Standard',
      questionText: 'Which legendary British band released the best-selling 1973 album "The Dark Side of the Moon"?',
      optionA: 'Pink Floyd',
      optionB: 'The Beatles',
      optionC: 'Led Zeppelin',
      optionD: 'The Rolling Stones',
      correctOption: 'A',
    ),
    Question(
      id: 'mus-02',
      category: 'Pop Culture & Music',
      difficulty: 'Standard',
      questionText: 'What artist released the highest-selling studio album of all time, "Thriller", in 1982?',
      optionA: 'Michael Jackson',
      optionB: 'Prince',
      optionC: 'Whitney Houston',
      optionD: 'Stevie Wonder',
      correctOption: 'A',
    ),
    Question(
      id: 'mus-03',
      category: 'Pop Culture & Music',
      difficulty: 'Standard',
      questionText: 'Which rock icon performed the historic guitar rendition of "The Star-Spangled Banner" at Woodstock in 1969?',
      optionA: 'Jimi Hendrix',
      optionB: 'Eric Clapton',
      optionC: 'Jimmy Page',
      optionD: 'Carlos Santana',
      correctOption: 'A',
    ),
  ];

  static final List<Question> _curated80s90sQuestions = [
    Question(
      id: '80s-01',
      category: '80s & 90s Nostalgia',
      difficulty: 'Standard',
      questionText: 'What handheld Nintendo gaming console was released in 1989 and sold over 118 million units worldwide?',
      optionA: 'Game Boy',
      optionB: 'Game Gear',
      optionC: 'PlayStation Portable',
      optionD: 'Nintendo DS',
      correctOption: 'A',
    ),
    Question(
      id: '90s-02',
      category: '80s & 90s Nostalgia',
      difficulty: 'Standard',
      questionText: 'Which 90s TV sitcom featured Jerry, George, Elaine, and Kramer living in New York City?',
      optionA: 'Seinfeld',
      optionB: 'Friends',
      optionC: 'Frasier',
      optionD: 'Cheers',
      correctOption: 'A',
    ),
  ];
}
