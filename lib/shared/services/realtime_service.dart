import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/question.dart';
import 'supabase_service.dart';
import 'broadcast_sync.dart';

class RealtimeService {
  RealtimeChannel? _channel;
  RealtimeChannel? _defaultChannel;
  RealtimeChannel? _globalChannel;

  // Static event bus for local dev testing / multi-view synchronization
  static final StreamController<Map<String, dynamic>> _localEventBus =
      StreamController<Map<String, dynamic>>.broadcast();

  StreamSubscription<Map<String, dynamic>>? _localSubscription;

  /// Subscribe to a room's broadcast channel
  RealtimeChannel joinRoomChannel({
    required String roomCode,
    required void Function(Map<String, dynamic> payload) onQuestionBroadcast,
    required void Function(Map<String, dynamic> payload) onTimerExpiredBroadcast,
    void Function(Map<String, dynamic> payload)? onPreGameCountdownBroadcast,
    void Function(Map<String, dynamic>)? onGamePausedBroadcast,
    void Function(Map<String, dynamic>)? onGameResumingBroadcast,
    void Function(Map<String, dynamic>)? onGameResetBroadcast,
    void Function(Map<String, dynamic>)? onRoundCompletedBroadcast,
    void Function(Map<String, dynamic>)? onLeaderboardUpdatedBroadcast,
  }) {
    void handleEvent(dynamic rawData) {
      if (rawData is Map<String, dynamic>) {
        final data = rawData;
        final eventRoom = (data['room_code'] as String?)?.toUpperCase();
        final currentRoom = roomCode.toUpperCase();
        
        // Accept events if room matches, or if either is TRIV / GLOBAL
        if (eventRoom != null &&
            eventRoom != currentRoom &&
            eventRoom != 'TRIV' &&
            eventRoom != 'GLOBAL' &&
            currentRoom != 'TRIV') {
          return;
        }

        final event = data['event'] as String?;
        if (event == 'pre_game_countdown' && onPreGameCountdownBroadcast != null) {
          onPreGameCountdownBroadcast(data);
        } else if (event == 'question_start') {
          onQuestionBroadcast(data);
        } else if (event == 'timer_expired') {
          onTimerExpiredBroadcast(data);
        } else if (event == 'game_paused' && onGamePausedBroadcast != null) {
          onGamePausedBroadcast(data);
        } else if (event == 'game_resuming' && onGameResumingBroadcast != null) {
          onGameResumingBroadcast(data);
        } else if (event == 'game_reset' && onGameResetBroadcast != null) {
          onGameResetBroadcast(data);
        } else if (event == 'round_completed' && onRoundCompletedBroadcast != null) {
          onRoundCompletedBroadcast(data);
        } else if (event == 'leaderboard_updated' && onLeaderboardUpdatedBroadcast != null) {
          if (data['players'] != null) {
            SupabaseService.syncPlayersFromBroadcast(eventRoom ?? roomCode, data['players']);
          }
          onLeaderboardUpdatedBroadcast(data);
        }
      }
    }

    // 1. Listen to local event bus for same-process responsiveness
    _localSubscription?.cancel();
    _localSubscription = _localEventBus.stream.listen(handleEvent);

    // 2. Listen to cross-tab web localStorage events
    BroadcastSync.listen(handleEvent);

    // Helper to register callbacks on any RealtimeChannel
    void attachListeners(RealtimeChannel ch) {
      ch
          .onBroadcast(
            event: 'question_start',
            callback: (payload) => onQuestionBroadcast(payload),
          )
          .onBroadcast(
            event: 'timer_expired',
            callback: (payload) => onTimerExpiredBroadcast(payload),
          )
          .onBroadcast(
            event: 'pre_game_countdown',
            callback: (payload) {
              if (onPreGameCountdownBroadcast != null) {
                onPreGameCountdownBroadcast(payload);
              }
            },
          )
          .onBroadcast(
            event: 'game_paused',
            callback: (payload) {
              if (onGamePausedBroadcast != null) {
                onGamePausedBroadcast(payload);
              }
            },
          )
          .onBroadcast(
            event: 'game_resuming',
            callback: (payload) {
              if (onGameResumingBroadcast != null) {
                onGameResumingBroadcast(payload);
              }
            },
          )
          .onBroadcast(
            event: 'game_reset',
            callback: (payload) {
              if (onGameResetBroadcast != null) {
                onGameResetBroadcast(payload);
              }
            },
          )
          .onBroadcast(
            event: 'round_completed',
            callback: (payload) {
              if (onRoundCompletedBroadcast != null) {
                onRoundCompletedBroadcast(payload);
              }
            },
          )
          .onBroadcast(
            event: 'leaderboard_updated',
            callback: (payload) {
              if (payload['players'] != null) {
                SupabaseService.syncPlayersFromBroadcast(roomCode, payload['players']);
              }
              if (onLeaderboardUpdatedBroadcast != null) {
                onLeaderboardUpdatedBroadcast(payload);
              }
            },
          )
          .subscribe();
    }

    // 3. Subscribe to Supabase Realtime channels
    try {
      _channel = SupabaseConfig.client.channel('room_$roomCode');
      attachListeners(_channel!);

      if (roomCode.toUpperCase() != 'TRIV') {
        _defaultChannel = SupabaseConfig.client.channel('room_TRIV');
        attachListeners(_defaultChannel!);
      }

      _globalChannel = SupabaseConfig.client.channel('room_GLOBAL');
      attachListeners(_globalChannel!);
    } catch (_) {}

    return _channel ?? SupabaseConfig.client.channel('room_$roomCode');
  }

  /// Broadcast 30-second pre-game warm-up countdown payload
  Future<void> broadcastGameStarting({
    required String roomCode,
    required int startsAtEpochMs,
  }) async {
    final payload = {
      'event': 'pre_game_countdown',
      'room_code': roomCode,
      'starts_at_epoch_ms': startsAtEpochMs,
    };

    _localEventBus.add(payload);
    BroadcastSync.postEvent(payload);

    try {
      final ch = _channel ?? SupabaseConfig.client.channel('room_$roomCode');
      ch.subscribe();
      await ch.sendBroadcastMessage(
        event: 'pre_game_countdown',
        payload: payload,
      );
    } catch (_) {}
  }

  /// Broadcast question start payload from Host to all connected player & TV views
  Future<void> broadcastQuestion({
    required String roomCode,
    required int questionIndex,
    required Question question,
    required int durationSeconds,
    required int timerEndsAtEpochMs,
  }) async {
    final payload = {
      'event': 'question_start',
      'room_code': roomCode,
      'question_index': questionIndex,
      'question_id': question.id,
      'id': question.id,
      'duration_seconds': durationSeconds,
      'timer_ends_at_epoch_ms': timerEndsAtEpochMs,
      'category': question.category,
      'difficulty': question.difficulty,
      'question_text': question.questionText,
      'option_a': question.optionA,
      'option_b': question.optionB,
      'option_c': question.optionC,
      'option_d': question.optionD,
      'correct_option': question.correctOption,
      'time_limit_seconds': durationSeconds,
    };

    _localEventBus.add(payload);
    BroadcastSync.postEvent(payload);

    try {
      final ch = _channel ?? SupabaseConfig.client.channel('room_$roomCode');
      ch.subscribe();
      await ch.sendBroadcastMessage(
        event: 'question_start',
        payload: payload,
      );
    } catch (_) {}
  }

  /// Broadcast timer expiration event
  Future<void> broadcastTimerExpired({
    required String roomCode,
    String? correctOption,
    int? nextQuestionStartsAtEpochMs,
    String gamePlayMode = 'Auto',
  }) async {
    final payload = {
      'event': 'timer_expired',
      'room_code': roomCode,
      'correct_option': correctOption,
      'next_question_starts_at_epoch_ms': nextQuestionStartsAtEpochMs ?? (DateTime.now().millisecondsSinceEpoch + 30000),
      'game_play_mode': gamePlayMode,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _localEventBus.add(payload);
    BroadcastSync.postEvent(payload);

    try {
      final ch = _channel ?? SupabaseConfig.client.channel('room_$roomCode');
      ch.subscribe();
      await ch.sendBroadcastMessage(
        event: 'timer_expired',
        payload: payload,
      );
    } catch (_) {}
  }

  /// Broadcast game paused event
  Future<void> broadcastGamePaused({required String roomCode}) async {
    final payload = {
      'event': 'game_paused',
      'room_code': roomCode,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _localEventBus.add(payload);
    BroadcastSync.postEvent(payload);

    try {
      final ch = _channel ?? SupabaseConfig.client.channel('room_$roomCode');
      ch.subscribe();
      await ch.sendBroadcastMessage(
        event: 'game_paused',
        payload: payload,
      );
    } catch (_) {}
  }

  /// Broadcast game resuming event (10-second countdown before continuing current question)
  Future<void> broadcastGameResuming({
    required String roomCode,
    required int startsAtEpochMs,
    required int remainingQuestionSeconds,
  }) async {
    final payload = {
      'event': 'game_resuming',
      'room_code': roomCode,
      'starts_at_epoch_ms': startsAtEpochMs,
      'remaining_question_seconds': remainingQuestionSeconds,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _localEventBus.add(payload);
    BroadcastSync.postEvent(payload);

    try {
      final ch = _channel ?? SupabaseConfig.client.channel('room_$roomCode');
      ch.subscribe();
      await ch.sendBroadcastMessage(
        event: 'game_resuming',
        payload: payload,
      );
    } catch (_) {}
  }

  /// Broadcast leaderboard update event
  Future<void> broadcastLeaderboardUpdated({
    required String roomCode,
    List<Map<String, dynamic>>? players,
  }) async {
    final payload = {
      'event': 'leaderboard_updated',
      'room_code': roomCode,
      'players': players ?? SupabaseService.getLocalPlayersJson(roomCode),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _localEventBus.add(payload);
    BroadcastSync.postEvent(payload);

    try {
      final ch = _channel ?? SupabaseConfig.client.channel('room_$roomCode');
      ch.subscribe();
      await ch.sendBroadcastMessage(
        event: 'leaderboard_updated',
        payload: payload,
      );
    } catch (_) {}
  }

  /// Broadcast game reset event (resetMode: 'keep_scores', 'zero_scores', 'clear_all')
  Future<void> broadcastGameReset({
    required String roomCode,
    required String resetMode,
  }) async {
    final payload = {
      'event': 'game_reset',
      'room_code': roomCode,
      'reset_mode': resetMode,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _localEventBus.add(payload);
    BroadcastSync.postEvent(payload);

    try {
      final ch = _channel ?? SupabaseConfig.client.channel('room_$roomCode');
      ch.subscribe();
      await ch.sendBroadcastMessage(
        event: 'game_reset',
        payload: payload,
      );
    } catch (_) {}
  }

  /// Broadcast round completed event with Top 3 Winners & 2-minute inter-round delay
  Future<void> broadcastRoundCompleted({
    required String roomCode,
    required List<Map<String, dynamic>> top3Winners,
    required int nextRoundStartsAtEpochMs,
  }) async {
    final payload = {
      'event': 'round_completed',
      'room_code': roomCode,
      'top_3_winners': top3Winners,
      'next_round_starts_at_epoch_ms': nextRoundStartsAtEpochMs,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _localEventBus.add(payload);
    BroadcastSync.postEvent(payload);

    try {
      final ch = _channel ?? SupabaseConfig.client.channel('room_$roomCode');
      ch.subscribe();
      await ch.sendBroadcastMessage(
        event: 'round_completed',
        payload: payload,
      );
    } catch (_) {}
  }

  void leaveChannel() {
    _localSubscription?.cancel();
    _localSubscription = null;
    if (_channel != null) {
      try {
        SupabaseConfig.client.removeChannel(_channel!);
      } catch (_) {}
      _channel = null;
    }
    if (_defaultChannel != null) {
      try {
        SupabaseConfig.client.removeChannel(_defaultChannel!);
      } catch (_) {}
      _defaultChannel = null;
    }
    if (_globalChannel != null) {
      try {
        SupabaseConfig.client.removeChannel(_globalChannel!);
      } catch (_) {}
      _globalChannel = null;
    }
  }
}
