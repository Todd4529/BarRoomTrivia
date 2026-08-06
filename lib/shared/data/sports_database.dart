import '../models/question.dart';

/// Specialized Question Generator and Data Bank for Sports & Stadiums
class SportsDatabase {
  static List<Question> generateQuestions() {
    final questions = <Question>[];
    questions.addAll(_curatedSportsQuestions);
    questions.addAll(_generateStadiumQuestions());
    questions.addAll(_generateSuperBowlQuestions());
    return questions;
  }

  static final List<Question> _curatedSportsQuestions = [
    Question(
      id: 'sp-01',
      category: 'Sports & Stadiums',
      difficulty: 'Standard',
      questionText: 'How many total players are on the field during a standard soccer match?',
      optionA: '22 Players (11 per team)',
      optionB: '20 Players',
      optionC: '18 Players',
      optionD: '24 Players',
      correctOption: 'A',
    ),
    Question(
      id: 'sp-02',
      category: 'Sports & Stadiums',
      difficulty: 'Standard',
      questionText: 'Which MLB stadium features the iconic 37-foot green wall known as the "Green Monster"?',
      optionA: 'Fenway Park (Boston Red Sox)',
      optionB: 'Wrigley Field (Chicago Cubs)',
      optionC: 'Yankee Stadium (New York Yankees)',
      optionD: 'Dodger Stadium (LA Dodgers)',
      correctOption: 'A',
    ),
    Question(
      id: 'sp-03',
      category: 'Sports & Stadiums',
      difficulty: 'Standard',
      questionText: 'In basketball, how far is the regulation NBA three-point line from the center of the basket at the arc?',
      optionA: '23 feet 9 inches',
      optionB: '22 feet 0 inches',
      optionC: '25 feet 0 inches',
      optionD: '21 feet 6 inches',
      correctOption: 'A',
    ),
    Question(
      id: 'sp-04',
      category: 'Sports & Stadiums',
      difficulty: 'Standard',
      questionText: 'What golfer holds the record for the most total Career Major Championships (18)?',
      optionA: 'Jack Nicklaus',
      optionB: 'Tiger Woods',
      optionC: 'Arnold Palmer',
      optionD: 'Phil Mickelson',
      correctOption: 'A',
    ),
    Question(
      id: 'sp-05',
      category: 'Sports & Stadiums',
      difficulty: 'Standard',
      questionText: 'Which country has won the most FIFA World Cup titles in men’s soccer history (5 titles)?',
      optionA: 'Brazil',
      optionB: 'Germany',
      optionC: 'Italy',
      optionD: 'Argentina',
      correctOption: 'A',
    ),
    Question(
      id: 'sp-06',
      category: 'Sports & Stadiums',
      difficulty: 'Standard',
      questionText: 'In American Football, how many points is a touchdown worth before any extra point attempt?',
      optionA: '6 Points',
      optionB: '3 Points',
      optionC: '7 Points',
      optionD: '4 Points',
      correctOption: 'A',
    ),
    Question(
      id: 'sp-07',
      category: 'Sports & Stadiums',
      difficulty: 'Standard',
      questionText: 'Which NHL team has won the most Stanley Cup championships in hockey history?',
      optionA: 'Montreal Canadiens',
      optionB: 'Toronto Maple Leafs',
      optionC: 'Detroit Red Wings',
      optionD: 'Boston Bruins',
      correctOption: 'A',
    ),
    Question(
      id: 'sp-08',
      category: 'Sports & Stadiums',
      difficulty: 'Standard',
      questionText: 'In tennis, what term describes a score of 40-40 in a game?',
      optionA: 'Deuce',
      optionB: 'Love-All',
      optionC: 'Advantage Out',
      optionD: 'Break Point',
      correctOption: 'A',
    ),
  ];

  static List<Question> _generateStadiumQuestions() {
    final stadiumData = [
      {'stadium': 'Lambeau Field', 'team': 'Green Bay Packers', 'city': 'Green Bay, WI'},
      {'stadium': 'Arrowhead Stadium', 'team': 'Kansas City Chiefs', 'city': 'Kansas City, MO'},
      {'stadium': 'Wrigley Field', 'team': 'Chicago Cubs', 'city': 'Chicago, IL'},
      {'stadium': 'Camp Nou', 'team': 'FC Barcelona', 'city': 'Barcelona, Spain'},
      {'stadium': 'Wembley Stadium', 'team': 'England National Football Team', 'city': 'London, UK'},
      {'stadium': 'Madison Square Garden', 'team': 'New York Knicks', 'city': 'New York City, NY'},
      {'stadium': 'Santiago Bernabéu', 'team': 'Real Madrid', 'city': 'Madrid, Spain'},
    ];

    final list = <Question>[];
    for (int i = 0; i < stadiumData.length; i++) {
      final data = stadiumData[i];
      list.add(
        Question(
          id: 'stadium-gen-$i',
          category: 'Sports & Stadiums',
          difficulty: 'Standard',
          questionText: 'Which famous sports team calls ${data['stadium']} in ${data['city']} their home stadium?',
          optionA: data['team']!,
          optionB: 'Real Madrid',
          optionC: 'Los Angeles Lakers',
          optionD: 'New England Patriots',
          correctOption: 'A',
        ),
      );
    }
    return list;
  }

  static List<Question> _generateSuperBowlQuestions() {
    final sbData = [
      {'year': '1985', 'champ': 'Chicago Bears', 'runner': 'New England Patriots'},
      {'year': '2007', 'champ': 'New York Giants', 'runner': 'New England Patriots'},
      {'year': '2020', 'champ': 'Kansas City Chiefs', 'runner': 'San Francisco 49ers'},
      {'year': '1972', 'champ': 'Miami Dolphins (Perfect 17-0)', 'runner': 'Washington Redskins'},
    ];

    final list = <Question>[];
    for (int i = 0; i < sbData.length; i++) {
      final item = sbData[i];
      list.add(
        Question(
          id: 'sb-gen-$i',
          category: 'Sports & Stadiums',
          difficulty: 'Standard',
          questionText: 'Which NFL franchise won the Super Bowl in ${item['year']}?',
          optionA: item['champ']!,
          optionB: item['runner']!,
          optionC: 'Dallas Cowboys',
          optionD: 'Pittsburgh Steelers',
          correctOption: 'A',
        ),
      );
    }
    return list;
  }
}
