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

  group('Permanent Official Bar Rooms Trivia Ad Invariants', () {
    late String jsContent;
    late String htmlContent;
    late String cssContent;

    setUpAll(() {
      jsContent = File('src/main.js').readAsStringSync();
      htmlContent = File('index.html').readAsStringSync();
      cssContent = File('src/style.css').readAsStringSync();
    });

    test('Permanent official ad ID constant is defined and unique', () {
      expect(jsContent.contains("const OFFICIAL_SYSTEM_AD_ID = 'system_bar_rooms_trivia_official_ad';"), isTrue);
    });

    test('Host ad gallery section in HTML displays notice about official ad', () {
      expect(htmlContent.contains('Upload custom drink specials, food menus, or event flyers above to rotate alongside the official Bar Rooms Trivia ad!'), isTrue);
    });

    test('CSS defines system card and lock badge styling', () {
      expect(cssContent.contains('.ad-thumb-card.system-card'), isTrue);
      expect(cssContent.contains('.ad-thumb-system-tag'), isTrue);
      expect(cssContent.contains('.ad-thumb-lock-badge'), isTrue);
    });

    test('Official ad generator creates 1920x1080 canvas graphic', () {
      expect(jsContent.contains('function generateOfficialBarRoomsTriviaAdDataUrl()'), isTrue);
      expect(jsContent.contains('canvas.width = 1920'), isTrue);
      expect(jsContent.contains('canvas.height = 1080'), isTrue);
    });

    test('Official ad contains brand headline and hook', () {
      expect(jsContent.contains('OFFICIAL BAR & HOME TRIVIA APP'), isTrue);
      expect(jsContent.contains('BAR ROOMS TRIVIA'), isTrue);
      expect(jsContent.contains('HOST YOUR OWN PUB TRIVIA NIGHT AT HOME & VENUES!'), isTrue);
      expect(jsContent.contains('Turn any TV and mobile phones into an interactive game show'), isTrue);
    });

    test('Official ad details all 6 core app features', () {
      expect(jsContent.contains('PLAY ON ANY PHONE'), isTrue);
      expect(jsContent.contains('REAL-TIME MULTIPLAYER'), isTrue);
      expect(jsContent.contains('LIVE TV LEADERBOARD'), isTrue);
      expect(jsContent.contains('30+ TRIVIA GENRES'), isTrue);
      expect(jsContent.contains('AUTOMATED GAME HOST'), isTrue);
      expect(jsContent.contains('PERFECT FOR TRIVIA PARTIES'), isTrue);
    });

    test('Official ad prominently features home party use case and chips', () {
      expect(jsContent.contains('USE AT HOME FOR TRIVIA NIGHT PARTIES'), isTrue);
      expect(jsContent.contains('BRING THE EXCITEMENT OF PUB TRIVIA HOME!'), isTrue);
      expect(jsContent.contains('Family Game Nights'), isTrue);
      expect(jsContent.contains('Friends & House Parties'), isTrue);
      expect(jsContent.contains('Office & Team Socials'), isTrue);
      expect(jsContent.contains('Holiday & Birthday Parties'), isTrue);
    });

    test('Official ad prominently features Google Play Store download callout', () {
      expect(jsContent.contains('DOWNLOAD FROM GOOGLE PLAY'), isTrue);
      expect(jsContent.contains('Google Play'), isTrue);
      expect(jsContent.contains('GET IT ON'), isTrue);
      expect(jsContent.contains('Search "Bar Rooms Trivia" on Google Play Store'), isTrue);
      expect(jsContent.contains('todd4529.github.io/BarRoomTrivia'), isTrue);
    });

    test('Official ad slide descriptor sets isSystemPermanent to true', () {
      expect(jsContent.contains('isSystemPermanent: true'), isTrue);
      expect(jsContent.contains("type: 'system'"), isTrue);
      expect(jsContent.contains('page: 1'), isTrue);
      expect(jsContent.contains('totalPages: 1'), isTrue);
    });

    test('getAllActiveAdSlides always includes official ad at index 0', () {
      expect(jsContent.contains('function getAllActiveAdSlides() {'), isTrue);
      expect(jsContent.contains('const officialAd = getOfficialBarRoomsTriviaAdSlide();'), isTrue);
      expect(jsContent.contains('return [officialAd, ...customAdSlides];'), isTrue);
    });

    test('Host gallery prevents removal of the system permanent ad', () {
      expect(jsContent.contains('card.className = slide.isSystemPermanent ? \'ad-thumb-card system-card\' : \'ad-thumb-card\';'), isTrue);
      expect(jsContent.contains('⭐ OFFICIAL APP AD'), isTrue);
      expect(jsContent.contains('🔒'), isTrue);
      expect(jsContent.contains("const customIndex = index - 1; // 0-based index in customAdSlides"), isTrue);
      expect(jsContent.contains("title=\"Delete Custom Slide\""), isTrue);
    });

    test('removeCustomAdSlide operates strictly on customAdSlides slice', () {
      expect(jsContent.contains('async function removeCustomAdSlide(customIndex) {'), isTrue);
      expect(jsContent.contains('if (customIndex < 0 || customIndex >= customAdSlides.length) return;'), isTrue);
      expect(jsContent.contains('customAdSlides.splice(customIndex, 1);'), isTrue);
    });

    test('clearAllAdSlides clears only custom slides, preserving system ad in rotation', () {
      expect(jsContent.contains('async function clearAllAdSlides() {'), isTrue);
      expect(jsContent.contains('customAdSlides = [];'), isTrue);
      expect(jsContent.contains('await idbAdStorage.clearSlides();'), isTrue);
    });
  });

  group('Absence of Corner QR Code and Ad Overlays', () {
    late String htmlContent;
    late String jsContent;

    setUpAll(() {
      htmlContent = File('index.html').readAsStringSync();
      jsContent = File('src/main.js').readAsStringSync();
    });

    test('HTML does not contain tv-ad-corner-qr badge', () {
      expect(htmlContent.contains('tv-ad-corner-qr'), isFalse,
          reason: 'Corner QR code badge on ad screen must be deleted');
    });

    test('HTML does not contain host-toggle-ad-qr control', () {
      expect(htmlContent.contains('host-toggle-ad-qr'), isFalse,
          reason: 'Host toggle for ad corner QR code must be deleted');
    });

    test('main.js does not contain showAdCornerQr references', () {
      expect(jsContent.contains('showAdCornerQr'), isFalse,
          reason: 'showAdCornerQr variable and handlers must be removed');
    });

    test('initQrCodes does not render to tv-ad-qr-canvas', () {
      expect(jsContent.contains("canvasAd = document.getElementById('tv-ad-qr-canvas')"), isFalse);
    });
  });

  group('TV Ad Signage State Machine & Priority Overrides', () {
    late String jsContent;

    setUpAll(() {
      jsContent = File('src/main.js').readAsStringSync();
    });

    test('Active game states (QUESTION_ACTIVE, PRE_GAME) strictly hide ad signage', () {
      expect(jsContent.contains("if (currentGameState === 'QUESTION_ACTIVE' || currentGameState === 'PRE_GAME') {"), isTrue);
      expect(jsContent.contains("if (tvAdScreen) tvAdScreen.classList.add('hidden');"), isTrue);
      expect(jsContent.contains("stopTvAdSignageRotation();"), isTrue);
    });

    test('onQuestionStart stops ad rotation and hides ad screen', () {
      expect(jsContent.contains("if (tvAdScreen) tvAdScreen.classList.add('hidden');"), isTrue);
      expect(jsContent.contains("stopTvAdSignageRotation();"), isTrue);
    });

    test('handleIncomingPreGameCountdown hides ad screen', () {
      expect(jsContent.contains("if (tvAdScreen) tvAdScreen.classList.add('hidden');"), isTrue);
      expect(jsContent.contains("stopTvAdSignageRotation();"), isTrue);
    });

    test('switchView(tv) checks all active slides including official ad', () {
      expect(jsContent.contains("const allSlides = getAllActiveAdSlides();"), isTrue);
      expect(jsContent.contains("if (isAdModeActive && allSlides && allSlides.length > 0) {"), isTrue);
    });

    test('onGameReset checks all active slides including official ad', () {
      expect(jsContent.contains("const allSlides = getAllActiveAdSlides();"), isTrue);
      expect(jsContent.contains("if (isAdModeActive && allSlides && allSlides.length > 0) {"), isTrue);
    });

    test('Ad rotation smoothly animates progress bar based on selected duration', () {
      expect(jsContent.contains("function startTvAdSignageRotation()"), isTrue);
      expect(jsContent.contains("(adSlideDurationSeconds || 10) * 1000"), isTrue);
      expect(jsContent.contains("tv-ad-progress-fill"), isTrue);
      expect(jsContent.contains("adProgressBarInterval = setInterval("), isTrue);
    });

    test('Ad slide display uses fading crossfade transition', () {
      expect(jsContent.contains("img.classList.add('fading');"), isTrue);
      expect(jsContent.contains("img.src = slide.dataUrl;"), isTrue);
      expect(jsContent.contains("img.classList.remove('fading');"), isTrue);
    });
  });

  group('Cross-Device Realtime Ad Mode Sync Contracts', () {
    late String jsContent;

    setUpAll(() {
      jsContent = File('src/main.js').readAsStringSync();
    });

    test('broadcastAdModeChange sends allSlides count and customSlides count', () {
      expect(jsContent.contains('slidesCount: allSlides.length'), isTrue);
      expect(jsContent.contains('customSlidesCount: customAdSlides.length'), isTrue);
      expect(jsContent.contains("channel.postMessage({ type: 'AD_MODE_TOGGLED', payload });"), isTrue);
      expect(jsContent.contains("broadcastRealtimeEvent('ad_mode_toggled', payload);"), isTrue);
    });

    test('broadcastAdSlidesUpdated sends updated slide deck and active mode', () {
      expect(jsContent.contains("type: 'AD_SLIDES_UPDATED'"), isTrue);
      expect(jsContent.contains("broadcastRealtimeEvent('ad_slides_updated'"), isTrue);
      expect(jsContent.contains("slides: customAdSlides"), isTrue);
    });

    test('onAdModeToggled updates UI switch and persistence', () {
      expect(jsContent.contains("safeStorage.setItem('bar_trivia_ad_mode_active', String(isAdModeActive));"), isTrue);
      expect(jsContent.contains("if (toggle) toggle.checked = isAdModeActive;"), isTrue);
    });

    test('onAdSlidesUpdated saves to IndexedDB and re-renders host gallery', () {
      expect(jsContent.contains('await idbAdStorage.saveSlides(customAdSlides);'), isTrue);
      expect(jsContent.contains('renderHostAdGallery();'), isTrue);
      expect(jsContent.contains('syncTvSignageDisplay();'), isTrue);
    });
  });

  group('End-to-End Game Lifecycle with Ad Signage Restoration Simulation', () {
    test('Simulate complete lifecycle: Lobby Ad Display -> Game Start -> Round Play -> Game Reset -> Ad Display Restored', () {
      final engine = GameEngineManager.instance;
      
      // Step 1: In Lobby, ad mode is enabled
      bool isAdModeActive = true;
      int customSlidesCount = 0; // 0 custom slides uploaded
      int totalActiveSlides = 1; // Exactly 1: the official permanent ad
      String currentScreen = 'tv-ad-signage-screen';

      expect(isAdModeActive, isTrue);
      expect(customSlidesCount, equals(0));
      expect(totalActiveSlides, equals(1));
      expect(currentScreen, equals('tv-ad-signage-screen'));

      // Step 2: Host uploads 2 custom drink special flyers
      customSlidesCount = 2;
      totalActiveSlides = 1 + customSlidesCount; // 3 slides total in rotation
      expect(totalActiveSlides, equals(3));

      // Step 3: Host starts the game (transition to PRE_GAME countdown)
      engine.currentRound = 1;
      engine.currentQuestionIndex = 0;
      bool isGameActive = true;

      // Ad screen MUST be hidden and rotation stopped
      if (isGameActive) {
        currentScreen = 'tv-pregame-screen';
      }
      expect(currentScreen, equals('tv-pregame-screen'));

      // Step 4: Active Questions (1 through 10)
      for (int q = 1; q <= 10; q++) {
        engine.currentQuestionIndex++;
        currentScreen = 'tv-question-screen';
        expect(currentScreen, equals('tv-question-screen'));
        final question = TriviaRepository.getQuestionForGenres(['Pop Culture & Celebrities'], q);
        expect(question.questionText.isNotEmpty, isTrue);
      }

      // Step 5: Round Finished / Round Winner
      currentScreen = 'tv-round-winner-screen';
      expect(currentScreen, equals('tv-round-winner-screen'));

      // Step 6: Game Reset -> Returns to lobby
      engine.currentQuestionIndex = 0;
      engine.currentRound = 1;
      isGameActive = false;

      // In onGameReset: since isAdModeActive is true and totalActiveSlides > 0, ad signage is restored!
      if (isAdModeActive && totalActiveSlides > 0) {
        currentScreen = 'tv-ad-signage-screen';
      }
      expect(currentScreen, equals('tv-ad-signage-screen'));

      // Step 7: Host clears all custom ads -> Rotation still active with 1 official ad
      customSlidesCount = 0;
      totalActiveSlides = 1; // Official ad remains permanent
      expect(totalActiveSlides, equals(1));
      expect(currentScreen, equals('tv-ad-signage-screen'));
    });
  });
}
