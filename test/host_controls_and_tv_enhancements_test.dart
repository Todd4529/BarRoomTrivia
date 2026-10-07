import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Host Controls & TV Enhancements Verification', () {
    late String tvQrAuthContent;
    late String indexHtmlContent;
    late String styleCssContent;
    late String mainJsContent;
    late String tvDisplayContent;
    late String playerControllerContent;

    setUpAll(() {
      tvQrAuthContent = File('lib/auth/tv_qr_auth_view.dart').readAsStringSync();
      indexHtmlContent = File('index.html').readAsStringSync();
      styleCssContent = File('src/style.css').readAsStringSync();
      mainJsContent = File('src/main.js').readAsStringSync();
      tvDisplayContent = File('lib/tv/views/tv_display_view.dart').readAsStringSync();
      playerControllerContent = File('lib/player/views/player_controller_view.dart').readAsStringSync();
    });

    test('1. Host Sign In Required screen has no back arrow IconButton', () {
      expect(tvQrAuthContent.contains('IconButton'), isFalse,
          reason: 'Back arrow IconButton should be removed from TV QR Auth screen');
      expect(tvQrAuthContent.contains('Icons.arrow_back'), isFalse,
          reason: 'Icons.arrow_back should not be present on TV QR Auth screen');
    });

    test('2. Room code TRIV pill moved down one line and difficulty chips are uniform', () {
      // Room pill positioning in style.css
      expect(styleCssContent.contains('flex-direction: column'), isTrue,
          reason: 'host-mobile-navbar should use flex-direction: column to stack title and room code');
      expect(styleCssContent.contains('position: static'), isTrue,
          reason: 'host-room-pill should use static positioning to stay below the title line');

      // Uniform Difficulty Chips Grid
      expect(styleCssContent.contains('grid-template-columns: repeat(4, 1fr)'), isTrue,
          reason: 'difficulty-chips should be a 4-column grid for uniform button widths');
    });

    test('3. Slide display duration has 45s, 60s, and 90s options', () {
      expect(indexHtmlContent.contains('data-dur="45">45s</button>'), isTrue);
      expect(indexHtmlContent.contains('data-dur="60">60s</button>'), isTrue);
      expect(indexHtmlContent.contains('data-dur="90">90s</button>'), isTrue);
    });

    test('4. In-between round duration selector configured with all requested intervals', () {
      expect(indexHtmlContent.contains('IN-BETWEEN ROUND DURATION'), isTrue);
      expect(indexHtmlContent.contains('data-round-dur="30">30s</button>'), isTrue);
      expect(indexHtmlContent.contains('data-round-dur="60">1 Min (Default)</button>'), isTrue);
      expect(indexHtmlContent.contains('data-round-dur="120">2 Min</button>'), isTrue);
      expect(indexHtmlContent.contains('data-round-dur="180">3 Min</button>'), isTrue);
      expect(indexHtmlContent.contains('data-round-dur="240">4 Min</button>'), isTrue);
      expect(indexHtmlContent.contains('data-round-dur="300">5 Min</button>'), isTrue);
      expect(indexHtmlContent.contains('data-round-dur="600">10 Min</button>'), isTrue);

      expect(mainJsContent.contains('selectedInterRoundDuration'), isTrue);
      expect(mainJsContent.contains('inter-round-chip'), isTrue);
    });

    test('5. Host Controls Pause & Resume broadcasts realtime events and toggles state', () {
      expect(mainJsContent.contains("broadcastRealtimeEvent('game_paused'"), isTrue);
      expect(mainJsContent.contains("broadcastRealtimeEvent('game_resuming'"), isTrue);
      expect(mainJsContent.contains("type: 'GAME_PAUSED'"), isTrue);
      expect(mainJsContent.contains("type: 'GAME_RESUMING'"), isTrue);
      expect(mainJsContent.contains("btnPauseText.textContent = 'Resume'"), isTrue);
    });

    test('6. Host Controls Reset broadcasts realtime event and clears sessions', () {
      expect(mainJsContent.contains("broadcastRealtimeEvent('game_reset'"), isTrue);
      expect(mainJsContent.contains("status: 'lobby'"), isTrue);
      expect(mainJsContent.contains("reset_mode: 'clear_all'"), isTrue);
    });

    test('7. Inter-round delay supports up to 10 minutes (660s) and formats countdown cleanly', () {
      expect(playerControllerContent.contains('.clamp(5, 660)'), isTrue,
          reason: 'Player controller must support up to 660s inter-round delay');
      expect(tvDisplayContent.contains('.clamp(5, 660)'), isTrue,
          reason: 'TV display must support up to 660s inter-round delay');
      expect(playerControllerContent.contains('_interRoundSecondsRemaining ~/ 60'), isTrue,
          reason: 'Player controller should format minutes and seconds for inter-round countdown');
    });

    test('8. Ad display signage mode displays when no game is active and toggle is on', () {
      expect(tvDisplayContent.contains('_buildOfficial4PageAdCarousel()'), isTrue);
      expect(mainJsContent.contains('syncTvSignageDisplay()'), isTrue);
      expect(mainJsContent.contains('startTvAdSignageRotation()'), isTrue);
    });

    test('9. Correct answer pop-up has matching format to missed pop-up with emerald text and celebration explosion', () {
      expect(playerControllerContent.contains('CelebrationExplosion()'), isTrue,
          reason: 'Celebration explosion must trigger on correct answer');
      expect(playerControllerContent.contains('CORRECT! YOU GOT IT!'), isTrue,
          reason: 'Headline for correct answer should be formatted');
      expect(playerControllerContent.contains('OOPS! YOU MISSED IT!'), isTrue,
          reason: 'Headline for missed answer should be formatted');
      expect(playerControllerContent.contains('Color(0xFF10B981)'), isTrue,
          reason: 'Emerald green color used for correct answer text and borders');
      expect(playerControllerContent.contains('Colors.redAccent'), isTrue,
          reason: 'Red accent color used for missed answer text and borders');
    });

    test('10. Web client pop-up matches format and triggers celebration confetti explosion', () {
      expect(mainJsContent.contains('CORRECT! YOU GOT IT!'), isTrue);
      expect(mainJsContent.contains('OOPS! YOU MISSED IT!'), isTrue);
      expect(mainJsContent.contains('confetti({'), isTrue);
    });

    test('11. Player view point count and TV display view point count synchronize bidirectionally', () {
      final supabaseServiceContent = File('lib/shared/services/supabase_service.dart').readAsStringSync();
      expect(playerControllerContent.contains('score: _myScore'), isTrue,
          reason: 'Player controller passes true cumulative score to updateLocalPlayerScore');
      expect(supabaseServiceContent.contains('int? score'), isTrue,
          reason: 'updateLocalPlayerScore supports direct score synchronization');
      expect(mainJsContent.contains('currentPlayer.score = topScore'), isTrue,
          reason: 'Web player view synchronizes with incoming leaderboard');
      expect(playerControllerContent.contains('final syncedScore = max(_myScore, incomingScore)'), isTrue,
          reason: 'Flutter player view synchronizes with incoming leaderboard');
    });

    test('12. Countdown timer on player view matches TV display view via epoch timestamp synchronization', () {
      // Flutter Player Controller
      expect(playerControllerContent.contains('_targetTimerEndsAtMs'), isTrue,
          reason: 'Player controller must store target epoch milliseconds');
      expect(playerControllerContent.contains('((_targetTimerEndsAtMs! - now) / 1000).ceil()'), isTrue,
          reason: 'Player countdown ticks must be derived from target epoch');

      // Flutter TV Display
      expect(tvDisplayContent.contains('_targetTimerEndsAtMs'), isTrue,
          reason: 'TV display must store target epoch milliseconds');
      expect(tvDisplayContent.contains('((_targetTimerEndsAtMs! - now) / 1000).ceil()'), isTrue,
          reason: 'TV countdown ticks must be derived from target epoch');

      // Web Client
      expect(mainJsContent.contains('timerEndsAtGlobalMs'), isTrue,
          reason: 'Web client must synchronize against timerEndsAtGlobalMs');
      expect(mainJsContent.contains('Math.ceil((timerEndsAtGlobalMs - Date.now()) / 1000)'), isTrue,
          reason: 'Web countdown must calculate remaining seconds against target epoch');
    });

    test('13. Player locked-in answer choice is preserved during mid-question state synchronization', () {
      expect(playerControllerContent.contains('if (isSameQuestion && _selectedOption != null)'), isTrue,
          reason: 'Flutter player controller must preserve selected option and input lock during question re-broadcast');
      expect(mainJsContent.contains('if (isSameQuestion && playerChoiceSubmitted !== null)'), isTrue,
          reason: 'Web client must preserve player choice and input lock during question re-broadcast');
    });

    test('14. Player view top sticker card displays name, counter, and points, does not scroll out of view and is visible on pop-ups', () {
      // Flutter verification
      expect(playerControllerContent.contains('_buildStickyPlayerHeaderCard'), isTrue,
          reason: 'Flutter player controller must implement _buildStickyPlayerHeaderCard');
      expect(playerControllerContent.contains("key: const Key('sticky-player-header-card')"), isTrue,
          reason: 'Sticky card should have identifying key');
      expect(playerControllerContent.contains('_player!.nickname.toUpperCase()'), isTrue,
          reason: 'Sticky card must display player nickname');
      expect(playerControllerContent.contains(r"'$_myScore PTS'"), isTrue,
          reason: 'Sticky card must display score pill');
      expect(playerControllerContent.contains(r'Round $_currentRound • Question $_questionNumberInRound of 10'), isTrue,
          reason: 'Sticky card must display question counter in round');

      // Web verification
      expect(styleCssContent.contains('position: sticky'), isTrue);
      expect(styleCssContent.contains('.controller-header'), isTrue);
      expect(styleCssContent.contains('z-index: 250'), isTrue,
          reason: 'Web sticker card must have z-index above pop-up backdrops (200)');
      expect(indexHtmlContent.contains('sticker-card'), isTrue,
          reason: 'Web controller header marked as sticker-card');

      // Sticky BAR ROOMS TRIVIA title and logo at very top verification
      expect(playerControllerContent.contains('_buildStickyTopHeader'), isTrue,
          reason: 'Flutter player controller must implement _buildStickyTopHeader');
      expect(playerControllerContent.contains("key: const Key('sticky-player-top-header')"), isTrue,
          reason: 'Sticky top header should have identifying key');
      expect(indexHtmlContent.contains('player-sticky-top-wrap'), isTrue,
          reason: 'Web player view must wrap top brand and sticker card in sticky container');
      expect(styleCssContent.contains('.player-sticky-top-wrap'), isTrue,
          reason: 'Web player sticky top container must be styled in CSS');
    });

    test('15. TV display exit menu features Host Control QR Code recovery option and modal', () {
      // Flutter verification
      expect(tvDisplayContent.contains('_showHostControlQrDialog'), isTrue,
          reason: 'Flutter TV display must implement _showHostControlQrDialog');
      expect(tvDisplayContent.contains('_buildActiveHostQrModal'), isTrue,
          reason: 'Flutter TV display must render active game host QR code modal');
      expect(tvDisplayContent.contains('_buildNoActiveGameModal'), isTrue,
          reason: 'Flutter TV display must render no-active-game modal when room is empty');
      expect(tvDisplayContent.contains('HOST CONTROL QR CODE'), isTrue,
          reason: 'Exit dialog must have button for Host Control QR Code');
      expect(tvDisplayContent.contains('NO CURRENT GAME RUNNING'), isTrue,
          reason: 'Modal must inform user when no active game is running');

      // Web verification
      expect(indexHtmlContent.contains('id="btn-tv-show-host-qr"'), isTrue,
          reason: 'Web TV exit dialog must include Host Control QR Code button');
      expect(indexHtmlContent.contains('id="tv-host-qr-modal-overlay"'), isTrue,
          reason: 'Web TV must include host QR modal overlay container');
      expect(mainJsContent.contains('initTvExitAndRecoveryMenu'), isTrue,
          reason: 'Web client must initialize TV exit and recovery menu');
    });

    test('16. TV display sound engine features bulletproof unlock, countdown ticks, and timer expiry alert', () {
      // Flutter verification
      expect(tvDisplayContent.contains('SystemSound.play(SystemSoundType.click)'), isTrue,
          reason: 'Flutter TV display must trigger click sound on question start and countdown ticks');
      expect(tvDisplayContent.contains('SystemSound.play(SystemSoundType.alert)'), isTrue,
          reason: 'Flutter TV display must trigger alert sound when timer expires');
      expect(tvDisplayContent.contains('_lastTickedSecond'), isTrue,
          reason: 'Flutter TV display must track last ticked second to prevent multiple ticks');

      // Web Web Audio API verification
      expect(mainJsContent.contains('unlockAudioContext'), isTrue,
          reason: 'Web audio engine must implement unlockAudioContext');
      expect(mainJsContent.contains('unlockAudioOnInteraction'), isTrue,
          reason: 'Web client must unlock AudioContext on user interaction');
      expect(mainJsContent.contains("playSound('tick')"), isTrue,
          reason: 'Web client must trigger tick sound during countdown');
      expect(mainJsContent.contains("playSound('buzz')"), isTrue,
          reason: 'Web client must trigger buzzer sound on timer expiration');
      expect(mainJsContent.contains("playSound('question_start')"), isTrue,
          reason: 'Web client must trigger question start stinger sound');
      expect(mainJsContent.contains('linearRampToValueAtTime'), isTrue,
          reason: 'Web client must use stable linear ramps to prevent IndexSizeError');
    });
  });
}
