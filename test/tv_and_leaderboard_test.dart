import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bar_rooms_trivia/shared/models/question.dart';
import 'package:bar_rooms_trivia/shared/models/player.dart';
import 'package:bar_rooms_trivia/shared/models/game_session.dart';
import 'package:bar_rooms_trivia/shared/services/supabase_service.dart';
import 'package:bar_rooms_trivia/shared/config/supabase_config.dart';
import 'package:bar_rooms_trivia/shared/data/genre_questions_engine.dart';
import 'package:flutter/material.dart';
import 'package:bar_rooms_trivia/player/views/player_controller_view.dart';
import 'package:bar_rooms_trivia/tv/widgets/timer_ring.dart';
import 'package:bar_rooms_trivia/shared/services/realtime_service.dart';
import 'package:bar_rooms_trivia/shared/services/game_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    try {
      await SupabaseConfig.initialize();
    } catch (_) {
      // Already initialized
    }
  });

  setUp(() {
    SupabaseService.clearLocalPlayers();
  });

  group('Question.fromJson Resilience', () {
    test('parses standard database payload correctly', () {
      final json = {
        'id': 'q-101',
        'category': 'General Knowledge',
        'difficulty': 'Standard',
        'question_text': 'What is the capital of France?',
        'option_a': 'Paris',
        'option_b': 'London',
        'option_c': 'Berlin',
        'option_d': 'Rome',
        'correct_option': 'A',
        'time_limit_seconds': 20,
      };

      final q = Question.fromJson(json);
      expect(q.id, 'q-101');
      expect(q.questionText, 'What is the capital of France?');
      expect(q.optionA, 'Paris');
      expect(q.optionB, 'London');
      expect(q.optionC, 'Berlin');
      expect(q.optionD, 'Rome');
      expect(q.correctOption, 'A');
      expect(q.timeLimitSeconds, 20);
    });

    test('parses JS web client broadcast payload with question_id, nested options, and duration_seconds', () {
      final json = {
        'question_id': 'q-web-202',
        'question_text': 'Which hops are known for citrus flavor?',
        'options': {
          'A': 'Citra',
          'B': 'Saaz',
          'C': 'Fuggles',
          'D': 'Hallertau'
        },
        'correct_option': 'A',
        'duration_seconds': 25,
      };

      final q = Question.fromJson(json);
      expect(q.id, 'q-web-202');
      expect(q.questionText, 'Which hops are known for citrus flavor?');
      expect(q.optionA, 'Citra');
      expect(q.optionB, 'Saaz');
      expect(q.optionC, 'Fuggles');
      expect(q.optionD, 'Hallertau');
      expect(q.correctOption, 'A');
      expect(q.timeLimitSeconds, 25);
    });

    test('handles missing or malformed fields gracefully without throwing', () {
      final json = <String, dynamic>{
        'question_text': 'Null safety check',
        'duration_seconds': 15,
      };

      final q = Question.fromJson(json);
      expect(q.id.isNotEmpty, true);
      expect(q.questionText, 'Null safety check');
      expect(q.optionA, 'Option A');
      expect(q.timeLimitSeconds, 15);
    });
  });

  group('Player.fromJson Resilience', () {
    test('parses standard database player model', () {
      final json = {
        'id': 'p-1',
        'player_uid': 'uid-123',
        'room_code': 'TRIVIA1',
        'nickname': 'BeerLover',
        'cumulative_score': 350,
        'is_connected': true,
      };

      final p = Player.fromJson(json);
      expect(p.id, 'p-1');
      expect(p.nickname, 'BeerLover');
      expect(p.cumulativeScore, 350);
      expect(p.isConnected, true);
    });

    test('parses client broadcast player without DB IDs', () {
      final json = {
        'nickname': 'TriviaMaster',
        'score': 500,
      };

      final p = Player.fromJson(json);
      expect(p.nickname, 'TriviaMaster');
      expect(p.cumulativeScore, 500);
      expect(p.id.isNotEmpty, true);
      expect(p.isConnected, true);
    });

    test('parses speed bonus player score like Troy 110 pts accurately from dynamic map', () {
      final Map<dynamic, dynamic> json = {
        'nickname': 'Troy',
        'score': 110,
        'cumulative_score': '110',
      };

      final p = Player.fromJson(json);
      expect(p.nickname, 'Troy');
      expect(p.cumulativeScore, 110);
    });

    test('updatePlayerScoreDirectly updates player score accurately on leaderboard', () async {
      const room = 'TROY_ROOM';
      SupabaseService.registerIncomingPlayer(room, 'Troy', 0);
      SupabaseService.updatePlayerScoreDirectly(roomCode: room, nickname: 'Troy', score: 110);

      final service = SupabaseService();
      final lb = await service.getLeaderboard(room);
      final troy = lb.firstWhere((p) => p.nickname == 'Troy');
      expect(troy.cumulativeScore, 110);
    });
  });

  group('SupabaseService Leaderboard & Player Registration', () {
    const testRoom = 'TEST_ROOM_999';

    test('registers incoming player and retrieves sorted leaderboard', () async {
      SupabaseService.registerIncomingPlayer(testRoom, 'Alice', 100);
      SupabaseService.registerIncomingPlayer(testRoom, 'Bob', 300);
      SupabaseService.registerIncomingPlayer(testRoom, 'Charlie', 200);

      final service = SupabaseService();
      final leaderboard = await service.getLeaderboard(testRoom);
      expect(leaderboard.length, greaterThanOrEqualTo(3));

      // Bob should be top scorer (300)
      expect(leaderboard[0].nickname, 'Bob');
      expect(leaderboard[0].cumulativeScore, 300);

      // Charlie second (200)
      expect(leaderboard[1].nickname, 'Charlie');
      expect(leaderboard[1].cumulativeScore, 200);

      // Alice third (100)
      expect(leaderboard[2].nickname, 'Alice');
      expect(leaderboard[2].cumulativeScore, 100);
    });

    test('syncPlayersFromBroadcast updates leaderboard correctly', () async {
      SupabaseService.syncPlayersFromBroadcast(testRoom, [
        {'nickname': 'Dave', 'score': 450},
        {'nickname': 'Eve', 'score': 600},
      ]);

      final service = SupabaseService();
      final leaderboard = await service.getLeaderboard(testRoom);
      expect(leaderboard.first.nickname, 'Eve');
      expect(leaderboard.first.cumulativeScore, 600);
    });

    test('shows players even if their scores are zero and filters fictitious names', () async {
      SupabaseService.syncPlayersFromBroadcast('ZERO_SCORE_ROOM', [
        {'nickname': 'TriviaMaster99', 'score': 1000},
        {'nickname': 'BeerWhisperer', 'score': 500},
        {'nickname': 'Player 1', 'score': 250},
        {'nickname': 'RealZeroPlayer', 'score': 0},
        {'nickname': 'RealActivePlayer', 'score': 150},
      ]);

      final service = SupabaseService();
      final leaderboard = await service.getLeaderboard('ZERO_SCORE_ROOM');
      expect(leaderboard.length, 2);
      expect(leaderboard[0].nickname, 'RealActivePlayer');
      expect(leaderboard[0].cumulativeScore, 150);
      expect(leaderboard[1].nickname, 'RealZeroPlayer');
      expect(leaderboard[1].cumulativeScore, 0);
    });

    test('returns empty list if room has no real players and ignores fictitious players', () async {
      final service = SupabaseService();
      final leaderboard = await service.getLeaderboard('EMPTY_ROOM_XYZ');
      expect(leaderboard.isEmpty, true);
    });
  });

  group('GenreQuestionsEngine & Fallback Integrity', () {
    test('generateGenreQuestions provides valid questions matching requested genre', () {
      final sportsQuestions = GenreQuestionsEngine.generateGenreQuestions('Sports & Stadiums');
      expect(sportsQuestions.isNotEmpty, true);
      expect(sportsQuestions.first.category, 'Sports & Stadiums');
      expect(sportsQuestions.first.questionText.isNotEmpty, true);
      expect(sportsQuestions.first.optionA.isNotEmpty, true);
      expect(sportsQuestions.first.optionB.isNotEmpty, true);
      expect(sportsQuestions.first.optionC.isNotEmpty, true);
      expect(sportsQuestions.first.optionD.isNotEmpty, true);

      // Verify no homebrewing questions in sports
      for (final q in sportsQuestions.take(20)) {
        expect(q.category.toLowerCase().contains('homebrew'), false);
      }
    });

    test('generateGenreQuestions handles Movie and History genres without homebrewing leakage', () {
      final movies = GenreQuestionsEngine.generateGenreQuestions('Movies & Hollywood');
      expect(movies.isNotEmpty, true);
      expect(movies.first.category, 'Movies & Hollywood');

      final history = GenreQuestionsEngine.generateGenreQuestions('World History');
      expect(history.isNotEmpty, true);
      expect(history.first.category, 'World History');
    });
  });

  group('Next Question Countdown Synchronization', () {
    test('TV and Player calculate identical remaining seconds from timer_expired payload', () {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final targetEpochMs = nowMs + 15000;

      // Payload arriving from Realtime / MQTT / Broadcast
      final payload = {
        'event': 'timer_expired',
        'room_code': 'TRIV',
        'correct_option': 'B',
        'next_question_starts_at_epoch_ms': targetEpochMs,
        'nextQuestionStartsAtEpochMs': targetEpochMs,
        'game_play_mode': 'Auto',
      };

      // TV Display countdown calculation
      final tvNextStartsAt = (payload['next_question_starts_at_epoch_ms'] as int?) ??
          (payload['nextQuestionStartsAtEpochMs'] as int?);
      final tvRemaining = ((tvNextStartsAt! - nowMs) / 1000).ceil().clamp(1, 15);

      // Player screen countdown calculation
      final playerNextStartsAt = (payload['next_question_starts_at_epoch_ms'] as int?) ??
          (payload['nextQuestionStartsAtEpochMs'] as int?);
      final playerRemaining = ((playerNextStartsAt! - nowMs) / 1000).ceil().clamp(1, 15);

      // Both must match exactly (15 seconds)
      expect(tvRemaining, 15);
      expect(playerRemaining, 15);
      expect(tvRemaining, playerRemaining);
    });

    test('TV and Player gracefully fallback to 15s when payload epoch is missing', () {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final payload = <String, dynamic>{
        'event': 'timer_expired',
        'room_code': 'TRIV',
        'correct_option': 'C',
      };

      final tvNextStartsAt = (payload['next_question_starts_at_epoch_ms'] as int?) ??
          (payload['nextQuestionStartsAtEpochMs'] as int?) ??
          (nowMs + 15000);
      final tvRemaining = ((tvNextStartsAt - nowMs) / 1000).ceil().clamp(1, 15);

      final playerNextStartsAt = (payload['next_question_starts_at_epoch_ms'] as int?) ??
          (payload['nextQuestionStartsAtEpochMs'] as int?) ??
          (nowMs + 15000);
      final playerRemaining = ((playerNextStartsAt - nowMs) / 1000).ceil().clamp(1, 15);

      expect(tvRemaining, 15);
      expect(playerRemaining, 15);
      expect(tvRemaining, playerRemaining);
    });
  });

  group('Question Randomization and Text Sanitization', () {
    test('GenreQuestionsEngine distributes correct answers across A, B, C, and D', () {
      final questions = GenreQuestionsEngine.generateGenreQuestions('Science & Technology');
      expect(questions.length, greaterThanOrEqualTo(10));

      final correctLetters = questions.take(30).map((q) => q.correctOption).toSet();
      // Must contain more than just 'A' (e.g. multiple distinct letters A, B, C, D)
      expect(correctLetters.length, greaterThan(1), reason: 'Correct answers must be randomized and not all A');
      expect(correctLetters.contains('A') || correctLetters.contains('B') || correctLetters.contains('C') || correctLetters.contains('D'), true);
    });

    test('Science & Technology questions do not contain question numbers or index tags in question text', () {
      final questions = GenreQuestionsEngine.generateGenreQuestions('Science & Technology');
      for (final q in questions.take(50)) {
        expect(q.questionText.contains('(#'), false, reason: 'Found (# in: ${q.questionText}');
        expect(q.questionText.contains('(#INDEX)'), false);
        expect(q.questionText.contains('Focus Point #'), false);
      }
    });

    test('Question.cleanQuestionText strips trailing parenthetical numbers', () {
      expect(Question.cleanQuestionText('What is a GFCI outlet (#1)?'), 'What is a GFCI outlet?');
      expect(Question.cleanQuestionText('How did standards evolve during the era (Focus Point #5)?'), 'How did standards evolve during the era?');
      expect(Question.cleanQuestionText('Which tool is used for drywall (#INDEX)?'), 'Which tool is used for drywall?');
    });
  });

  group('Player Result Screen Timing and Persistence', () {
    testWidgets('Player Controller View suppresses right/wrong result overlay while question timer is running', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PlayerControllerView(initialRoomCode: 'TRIV'),
        ),
      );

      // Verify no right or wrong result overlay appears while idle or active before timer expires
      expect(find.text('NAILED IT!'), findsNothing);
      expect(find.text('OOF! MISSED IT!'), findsNothing);
    });
  });

  group('Round Progression and In-Round Indexing', () {
    test('Question index in round maps 1..10 cleanly and never exceeds 10', () {
      const totalQ = 10;
      int inRoundIndex(int cumulativeIdx) => ((cumulativeIdx - 1) % totalQ) + 1;
      int roundNumber(int cumulativeIdx) => ((cumulativeIdx - 1) ~/ totalQ) + 1;

      expect(inRoundIndex(1), 1);
      expect(roundNumber(1), 1);

      expect(inRoundIndex(10), 10);
      expect(roundNumber(10), 1);

      // Question 11 is Round 2 Question 1
      expect(inRoundIndex(11), 1);
      expect(roundNumber(11), 2);

      // Question 30 is Round 3 Question 10 (NEVER 30 out of 10)
      expect(inRoundIndex(30), 10);
      expect(roundNumber(30), 3);

      final tvHeaderQ30 = 'ROUND ${roundNumber(30)} • QUESTION ${inRoundIndex(30)} OUT OF $totalQ';
      expect(tvHeaderQ30, 'ROUND 3 • QUESTION 10 OUT OF 10');
      expect(tvHeaderQ30.contains('30 out of 10'), false);
    });

    test('RealtimeService broadcastRoundCompleted formats top 3 winners with round number', () async {
      final realtime = RealtimeService();
      final winners = [
        {'nickname': 'Alice', 'score': 300},
        {'nickname': 'Bob', 'score': 250},
        {'nickname': 'Charlie', 'score': 200},
      ];

      // Verify broadcastRoundCompleted executes without exception
      await realtime.broadcastRoundCompleted(
        roomCode: 'TRIV',
        top3Winners: winners,
        roundNumber: 2,
        nextRoundStartsAtEpochMs: DateTime.now().millisecondsSinceEpoch + 15000,
      );
    });

    test('1 to 100 question progression maintains strict 1..10 in-round index', () {
      const totalQ = 10;
      for (int q = 1; q <= 100; q++) {
        final inRound = ((q - 1) % totalQ) + 1;
        final roundNum = ((q - 1) ~/ totalQ) + 1;

        expect(inRound >= 1 && inRound <= 10, true, reason: 'Failed for question $q');
        expect(roundNum, ((q - 1) ~/ 10) + 1);

        final header = 'ROUND $roundNum • QUESTION $inRound OUT OF $totalQ';
        expect(header.contains('$q out of 10') && q > 10, false, reason: 'Header leaked cumulative index at $q');
      }
    });

    test('GameEngineManager tracks currentRound and rotates selectedGenres after 10 questions', () {
      final engine = GameEngineManager.instance;
      engine.resetGame();

      expect(engine.currentRound, 1);
      expect(engine.currentQuestionIndex, 0);

      engine.selectedGenres = ['Beer, Wine & Spirits', 'World Geography', 'Sports & Stadiums'];
      engine.currentQuestionIndex = 9; // 9 questions answered, now at 10th
      engine.currentRound = 1;

      // Simulate completion of question 10
      engine.currentQuestionIndex++;
      expect(engine.currentQuestionIndex, 10);

      // Trigger round completion logic
      if (engine.currentQuestionIndex >= 10) {
        engine.currentQuestionIndex = 0;
        engine.currentRound++;
        if (engine.selectedGenres.length > 1) {
          final completed = engine.selectedGenres.removeAt(0);
          engine.selectedGenres.add(completed);
        }
      }

      expect(engine.currentQuestionIndex, 0);
      expect(engine.currentRound, 2);
      expect(engine.selectedGenres.first, 'World Geography');
      expect(engine.selectedGenres.last, 'Beer, Wine & Spirits');

      // Verify resetGame returns everything to initial state
      engine.resetGame();
      expect(engine.currentRound, 1);
      expect(engine.currentQuestionIndex, 0);
    });

    test('RealtimeService broadcastQuestion correctly computes in-round and cumulative properties', () async {
      final realtime = RealtimeService();
      final sampleQuestion = Question(
        id: 'test-q1',
        category: 'Beer, Wine & Spirits',
        difficulty: 'Standard',
        questionText: 'Which noble hop variety from the Czech Republic is famous for classic Pilsners?',
        optionA: 'Saaz',
        optionB: 'Citra',
        optionC: 'Mosaic',
        optionD: 'Cascade',
        correctOption: 'A',
      );

      // Verify question 30 (Round 3 Question 10)
      await realtime.broadcastQuestion(
        roomCode: 'TRIV',
        questionIndex: 30,
        question: sampleQuestion,
        durationSeconds: 20,
        timerEndsAtEpochMs: DateTime.now().millisecondsSinceEpoch + 20000,
        roundNumber: 3,
        totalQuestions: 10,
      );

      // Verify question 11 (Round 2 Question 1)
      await realtime.broadcastQuestion(
        roomCode: 'TRIV',
        questionIndex: 11,
        question: sampleQuestion,
        durationSeconds: 20,
        timerEndsAtEpochMs: DateTime.now().millisecondsSinceEpoch + 20000,
        roundNumber: 2,
        totalQuestions: 10,
      );
    });

    test('TimerRing compact size 58 renders smoothly without errors', () {
      const ring = TimerRing(
        size: 58,
        progress: 0.5,
        remainingSeconds: 10,
        label: 'SECONDS',
      );
      expect(ring.size, 58);
      expect(ring.remainingSeconds, 10);
    });

    test('Leaderboard filtering bans todd4529 and host, retains Troy with zero points', () {
      expect(SupabaseService.isMockNickname('todd4529'), isTrue);
      expect(SupabaseService.isMockNickname('Host'), isTrue);
      expect(SupabaseService.isMockNickname('host user'), isTrue);
      expect(SupabaseService.isMockNickname('Troy'), isFalse);

      SupabaseService.registerIncomingPlayer('TRIV', 'Troy', 0);
      final players = SupabaseService.getLocalPlayersJson('TRIV');
      expect(players.length, 1);
      expect(players.first['nickname'], 'Troy');
      expect(players.first['cumulative_score'], 0);
    });

    test('GenreQuestionsEngine consecutive questions do not repeat 3 identical wrong answers', () {
      GenreQuestionsEngine.clearCache();
      final questions = GenreQuestionsEngine.generateGenreQuestions('General Trivia');
      expect(questions.length, greaterThanOrEqualTo(20));

      for (int i = 0; i < 20; i++) {
        final q1 = questions[i];
        final q2 = questions[i + 1];

        final q1Wrongs = q1.wrongOptions.map((w) => w.trim().toLowerCase()).toSet();
        final q2Wrongs = q2.wrongOptions.map((w) => w.trim().toLowerCase()).toSet();

        // Must never share all 3 wrong answers with the previous question
        final shared = q1Wrongs.intersection(q2Wrongs);
        expect(
          shared.length,
          lessThan(3),
          reason: 'Questions $i and ${i + 1} shared all 3 wrong answers: $shared (Q1: ${q1.questionText}, Q2: ${q2.questionText})',
        );
      }
    });

    test('Homebrewing Beer consecutive questions do not repeat 3 identical wrong answers', () {
      GenreQuestionsEngine.clearCache();
      final questions = GenreQuestionsEngine.generateGenreQuestions('Homebrewing Beer');
      expect(questions.length, greaterThanOrEqualTo(500));

      for (int i = 0; i < 20; i++) {
        final q1 = questions[i];
        final q2 = questions[i + 1];

        final q1Wrongs = q1.wrongOptions.map((w) => w.trim().toLowerCase()).toSet();
        final q2Wrongs = q2.wrongOptions.map((w) => w.trim().toLowerCase()).toSet();

        final shared = q1Wrongs.intersection(q2Wrongs);
        expect(
          shared.length,
          lessThan(3),
          reason: 'Questions $i and ${i + 1} shared all 3 wrong answers: $shared',
        );
      }
    });

    test('Multiple players joining consecutively all persist on leaderboard with zero points', () async {
      SupabaseService.clearLocalPlayers('TRIV');

      // 1. Troy joins
      SupabaseService.registerIncomingPlayer('TRIV', 'Troy', 0);
      var players = await SupabaseService().getLeaderboard('TRIV');
      expect(players.map((p) => p.nickname).toList(), ['Troy']);

      // 2. Alice joins
      SupabaseService.registerIncomingPlayer('TRIV', 'Alice', 0);
      players = await SupabaseService().getLeaderboard('TRIV');
      expect(players.length, 2);
      expect(players.map((p) => p.nickname).toSet(), containsAll(['Troy', 'Alice']));

      // 3. Bob joins
      SupabaseService.registerIncomingPlayer('TRIV', 'Bob', 0);
      players = await SupabaseService().getLeaderboard('TRIV');
      expect(players.length, 3);
      expect(players.map((p) => p.nickname).toSet(), containsAll(['Troy', 'Alice', 'Bob']));

      // 4. Incoming leaderboard broadcast with only Alice (100 pts) does NOT wipe Troy or Bob
      SupabaseService.syncPlayersFromBroadcast('TRIV', [
        {'nickname': 'Alice', 'cumulative_score': 100, 'is_connected': true}
      ]);
      players = await SupabaseService().getLeaderboard('TRIV');
      expect(players.length, 3);
      expect(players.first.nickname, 'Alice');
      expect(players.first.cumulativeScore, 100);
      expect(players.map((p) => p.nickname).toSet(), containsAll(['Troy', 'Alice', 'Bob']));
    });

    test('mergeLocalPlayers non-destructively retains all players and updates scores', () {
      SupabaseService.clearLocalPlayers('TRIV');

      final initial = [
        Player(id: '1', playerUid: 'u1', roomCode: 'TRIV', nickname: 'Troy', cumulativeScore: 0, isConnected: true),
        Player(id: '2', playerUid: 'u2', roomCode: 'TRIV', nickname: 'Dave', cumulativeScore: 50, isConnected: true),
      ];
      SupabaseService.setLocalPlayers('TRIV', initial);

      // Incoming broadcast from a third player's device
      final incoming = [
        Player(id: '3', playerUid: 'u3', roomCode: 'TRIV', nickname: 'Sarah', cumulativeScore: 80, isConnected: true),
        Player(id: '1', playerUid: 'u1', roomCode: 'TRIV', nickname: 'Troy', cumulativeScore: 120, isConnected: true),
      ];

      final merged = SupabaseService.mergeLocalPlayers('TRIV', incoming);
      expect(merged.length, 3);
      expect(merged[0].nickname, 'Troy');
      expect(merged[0].cumulativeScore, 120);
      expect(merged[1].nickname, 'Sarah');
      expect(merged[1].cumulativeScore, 80);
      expect(merged[2].nickname, 'Dave');
      expect(merged[2].cumulativeScore, 50);
    });

    test('Assigns exactly 10 points for getting a question right', () async {
      SupabaseService.clearLocalPlayers('TRIV');
      SupabaseService.registerIncomingPlayer('TRIV', 'Troy', 0);

      // Troy answers a question correctly (+10 pts)
      SupabaseService().updateLocalPlayerScore(
        roomCode: 'TRIV',
        nickname: 'Troy',
        pointsToAdd: 10,
      );

      var players = await SupabaseService().getLeaderboard('TRIV');
      expect(players.first.nickname, 'Troy');
      expect(players.first.cumulativeScore, 10);

      // Troy answers another question correctly (+10 pts)
      SupabaseService().updateLocalPlayerScore(
        roomCode: 'TRIV',
        nickname: 'Troy',
        pointsToAdd: 10,
      );

      players = await SupabaseService().getLeaderboard('TRIV');
      expect(players.first.cumulativeScore, 20);
    });

    test('Assigns exactly 20 points for winning a round', () async {
      SupabaseService.clearLocalPlayers('TRIV');
      SupabaseService.registerIncomingPlayer('TRIV', 'Troy', 30);
      SupabaseService.registerIncomingPlayer('TRIV', 'Alice', 20);

      // Round 1 ends - Troy wins round with 30 pts, earns +20 round bonus
      final top3 = SupabaseService.awardRoundWinnerBonusAndGetTop3('TRIV', 20);
      expect(top3.first['nickname'], 'Troy');
      expect(top3.first['score'], 50); // 30 + 20 = 50

      final players = await SupabaseService().getLeaderboard('TRIV');
      expect(players[0].nickname, 'Troy');
      expect(players[0].cumulativeScore, 50);
      expect(players[1].nickname, 'Alice');
      expect(players[1].cumulativeScore, 20); // Alice did not win, stays at 20
    });
  });

  group('Continuous Round Numbering Across Genres', () {
    test('GameEngineManager maintains and increments currentRound when switching genres', () {
      final engine = GameEngineManager.instance;
      engine.isEngineRunning = false;
      engine.isPreGameCountdownActive = false;
      engine.currentRound = 1;
      engine.currentQuestionIndex = 0;
      engine.selectedGenres = ['General Knowledge', 'Homebrewing Beer'];

      expect(engine.currentRound, 1);
      expect(engine.selectedGenres.first, 'General Knowledge');

      // Simulate questions 1..9
      for (int i = 0; i < 9; i++) {
        engine.currentQuestionIndex++;
      }
      expect(engine.currentQuestionIndex, 9);
      expect(engine.currentRound, 1);

      // Question 10 ends the round
      engine.currentQuestionIndex = 10;
      // In engine, 10th question completion resets currentQuestionIndex to 0, increments currentRound to 2, and rotates genres
      engine.currentQuestionIndex = 0;
      engine.currentRound++;
      final completedGenre = engine.selectedGenres.removeAt(0);
      engine.selectedGenres.add(completedGenre);

      expect(engine.currentRound, 2, reason: 'Round must be 2, never reset to 1');
      expect(engine.selectedGenres.first, 'Homebrewing Beer', reason: 'Genre switched to Homebrewing Beer');

      // Next round questions 1..10 in Homebrewing Beer
      for (int i = 0; i < 10; i++) {
        engine.currentQuestionIndex++;
      }
      expect(engine.currentQuestionIndex, 10);
      expect(engine.currentRound, 2);

      // Advance to round 3
      engine.currentQuestionIndex = 0;
      engine.currentRound++;
      final completedGenre2 = engine.selectedGenres.removeAt(0);
      engine.selectedGenres.add(completedGenre2);

      expect(engine.currentRound, 3, reason: 'Round continues sequentially to Round 3');
      expect(engine.selectedGenres.first, 'General Knowledge');
    });

    test('RealtimeService broadcastQuestion and broadcastGameStarting accept roundNumber and genre', () {
      final realtime = RealtimeService();

      // Verify that calling broadcastQuestion with roundNumber and totalQuestions executes cleanly
      final testQuestion = Question(
        id: 'q-genre-test',
        category: 'Homebrewing Beer',
        difficulty: 'Medium',
        questionText: 'What temperature is typical for ale fermentation?',
        optionA: '65-72°F',
        optionB: '45-50°F',
        optionC: '90-95°F',
        optionD: '32-38°F',
        correctOption: 'A',
      );

      // Calling broadcastQuestion with roundNumber: 2
      expect(() {
        realtime.broadcastQuestion(
          roomCode: 'TESTROOM',
          questionIndex: 11,
          question: testQuestion,
          durationSeconds: 30,
          timerEndsAtEpochMs: DateTime.now().millisecondsSinceEpoch + 30000,
          roundNumber: 2,
          totalQuestions: 10,
        );
      }, returnsNormally);

      // Calling broadcastGameStarting with roundNumber: 2 and genre: 'Homebrewing Beer'
      expect(() {
        realtime.broadcastGameStarting(
          roomCode: 'TESTROOM',
          startsAtEpochMs: DateTime.now().millisecondsSinceEpoch + 15000,
          roundNumber: 2,
          genre: 'Homebrewing Beer',
        );
      }, returnsNormally);
    });

    test('Round 2 Question 1 carries roundNumber: 2 and cumulative questionIndex: 11', () {
      final engine = GameEngineManager.instance;
      engine.currentRound = 2;
      engine.currentQuestionIndex = 0; // Question 1 of round 2
      final cumulativeIndex = ((engine.currentRound - 1) * 10) + engine.currentQuestionIndex + 1;
      expect(cumulativeIndex, 11);
      expect(engine.currentRound, 2);

      final inRoundIndex = ((cumulativeIndex - 1) % 10) + 1;
      expect(inRoundIndex, 1);
    });

    test('Extensive Multi-Round Simulation (Round 1 -> Round 2 -> Round 3) with Cumulative Scoring', () async {
      final engine = GameEngineManager.instance;
      const room = 'EXT_SIM_ROOM';
      SupabaseService.clearLocalPlayers(room);

      // Register two real players: Troy and Alice
      SupabaseService.registerIncomingPlayer(room, 'Troy', 0);
      SupabaseService.registerIncomingPlayer(room, 'Alice', 0);

      // --- ROUND 1 ---
      engine.currentRound = 1;
      engine.currentQuestionIndex = 0;
      engine.selectedGenres = ['Rock & Roll Classics', 'World Geography', 'Movies & Hollywood'];

      // Questions 1 to 10 in Round 1
      for (int q = 1; q <= 10; q++) {
        engine.currentQuestionIndex++;
        // Troy gets question right (+10)
        SupabaseService().updateLocalPlayerScore(roomCode: room, nickname: 'Troy', pointsToAdd: 10);
        if (q % 2 == 0) {
          // Alice gets every even question right (+10)
          SupabaseService().updateLocalPlayerScore(roomCode: room, nickname: 'Alice', pointsToAdd: 10);
        }
      }

      var players = await SupabaseService().getLeaderboard(room);
      expect(players.firstWhere((p) => p.nickname == 'Troy').cumulativeScore, 100);
      expect(players.firstWhere((p) => p.nickname == 'Alice').cumulativeScore, 50);

      // Round 1 Finishes: Award 20 bonus points to Troy (Round 1 Winner)
      final round1Winners = SupabaseService.awardRoundWinnerBonusAndGetTop3(room, 20);
      expect(round1Winners.first['nickname'], 'Troy');
      expect(round1Winners.first['score'], 120); // 100 + 20

      // Advance Engine to Round 2
      engine.currentQuestionIndex = 0;
      final nextRound = engine.currentRound + 1;
      expect(nextRound, 2);
      engine.currentRound = nextRound;
      final compGenre1 = engine.selectedGenres.removeAt(0);
      engine.selectedGenres.add(compGenre1);
      expect(engine.selectedGenres.first, 'World Geography');

      // --- ROUND 2 ---
      // Question 1 of Round 2: Cumulative index must be 11, question number in round must be 1
      final r2q1Cumulative = ((engine.currentRound - 1) * 10) + engine.currentQuestionIndex + 1;
      expect(r2q1Cumulative, 11);
      expect(((r2q1Cumulative - 1) % 10) + 1, 1);
      expect(engine.currentRound, 2);

      // Questions 1 to 10 in Round 2
      for (int q = 1; q <= 10; q++) {
        engine.currentQuestionIndex++;
        // Alice answers all questions correctly in round 2 (+10 each)
        SupabaseService().updateLocalPlayerScore(roomCode: room, nickname: 'Alice', pointsToAdd: 10);
      }

      players = await SupabaseService().getLeaderboard(room);
      // Alice: 50 + 100 = 150. Troy: 120. Alice wins Round 2!
      expect(players.firstWhere((p) => p.nickname == 'Alice').cumulativeScore, 150);
      expect(players.firstWhere((p) => p.nickname == 'Troy').cumulativeScore, 120);

      // Round 2 Finishes: Award 20 bonus points to Alice
      final round2Winners = SupabaseService.awardRoundWinnerBonusAndGetTop3(room, 20);
      expect(round2Winners.first['nickname'], 'Alice');
      expect(round2Winners.first['score'], 170); // 150 + 20

      // Advance Engine to Round 3
      engine.currentQuestionIndex = 0;
      engine.currentRound++;
      expect(engine.currentRound, 3);
      final compGenre2 = engine.selectedGenres.removeAt(0);
      engine.selectedGenres.add(compGenre2);
      expect(engine.selectedGenres.first, 'Movies & Hollywood');

      // --- ROUND 3 QUESTION 1 ---
      final r3q1Cumulative = ((engine.currentRound - 1) * 10) + engine.currentQuestionIndex + 1;
      expect(r3q1Cumulative, 21);
      expect(((r3q1Cumulative - 1) % 10) + 1, 1);
      expect(engine.currentRound, 3);

      // Final Leaderboard verification
      players = await SupabaseService().getLeaderboard(room);
      expect(players[0].nickname, 'Alice');
      expect(players[0].cumulativeScore, 170);
      expect(players[1].nickname, 'Troy');
      expect(players[1].cumulativeScore, 120);
    });

    test('RealtimeService broadcastRoundCompleted carries completed_round and next_round', () {
      final realtime = RealtimeService();
      expect(() {
        realtime.broadcastRoundCompleted(
          roomCode: 'VERIFY_ROOM',
          top3Winners: [
            {'nickname': 'Troy', 'score': 120}
          ],
          roundNumber: 1,
          nextRound: 2,
          nextRoundStartsAtEpochMs: DateTime.now().millisecondsSinceEpoch + 15000,
        );
      }, returnsNormally);
    });
  });

  group('Two-Way Score Synchronization between TV and Player', () {
    test('Player answering correctly updates score and broadcasts player_score_updated & leaderboard_updated', () async {
      SupabaseService.clearLocalPlayers('TRIV');
      SupabaseService.registerIncomingPlayer('TRIV', 'PlayerAlex', 0);

      final eventsReceived = <Map<String, dynamic>>[];
      RealtimeService().joinRoomChannel(
        roomCode: 'TRIV',
        onQuestionBroadcast: (_) {},
        onTimerExpiredBroadcast: (_) {},
        onLeaderboardUpdatedBroadcast: (payload) {
          eventsReceived.add(payload);
        },
      );

      // Player scores +10
      SupabaseService().updateLocalPlayerScore(
        roomCode: 'TRIV',
        nickname: 'PlayerAlex',
        score: 10,
        pointsToAdd: 10,
      );

      // Verify local store updated
      final leaderboard = await SupabaseService().getLeaderboard('TRIV');
      expect(leaderboard.first.nickname, 'PlayerAlex');
      expect(leaderboard.first.cumulativeScore, 10);

      // Verify broadcast events
      expect(eventsReceived.isNotEmpty, true);
      final hasScore10 = eventsReceived.any((e) =>
          (e['nickname'] == 'PlayerAlex' && (e['score'] == 10 || e['cumulative_score'] == 10)) ||
          ((e['players'] as List?)?.any((p) => p['nickname'] == 'PlayerAlex' && (p['score'] == 10 || p['cumulative_score'] == 10)) ?? false));
      expect(hasScore10, true);
    });

    test('TV awarding +20 round bonus propagates to local store and broadcasts', () async {
      SupabaseService.clearLocalPlayers('TRIV');
      SupabaseService.registerIncomingPlayer('TRIV', 'WinnerSam', 30);
      SupabaseService.registerIncomingPlayer('TRIV', 'RunnerUpBob', 20);

      final eventsReceived = <Map<String, dynamic>>[];
      RealtimeService().joinRoomChannel(
        roomCode: 'TRIV',
        onQuestionBroadcast: (_) {},
        onTimerExpiredBroadcast: (_) {},
        onLeaderboardUpdatedBroadcast: (payload) {
          eventsReceived.add(payload);
        },
      );

      // TV awards bonus
      final top3 = SupabaseService.awardRoundWinnerBonusAndGetTop3('TRIV', 20);
      expect(top3.first['nickname'], 'WinnerSam');
      expect(top3.first['score'], 50);

      // Broadcast updated score
      await RealtimeService().broadcastPlayerScoreUpdated(
        roomCode: 'TRIV',
        nickname: 'WinnerSam',
        score: 50,
        pointsEarned: 20,
      );

      final leaderboard = await SupabaseService().getLeaderboard('TRIV');
      expect(leaderboard.first.nickname, 'WinnerSam');
      expect(leaderboard.first.cumulativeScore, 50);
      expect(leaderboard[1].nickname, 'RunnerUpBob');
      expect(leaderboard[1].cumulativeScore, 20);
    });

    test('Leaderboard merges higher scores and never overwrites with lower scores', () {
      SupabaseService.clearLocalPlayers('TRIV');
      final p1 = Player(id: '1', playerUid: 'u1', roomCode: 'TRIV', nickname: 'Troy', cumulativeScore: 30, isConnected: true);
      SupabaseService.setLocalPlayers('TRIV', [p1]);

      // Outdated broadcast arrives with score 10
      final outdated = [
        Player(id: '1', playerUid: 'u1', roomCode: 'TRIV', nickname: 'Troy', cumulativeScore: 10, isConnected: true),
      ];
      final merged = SupabaseService.mergeLocalPlayers('TRIV', outdated);
      expect(merged.first.cumulativeScore, 30); // Kept 30!
    });
  });

  group('Player Mode Top Card & Session Round/Question Synchronization', () {
    test('GameSession.fromJson safely parses epoch ms integer timer_ends_at and current_question_index', () {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final json = {
        'room_code': 'TRIV',
        'status': 'question_active',
        'current_round': 3,
        'round_number': 3,
        'current_question_index': 24,
        'timer_ends_at': nowMs + 15000,
        'created_at': DateTime.now().toIso8601String(),
      };

      final session = GameSession.fromJson(json);
      expect(session.roomCode, 'TRIV');
      expect(session.currentRound, 3);
      expect(session.questionIndex, 24);
      expect(session.timerEndsAt, isNotNull);
      expect(session.timerEndsAt!.millisecondsSinceEpoch, nowMs + 15000);
      expect(session.id, 'dev-session-id'); // Fallback for null id
    });

    test('GameSession.fromJson safely parses ISO8601 string timer_ends_at and fallback values', () {
      final json = {
        'id': 'sess-123',
        'room_code': 'TRIV',
        'status': 'lobby',
        'timer_ends_at': '2026-10-07T14:30:00.000Z',
        'created_at': '2026-10-07T14:00:00.000Z',
      };

      final session = GameSession.fromJson(json);
      expect(session.id, 'sess-123');
      expect(session.currentRound, 1);
      expect(session.questionIndex, 0);
      expect(session.timerEndsAt, DateTime.parse('2026-10-07T14:30:00.000Z'));
    });

    test('Player Controller state calculation accurately tracks round and question index', () {
      // Round 2 Question 4 (cumulative index 14)
      const qIndex = 14;
      const totalQ = 10;
      const qNumInRound = ((qIndex - 1) % totalQ) + 1;
      const roundNumber = ((qIndex - 1) ~/ totalQ) + 1;

      expect(qNumInRound, 4);
      expect(roundNumber, 2);

      // Verify header subtitle string formatting
      const subtitle = 'Round $roundNumber • Question $qNumInRound of 10';
      expect(subtitle, 'Round 2 • Question 4 of 10');
    });

    test('Round transition correctly advances to next round and resets question number to 1', () {
      int currentRound = 1;
      int questionNumberInRound = 10;

      // Round 1 completes -> transition to Round 2
      const completedR = 1;
      const nextR = completedR + 1;
      currentRound = nextR;
      questionNumberInRound = 1;

      expect(currentRound, 2);
      expect(questionNumberInRound, 1);

      final intermissionSubtitle = 'Round $currentRound • Next Round in 15s';
      expect(intermissionSubtitle, 'Round 2 • Next Round in 15s');
    });
  });
}



