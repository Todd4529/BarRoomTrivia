import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bar_rooms_trivia/shared/models/question.dart';
import 'package:bar_rooms_trivia/shared/services/supabase_service.dart';
import 'package:bar_rooms_trivia/shared/config/supabase_config.dart';
import 'package:bar_rooms_trivia/shared/data/trivia_repository.dart';
import 'package:bar_rooms_trivia/shared/data/trivia_genres.dart';
import 'package:bar_rooms_trivia/shared/data/genre_questions_engine.dart';
import 'package:bar_rooms_trivia/shared/services/game_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    try {
      await SupabaseConfig.initialize();
    } catch (_) {}
  });

  setUp(() {
    SupabaseService.clearLocalPlayers();
    TriviaRepository.resetSessionDecks();
  });

  group('Extensive Game Lifecycle & Multi-Round Scoring Tests', () {
    test('5-Round Continuous Marathon with 5 Real Players and Strict Scoring', () async {
      const room = 'MARATHON_99';
      final engine = GameEngineManager.instance;
      engine.currentRound = 1;
      engine.currentQuestionIndex = 0;
      engine.selectedGenres = [
        'Sports & Stadiums',
        'World History',
        'Rock & Roll Classics',
        'Science & Technology',
        'Movies & Hollywood'
      ];

      // 1. Register 5 real players
      final playerNames = ['Troy', 'Alice', 'Bob', 'Charlie', 'Dana'];
      for (final name in playerNames) {
        SupabaseService.registerIncomingPlayer(room, name, 0);
      }

      var players = await SupabaseService().getLeaderboard(room);
      expect(players.length, equals(5));
      for (final p in players) {
        expect(p.cumulativeScore, equals(0));
      }

      // Simulate 5 Full Rounds (50 questions total)
      final roundWinnersExpected = ['Troy', 'Alice', 'Bob', 'Charlie', 'Dana'];

      for (int round = 1; round <= 5; round++) {
        expect(engine.currentRound, equals(round));
        final activeGenre = engine.selectedGenres.first;
        expect(activeGenre.isNotEmpty, isTrue);

        for (int q = 1; q <= 10; q++) {
          engine.currentQuestionIndex++;
          final inRoundIdx = ((engine.currentQuestionIndex - 1) % 10) + 1;
          expect(inRoundIdx, equals(q), reason: 'In-round index must strictly match question counter 1..10');
          expect(inRoundIdx, inInclusiveRange(1, 10));

          // Calculate cumulative question index across the entire session
          final cumulativeQuestionNum = ((engine.currentRound - 1) * 10) + inRoundIdx;
          expect(cumulativeQuestionNum, equals(((round - 1) * 10) + q));

          // Fetch question from TriviaRepository to ensure no crash and valid options
          final servedQ = TriviaRepository.getQuestionForGenres(engine.selectedGenres, cumulativeQuestionNum);
          expect(servedQ.questionText.isNotEmpty, isTrue);
          expect(['A', 'B', 'C', 'D'].contains(servedQ.correctOption), isTrue);
          expect(servedQ.optionA.isNotEmpty, isTrue);
          expect(servedQ.optionB.isNotEmpty, isTrue);
          expect(servedQ.optionC.isNotEmpty, isTrue);
          expect(servedQ.optionD.isNotEmpty, isTrue);

          // Simulated answering:
          // The designated round winner gets questions right (+10 pts each question)
          final winnerName = roundWinnersExpected[round - 1];
          SupabaseService().updateLocalPlayerScore(roomCode: room, nickname: winnerName, pointsToAdd: 10 + (round * 5));

          // Other players answer occasionally
          for (final p in playerNames) {
            if (p != winnerName && q == 5) {
              SupabaseService().updateLocalPlayerScore(roomCode: room, nickname: p, pointsToAdd: 10);
            }
          }
        }

        // Award Round Winner Bonus (+20 points)
        final top3 = SupabaseService.awardRoundWinnerBonusAndGetTop3(room, 20);
        expect(top3.isNotEmpty, isTrue);
        final roundWinner = top3.first['nickname'];
        expect(roundWinner, equals(roundWinnersExpected[round - 1]),
            reason: 'Winner of round $round must be ${roundWinnersExpected[round - 1]}');

        // Advance to Next Round (if not final)
        if (round < 5) {
          engine.currentQuestionIndex = 0;
          engine.currentRound++;
          final rotatedGenre = engine.selectedGenres.removeAt(0);
          engine.selectedGenres.add(rotatedGenre);
        }
      }

      // Final Leaderboard Verification
      players = await SupabaseService().getLeaderboard(room);
      expect(players.length, equals(5));
      // All 5 players must have positive cumulative scores
      for (final p in players) {
        expect(p.cumulativeScore, greaterThan(0));
      }

      // Leaderboard must be strictly ordered descending
      for (int i = 0; i < players.length - 1; i++) {
        expect(players[i].cumulativeScore, greaterThanOrEqualTo(players[i + 1].cumulativeScore));
      }
    });

    test('Zero Fictitious or Bogus Players on Leaderboard or Round Podium', () async {
      const room = 'SECURITY_ROOM_01';

      // Attempt to register all known legacy mock names and prefixes
      final bannedNames = [
        'todd4529',
        'host',
        'host-tv',
        'TriviaMaster99',
        'BeerGuru',
        'BeerWhisperer',
        'Player 1',
        'Player 2',
        'Champion',
        'Runner Up',
        'Third Place',
        'SimulatedPlayer_1'
      ];

      for (final bogus in bannedNames) {
        SupabaseService.registerIncomingPlayer(room, bogus, 0);
      }

      // Also register one legitimate player
      SupabaseService.registerIncomingPlayer(room, 'Troy', 0);

      final leaderboard = await SupabaseService().getLeaderboard(room);
      // Only 'Troy' should exist; all bogus/fictitious names must be rejected
      expect(leaderboard.length, equals(1));
      expect(leaderboard.first.nickname, equals('Troy'));

      // Round podium awards must never include banned names
      final top3 = SupabaseService.awardRoundWinnerBonusAndGetTop3(room, 20);
      expect(top3.length, equals(1));
      expect(top3.first['nickname'], equals('Troy'));
    });

    test('Distractor Sanitization Across All 30 Standard Genres', () {
      // For every standard genre, generate 10 consecutive questions
      // and verify that no two consecutive questions have the exact same 3 distractors
      for (final genre in TriviaGenres.allGenres) {
        if (genre == 'Auto Select' || genre == 'Random (Mixed)') continue;

        final questions = GenreQuestionsEngine.generateGenreQuestions(genre);
        expect(questions.length, greaterThanOrEqualTo(500),
            reason: 'Genre $genre must contain at least 500 questions');

        Set<String>? prevWrongs;
        for (int i = 0; i < min(30, questions.length); i++) {
          final q = questions[i];
          final currentWrongs = q.wrongOptions.map((o) => o.trim().toLowerCase()).toSet();
          expect(currentWrongs.length, equals(3),
              reason: 'Question $i in $genre must have 3 distinct wrong options');

          if (prevWrongs != null) {
            final identicalCount = currentWrongs.intersection(prevWrongs).length;
            expect(identicalCount, lessThan(3),
                reason: 'Question $i in $genre duplicated all 3 wrong answers from previous question!');
          }
          prevWrongs = currentWrongs;
        }
      }
    });

    test('TriviaRepository Option Shuffling Distributes Correct Answers Uniformly', () {
      final queued = ['Sports & Stadiums'];
      final optionCounts = {'A': 0, 'B': 0, 'C': 0, 'D': 0};

      // Serve 100 questions and tally correct option letters
      for (int i = 1; i <= 100; i++) {
        final q = TriviaRepository.getQuestionForGenres(queued, i);
        final opt = q.correctOption;
        optionCounts[opt] = (optionCounts[opt] ?? 0) + 1;
      }

      // Verify that all 4 positions (A, B, C, D) are used and no single position dominates 100%
      expect(optionCounts['A']!, greaterThan(10));
      expect(optionCounts['B']!, greaterThan(10));
      expect(optionCounts['C']!, greaterThan(10));
      expect(optionCounts['D']!, greaterThan(10));
    });

    test('Dynamic Weekly Question Ingestion Is Served In Active Rounds', () {
      const customGenre = 'Pop Culture & Music';
      final dynamicQ = Question(
        id: 'weekly-test-999',
        category: customGenre,
        difficulty: 'Standard',
        questionText: 'Which blockbuster animated film featured the song "Peaches" in 2023?',
        optionA: 'The Super Mario Bros. Movie',
        optionB: 'Spider-Man: Across the Spider-Verse',
        optionC: 'Wish',
        optionD: 'Elemental',
        correctOption: 'A',
      );

      TriviaRepository.injectQuestions([dynamicQ]);

      final pool = TriviaRepository.getQuestionsForCategory(customGenre);
      expect(pool.any((q) => q.questionText.contains('"Peaches"')), isTrue);

      // Verify that when serving a round question for this genre, the dynamic question is reachable
      bool foundInDeck = false;
      for (int i = 1; i <= 50; i++) {
        final q = TriviaRepository.getQuestionForGenres([customGenre], i);
        if (q.questionText.contains('"Peaches"')) {
          foundInDeck = true;
          break;
        }
      }
      expect(foundInDeck, isTrue);
    });
  });
}
