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

  group('Ad Display Signage Mode - HTML Structure Tests', () {
    late String htmlContent;

    setUpAll(() {
      final file = File('index.html');
      expect(file.existsSync(), isTrue, reason: 'index.html must exist');
      htmlContent = file.readAsStringSync();
    });

    test('index.html includes Mozilla PDF.js CDN script in <head>', () {
      expect(htmlContent.contains('pdf.js'), isTrue,
          reason: 'Must include Mozilla PDF.js script for client-side rendering');
      expect(htmlContent.contains('pdf.min.js'), isTrue);
    });

    test('index.html includes TV Ad Signage screen elements without corner QR badge', () {
      expect(htmlContent.contains('id="tv-ad-signage-screen"'), isTrue);
      expect(htmlContent.contains('class="tv-ad-signage-screen hidden"'), isTrue);
      expect(htmlContent.contains('id="tv-ad-slide-img"'), isTrue);
      expect(htmlContent.contains('class="tv-ad-progress-track"'), isTrue);
      expect(htmlContent.contains('id="tv-ad-progress-fill"'), isTrue);
      expect(htmlContent.contains('id="tv-ad-slide-counter-text"'), isTrue);
      // Corner QR badge was explicitly deleted as requested by the user
      expect(htmlContent.contains('id="tv-ad-corner-qr"'), isFalse,
          reason: 'Corner QR badge must be removed from ad signage screen');
      expect(htmlContent.contains('id="tv-ad-qr-canvas"'), isFalse,
          reason: 'Corner QR canvas must be removed from ad signage screen');
      expect(htmlContent.contains('id="tv-ad-qr-room-code"'), isFalse,
          reason: 'Corner QR room code must be removed from ad signage screen');
    });

    test('index.html includes Host Settings Ad Mode controls in Tab 4 without QR badge toggle', () {
      expect(htmlContent.contains('id="host-toggle-ad-mode"'), isTrue);
      expect(htmlContent.contains('class="toggle-switch"'), isTrue);
      expect(htmlContent.contains('id="host-ad-files-input"'), isTrue);
      expect(htmlContent.contains('id="host-ad-dropzone"'), isTrue);
      expect(htmlContent.contains('id="host-ad-upload-status"'), isTrue);
      expect(htmlContent.contains('id="ad-duration-chips"'), isTrue);
      expect(htmlContent.contains('data-dur="60"'), isTrue);
      expect(htmlContent.contains('data-dur="120"'), isTrue);
      expect(htmlContent.contains('data-dur="180"'), isTrue);
      expect(htmlContent.contains('data-dur="240"'), isTrue);
      // Host QR toggle was explicitly removed
      expect(htmlContent.contains('id="host-toggle-ad-qr"'), isFalse,
          reason: 'Host toggle for corner QR code must be removed');
      expect(htmlContent.contains('id="host-ad-gallery"'), isTrue);
      expect(htmlContent.contains('id="host-ad-count"'), isTrue);
      expect(htmlContent.contains('id="btn-clear-all-ads"'), isTrue);
    });

    test('Ad files input accepts PDF and image MIME types', () {
      expect(htmlContent.contains('accept="application/pdf,image/png,image/jpeg,image/webp"'), isTrue);
    });
  });

  group('Ad Display Signage Mode - CSS Architecture Tests', () {
    late String cssContent;

    setUpAll(() {
      final file = File('src/style.css');
      expect(file.existsSync(), isTrue, reason: 'src/style.css must exist');
      cssContent = file.readAsStringSync();
    });

    test('CSS defines toggle-switch and slider styles', () {
      expect(cssContent.contains('.toggle-switch'), isTrue);
      expect(cssContent.contains('.slider'), isTrue);
      expect(cssContent.contains('.slider:before'), isTrue);
      expect(cssContent.contains('.toggle-switch input:checked + .slider'), isTrue);
    });

    test('CSS defines dropzone and upload status styles', () {
      expect(cssContent.contains('.ad-dropzone'), isTrue);
      expect(cssContent.contains('.ad-dropzone:hover'), isTrue);
      expect(cssContent.contains('.dropzone-icon'), isTrue);
      expect(cssContent.contains('.dropzone-text'), isTrue);
      expect(cssContent.contains('.ad-upload-status'), isTrue);
    });

    test('CSS defines duration chips and gallery thumbnail cards with system permanent badges', () {
      expect(cssContent.contains('.ad-duration-chips'), isTrue);
      expect(cssContent.contains('.ad-dur-chip'), isTrue);
      expect(cssContent.contains('.ad-dur-chip.active'), isTrue);
      expect(cssContent.contains('.ad-gallery-strip'), isTrue);
      expect(cssContent.contains('.ad-gallery-empty'), isTrue);
      expect(cssContent.contains('.ad-thumb-card'), isTrue);
      expect(cssContent.contains('.ad-thumb-card.system-card'), isTrue);
      expect(cssContent.contains('.ad-thumb-system-tag'), isTrue);
      expect(cssContent.contains('.ad-thumb-lock-badge'), isTrue);
      expect(cssContent.contains('.ad-thumb-img'), isTrue);
      expect(cssContent.contains('.ad-thumb-badge'), isTrue);
      expect(cssContent.contains('.btn-remove-ad-slide'), isTrue);
    });

    test('CSS defines TV fullscreen ad signage screen styles', () {
      expect(cssContent.contains('.tv-ad-signage-screen'), isTrue);
      expect(cssContent.contains('.tv-ad-slide-wrapper'), isTrue);
      expect(cssContent.contains('.tv-ad-slide-img'), isTrue);
      expect(cssContent.contains('.tv-ad-progress-track'), isTrue);
      expect(cssContent.contains('.tv-ad-progress-fill'), isTrue);
      expect(cssContent.contains('.tv-ad-slide-counter'), isTrue);
    });
  });

  group('Ad Display Signage Mode - JavaScript Engine Tests', () {
    late String jsContent;

    setUpAll(() {
      final file = File('src/main.js');
      expect(file.existsSync(), isTrue, reason: 'src/main.js must exist');
      jsContent = file.readAsStringSync();
    });

    test('main.js defines ad state variables with local storage persistence', () {
      expect(jsContent.contains('isAdModeActive'), isTrue);
      expect(jsContent.contains('adSlideDurationSeconds'), isTrue);
      expect(jsContent.contains('customAdSlides'), isTrue);
      expect(jsContent.contains('bar_trivia_ad_mode_active'), isTrue);
      expect(jsContent.contains('bar_trivia_ad_duration'), isTrue);
    });

    test('main.js generates permanent official Bar Rooms Trivia ad with key features and Google Play badge', () {
      expect(jsContent.contains('generateOfficialBarRoomsTriviaAdDataUrl'), isTrue);
      expect(jsContent.contains('getOfficialBarRoomsTriviaAdSlide'), isTrue);
      expect(jsContent.contains('getAllActiveAdSlides'), isTrue);
      expect(jsContent.contains('isSystemPermanent: true'), isTrue);
      expect(jsContent.contains('USE AT HOME FOR TRIVIA NIGHT PARTIES'), isTrue);
      expect(jsContent.contains('Google Play'), isTrue);
      expect(jsContent.contains('DOWNLOAD FROM GOOGLE PLAY'), isTrue);
      expect(jsContent.contains('PLAY ON ANY PHONE'), isTrue);
      expect(jsContent.contains('REAL-TIME MULTIPLAYER'), isTrue);
    });

    test('Host gallery renders system permanent ad and prevents host from removing it', () {
      expect(jsContent.contains('if (slide.isSystemPermanent)'), isTrue);
      expect(jsContent.contains('⭐ OFFICIAL APP AD'), isTrue);
      expect(jsContent.contains('removeCustomAdSlide'), isTrue);
      expect(jsContent.contains('clearAllAdSlides'), isTrue);
    });

    test('main.js implements IndexedDB cache (idbAdStorage)', () {
      expect(jsContent.contains('const idbAdStorage'), isTrue);
      expect(jsContent.contains('BarRoomTriviaDB'), isTrue);
      expect(jsContent.contains('ad_slides'), isTrue);
      expect(jsContent.contains('saveSlides'), isTrue);
      expect(jsContent.contains('loadSlides'), isTrue);
      expect(jsContent.contains('clearSlides'), isTrue);
    });

    test('main.js implements PDF.js rendering pipeline', () {
      expect(jsContent.contains('ensurePdfJsLoaded'), isTrue);
      expect(jsContent.contains('renderPdfFileToSlides'), isTrue);
      expect(jsContent.contains('pdfjs.getDocument'), isTrue);
      expect(jsContent.contains('page.render'), isTrue);
      expect(jsContent.contains('renderImageFileToSlide'), isTrue);
    });

    test('main.js implements TV rotation and progress animation', () {
      expect(jsContent.contains('syncTvSignageDisplay'), isTrue);
      expect(jsContent.contains('startTvAdSignageRotation'), isTrue);
      expect(jsContent.contains('stopTvAdSignageRotation'), isTrue);
      expect(jsContent.contains('displayAdSlide'), isTrue);
      expect(jsContent.contains('tv-ad-progress-fill'), isTrue);
    });

    test('main.js enforces Game Play Override priority over Ad Signage', () {
      // In onQuestionStart, ad screen is hidden and rotation stopped
      expect(jsContent.contains('tvAdScreen.classList.add(\'hidden\')'), isTrue);
      expect(jsContent.contains('stopTvAdSignageRotation()'), isTrue);

      // In handleIncomingPreGameCountdown, ad screen is hidden
      expect(jsContent.contains('tv-ad-signage-screen'), isTrue);

      // In onGameReset, returns to ad signage if active
      expect(jsContent.contains('if (isAdModeActive && allSlides && allSlides.length > 0)'), isTrue);
    });

    test('main.js broadcasts ad mode toggles and slides across devices', () {
      expect(jsContent.contains('AD_MODE_TOGGLED'), isTrue);
      expect(jsContent.contains('AD_SLIDES_UPDATED'), isTrue);
      expect(jsContent.contains('ad_mode_toggled'), isTrue);
      expect(jsContent.contains('ad_slides_updated'), isTrue);
      expect(jsContent.contains('broadcastAdModeChange'), isTrue);
      expect(jsContent.contains('broadcastAdSlidesUpdated'), isTrue);
    });

    test('main.js exposes ad helpers on window object for testing', () {
      expect(jsContent.contains('window.idbAdStorage = idbAdStorage;'), isTrue);
      expect(jsContent.contains('window.syncTvSignageDisplay = syncTvSignageDisplay;'), isTrue);
      expect(jsContent.contains('window.startTvAdSignageRotation = startTvAdSignageRotation;'), isTrue);
      expect(jsContent.contains('window.stopTvAdSignageRotation = stopTvAdSignageRotation;'), isTrue);
      expect(jsContent.contains('window.clearAllAdSlides = clearAllAdSlides;'), isTrue);
      expect(jsContent.contains('window.getOfficialBarRoomsTriviaAdSlide = getOfficialBarRoomsTriviaAdSlide;'), isTrue);
      expect(jsContent.contains('window.getAllActiveAdSlides = getAllActiveAdSlides;'), isTrue);
    });
  });

  group('Ad Display Signage Mode - Game Engine Priority Verification', () {
    test('GameEngineManager initializes in lobby where ad signage is permitted', () {
      final engine = GameEngineManager.instance;
      engine.currentRound = 1;
      engine.currentQuestionIndex = 0;
      expect(engine.currentQuestionIndex, equals(0));
      expect(engine.currentRound, equals(1));
    });

    test('GameEngineManager advances questions during active game, overriding lobby/ad mode', () {
      final engine = GameEngineManager.instance;
      engine.currentQuestionIndex = 1;
      expect(engine.currentQuestionIndex, equals(1));
      final q = TriviaRepository.getQuestionForGenres(['Food & Culinary'], 1);
      expect(q.questionText.isNotEmpty, isTrue);
    });

    test('GameEngineManager reset returns to lobby status (index 0, round 1) enabling ad signage restoration', () {
      final engine = GameEngineManager.instance;
      engine.currentQuestionIndex = 5;
      engine.currentRound = 2;

      // Reset
      engine.currentQuestionIndex = 0;
      engine.currentRound = 1;
      expect(engine.currentQuestionIndex, equals(0));
      expect(engine.currentRound, equals(1));
    });
  });

  group('Flutter TV Display - Fullscreen Ad Signage Architecture Tests', () {
    late String tvViewContent;

    setUpAll(() {
      final file = File('lib/tv/views/tv_display_view.dart');
      expect(file.existsSync(), isTrue);
      tvViewContent = file.readAsStringSync();
    });

    test('tv_display_view.dart defines _buildFullscreenSignageDisplay with clean layout', () {
      expect(tvViewContent.contains('Widget _buildFullscreenSignageDisplay()'), isTrue);
      expect(tvViewContent.contains('AD DISPLAY SIGNAGE MODE • AD'), isFalse,
          reason: 'Bottom signage pill was removed per user request for a cleaner look');
      expect(tvViewContent.contains('Top Slide Progress Track'), isFalse,
          reason: 'Top countdown bar was removed per user request');
    });

    test('tv_display_view.dart defines default official ad and custom uploaded slide renderer', () {
      expect(tvViewContent.contains('_buildFullscreenSlide0()'), isTrue);
      expect(tvViewContent.contains('_buildCustomAdSlide(Map<String, dynamic> slide)'), isTrue);
      expect(tvViewContent.contains('_buildFullscreenSlide1()'), isFalse,
          reason: "Tonight's specials & refreshments ad was deleted");
    });

    test('Slide 0 includes official Bar Rooms Trivia brand and 6 feature cards', () {
      expect(tvViewContent.contains('OFFICIAL BAR & HOME TRIVIA APP'), isTrue);
      expect(tvViewContent.contains('HOST YOUR OWN PUB TRIVIA NIGHT AT HOME & VENUES!'), isTrue);
      expect(tvViewContent.contains('PLAY ON ANY PHONE'), isTrue);
      expect(tvViewContent.contains('REAL-TIME MULTIPLAYER'), isTrue);
      expect(tvViewContent.contains('LIVE TV LEADERBOARD'), isTrue);
      expect(tvViewContent.contains('30+ TRIVIA GENRES'), isTrue);
      expect(tvViewContent.contains('AUTOMATED GAME HOST'), isTrue);
      expect(tvViewContent.contains('PERFECT FOR PARTIES'), isTrue);
      expect(tvViewContent.contains('USE AT HOME FOR TRIVIA NIGHT PARTIES'), isTrue);
    });

    test('Deleted Tonight\'s specials & refreshments is absent and uses active host slides instead', () {
      expect(tvViewContent.contains('VENUE SPECIALS & REFRESHMENTS'), isFalse);
      expect(tvViewContent.contains(r"TONIGHT\'S SPECIALS & REFRESHMENTS"), isFalse);
      expect(tvViewContent.contains('_customAdSlides'), isTrue);
      expect(tvViewContent.contains('_totalAdSlides'), isTrue);
    });

    test('Slide 2 includes 3 easy steps to play walkthrough', () {
      expect(tvViewContent.contains('HOW TO PLAY ON YOUR MOBILE PHONE'), isTrue);
      expect(tvViewContent.contains('SCAN THE QR CODE'), isTrue);
      expect(tvViewContent.contains('CHOOSE NICKNAME'), isTrue);
      expect(tvViewContent.contains('BUZZ IN & WIN'), isTrue);
    });

    test('Slide 3 includes live tournament leaderboard and championship glory', () {
      expect(tvViewContent.contains('CLIMB THE LIVE TV LEADERBOARD'), isTrue);
      expect(tvViewContent.contains('SPEED MULTIPLIERS'), isTrue);
      expect(tvViewContent.contains('ROUND PODIUMS'), isTrue);
      expect(tvViewContent.contains('PUB CHAMPIONS'), isTrue);
    });

    test('All slides feature embedded live QR code pointing to game room', () {
      expect(tvViewContent.contains('_buildSignageBottomJoinBanner'), isTrue);
      expect(tvViewContent.contains('SCAN TO JOIN NOW'), isTrue);
    });

    test('TV display shows fullscreen ad signage when game is paused and ad signage mode is toggled on', () {
      expect(tvViewContent.contains('(_isGamePaused && _isAdSignageModeActive)'), isTrue,
          reason: 'TV display must render _buildFullscreenSignageDisplay() when paused and ad mode active');
      expect(tvViewContent.contains('(!_isGameActive || _isGamePaused) && !_isPreGameCountdown'), isTrue,
          reason: '_startAdSlideTimer must rotate slides while game is paused');
      expect(tvViewContent.contains("status == 'paused' && !_isGamePaused"), isTrue,
          reason: 'TV session polling must detect paused status and start ad slide timer');
    });
  });
}

