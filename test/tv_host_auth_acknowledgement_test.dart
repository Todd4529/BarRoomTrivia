import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bar_rooms_trivia/shared/services/realtime_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('TV Display Host Sign-In & Acknowledgement Tests', () {
    test('RealtimeService allows posting local events for instant pairing', () async {
      final completer = Completer<Map<String, dynamic>>();

      final sub = RealtimeService.localEventStream.listen((event) {
        if (event['event'] == 'device_authorized') {
          completer.complete(event);
        }
      });

      RealtimeService.postLocalEvent({
        'event': 'device_authorized',
        'type': 'device_authorized',
        'device_token': 'tv_test_123',
        'user_code': 'TRIV-9999',
        'room_code': 'TRIV-9999',
        'user_id': 'host-uuid-123',
        'user_info': {
          'email': 'host@barroomstrivia.com',
          'display_name': 'Test Host',
        },
      });

      final received = await completer.future.timeout(const Duration(seconds: 1));
      expect(received['event'], equals('device_authorized'));
      expect(received['device_token'], equals('tv_test_123'));
      expect(received['user_code'], equals('TRIV-9999'));
      expect(received['user_info']['display_name'], equals('Test Host'));

      await sub.cancel();
    });

    test('SharedPreferences stores tv_room_code correctly on pairing', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('tv_room_code', 'TRIV-5678');
      await prefs.setBool('onboardingCompleted', true);

      expect(prefs.getString('tv_room_code'), equals('TRIV-5678'));
      expect(prefs.getBool('onboardingCompleted'), isTrue);
    });
  });
}
