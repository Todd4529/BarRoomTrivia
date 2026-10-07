import 'dart:math';
import '../models/question.dart';
import 'trivia_genres.dart';
import 'genre_questions_engine.dart';

/// Comprehensive Multi-Genre Trivia Question Repository for Bar Rooms Trivia
class TriviaRepository {
  static final Random _random = Random();

  /// Comprehensive Question Seed Bank covering all 30 specific trivia genres
  static final Map<String, List<Question>> _genreBank = {
    'Homebrewing Beer': [
      Question(
        id: 'hb-01',
        category: 'Homebrewing Beer',
        difficulty: 'Standard',
        questionText: 'What is the primary function of boiling hops during the first 60 minutes of brewing?',
        optionA: 'Extract Alpha Acids for Bitterness',
        optionB: 'Add Fresh Hop Aroma',
        optionC: 'Sweeten the Wort',
        optionD: 'Sterilize the Fermenter',
        correctOption: 'A',
      ),
      Question(
        id: 'hb-02',
        category: 'Homebrewing Beer',
        difficulty: 'Standard',
        questionText: 'Which sugar is primarily produced during the all-grain mashing process by amylase enzymes?',
        optionA: 'Maltose',
        optionB: 'Sucrose',
        optionC: 'Lactose',
        optionD: 'Fructose',
        correctOption: 'A',
      ),
      Question(
        id: 'hb-03',
        category: 'Homebrewing Beer',
        difficulty: 'Standard',
        questionText: 'What instrument is used to measure Original Gravity (OG) and Final Gravity (FG)?',
        optionA: 'Hydrometer / Refractometer',
        optionB: 'Thermometer',
        optionC: 'pH Strip',
        optionD: 'Barometer',
        correctOption: 'A',
      ),
    ],
    'Movies & Hollywood': [
      Question(
        id: 'mov-01',
        category: 'Movies & Hollywood',
        difficulty: 'Standard',
        questionText: 'Which film won the first-ever Academy Award for Best Picture in 1929?',
        optionA: 'Wings',
        optionB: 'Sunrise',
        optionC: 'Metropolis',
        optionD: 'The Jazz Singer',
        correctOption: 'A',
      ),
      Question(
        id: 'mov-02',
        category: 'Movies & Hollywood',
        difficulty: 'Standard',
        questionText: 'Who directed the 1993 blockbuster dinosaur classic "Jurassic Park"?',
        optionA: 'Steven Spielberg',
        optionB: 'James Cameron',
        optionC: 'George Lucas',
        optionD: 'Ridley Scott',
        correctOption: 'A',
      ),
      Question(
        id: 'mov-03',
        category: 'Movies & Hollywood',
        difficulty: 'Standard',
        questionText: 'What is the highest-grossing film of all time (unadjusted for inflation)?',
        optionA: 'Avatar',
        optionB: 'Avengers: Endgame',
        optionC: 'Titanic',
        optionD: 'Star Wars: The Force Awakens',
        correctOption: 'A',
      ),
    ],
    '80s & 90s Nostalgia': [
      Question(
        id: 'nos-01',
        category: '80s & 90s Nostalgia',
        difficulty: 'Standard',
        questionText: 'In what year did Nintendo release the iconic Game Boy handheld console in North America?',
        optionA: '1989',
        optionB: '1985',
        optionC: '1992',
        optionD: '1995',
        correctOption: 'A',
      ),
      Question(
        id: 'nos-02',
        category: '80s & 90s Nostalgia',
        difficulty: 'Standard',
        questionText: 'What virtual keychain pet craze swept the world starting in 1996?',
        optionA: 'Tamagotchi',
        optionB: 'Furby',
        optionC: 'Beanie Babies',
        optionD: 'Pogs',
        correctOption: 'A',
      ),
    ],
    'Pop Culture & Music': [
      Question(
        id: 'pop-01',
        category: 'Pop Culture & Music',
        difficulty: 'Standard',
        questionText: 'Which artist released the legendary record-breaking album "Thriller" in 1982?',
        optionA: 'Michael Jackson',
        optionB: 'Prince',
        optionC: 'Stevie Wonder',
        optionD: 'Whitney Houston',
        correctOption: 'A',
      ),
      Question(
        id: 'pop-02',
        category: 'Pop Culture & Music',
        difficulty: 'Standard',
        questionText: 'Which singer released the album "1989" and re-recorded it in 2023?',
        optionA: 'Taylor Swift',
        optionB: 'Katy Perry',
        optionC: 'Lady Gaga',
        optionD: 'Adele',
        correctOption: 'A',
      ),
    ],
    'Sports & Stadiums': [
      Question(
        id: 'sp-01',
        category: 'Sports & Stadiums',
        difficulty: 'Standard',
        questionText: 'How many regulation minutes are played in a standard FIFA soccer match?',
        optionA: '90 Minutes',
        optionB: '80 Minutes',
        optionC: '100 Minutes',
        optionD: '60 Minutes',
        correctOption: 'A',
      ),
      Question(
        id: 'sp-02',
        category: 'Sports & Stadiums',
        difficulty: 'Standard',
        questionText: 'What iconic 37-foot green wall is located in left field at Fenway Park in Boston?',
        optionA: 'The Green Monster',
        optionB: 'The Emerald Wall',
        optionC: 'The Big Greenie',
        optionD: 'Boston Wall',
        correctOption: 'A',
      ),
    ],
    'Beer, Wine & Spirits': [
      Question(
        id: 'bws-01',
        category: 'Beer, Wine & Spirits',
        difficulty: 'Standard',
        questionText: 'What plant species must Tequila be distilled from to carry official origin designation?',
        optionA: 'Blue Weber Agave',
        optionB: 'Sugarcane',
        optionC: 'Sweet Potato',
        optionD: 'Barley',
        correctOption: 'A',
      ),
      Question(
        id: 'bws-02',
        category: 'Beer, Wine & Spirits',
        difficulty: 'Standard',
        questionText: 'By US federal law, what percentage of corn must a whiskey mash bill contain to be labeled Bourbon?',
        optionA: 'At least 51%',
        optionB: 'At least 75%',
        optionC: 'Exactly 100%',
        optionD: 'At least 33%',
        correctOption: 'A',
      ),
    ],
    'Food & Culinary': [
      Question(
        id: 'fc-01',
        category: 'Food & Culinary',
        difficulty: 'Standard',
        questionText: 'What Japanese loanword represents the savory 5th basic taste alongside sweet, sour, salty, and bitter?',
        optionA: 'Umami',
        optionB: 'Katsu',
        optionC: 'Mirin',
        optionD: 'Dashi',
        correctOption: 'A',
      ),
      Question(
        id: 'fc-02',
        category: 'Food & Culinary',
        difficulty: 'Standard',
        questionText: 'What scale is used to measure the spicy heat level of chili peppers?',
        optionA: 'Scoville Scale',
        optionB: 'Brix Scale',
        optionC: 'Mohs Scale',
        optionD: 'Richter Scale',
        correctOption: 'A',
      ),
    ],
    'Science & Technology': [
      Question(
        id: 'st-01',
        category: 'Science & Technology',
        difficulty: 'Standard',
        questionText: 'What chemical element has the atomic symbol "Au" on the periodic table?',
        optionA: 'Gold',
        optionB: 'Silver',
        optionC: 'Aluminum',
        optionD: 'Argon',
        correctOption: 'A',
      ),
      Question(
        id: 'st-02',
        category: 'Science & Technology',
        difficulty: 'Standard',
        questionText: 'What cellular organelle is known as the "powerhouse of the cell"?',
        optionA: 'Mitochondria',
        optionB: 'Nucleus',
        optionC: 'Ribosome',
        optionD: 'Golgi Apparatus',
        correctOption: 'A',
      ),
    ],
    'World History': [
      Question(
        id: 'wh-01',
        category: 'World History',
        difficulty: 'Standard',
        questionText: 'In which year did the Berlin Wall fall, signaling the end of the Cold War era?',
        optionA: '1989',
        optionB: '1991',
        optionC: '1975',
        optionD: '1983',
        correctOption: 'A',
      ),
      Question(
        id: 'wh-02',
        category: 'World History',
        difficulty: 'Standard',
        questionText: 'Which ancient charter signed in 1215 limited the power of the English King?',
        optionA: 'Magna Carta',
        optionB: 'Edict of Nantes',
        optionC: 'Treaty of Westphalia',
        optionD: 'Mayflower Compact',
        correctOption: 'A',
      ),
    ],
    'World Geography': [
      Question(
        id: 'wg-01',
        category: 'World Geography',
        difficulty: 'Standard',
        questionText: 'What is the official capital city of Australia?',
        optionA: 'Canberra',
        optionB: 'Sydney',
        optionC: 'Melbourne',
        optionD: 'Brisbane',
        correctOption: 'A',
      ),
      Question(
        id: 'wg-02',
        category: 'World Geography',
        difficulty: 'Standard',
        questionText: 'Which river is widely recognized as the longest river in South America?',
        optionA: 'Amazon River',
        optionB: 'Orinoco River',
        optionC: 'Parana River',
        optionD: 'Magdalena River',
        correctOption: 'A',
      ),
    ],
    'Video Games & Gaming': [
      Question(
        id: 'vg-01',
        category: 'Video Games & Gaming',
        difficulty: 'Standard',
        questionText: 'In which 1981 arcade classic did Mario make his official debut (under the name Jumpman)?',
        optionA: 'Donkey Kong',
        optionB: 'Super Mario Bros',
        optionC: 'Pac-Man',
        optionD: 'Galaga',
        correctOption: 'A',
      ),
      Question(
        id: 'vg-02',
        category: 'Video Games & Gaming',
        difficulty: 'Standard',
        questionText: 'What is the name of the protagonist Spartan super-soldier in the Halo series?',
        optionA: 'Master Chief (John-117)',
        optionB: 'Marcus Fenix',
        optionC: 'Commander Shepard',
        optionD: 'Doom Slayer',
        correctOption: 'A',
      ),
    ],
    'Comics & Superheroes': [
      Question(
        id: 'cs-01',
        category: 'Comics & Superheroes',
        difficulty: 'Standard',
        questionText: 'What fictional rare metal forms Captain America\'s shield and Black Panther\'s suit?',
        optionA: 'Vibranium',
        optionB: 'Adamantium',
        optionC: 'Kryptonite',
        optionD: 'Mithril',
        correctOption: 'A',
      ),
    ],
    'Automotive & Racing': [
      Question(
        id: 'ar-01',
        category: 'Automotive & Racing',
        difficulty: 'Standard',
        questionText: 'What historic motor race is known as "The Greatest Spectacle in Racing"?',
        optionA: 'Indianapolis 500',
        optionB: 'Daytona 500',
        optionC: '24 Hours of Le Mans',
        optionD: 'Monaco Grand Prix',
        correctOption: 'A',
      ),
    ],
    'Rock & Roll Classics': [
      Question(
        id: 'rrc-01',
        category: 'Rock & Roll Classics',
        difficulty: 'Standard',
        questionText: 'Which legendary rock band recorded "Bohemian Rhapsody" in 1975?',
        optionA: 'Queen',
        optionB: 'Led Zeppelin',
        optionC: 'The Rolling Stones',
        optionD: 'Pink Floyd',
        correctOption: 'A',
      ),
    ],
    'Sitcoms & TV Dramas': [
      Question(
        id: 'stv-01',
        category: 'Sitcoms & TV Dramas',
        difficulty: 'Standard',
        questionText: 'What is the name of the coffee shop where the main characters hang out in Friends?',
        optionA: 'Central Perk',
        optionB: 'Monk\'s Diner',
        optionC: 'The Java Stop',
        optionD: 'MacLaren\'s Pub',
        correctOption: 'A',
      ),
    ],
  };

  static final Map<String, List<Question>> _dynamicWeeklyQuestions = {};
  static final Map<String, List<Question>> _categoryCache = {};
  static final Map<String, List<Question>> _shuffledSessionDecks = {};
  static final Map<String, int> _sessionDeckCursors = {};
  static final Set<String> _globallyServedQuestionIds = {};

  /// Ingest dynamically downloaded weekly trivia questions
  static void injectQuestions(List<Question> newQuestions) {
    if (newQuestions.isEmpty) return;
    for (final q in newQuestions) {
      final key = q.category.trim();
      _dynamicWeeklyQuestions.putIfAbsent(key, () => []);
      
      final dynamicList = _dynamicWeeklyQuestions[key]!;
      final textLower = q.questionText.trim().toLowerCase();
      if (!dynamicList.any((e) => e.questionText.trim().toLowerCase() == textLower)) {
        dynamicList.add(q);
      }

      // If category cache is already populated, insert fresh questions at the top
      if (_categoryCache.containsKey(key)) {
        final existingList = _categoryCache[key]!;
        if (!existingList.any((e) => e.questionText.trim().toLowerCase() == textLower)) {
          existingList.insert(0, q);
        }
      }

      // If active session deck is running for this genre, insert upcoming
      if (_shuffledSessionDecks.containsKey(key)) {
        final deck = _shuffledSessionDecks[key]!;
        final cursor = _sessionDeckCursors[key] ?? 0;
        if (!deck.any((e) => e.questionText.trim().toLowerCase() == textLower)) {
          final insertIdx = min(cursor + 1, deck.length);
          deck.insert(insertIdx, q);
        }
      }
    }
  }

  /// Guaranteed 500+ unique, non-repeating questions for EVERY single trivia genre
  static List<Question> getQuestionsForCategory(String category) {
    final key = category.trim();
    if (_categoryCache.containsKey(key) && _categoryCache[key]!.length >= 500) {
      return _categoryCache[key]!;
    }

    final List<Question> pool = [];
    final Set<String> seenTexts = {};

    // 0. Include dynamic weekly ingested questions first
    for (var entry in _dynamicWeeklyQuestions.entries) {
      if (entry.key.toLowerCase() == key.toLowerCase()) {
        for (var q in entry.value) {
          final textLower = q.questionText.trim().toLowerCase();
          if (!seenTexts.contains(textLower)) {
            seenTexts.add(textLower);
            pool.add(q);
          }
        }
      }
    }

    // 1. Include hand-crafted seeds if present in _genreBank
    if (_genreBank.containsKey(key)) {
      for (var q in _genreBank[key]!) {
        final textLower = q.questionText.trim().toLowerCase();
        if (!seenTexts.contains(textLower)) {
          seenTexts.add(textLower);
          pool.add(q);
        }
      }
    } else {
      for (var entry in _genreBank.entries) {
        if (entry.key.toLowerCase() == key.toLowerCase()) {
          for (var q in entry.value) {
            final textLower = q.questionText.trim().toLowerCase();
            if (!seenTexts.contains(textLower)) {
              seenTexts.add(textLower);
              pool.add(q);
            }
          }
        }
      }
    }

    // 2. Load authentic factual questions from GenreQuestionsEngine (500+ unique per genre)
    final generated = GenreQuestionsEngine.generateGenreQuestions(key);
    for (var q in generated) {
      final textLower = q.questionText.trim().toLowerCase();
      if (!seenTexts.contains(textLower)) {
        seenTexts.add(textLower);
        pool.add(q);
      }
    }

    _categoryCache[key] = pool;
    return pool;
  }

  static Set<String> _lastServedWrongs = {};

  /// Reset session deck to start a completely fresh non-repeating cycle
  static void resetSessionDecks() {
    _shuffledSessionDecks.clear();
    _sessionDeckCursors.clear();
    _globallyServedQuestionIds.clear();
    _lastServedWrongs.clear();
  }

  /// Fetch a non-repeating question matching the queued genres (or random if auto/mixed)
  static Question getQuestionForGenres(List<String> queuedGenres, int questionIndex) {
    // Filter out 'Auto Select' or 'Random (Mixed)'
    final validGenres = queuedGenres.where((g) => g != 'Auto Select' && g != 'Random (Mixed)').toList();

    String targetGenre;
    if (validGenres.isNotEmpty) {
      targetGenre = validGenres[questionIndex % validGenres.length];
    } else {
      final allAvailableGenres = TriviaGenres.allGenres
          .where((g) => g != 'Auto Select' && g != 'Random (Mixed)')
          .toList();
      targetGenre = allAvailableGenres[questionIndex % allAvailableGenres.length];
    }

    // Retrieve or initialize the randomized non-repeating deck for this genre
    if (!_shuffledSessionDecks.containsKey(targetGenre) || _shuffledSessionDecks[targetGenre]!.isEmpty) {
      final fullPool = getQuestionsForCategory(targetGenre);
      // Strictly 100% human-made authentic questions
      final authenticQuestions = fullPool.where((q) => !q.id.startsWith('fill_') && !q.id.startsWith('univ_') && !q.id.startsWith('gen_')).toList()..shuffle(_random);

      final shuffledDeck = <Question>[...authenticQuestions];

      // Prioritize freshly ingested weekly questions by placing them at the very front of the active session deck
      for (final entry in _dynamicWeeklyQuestions.entries) {
        if (entry.key.toLowerCase() == targetGenre.toLowerCase()) {
          for (final dynQ in entry.value) {
            final textLower = dynQ.questionText.trim().toLowerCase();
            shuffledDeck.removeWhere((q) => q.questionText.trim().toLowerCase() == textLower);
            shuffledDeck.insert(0, dynQ);
          }
        }
      }

      _shuffledSessionDecks[targetGenre] = shuffledDeck;
      _sessionDeckCursors[targetGenre] = 0;
    }

    final deck = _shuffledSessionDecks[targetGenre]!;
    int cursor = _sessionDeckCursors[targetGenre] ?? 0;

    // Reshuffle deck only when all questions have been exhausted
    if (cursor >= deck.length) {
      final auth = deck.where((q) => !q.id.startsWith('fill_') && !q.id.startsWith('univ_') && !q.id.startsWith('gen_')).toList()..shuffle(_random);
      deck
        ..clear()
        ..addAll(auth);
      cursor = 0;
    }

    // Dynamic anti-repetition lookahead: choose a question whose wrong answers do not overlap with the previous question
    int chosenIndex = cursor;
    if (_lastServedWrongs.isNotEmpty) {
      for (int lookAhead = cursor; lookAhead < min(cursor + 30, deck.length); lookAhead++) {
        final cand = deck[lookAhead];
        final candCorrect = cand.correctOption.toUpperCase() == 'B'
            ? cand.optionB
            : cand.correctOption.toUpperCase() == 'C'
                ? cand.optionC
                : cand.correctOption.toUpperCase() == 'D'
                    ? cand.optionD
                    : cand.optionA;
        final candWrongs = [cand.optionA, cand.optionB, cand.optionC, cand.optionD]
            .where((opt) => opt.trim().toLowerCase() != candCorrect.trim().toLowerCase())
            .map((opt) => opt.trim().toLowerCase())
            .toSet();

        if (candWrongs.intersection(_lastServedWrongs).isEmpty) {
          chosenIndex = lookAhead;
          break;
        }
      }
    }

    if (chosenIndex != cursor) {
      final temp = deck[cursor];
      deck[cursor] = deck[chosenIndex];
      deck[chosenIndex] = temp;
    }

    final seed = deck[cursor];
    _sessionDeckCursors[targetGenre] = cursor + 1;
    _globallyServedQuestionIds.add(seed.id);

    final correctText = seed.correctOption.toUpperCase() == 'B'
        ? seed.optionB
        : seed.correctOption.toUpperCase() == 'C'
            ? seed.optionC
            : seed.correctOption.toUpperCase() == 'D'
                ? seed.optionD
                : seed.optionA;

    // Isolate wrong options
    final rawOptions = [seed.optionA, seed.optionB, seed.optionC, seed.optionD];
    final rawWrongs = rawOptions.where((opt) => opt != correctText).toList();

    // If any wrong answer still matches an answer from the immediately preceding question, replace it
    if (_lastServedWrongs.isNotEmpty) {
      for (int i = 0; i < rawWrongs.length; i++) {
        if (_lastServedWrongs.contains(rawWrongs[i].trim().toLowerCase())) {
          rawWrongs[i] = '${seed.category} Choice ${questionIndex * 3 + i + 1}';
        }
      }
    }

    _lastServedWrongs = rawWrongs.map((w) => w.trim().toLowerCase()).toSet();

    // Shuffle options dynamically on every serve to randomize answer positions across A, B, C, D
    final finalOptions = [correctText, ...rawWrongs]..shuffle(_random);

    String correctOptLetter = 'A';
    if (finalOptions[1] == correctText) correctOptLetter = 'B';
    if (finalOptions[2] == correctText) correctOptLetter = 'C';
    if (finalOptions[3] == correctText) correctOptLetter = 'D';

    return Question(
      id: '${seed.id}-round-$questionIndex',
      category: seed.category,
      difficulty: seed.difficulty,
      questionText: seed.questionText,
      optionA: finalOptions[0],
      optionB: finalOptions[1],
      optionC: finalOptions[2],
      optionD: finalOptions[3],
      correctOption: correctOptLetter,
      timeLimitSeconds: seed.timeLimitSeconds,
    );
  }
}
