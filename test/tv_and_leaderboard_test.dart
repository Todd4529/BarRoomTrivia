import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bar_rooms_trivia/shared/models/question.dart';
import 'package:bar_rooms_trivia/shared/models/player.dart';
import 'package:bar_rooms_trivia/shared/services/supabase_service.dart';
import 'package:bar_rooms_trivia/shared/config/supabase_config.dart';
import 'package:bar_rooms_trivia/shared/data/genre_questions_engine.dart';
import 'package:bar_rooms_trivia/tv/widgets/timer_ring.dart';

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

    test('returns default pub players if room is empty', () async {
      final service = SupabaseService();
      final leaderboard = await service.getLeaderboard('EMPTY_ROOM_XYZ');
      expect(leaderboard.length, 10);
      expect(leaderboard.first.nickname.isNotEmpty, true);
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
}
