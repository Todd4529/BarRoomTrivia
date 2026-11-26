import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bar_rooms_trivia/shared/config/supabase_config.dart';
import 'package:bar_rooms_trivia/shared/data/trivia_genres.dart';
import 'package:bar_rooms_trivia/shared/data/trivia_repository.dart';
import 'package:bar_rooms_trivia/shared/services/game_engine.dart';
import 'package:bar_rooms_trivia/shared/services/mqtt_service.dart';
import 'package:bar_rooms_trivia/shared/services/realtime_service.dart';
import 'package:bar_rooms_trivia/shared/services/supabase_service.dart';

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

  group('Audit Regression — TriviaRepository Safety & Difficulty Matching', () {
    test('Every genre in TriviaGenres always yields a valid question with 4 non-empty options', () {
      for (final genre in TriviaGenres.allGenres) {
        final q = TriviaRepository.getQuestionForGenres([genre], 1, difficulty: 'Standard');
        expect(q.questionText.trim().isNotEmpty, isTrue, reason: 'Genre "$genre" returned empty question');
        expect(q.optionA.trim().isNotEmpty, isTrue, reason: 'Genre "$genre" missing optionA');
        expect(q.optionB.trim().isNotEmpty, isTrue, reason: 'Genre "$genre" missing optionB');
        expect(q.optionC.trim().isNotEmpty, isTrue, reason: 'Genre "$genre" missing optionC');
        expect(q.optionD.trim().isNotEmpty, isTrue, reason: 'Genre "$genre" missing optionD');
        expect(['A', 'B', 'C', 'D'].contains(q.correctOption), isTrue,
            reason: 'Genre "$genre" invalid correctOption ${q.correctOption}');
      }
    });

    test('Difficulty preferences (Kids, Beginner, Standard, Advanced) do not crash and return valid questions', () {
      for (final diff in ['Kids', 'Beginner', 'Standard', 'Advanced']) {
        final q = TriviaRepository.getQuestionForGenres(['Science & Technology'], 1, difficulty: diff);
        expect(q.questionText.isNotEmpty, isTrue);
        expect(q.optionD.isNotEmpty, isTrue);
      }
    });
  });

  group('Audit Regression — Room Isolation & Player State Integrity', () {
    test('registerPlayer preserves existing player score on rejoin in same room', () async {
      final svc = SupabaseService();
      final p1 = await svc.registerPlayer(roomCode: 'ROOM1', nickname: 'Alice');
      expect(p1.cumulativeScore, 0);

      SupabaseService.updatePlayerScoreDirectly(
        roomCode: 'ROOM1',
        nickname: 'Alice',
        score: 70,
      );

      final rejoined = await svc.registerPlayer(roomCode: 'ROOM1', nickname: 'Alice');
      expect(rejoined.cumulativeScore, 70, reason: 'Rejoining player must keep existing score');
      expect(SupabaseService.getLocalPlayersJson('ROOM1').length, 1);
    });

    test('syncPlayersFromBroadcast with an empty list clears local players for that room only', () async {
      final svc = SupabaseService();
      await svc.registerPlayer(roomCode: 'ROOMA', nickname: 'Alice');
      await svc.registerPlayer(roomCode: 'ROOMB', nickname: 'Bob');

      SupabaseService.syncPlayersFromBroadcast('ROOMA', <Map<String, dynamic>>[]);

      expect(SupabaseService.getLocalPlayersJson('ROOMA'), isEmpty,
          reason: 'Empty broadcast list must clear ROOMA leaderboard');
      expect(SupabaseService.getLocalPlayersJson('ROOMB').length, 1,
          reason: 'Clearing ROOMA must never clear ROOMB');
    });

    test('RealtimeService isolates broadcasts strictly to matching room and handles leaderboard_cleared', () async {
      final svc = SupabaseService();
      await svc.registerPlayer(roomCode: 'ALPHA', nickname: 'PlayerAlpha');

      final rt = RealtimeService();
      final receivedRoomAQuestions = <Map<String, dynamic>>[];
      var leaderboardClearedEventCount = 0;

      rt.joinRoomChannel(
        roomCode: 'ALPHA',
        onQuestionBroadcast: (payload) => receivedRoomAQuestions.add(payload),
        onTimerExpiredBroadcast: (_) {},
        onLeaderboardUpdatedBroadcast: (payload) {
          final players = payload['players'];
          if (players is List && players.isEmpty) {
            leaderboardClearedEventCount++;
          }
        },
      );

      // Broadcast to BETA — ALPHA listener must ignore it completely
      await rt.broadcastQuestion(
        roomCode: 'BETA',
        questionIndex: 1,
        question: TriviaRepository.getQuestionForGenres(['World Geography'], 1),
        durationSeconds: 20,
        timerEndsAtEpochMs: DateTime.now().millisecondsSinceEpoch + 20000,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(receivedRoomAQuestions, isEmpty,
          reason: 'ALPHA channel must never receive BETA room broadcasts');

      // Broadcast empty leaderboard_updated for ALPHA — clears local players and notifies UI
      await rt.broadcastLeaderboardUpdated(roomCode: 'ALPHA', players: const []);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(SupabaseService.getLocalPlayersJson('ALPHA'), isEmpty);
      expect(leaderboardClearedEventCount, greaterThanOrEqualTo(1));

      rt.leaveChannel();
    });

    test('MqttService does not subscribe to global tv_pairing topic and unsubscribes cleanly', () {
      final mqttSource = File('lib/shared/services/mqtt_service.dart').readAsStringSync();
      expect(mqttSource.contains("subscribe('tv_pairing'"), isFalse,
          reason: 'MqttService must not auto-subscribe to global tv_pairing topic');
      expect(mqttSource.contains('void unsubscribeFromRoom('), isTrue);
      expect(mqttSource.contains('void _disconnectIfIdle('), isTrue);

      final mqtt = MqttService();
      mqtt.subscribeToRoom('TEST-1234');
      mqtt.unsubscribeFromRoom('TEST-1234');
      expect(mqtt.isConnected, isFalse);
    });
  });

  group('Audit Regression — GameEngineManager Stop & Manual Pause/Resume', () {
    test('stopGameToLobby cleanly cancels pre-game countdown and resets state without looping', () {
      final engine = GameEngineManager.instance;
      engine.gamePlayMode = 'Manual';
      engine.startPreGame(
        roomCode: 'STOP1',
        timerSeconds: 20,
        genres: const ['Movies & Hollywood'],
        isNewGame: true,
        roundNumber: 1,
      );
      expect(engine.isPreGameCountdownActive, isTrue);

      engine.stopGameToLobby(roomCode: 'STOP1');
      expect(engine.isPreGameCountdownActive, isFalse);
      expect(engine.isEngineRunning, isFalse);
      expect(engine.isGamePaused, isFalse);
      expect(engine.activeQuestion, isNull);
    });

    test('Manual mode pause during reading phase preserves reading phase instead of forcing active timer', () {
      final engine = GameEngineManager.instance;
      engine.stopGameToLobby(roomCode: 'MANP1');
      engine.gamePlayMode = 'Manual';
      engine.selectedGenres = ['World History'];
      engine.isEngineRunning = true;
      engine.currentRound = 1;
      engine.currentQuestionIndex = 1;
      engine.activeQuestion = TriviaRepository.getQuestionForGenres(['World History'], 1);
      engine.isQuestionTimerRunning = false;
      engine.isReviewPhase = false;

      engine.pauseGame(roomCode: 'MANP1');
      expect(engine.isGamePaused, isTrue);
      expect(engine.isQuestionTimerRunning, isFalse);

      // Clean up
      engine.stopGameToLobby(roomCode: 'MANP1');
    });
  });

  group('Audit Regression — Security, Web HTML & CSS Hardening', () {
    test('Security invariants: no public token broadcast, HTTPS cleartext disabled, no hardcoded FTP password, RLS migration exists', () {
      final tvVerifyDart = File('lib/auth/tv_auth_verify_view.dart').readAsStringSync();
      // auth_tokens must NOT be included in public MQTT/Supabase payload
      final publicPayloadMatch = RegExp(r'final\s+payload\s*=\s*\{[\s\S]*?\};').firstMatch(tvVerifyDart);
      expect(publicPayloadMatch, isNotNull);
      expect(publicPayloadMatch!.group(0)!.contains('auth_tokens'), isFalse,
          reason: 'Public MQTT/Realtime device_authorized payload must never contain auth_tokens');

      final manifestXml = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifestXml.contains('android:usesCleartextTraffic="false"'), isTrue,
          reason: 'AndroidManifest must disable cleartext traffic');

      final deployPs1 = File('scripts/deploy_ftp.ps1').readAsStringSync();
      expect(deployPs1.contains('env:HOSTINGER_FTP_PASSWORD'), isTrue,
          reason: 'FTP deployment script must read password from environment variable');
      expect(deployPs1.contains('T0dd4529'), isFalse,
          reason: 'FTP deployment script must never contain hardcoded credentials');

      final migrationSql = File('supabase/migrations/20261126_harden_schema_and_rls.sql');
      expect(migrationSql.existsSync(), isTrue);
      final sql = migrationSql.readAsStringSync();
      expect(sql.contains('DROP POLICY IF EXISTS "Hosts can update their own subscriptions"'), isTrue);
      expect(sql.contains('CREATE POLICY "Room host can delete room players"'), isTrue);
    });

    test('Web index.html and src/style.css satisfy all post-audit UX invariants', () {
      final html = File('index.html').readAsStringSync();
      final css = File('src/style.css').readAsStringSync();

      // Viewport allows zoom (accessibility)
      expect(html.contains('maximum-scale=1.0'), isFalse);
      expect(html.contains('user-scalable=no'), isFalse);

      // Landing page has direct launch links and clickable store links
      expect(html.contains('data-nav-view="player"'), isTrue);
      expect(html.contains('data-nav-view="host"'), isTrue);
      expect(html.contains('data-nav-view="tv"'), isTrue);
      expect(html.contains('play.google.com/store/search?q=Bar%20Rooms%20Trivia'), isTrue);
      expect(html.contains('amazon.com/s?k=Bar+Rooms+Trivia'), isTrue);

      // 4th Players tab restored in Host Console
      expect(html.contains('data-tab="players"'), isTrue);

      // No duplicate inline submit/click handlers on auth form
      expect(html.contains('onsubmit="window.handleAuthFormSubmit'), isFalse);
      expect(html.contains('onclick="window.handleQuickConnectHost'), isFalse);

      // CSS tokens, modal backdrop opacity, and z-index hierarchy
      expect(css.contains('--neon-gold:'), isTrue);
      expect(css.contains('.btn-warning'), isTrue);
      expect(css.contains('.status-badge'), isTrue);
      expect(css.contains('body[data-view="host"] .app-header'), isTrue);
      expect(css.contains('z-index: 1200;'), isTrue);
      expect(css.contains('z-index: 10050;'), isTrue);

      // Web BroadcastChannel room isolation & Manual Reading Phase button lock
      final js = File('src/main.js').readAsStringSync();
      expect(js.contains('function createRoomBroadcastChannel(roomCode)'), isTrue);
      expect(js.contains('btn.disabled = isIdle;'), isTrue);
    });
  });
}
