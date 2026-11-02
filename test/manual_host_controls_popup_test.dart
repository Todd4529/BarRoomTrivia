import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bar_rooms_trivia/host/views/host_dashboard_view.dart';
import 'package:bar_rooms_trivia/shared/config/supabase_config.dart';
import 'package:bar_rooms_trivia/shared/services/game_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'tv_room_code': 'TRIV'});
    try {
      await SupabaseConfig.initialize();
    } catch (_) {}
  });

  group('Manual Live Host Controls & Pop-up Modal Tests', () {
    test('1. index.html defines #host-manual-modal-overlay with dedicated start timer, pause, reveal answer, and next question buttons', () {
      final html = File('index.html').readAsStringSync();
      expect(html.contains('id="host-manual-modal-overlay"'), isTrue,
          reason: 'index.html must define the host manual modal overlay');
      expect(html.contains('id="btn-manual-modal-start-timer"'), isTrue,
          reason: 'index.html must define the start timer button in the manual pop-up');
      expect(html.contains('id="btn-manual-modal-pause"'), isTrue,
          reason: 'index.html must define the pause/resume button in the manual pop-up');
      expect(html.contains('id="btn-manual-modal-reveal"'), isTrue,
          reason: 'index.html must define the reveal answer button in the manual pop-up');
      expect(html.contains('id="btn-manual-modal-next-q"'), isTrue,
          reason: 'index.html must define the next question button in the manual pop-up');
      expect(html.contains('id="btn-manual-modal-start-game"'), isTrue,
          reason: 'index.html must define the Start Game button on the bottom of the manual pop-up');
      expect(html.contains('id="btn-open-manual-modal"'), isTrue,
          reason: 'index.html must provide an open console button in the bottom dock');
      expect(html.indexOf('Read question aloud to venue') < html.indexOf('id="manual-modal-question-text"'), isTrue,
          reason: 'Read question tip must be placed just above the question text');
    });

    test('2. src/style.css defines styling for manual modal and dedicated buttons', () {
      final css = File('src/style.css').readAsStringSync();
      expect(css.contains('.host-manual-modal-overlay'), isTrue);
      expect(css.contains('.btn-manual-start'), isTrue);
      expect(css.contains('.btn-manual-pause'), isTrue);
      expect(css.contains('.btn-manual-reveal'), isTrue);
      expect(css.contains('.btn-manual-next-q'), isTrue);
      expect(css.contains('.btn-manual-start-game'), isTrue);
      expect(css.contains('.manual-tip-banner'), isTrue);
      expect(css.contains('.manual-option-correct'), isTrue);
    });

    test('3. src/main.js implements manual pop-up logic and triggers when Manual mode is selected', () {
      final js = File('src/main.js').readAsStringSync();
      expect(js.contains('function openHostManualModal()'), isTrue);
      expect(js.contains('function closeHostManualModal()'), isTrue);
      expect(js.contains('function updateHostManualModalUI()'), isTrue);
      expect(js.contains('function handleManualHostNextQuestionAction()'), isTrue);
      expect(js.contains("openHostManualModal();"), isTrue,
          reason: 'Selecting Manual mode must immediately open the host manual modal console');
      expect(js.contains("const isIdleTimer = payload.timer_state === 'idle' || payload.question_phase === 'reading';"), isTrue,
          reason: 'handleIncomingQuestionStart must preserve idle timer state during Manual reading phase');
      expect(js.contains("if (questionInRound === 10) {\n    hostEngineState = 'QUESTION_REVIEW';\n    handleHostAdvanceAfterReview(10, currentRound);"), isTrue,
          reason: 'Skipping Question 10 in Manual mode must transition hostEngineState to QUESTION_REVIEW before advancing');
    });

    test('4. lib/host/views/host_dashboard_view.dart defines _showManualHostControlDialog', () {
      final dartCode = File('lib/host/views/host_dashboard_view.dart').readAsStringSync();
      expect(dartCode.contains('void _showManualHostControlDialog(BuildContext context)'), isTrue);
      expect(dartCode.contains('_showManualHostControlDialog(context);'), isTrue,
          reason: 'Tapping Manual mode in game mode chips must launch the modal dialog');
      expect(dartCode.contains('Start Timer'), isTrue);
      expect(dartCode.contains('Reveal Answer'), isTrue);
      expect(dartCode.contains('((engine.currentQuestionIndex - 1) % 10) + 1'), isTrue,
          reason: 'Question number in Manual modal must be 1-based matching currentQuestionIndex');
    });

    testWidgets('5. Flutter Manual Host Console Modal full interactive lifecycle (Start -> Reading Q1 -> Start 20s Timer -> Reveal Answer -> Next Question)', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({'tv_room_code': 'TRIV'});
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        GameEngineManager.instance.pauseGame(roomCode: 'TRIV');
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final engine = GameEngineManager.instance;
      engine.resetGame(roomCode: 'TRIV', resetMode: 'clear_all');

      await tester.pumpWidget(
        const MaterialApp(
          home: HostDashboardView(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      // Tap the 'MANUAL (HOST DRIVEN)' mode chip to open the Manual Host Console modal
      final manualChipFinder = find.text('MANUAL (HOST DRIVEN)');
      expect(manualChipFinder, findsOneWidget);
      await tester.ensureVisible(manualChipFinder);
      await tester.tap(manualChipFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('MANUAL HOST CONSOLE'), findsOneWidget);
      expect(find.text('🏁 READY / LOBBY'), findsOneWidget);
      expect(find.text('Start Game'), findsOneWidget);

      // Tap 'Start Game' inside the Manual Host Console modal
      await tester.tap(find.text('Start Game'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(engine.isPreGameCountdownActive, isTrue);

      // Fast-forward through 30s pre-game countdown so Question 1 is broadcast in Manual reading phase
      for (int i = 0; i < 31; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump(const Duration(milliseconds: 600));

      expect(engine.isEngineRunning, isTrue);
      expect(engine.activeQuestion, isNotNull);
      expect(engine.isQuestionTimerRunning, isFalse);
      expect(find.text('📖 READING QUESTION'), findsOneWidget);
      expect(find.text('ROUND 1'), findsOneWidget);
      expect(find.text('Q1 / 10'), findsOneWidget);

      // Tap 'Start Timer' to begin the 20s manual countdown
      await tester.tap(find.text('Start Timer').last);
      await tester.pump(const Duration(milliseconds: 500));
      expect(engine.isQuestionTimerRunning, isTrue);
      expect(find.textContaining('⏱️ TIMER ACTIVE'), findsOneWidget);

      // Tap 'Reveal Answer' to expire timer early and reveal the correct option
      await tester.tap(find.text('Reveal Answer').last);
      await tester.pump(const Duration(milliseconds: 500));
      expect(engine.isReviewPhase, isTrue);
      expect(find.text('💡 ANSWER REVEALED'), findsOneWidget);
      expect(find.text('ADVANCE TO NEXT QUESTION ➔ (Q2)'), findsOneWidget);

      // Tap 'ADVANCE TO NEXT QUESTION ➔ (Q2)' and verify transition to Question 2 reading phase
      await tester.tap(find.text('ADVANCE TO NEXT QUESTION ➔ (Q2)'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(engine.currentQuestionIndex, equals(2));
      expect(engine.isReviewPhase, isFalse);
      expect(engine.isQuestionTimerRunning, isFalse);
      expect(find.text('Q2 / 10'), findsOneWidget);
      expect(find.text('📖 READING QUESTION'), findsOneWidget);

      engine.resetGame(roomCode: 'TRIV', resetMode: 'clear_all');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
