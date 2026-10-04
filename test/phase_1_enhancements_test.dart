import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  group('Phase 1 - Privacy Policy & Terms Compliance Tests', () {
    late String privacyHtml;
    late String termsHtml;

    setUpAll(() {
      final privacyFile = File('privacy.html');
      expect(privacyFile.existsSync(), isTrue, reason: 'privacy.html must exist in root');
      privacyHtml = privacyFile.readAsStringSync();

      final termsFile = File('terms.html');
      expect(termsFile.existsSync(), isTrue, reason: 'terms.html must exist in root');
      termsHtml = termsFile.readAsStringSync();

      expect(File('dist/privacy.html').existsSync(), isTrue, reason: 'privacy.html must be in dist for GitHub Pages');
      expect(File('dist/terms.html').existsSync(), isTrue, reason: 'terms.html must be in dist for GitHub Pages');
    });

    test('privacy.html covers Google Play mandatory Data Safety clauses', () {
      expect(privacyHtml.contains('Privacy Policy for Bar Rooms Trivia'), isTrue);
      expect(privacyHtml.contains('Zero Personal Data Sold'), isTrue);
      expect(privacyHtml.contains('Camera Access'), isTrue);
      expect(privacyHtml.contains('No video feeds or images are ever recorded, stored, or uploaded'), isTrue);
      expect(privacyHtml.contains('Local Storage'), isTrue);
      expect(privacyHtml.contains('Supabase'), isTrue);
      expect(privacyHtml.contains('Children\'s Privacy'), isTrue);
      expect(privacyHtml.contains('todd4529@yahoo.com'), isTrue);
    });

    test('terms.html defines user-uploaded signage and entertainment license', () {
      expect(termsHtml.contains('Terms of Service for Bar Rooms Trivia'), isTrue);
      expect(termsHtml.contains('User-Uploaded Content & Venue Signage'), isTrue);
      expect(termsHtml.contains('Limitation of Liability'), isTrue);
      expect(termsHtml.contains('todd4529@yahoo.com'), isTrue);
    });
  });

  group('Phase 1 - UI & Host Controls Integration Tests', () {
    late String htmlContent;
    late String cssContent;

    setUpAll(() {
      htmlContent = File('index.html').readAsStringSync();
      cssContent = File('src/style.css').readAsStringSync();
    });

    test('index.html contains global network resilience status banner', () {
      expect(htmlContent.contains('id="network-status-banner"'), isTrue);
      expect(htmlContent.contains('class="network-status-banner hidden"'), isTrue);
      expect(htmlContent.contains('id="network-status-text"'), isTrue);
      expect(htmlContent.contains('class="status-dot"'), isTrue);
    });

    test('index.html contains Game Sound Effects toggle in Host Settings (Tab 4)', () {
      expect(htmlContent.contains('id="host-toggle-sound"'), isTrue);
      expect(htmlContent.contains('GAME SOUND EFFECTS'), isTrue);
      expect(htmlContent.contains('Synthesized audio cues for countdown timer, buzzers & winner fanfares'), isTrue);
    });

    test('index.html contains About & Legal section linking to privacy and terms', () {
      expect(htmlContent.contains('ABOUT & LEGAL'), isTrue);
      expect(htmlContent.contains('href="privacy.html"'), isTrue);
      expect(htmlContent.contains('href="terms.html"'), isTrue);
      expect(htmlContent.contains('Privacy Policy'), isTrue);
      expect(htmlContent.contains('Terms of Service'), isTrue);
    });

    test('CSS defines network status banner animations and state classes', () {
      expect(cssContent.contains('.network-status-banner'), isTrue);
      expect(cssContent.contains('.network-status-banner.hidden'), isTrue);
      expect(cssContent.contains('.network-status-banner.offline'), isTrue);
      expect(cssContent.contains('.network-status-banner.reconnecting'), isTrue);
      expect(cssContent.contains('.network-status-banner.connected'), isTrue);
      expect(cssContent.contains('@keyframes pulseDot'), isTrue);
    });
  });

  group('Phase 1 - Web Audio API Sound Engine & Haptics Tests', () {
    late String jsContent;

    setUpAll(() {
      jsContent = File('src/main.js').readAsStringSync();
    });

    test('main.js defines audio context, unlocker, and sound enabled state', () {
      expect(jsContent.contains('function getAudioContext()'), isTrue);
      expect(jsContent.contains('function unlockAudioOnInteraction()'), isTrue);
      expect(jsContent.contains('isSoundEffectsEnabled'), isTrue);
      expect(jsContent.contains('bar_trivia_sound_enabled'), isTrue);
      expect(jsContent.contains('function playSound(type)'), isTrue);
      expect(jsContent.contains('function setSoundEffectsEnabled(enabled, shouldBroadcast = true)'), isTrue);
    });

    test('playSound synthesizes all required sound types (tick, tap, correct, wrong, buzz, fanfare)', () {
      expect(jsContent.contains("if (type === 'tick')"), isTrue);
      expect(jsContent.contains("if (type === 'tap')"), isTrue);
      expect(jsContent.contains("if (type === 'correct')"), isTrue);
      expect(jsContent.contains("if (type === 'wrong')"), isTrue);
      expect(jsContent.contains("if (type === 'buzz')"), isTrue);
      expect(jsContent.contains("if (type === 'fanfare')"), isTrue);
    });

    test('main.js triggers haptic vibration and tap sound on player answer button click', () {
      expect(jsContent.contains("'vibrate' in navigator"), isTrue);
      expect(jsContent.contains("navigator.vibrate(45)"), isTrue);
      expect(jsContent.contains("playSound('tap')"), isTrue);
    });

    test('main.js triggers tick sounds during countdown and buzz on expiration', () {
      expect(jsContent.contains("playSound('tick')"), isTrue);
      expect(jsContent.contains("playSound('buzz')"), isTrue);
    });

    test('main.js triggers correct or wrong sound in onTimerExpired', () {
      expect(jsContent.contains("playSound('correct')"), isTrue);
      expect(jsContent.contains("playSound('wrong')"), isTrue);
    });

    test('main.js triggers victory fanfare sound in onRoundWinner', () {
      expect(jsContent.contains("playSound('fanfare')"), isTrue);
    });

    test('main.js syncs sound preference across broadcast channel and realtime events', () {
      expect(jsContent.contains("SOUND_TOGGLED"), isTrue);
      expect(jsContent.contains("sound_toggled"), isTrue);
    });

    test('main.js implements network status resilience handlers', () {
      expect(jsContent.contains("function showNetworkStatus"), isTrue);
      expect(jsContent.contains("window.addEventListener('online'"), isTrue);
      expect(jsContent.contains("window.addEventListener('offline'"), isTrue);
    });

    test('main.js exposes sound and network functions on window', () {
      expect(jsContent.contains("window.playSound = playSound;"), isTrue);
      expect(jsContent.contains("window.setSoundEffectsEnabled = setSoundEffectsEnabled;"), isTrue);
      expect(jsContent.contains("window.isSoundEffectsEnabled = () => isSoundEffectsEnabled;"), isTrue);
      expect(jsContent.contains("window.showNetworkStatus = showNetworkStatus;"), isTrue);
    });
  });

  group('Phase 1 - Sound Engine Mute Invariant Simulation', () {
    test('Simulate Host muting sound for noisy tavern / bar DJ environment', () {
      bool isSoundEffectsEnabled = true;
      int soundPlaysCount = 0;

      void simulatePlaySound(String type) {
        if (!isSoundEffectsEnabled) return;
        soundPlaysCount++;
      }

      // Step 1: Default ON -> sounds play normally
      simulatePlaySound('tick');
      simulatePlaySound('correct');
      simulatePlaySound('fanfare');
      expect(soundPlaysCount, equals(3));

      // Step 2: Bar Host toggles sound OFF
      isSoundEffectsEnabled = false;

      // Subsequent sound events must be completely suppressed
      simulatePlaySound('tick');
      simulatePlaySound('tick');
      simulatePlaySound('tap');
      simulatePlaySound('wrong');
      simulatePlaySound('buzz');
      simulatePlaySound('fanfare');

      expect(soundPlaysCount, equals(3), reason: 'No new sounds played while muted');

      // Step 3: Home party host toggles sound back ON
      isSoundEffectsEnabled = true;
      simulatePlaySound('correct');
      expect(soundPlaysCount, equals(4), reason: 'Sounds resume when enabled');
    });
  });
}
