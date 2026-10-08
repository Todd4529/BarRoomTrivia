import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/question.dart';
import 'supabase_service.dart';
import 'broadcast_sync.dart';
import 'mqtt_service.dart';

class RealtimeService {
  RealtimeChannel? _channel;
  RealtimeChannel? _defaultChannel;
  RealtimeChannel? _globalChannel;

  // Static event bus for local dev testing / multi-view synchronization
  static final StreamController<Map<String, dynamic>> _localEventBus =
      StreamController<Map<String, dynamic>>.broadcast();

  // Cache of active, subscribed Supabase channels by room code
  static final Map<String, RealtimeChannel> _activeChannels = {};

  RealtimeChannel _getChannel(String roomCode) {
    final normRoom = roomCode.toUpperCase().trim();
    return _channel ?? _activeChannels[normRoom] ?? SupabaseConfig.client.channel('room_$normRoom');
  }

  StreamSubscription<Map<String, dynamic>>? _localSubscription;
  StreamSubscription<Map<String, dynamic>>? _mqttSubscription;

  /// Epoch-millisecond deadline fields that are expressed in the SENDER's clock.
  static const List<String> _senderEpochKeys = [
    'timer_ends_at_epoch_ms',
    'timerEndsAtMs',
    'starts_at_epoch_ms',
    'next_question_starts_at_epoch_ms',
    'nextQuestionStartsAtEpochMs',
    'next_round_starts_at_epoch_ms',
    'nextRoundStartsAtEpochMs',
  ];

  /// Re-bases absolute deadlines from the sender's clock onto this device's clock.
  ///
  /// Different devices (Android TV boxes, phones) frequently have clocks that
  /// disagree by many seconds. Without correction, a player whose clock runs
  /// ahead of the TV/host sees a deadline that is already (almost) past and the
  /// question times out after ~1 second. Every broadcast carries the sender's
  /// `timestamp`, so `now - timestamp` approximates the clock offset (plus a
  /// small network latency). Offsets under 1.5s are treated as normal latency.
  static Map<String, dynamic> normalizeClockSkew(Map<String, dynamic> payload) {
    final sentRaw = payload['timestamp'] ?? payload['sent_at_epoch_ms'];
    final sent = sentRaw is num ? sentRaw.toInt() : int.tryParse('${sentRaw ?? ''}');
    if (sent == null || sent <= 0) return payload;

    final skew = DateTime.now().millisecondsSinceEpoch - sent;
    if (skew.abs() < 1500) return payload;

    final out = Map<String, dynamic>.from(payload);
    for (final key in _senderEpochKeys) {
      final v = out[key];
      if (v is num && v > 0) {
        out[key] = v.toInt() + skew;
      }
    }
    // Re-stamp so downstream code sees a consistent local-clock payload
    out['timestamp'] = sent + skew;
    return out;
  }

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
    void Function(Map<String, dynamic>)? onRequestStateSyncBroadcast,
    void Function(Map<String, dynamic>)? onAdModeToggledBroadcast,
  }) {
    void handleEvent(dynamic rawData) {
      if (rawData is Map<String, dynamic>) {
        // Convert sender-clock deadlines to this device's clock
        final data = normalizeClockSkew(rawData);
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
        } else if (event == 'ad_mode_toggled' && onAdModeToggledBroadcast != null) {
          onAdModeToggledBroadcast(data);
        } else if (event == 'request_state_sync' && onRequestStateSyncBroadcast != null) {
          onRequestStateSyncBroadcast(data);
        } else if (event == 'player_joined') {
          final nick = data['nickname']?.toString();
          if (nick != null && nick.isNotEmpty) {
            SupabaseService.registerIncomingPlayer(eventRoom ?? roomCode, nick);
          }
          if (onLeaderboardUpdatedBroadcast != null) {
            onLeaderboardUpdatedBroadcast(data);
          }
        } else if (event == 'leaderboard_updated' && onLeaderboardUpdatedBroadcast != null) {
          final pList = data['players'] ?? data['leaderboard'];
          if (pList != null) {
            SupabaseService.syncPlayersFromBroadcast(eventRoom ?? roomCode, pList);
          }
          onLeaderboardUpdatedBroadcast(data);
        } else if (event == 'player_score_updated') {
          final nick = data['nickname']?.toString();
          final rawScore = data['cumulative_score'] ?? data['score'] ?? data['points'];
          int score = 0;
          if (rawScore is num) {
            score = rawScore.toInt();
          } else if (rawScore != null) {
            score = int.tryParse(rawScore.toString()) ?? 0;
          }
          if (nick != null && nick.isNotEmpty) {
            SupabaseService.updatePlayerScoreDirectly(
              roomCode: eventRoom ?? roomCode,
              nickname: nick,
              score: score,
            );
          }
          if (onLeaderboardUpdatedBroadcast != null) {
            onLeaderboardUpdatedBroadcast(data);
          }
        }
      }
    }

    // 1. Listen to local event bus for same-process responsiveness
    _localSubscription?.cancel();
    _localSubscription = _localEventBus.stream.listen(handleEvent);

    // 2. Listen to cross-tab web localStorage events
    BroadcastSync.listen(handleEvent);

    // 3. Connect to EMQX MQTT broker for 100% reliable internet cross-device events
    final mqtt = MqttService();
    mqtt.connect();
    mqtt.subscribeToRoom(roomCode);
    _mqttSubscription?.cancel();
    _mqttSubscription = mqtt.eventStream.listen(handleEvent);

    // Helper to register callbacks on any RealtimeChannel
    void attachListeners(RealtimeChannel ch) {
      ch
          .onBroadcast(
            event: 'question_start',
            callback: (payload) => onQuestionBroadcast(normalizeClockSkew(payload)),
          )
          .onBroadcast(
            event: 'timer_expired',
            callback: (payload) => onTimerExpiredBroadcast(normalizeClockSkew(payload)),
          )
          .onBroadcast(
            event: 'pre_game_countdown',
            callback: (payload) {
              if (onPreGameCountdownBroadcast != null) {
                onPreGameCountdownBroadcast(normalizeClockSkew(payload));
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
                onGameResumingBroadcast(normalizeClockSkew(payload));
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
                onRoundCompletedBroadcast(normalizeClockSkew(payload));
              }
            },
          )
          .onBroadcast(
            event: 'leaderboard_updated',
            callback: (payload) {
              final pList = payload['players'] ?? payload['leaderboard'];
              if (pList != null) {
                SupabaseService.syncPlayersFromBroadcast(roomCode, pList);
              }
              if (onLeaderboardUpdatedBroadcast != null) {
                onLeaderboardUpdatedBroadcast(payload);
              }
            },
          )
          .onBroadcast(
            event: 'player_score_updated',
            callback: (payload) {
              final nick = payload['nickname']?.toString();
              final rawScore = payload['cumulative_score'] ?? payload['score'] ?? payload['points'];
              int score = 0;
              if (rawScore is num) {
                score = rawScore.toInt();
              } else if (rawScore != null) {
                score = int.tryParse(rawScore.toString()) ?? 0;
              }
              if (nick != null && nick.isNotEmpty) {
                SupabaseService.updatePlayerScoreDirectly(
                  roomCode: roomCode,
                  nickname: nick,
                  score: score,
                );
              }
              if (onLeaderboardUpdatedBroadcast != null) {
                onLeaderboardUpdatedBroadcast(payload);
              }
            },
          )
          .onBroadcast(
            event: 'player_joined',
            callback: (payload) {
              final nick = payload['nickname']?.toString();
              if (nick != null && nick.isNotEmpty) {
                SupabaseService.registerIncomingPlayer(roomCode, nick);
              }
              if (onLeaderboardUpdatedBroadcast != null) {
                onLeaderboardUpdatedBroadcast(payload);
              }
            },
          )
          .onBroadcast(
            event: 'request_state_sync',
            callback: (payload) {
              if (onRequestStateSyncBroadcast != null) {
                onRequestStateSyncBroadcast(payload);
              }
            },
          )
          .subscribe();
    }

    // 3. Subscribe to Supabase Realtime channels
    try {
      final norm = roomCode.toUpperCase().trim();
      _channel = SupabaseConfig.client.channel('room_$norm');
      attachListeners(_channel!);
      _activeChannels[norm] = _channel!;

      if (norm != 'TRIV') {
        _defaultChannel = SupabaseConfig.client.channel('room_TRIV');
        attachListeners(_defaultChannel!);
        _activeChannels['TRIV'] = _defaultChannel!;
      }

      _globalChannel = SupabaseConfig.client.channel('room_GLOBAL');
      attachListeners(_globalChannel!);
      _activeChannels['GLOBAL'] = _globalChannel!;
    } catch (_) {}

    return _channel ?? SupabaseConfig.client.channel('room_$roomCode');
  }

  /// Broadcast pre-game countdown payload
  Future<void> broadcastGameStarting({
    required String roomCode,
    required int startsAtEpochMs,
    int? roundNumber,
    String? genre,
  }) async {
    final payload = {
      'event': 'pre_game_countdown',
      'room_code': roomCode,
      'starts_at_epoch_ms': startsAtEpochMs,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      if (roundNumber != null) 'round_number': roundNumber,
      if (roundNumber != null) 'roundNumber': roundNumber,
      if (genre != null) 'genre': genre,
      if (genre != null) 'current_genre': genre,
      if (genre != null) 'category': genre,
    };

    _localEventBus.add(payload);
    BroadcastSync.postEvent(payload);
    _publishMqtt(roomCode, payload);

    try {
      final ch = _getChannel(roomCode);
      ch.subscribe();
      await ch.sendBroadcastMessage(
        event: 'pre_game_countdown',
        payload: payload,
      );
    } catch (_) {}

    try {
      final norm = roomCode.toUpperCase().trim();
      SupabaseConfig.client.from('game_sessions').upsert({
        'room_code': norm,
        'status': 'pre_game_countdown',
        'starts_at': startsAtEpochMs,
        if (roundNumber != null) 'current_round': roundNumber,
        if (roundNumber != null) 'round_number': roundNumber,
        if (genre != null) 'genre': genre,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'room_code').then((_) {}).catchError((_) {});
    } catch (_) {}
  }

  /// Broadcast player joined event so TV immediately registers the incoming player
  Future<void> broadcastPlayerJoined({
    required String roomCode,
    required String nickname,
    int score = 0,
  }) async {
    final normRoom = roomCode.toUpperCase().trim();
    final payload = {
      'event': 'player_joined',
      'room_code': normRoom,
      'nickname': nickname,
      'score': score,
      'cumulative_score': score,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _localEventBus.add(payload);
    BroadcastSync.postEvent(payload);
    _publishMqtt(normRoom, payload);

    try {
      final ch = _getChannel(normRoom);
      ch.subscribe();
      await ch.sendBroadcastMessage(
        event: 'player_joined',
        payload: payload,
      );
    } catch (_) {}
  }

  void _publishMqtt(String roomCode, Map<String, dynamic> payload) {
    final mqtt = MqttService();
    final norm = roomCode.toUpperCase().trim();
    mqtt.publish('barrooms_trivia/room_$norm', payload);
    if (norm != 'TRIV') {
      mqtt.publish('barrooms_trivia/room_TRIV', payload);
    }
  }

  /// Broadcast state sync request across all connected clients
  Future<void> broadcastSyncRequest({required String roomCode, String? sender}) async {
    final payload = {
      'event': 'request_state_sync',
      'room_code': roomCode,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      if (sender != null) 'sender': sender,
    };

    _localEventBus.add(payload);
    BroadcastSync.postEvent(payload);
    _publishMqtt(roomCode, payload);

    try {
      final ch = _getChannel(roomCode);
      ch.subscribe();
      await ch.sendBroadcastMessage(
        event: 'request_state_sync',
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
    int totalQuestions = 10,
    int roundNumber = 1,
  }) async {
    final payload = {
      'event': 'question_start',
      'room_code': roomCode,
      'question_index': ((questionIndex - 1) % totalQuestions) + 1,
      'cumulative_question_index': questionIndex,
      'question_number_in_round': ((questionIndex - 1) % totalQuestions) + 1,
      'total_questions': totalQuestions,
      'total_questions_in_round': totalQuestions,
      'round_number': roundNumber,
      'question_id': question.id,
      'id': question.id,
      'duration_seconds': durationSeconds,
      'timer_ends_at_epoch_ms': timerEndsAtEpochMs,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'category': question.category,
      'genre': question.category,
      'difficulty': question.difficulty,
      'question_text': question.questionText,
      'option_a': question.optionA,
      'option_b': question.optionB,
      'option_c': question.optionC,
      'option_d': question.optionD,
      'options': {
        'A': question.optionA,
        'B': question.optionB,
        'C': question.optionC,
        'D': question.optionD,
      },
      'questionData': {
        'id': question.id,
        'category': question.category,
        'difficulty': question.difficulty,
        'text': question.questionText,
        'question_text': question.questionText,
        'options': {
          'A': question.optionA,
          'B': question.optionB,
          'C': question.optionC,
          'D': question.optionD,
        },
        'correct': question.correctOption,
        'correct_option': question.correctOption,
      },
      'correct_option': question.correctOption,
      'time_limit_seconds': durationSeconds,
    };

    _localEventBus.add(payload);
    BroadcastSync.postEvent(payload);
    _publishMqtt(roomCode, payload);

    try {
      final ch = _getChannel(roomCode);
      ch.subscribe();
      await ch.sendBroadcastMessage(
        event: 'question_start',
        payload: payload,
      );
    } catch (_) {}

    try {
      final norm = roomCode.toUpperCase().trim();
      SupabaseConfig.client.from('game_sessions').upsert({
        'room_code': norm,
        'status': 'question_active',
        'current_question_index': questionIndex,
        'current_round': roundNumber,
        'round_number': roundNumber,
        'current_question_data': payload,
        'question_data': payload,
        'duration_seconds': durationSeconds,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'room_code').then((_) {}).catchError((_) {});
    } catch (_) {}
  }

  /// Broadcast timer expiration event
  Future<void> broadcastTimerExpired({
    required String roomCode,
    String? correctOption,
    int? nextQuestionStartsAtEpochMs,
    String gamePlayMode = 'Auto',
    String? questionId,
    int? questionIndex,
    int? roundNumber,
  }) async {
      final targetEpoch = nextQuestionStartsAtEpochMs ?? (DateTime.now().millisecondsSinceEpoch + 15000);
      final payload = {
        'event': 'timer_expired',
        'room_code': roomCode,
        'correct_option': correctOption,
        'next_question_starts_at_epoch_ms': targetEpoch,
        'nextQuestionStartsAtEpochMs': targetEpoch,
        'game_play_mode': gamePlayMode,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        if (questionId != null) 'question_id': questionId,
        if (questionId != null) 'id': questionId,
        if (questionIndex != null) 'question_index': questionIndex,
        if (roundNumber != null) 'round_number': roundNumber,
      };

    _localEventBus.add(payload);
    BroadcastSync.postEvent(payload);
    _publishMqtt(roomCode, payload);

    try {
      final ch = _getChannel(roomCode);
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
    _publishMqtt(roomCode, payload);

    try {
      final ch = _getChannel(roomCode);
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
    _publishMqtt(roomCode, payload);

    try {
      final ch = _getChannel(roomCode);
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
    _publishMqtt(roomCode, payload);

    try {
      final ch = _getChannel(roomCode);
      ch.subscribe();
      await ch.sendBroadcastMessage(
        event: 'leaderboard_updated',
        payload: payload,
      );
    } catch (_) {}
  }

  /// Broadcast single player score update
  Future<void> broadcastPlayerScoreUpdated({
    required String roomCode,
    required String nickname,
    required int score,
    int? pointsEarned,
  }) async {
    final payload = {
      'event': 'player_score_updated',
      'room_code': roomCode,
      'nickname': nickname,
      'score': score,
      'cumulative_score': score,
      'points_earned': pointsEarned ?? 10,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _localEventBus.add(payload);
    BroadcastSync.postEvent(payload);
    _publishMqtt(roomCode, payload);

    try {
      final ch = _getChannel(roomCode);
      ch.subscribe();
      await ch.sendBroadcastMessage(
        event: 'player_score_updated',
        payload: payload,
      );
    } catch (_) {}
  }

  /// Broadcast player answer submission
  Future<void> broadcastAnswerSubmitted({
    required String roomCode,
    required String nickname,
    required String selectedOption,
  }) async {
    final payload = {
      'event': 'answer_submitted',
      'room_code': roomCode,
      'nickname': nickname,
      'selected_option': selectedOption,
      'player': {'nickname': nickname},
      'choice': selectedOption,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _localEventBus.add(payload);
    BroadcastSync.postEvent(payload);
    _publishMqtt(roomCode, payload);

    try {
      final ch = _getChannel(roomCode);
      ch.subscribe();
      await ch.sendBroadcastMessage(
        event: 'answer_submitted',
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
    _publishMqtt(roomCode, payload);

    try {
      final ch = _getChannel(roomCode);
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
    int? roundNumber,
    int? nextRound,
  }) async {
    final curR = roundNumber ?? 1;
    final upR = nextRound ?? (curR + 1);
    final payload = {
      'event': 'round_completed',
      'room_code': roomCode,
      'top_3_winners': top3Winners,
      'top3_winners': top3Winners,
      'top3Winners': top3Winners,
      'round_number': curR,
      'roundNumber': curR,
      'completed_round': curR,
      'next_round': upR,
      'nextRound': upR,
      'next_round_starts_at_epoch_ms': nextRoundStartsAtEpochMs,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _localEventBus.add(payload);
    BroadcastSync.postEvent(payload);
    _publishMqtt(roomCode, payload);

    try {
      final ch = _getChannel(roomCode);
      ch.subscribe();
      await ch.sendBroadcastMessage(
        event: 'round_completed',
        payload: payload,
      );
    } catch (_) {}

    try {
      final norm = roomCode.toUpperCase().trim();
      SupabaseConfig.client.from('game_sessions').upsert({
        'room_code': norm,
        'status': 'round_summary',
        'current_round': upR,
        'round_number': upR,
        'starts_at': nextRoundStartsAtEpochMs,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'room_code').then((_) {}).catchError((_) {});
    } catch (_) {}
  }

  Future<void> broadcastAdModeToggled({
    required String roomCode,
    required bool isAdModeActive,
  }) async {
    final norm = roomCode.toUpperCase().trim();
    final payload = {
      'event': 'ad_mode_toggled',
      'isAdModeActive': isAdModeActive,
      'is_ad_mode_active': isAdModeActive,
      'room_code': norm,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    _localEventBus.add(payload);
    BroadcastSync.postEvent(payload);
    _publishMqtt(norm, payload);

    try {
      final ch = _getChannel(norm);
      ch.subscribe();
      await ch.sendBroadcastMessage(
        event: 'ad_mode_toggled',
        payload: payload,
      );
    } catch (_) {}

    try {
      SupabaseConfig.client.from('game_sessions').upsert({
        'room_code': norm,
        'is_ad_mode_active': isAdModeActive,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'room_code').then((_) {}).catchError((_) {});
    } catch (_) {}
  }

  void leaveChannel() {
    _localSubscription?.cancel();
    _localSubscription = null;
    _mqttSubscription?.cancel();
    _mqttSubscription = null;
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
