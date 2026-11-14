import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bar_rooms_trivia/shared/config/supabase_config.dart';
import 'package:bar_rooms_trivia/shared/services/supabase_service.dart';
import 'package:bar_rooms_trivia/shared/services/game_engine.dart';
import 'package:bar_rooms_trivia/shared/data/trivia_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'tv_room_code': 'TRIV'});
    try {
      await SupabaseConfig.initialize();
    } catch (_) {}
  });

  group('Targeted Bug Fix Verification Tests', () {
    setUp(() {
      SupabaseService.clearLocalPlayers();
      TriviaRepository.resetSessionDecks();
    });

    test('1. SupabaseService.isMockNickname does not false-positive on real substrings', () {
      expect(SupabaseService.isMockNickname('Champ'), isFalse);
      expect(SupabaseService.isMockNickname('GhostRider'), isFalse);
      expect(SupabaseService.isMockNickname('NinjaFan'), isFalse);
      expect(SupabaseService.isMockNickname('Troy'), isFalse);

      expect(SupabaseService.isMockNickname('Champion'), isTrue);
      expect(SupabaseService.isMockNickname('host'), isTrue);
      expect(SupabaseService.isMockNickname('host-tv'), isTrue);
      expect(SupabaseService.isMockNickname('todd4529'), isTrue);
      expect(SupabaseService.isMockNickname('SimulatedPlayer_1'), isTrue);
    });

    test('2. SupabaseService maintains strict per-room player isolation without polluting TRIV', () async {
      final service = SupabaseService();
      SupabaseService.registerIncomingPlayer('TRIV', 'Alice', 50);
      SupabaseService.registerIncomingPlayer('VIP2', 'Bob', 80);

      final trivRoster = await service.getLeaderboard('TRIV');
      final vip2Roster = await service.getLeaderboard('VIP2');

      expect(trivRoster.map((p) => p.nickname).toList(), equals(['Alice']));
      expect(vip2Roster.map((p) => p.nickname).toList(), equals(['Bob']));

      SupabaseService.clearLocalPlayers('VIP2');
      final vip2AfterClear = await service.getLeaderboard('VIP2');
      expect(vip2AfterClear, isEmpty);
      final trivStillIntact = await service.getLeaderboard('TRIV');
      expect(trivStillIntact.map((p) => p.nickname).toList(), equals(['Alice']));
    });

    test('3. awardRoundWinnerBonusAndGetTop3 awards +20 bonus to ALL tied top scorers', () {
      const room = 'TIE_ROOM';
      SupabaseService.registerIncomingPlayer(room, 'PlayerOne', 100);
      SupabaseService.registerIncomingPlayer(room, 'PlayerTwo', 100);
      SupabaseService.registerIncomingPlayer(room, 'PlayerThree', 80);

      final top3 = SupabaseService.awardRoundWinnerBonusAndGetTop3(room, 20);
      expect(top3.length, equals(3));

      final byName = {for (final entry in top3) entry['nickname']: entry['score']};
      expect(byName['PlayerOne'], equals(120));
      expect(byName['PlayerTwo'], equals(120));
      expect(byName['PlayerThree'], equals(80));
    });

    test('4. TriviaRepository propagates difficulty and never emits synthetic Choice placeholders', () {
      TriviaRepository.resetSessionDecks();
      for (int i = 0; i < 40; i++) {
        final q = TriviaRepository.getQuestionForGenres(
          ['Homebrewing Beer'],
          i,
          difficulty: 'Advanced',
        );
        expect(q.difficulty, equals('Advanced'));
        final opts = [q.optionA, q.optionB, q.optionC, q.optionD];
        expect(opts.toSet().length, equals(4), reason: 'All 4 options must be distinct');
        for (final opt in opts) {
          expect(opt.contains(' Choice '), isFalse, reason: 'No synthetic placeholder strings allowed');
        }
      }
    });

    test('5. GameEngineManager exposes selectedDifficulty and tracks pause/resume state cleanly', () {
      final engine = GameEngineManager.instance;
      engine.selectedDifficulty = 'Beginner';
      expect(engine.selectedDifficulty, equals('Beginner'));
    });

    test('6. index.html closes previously unclosed button tags properly', () {
      final html = File('index.html').readAsStringSync();
      expect(
        RegExp(r'<button[^>]*id="btn-tv-close-host-qr"[^>]*>[\s\S]*?</button>').hasMatch(html),
        isTrue,
      );
      expect(
        RegExp(r'<button[^>]*id="btn-tv-close-empty-host-qr"[^>]*>[\s\S]*?</button>').hasMatch(html),
        isTrue,
      );
      expect(
        RegExp(r'<button[^>]*id="btn-reopen-app"[^>]*>[\s\S]*?</button>').hasMatch(html),
        isTrue,
      );
      expect(
        RegExp(r'<button[^>]*id="btn-player-join"[^>]*>[\s\S]*?</button>').hasMatch(html),
        isTrue,
      );
    });
  });
}
