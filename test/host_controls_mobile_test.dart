import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bar_rooms_trivia/shared/services/game_engine.dart';
import 'package:bar_rooms_trivia/shared/services/supabase_service.dart';
import 'package:bar_rooms_trivia/shared/config/supabase_config.dart';
import 'package:bar_rooms_trivia/shared/data/trivia_repository.dart';

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

  group('Mobile Host Controls HTML Architecture Tests', () {
    late String htmlContent;

    setUpAll(() {
      final file = File('index.html');
      expect(file.existsSync(), isTrue, reason: 'index.html must exist');
      htmlContent = file.readAsStringSync();
    });

    test('index.html contains modern mobile host container architecture', () {
      expect(htmlContent.contains('<section id="view-host" class="view-panel">'), isTrue);
      expect(htmlContent.contains('class="host-app-container"'), isTrue);
      expect(htmlContent.contains('class="host-mobile-navbar"'), isTrue);
      expect(htmlContent.contains('class="host-status-ribbon"'), isTrue);
      expect(htmlContent.contains('class="host-segmented-tabs"'), isTrue);
      expect(htmlContent.contains('class="host-sticky-bottom-dock"'), isTrue);
    });

    test('index.html includes all 4 host segmented navigation tabs', () {
      expect(htmlContent.contains('data-tab="stage"'), isTrue);
      expect(htmlContent.contains('data-tab="playlist"'), isTrue);
      expect(htmlContent.contains('data-tab="players"'), isTrue);
      expect(htmlContent.contains('data-tab="settings"'), isTrue);

      expect(htmlContent.contains('id="host-pane-stage"'), isTrue);
      expect(htmlContent.contains('id="host-pane-playlist"'), isTrue);
      expect(htmlContent.contains('id="host-pane-players"'), isTrue);
      expect(htmlContent.contains('id="host-pane-settings"'), isTrue);
    });

    test('Tab 1 (Live Stage) contains question preview, answer key, and countdown', () {
      expect(htmlContent.contains('id="host-stage-badge"'), isTrue);
      expect(htmlContent.contains('id="host-stage-q-counter"'), isTrue);
      expect(htmlContent.contains('id="host-live-genre-pill"'), isTrue);
      expect(htmlContent.contains('id="host-live-q-text"'), isTrue);

      // Answer key cards A, B, C, D
      expect(htmlContent.contains('id="host-ans-A"'), isTrue);
      expect(htmlContent.contains('id="host-ans-B"'), isTrue);
      expect(htmlContent.contains('id="host-ans-C"'), isTrue);
      expect(htmlContent.contains('id="host-ans-D"'), isTrue);
      expect(htmlContent.contains('id="host-ans-text-A"'), isTrue);
      expect(htmlContent.contains('id="host-ans-text-B"'), isTrue);
      expect(htmlContent.contains('id="host-ans-text-C"'), isTrue);
      expect(htmlContent.contains('id="host-ans-text-D"'), isTrue);

      // Timer progress and countdown
      expect(htmlContent.contains('id="host-timer-progress-fill"'), isTrue);
      expect(htmlContent.contains('id="host-live-timer-secs"'), isTrue);
      expect(htmlContent.contains('id="host-stage-queue-preview"'), isTrue);
    });

    test('Tab 2 (Playlist) contains queue bar, search input, category filters, and genre chips', () {
      expect(htmlContent.contains('id="host-queue-list-display"'), isTrue);
      expect(htmlContent.contains('id="btn-clear-queue"'), isTrue);
      expect(htmlContent.contains('id="host-genre-search-input"'), isTrue);
      expect(htmlContent.contains('id="btn-clear-genre-search"'), isTrue);

      // Category filter pills
      expect(htmlContent.contains('data-cat="all"'), isTrue);
      expect(htmlContent.contains('data-cat="bar"'), isTrue);
      expect(htmlContent.contains('data-cat="ent"'), isTrue);
      expect(htmlContent.contains('data-cat="brain"'), isTrue);
      expect(htmlContent.contains('data-cat="world"'), isTrue);
      expect(htmlContent.contains('data-cat="life"'), isTrue);

      // Genre chips container and sample genres
      expect(htmlContent.contains('id="genre-chips-container"'), isTrue);
      expect(htmlContent.contains('data-genre="Auto Select"'), isTrue);
      expect(htmlContent.contains('data-genre="Homebrewing Beer"'), isTrue);
      expect(htmlContent.contains('data-genre="Science & Technology"'), isTrue);
      expect(htmlContent.contains('data-genre="Sports & Stadiums"'), isTrue);
    });

    test('Tab 3 (Players) contains connected players list and live counter badges', () {
      expect(htmlContent.contains('id="host-connected-players-list"'), isTrue);
      expect(htmlContent.contains('id="host-live-player-badge"'), isTrue);
      expect(htmlContent.contains('id="host-tab-player-count"'), isTrue);
      expect(htmlContent.contains('id="btn-refresh-players"'), isTrue);
      expect(htmlContent.contains('id="host-players-room-code"'), isTrue);
    });

    test('Tab 4 (Settings) retains difficulty chips and timer chips', () {
      expect(htmlContent.contains('class="diff-chip"'), isTrue);
      expect(htmlContent.contains('data-diff="Kids"'), isTrue);
      expect(htmlContent.contains('data-diff="Beginner"'), isTrue);
      expect(htmlContent.contains('data-diff="Standard"'), isTrue);
      expect(htmlContent.contains('data-diff="Advanced"'), isTrue);

      expect(htmlContent.contains('class="timer-chip"'), isTrue);
      expect(htmlContent.contains('data-timer="10"'), isTrue);
      expect(htmlContent.contains('data-timer="20"'), isTrue);
      expect(htmlContent.contains('data-timer="60"'), isTrue);
      expect(htmlContent.contains('data-timer="120"'), isTrue);
    });

    test('Sticky bottom dock contains ergonomic action buttons', () {
      expect(htmlContent.contains('id="btn-start-auto"'), isTrue);
      expect(htmlContent.contains('id="btn-pause-auto"'), isTrue);
      expect(htmlContent.contains('id="btn-reset-game"'), isTrue);
    });
  });

  group('Mobile Host Controls CSS Styling Tests', () {
    late String cssContent;

    setUpAll(() {
      final file = File('src/style.css');
      expect(file.existsSync(), isTrue, reason: 'src/style.css must exist');
      cssContent = file.readAsStringSync();
    });

    test('CSS supports modern mobile app layout and safe area insets', () {
      expect(cssContent.contains('.host-app-container'), isTrue);
      expect(cssContent.contains('.host-mobile-navbar'), isTrue);
      expect(cssContent.contains('.host-status-ribbon'), isTrue);
      expect(cssContent.contains('.host-segmented-tabs'), isTrue);
      expect(cssContent.contains('.host-tab-pane'), isTrue);
      expect(cssContent.contains('.host-sticky-bottom-dock'), isTrue);
      expect(cssContent.contains('safe-area-inset-bottom'), isTrue);
    });

    test('CSS includes glowing emerald answer key and tactile card styles', () {
      expect(cssContent.contains('.answer-key-card.correct-key'), isTrue);
      expect(cssContent.contains('.stage-timer-fill'), isTrue);
      expect(cssContent.contains('.host-player-item'), isTrue);
      expect(cssContent.contains('.genre-cat-pill'), isTrue);
      expect(cssContent.contains('.genre-search-bar'), isTrue);
    });
  });

  group('Mobile Host Controls JS Implementation Tests', () {
    late String jsContent;

    setUpAll(() {
      final file = File('src/main.js');
      expect(file.existsSync(), isTrue, reason: 'src/main.js must exist');
      jsContent = file.readAsStringSync();
    });

    test('main.js implements tab switching logic', () {
      expect(jsContent.contains('switchHostTab('), isTrue);
      expect(jsContent.contains('.host-tab-btn'), isTrue);
      expect(jsContent.contains('.host-tab-pane'), isTrue);
      expect(jsContent.contains('btn-host-goto-playlist'), isTrue);
    });

    test('main.js implements genre search and category filtering', () {
      expect(jsContent.contains('filterGenreChips'), isTrue);
      expect(jsContent.contains('host-genre-search-input'), isTrue);
      expect(jsContent.contains('btn-clear-genre-search'), isTrue);
      expect(jsContent.contains('genre-cat-pill'), isTrue);
    });

    test('main.js implements host timeout and advance review logic', () {
      expect(jsContent.contains('handleHostQuestionTimeout'), isTrue);
      expect(jsContent.contains('handleHostAdvanceAfterReview'), isTrue);
    });

    test('main.js updates host live stage preview card in onQuestionStart and onTimerExpired', () {
      expect(jsContent.contains('host-stage-badge'), isTrue);
      expect(jsContent.contains('host-stage-q-counter'), isTrue);
      expect(jsContent.contains('host-live-genre-pill'), isTrue);
      expect(jsContent.contains('host-live-q-text'), isTrue);
      expect(jsContent.contains('host-ans-'), isTrue);
      expect(jsContent.contains('correct-key'), isTrue);
      expect(jsContent.contains('host-timer-progress-fill'), isTrue);
      expect(jsContent.contains('host-live-timer-secs'), isTrue);
    });

    test('main.js implements renderHostPlayersRoster with ranks and scores', () {
      expect(jsContent.contains('function renderHostPlayersRoster()'), isTrue);
      expect(jsContent.contains('host-connected-players-list'), isTrue);
      expect(jsContent.contains('host-live-player-badge'), isTrue);
      expect(jsContent.contains('host-tab-player-count'), isTrue);
      expect(jsContent.contains('host-player-item'), isTrue);
    });
  });

  group('Extensive Game State Machine and Scoring Lifecycle Tests', () {
    test('Host starts game, advances questions, allocates 10 pts per correct answer and 20 pts for round win', () async {
      const room = 'HOST_CTRL_TEST';
      final engine = GameEngineManager.instance;
      engine.currentRound = 1;
      engine.currentQuestionIndex = 0;
      engine.selectedGenres = ['Food & Culinary', 'World History'];

      // Register two real players
      SupabaseService.registerIncomingPlayer(room, 'Alice', 0);
      SupabaseService.registerIncomingPlayer(room, 'Bob', 0);

      var players = await SupabaseService().getLeaderboard(room);
      expect(players.length, 2);

      // Question 1 starts
      engine.currentQuestionIndex = 1;
      final q1 = TriviaRepository.getQuestionForGenres(engine.selectedGenres, 1);
      expect(q1.questionText.isNotEmpty, isTrue);

      // Alice answers correctly (+10 pts)
      SupabaseService().updateLocalPlayerScore(roomCode: room, nickname: 'Alice', pointsToAdd: 10);
      players = await SupabaseService().getLeaderboard(room);
      final aliceP1 = players.firstWhere((p) => p.nickname == 'Alice');
      final bobP1 = players.firstWhere((p) => p.nickname == 'Bob');
      expect(aliceP1.cumulativeScore, 10);
      expect(bobP1.cumulativeScore, 0);

      // Advance through questions 2 to 10
      for (int i = 2; i <= 10; i++) {
        engine.currentQuestionIndex = i;
        final q = TriviaRepository.getQuestionForGenres(engine.selectedGenres, i);
        expect(q.questionText.isNotEmpty, isTrue);
        // Alice answers correctly (+10 pts each)
        SupabaseService().updateLocalPlayerScore(roomCode: room, nickname: 'Alice', pointsToAdd: 10);
      }

      // Round 1 ends: Award Round Winner Bonus (+20 points)
      final top3 = SupabaseService.awardRoundWinnerBonusAndGetTop3(room, 20);
      expect(top3.isNotEmpty, isTrue);
      expect(top3.first['nickname'], 'Alice');

      // Alice total = (10 q * 10 pts) + 20 round bonus = 120 pts
      players = await SupabaseService().getLeaderboard(room);
      final aliceFinalR1 = players.firstWhere((p) => p.nickname == 'Alice');
      expect(aliceFinalR1.cumulativeScore, 120);

      // Host advances to Round 2
      engine.currentQuestionIndex = 0;
      engine.currentRound = 2;
      expect(engine.currentRound, 2);

      // Score persists into Round 2
      players = await SupabaseService().getLeaderboard(room);
      final aliceR2 = players.firstWhere((p) => p.nickname == 'Alice');
      expect(aliceR2.cumulativeScore, 120);
    });

    test('Repeated cycle test: 10 consecutive game cycles verify host reset and state resilience', () async {
      final engine = GameEngineManager.instance;

      for (int cycle = 1; cycle <= 10; cycle++) {
        final room = 'CYCLE_ROOM_$cycle';
        engine.currentRound = 1;
        engine.currentQuestionIndex = 0;
        engine.selectedGenres = ['Rock & Roll Classics', 'Sports & Stadiums'];

        SupabaseService.registerIncomingPlayer(room, 'Tester_$cycle', 0);
        var players = await SupabaseService().getLeaderboard(room);
        expect(players.length, 1);
        expect(players.first.cumulativeScore, 0);

        // Host serves question and player answers
        engine.currentQuestionIndex = 1;
        final q = TriviaRepository.getQuestionForGenres(engine.selectedGenres, 1);
        expect(q.questionText.isNotEmpty, isTrue);

        SupabaseService().updateLocalPlayerScore(roomCode: room, nickname: 'Tester_$cycle', pointsToAdd: 10);
        players = await SupabaseService().getLeaderboard(room);
        expect(players.first.cumulativeScore, 10);
      }
    });
  });
}
