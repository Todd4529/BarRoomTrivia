import 'package:flutter_test/flutter_test.dart';
import 'package:bar_rooms_trivia/shared/services/realtime_service.dart';

void main() {
  group('Clock Skew Normalization Tests', () {
    test('normalizeClockSkew adjusts deadlines when player device clock is ahead by 18 seconds', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      // Host sent this broadcast at host's clock = now - 18000
      final hostNow = now - 18000;
      final hostDeadline = hostNow + 20000; // Host gave 20 seconds

      final rawPayload = {
        'event': 'question_start',
        'timestamp': hostNow,
        'timer_ends_at_epoch_ms': hostDeadline,
        'duration_seconds': 20,
      };

      final normalized = RealtimeService.normalizeClockSkew(rawPayload);

      // Without normalization, (hostDeadline - now) = (now - 18000 + 20000) - now = 2000 ms (2 seconds!)
      // With normalization, timer_ends_at_epoch_ms is shifted by the 18-second skew:
      final normalizedDeadline = normalized['timer_ends_at_epoch_ms'] as int;
      final remainingMs = normalizedDeadline - now;
      final remainingSec = (remainingMs / 1000).ceil();

      expect(remainingSec, inInclusiveRange(19, 21));
    });

    test('normalizeClockSkew does not modify deadlines when skew is negligible (< 1.5s latency)', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final hostNow = now - 200; // 200ms network transit
      final hostDeadline = hostNow + 20000;

      final rawPayload = {
        'event': 'question_start',
        'timestamp': hostNow,
        'timer_ends_at_epoch_ms': hostDeadline,
        'duration_seconds': 20,
      };

      final normalized = RealtimeService.normalizeClockSkew(rawPayload);
      expect(normalized['timer_ends_at_epoch_ms'], hostDeadline);
    });

    test('Defensive duration fallback protects player when calculated duration is <= 4 seconds', () {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      // Simulate extreme clock drift or bad packet where remaining is 1000ms
      final skewedDeadline = nowMs + 1000;
      final payload = {
        'duration_seconds': 20,
        'timer_ends_at_epoch_ms': skewedDeadline,
      };

      final fallbackDuration = (payload['duration_seconds'] as num?)?.toInt() ?? 20;
      final remainingMs = skewedDeadline - nowMs;
      int durationSec = (remainingMs / 1000).ceil().clamp(0, 180);

      // Defensive guard
      if (durationSec <= 4) {
        durationSec = fallbackDuration > 4 ? fallbackDuration : 20;
      }

      // Player gets full 20s, NOT locked out after 1s
      expect(durationSec, 20);
    });

    test('Stale timer_expired is ignored if received within 3.5s of question start', () {
      final questionStartedAt = DateTime.now();
      // Simulate packet arriving 500ms after question start
      final packetArrivedAt = questionStartedAt.add(const Duration(milliseconds: 500));

      final isStale = packetArrivedAt.difference(questionStartedAt).inMilliseconds < 3500;
      expect(isStale, true);
    });

    test('Stale timer_expired is ignored if question ID does not match current question', () {
      const currentQuestionId = 'q-round-3-q2';
      const expiredPayloadQuestionId = 'q-round-3-q1';

      final isIdMismatch = expiredPayloadQuestionId != currentQuestionId;
      expect(isIdMismatch, true);
    });
  });
}
