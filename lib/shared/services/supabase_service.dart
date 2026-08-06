import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/game_session.dart';
import '../models/player.dart';
import '../models/question.dart';
import '../data/homebrewing_database.dart';
import 'realtime_service.dart';

class SupabaseService {
  final SupabaseClient _client = SupabaseConfig.client;

  /// Anonymous Authentication for Frictionless Player Entry
  Future<User?> signInAnonymously() async {
    try {
      final response = await _client.auth.signInAnonymously();
      return response.user;
    } catch (_) {
      return null;
    }
  }

  /// Email / Password sign‑in
  Future<User?> signInWithEmail(String email, String password) async {
    try {
      final response = await _client.auth.signInWithPassword(email: email, password: password);
      return response.user;
    } catch (_) {
      return null;
    }
  }

  /// Email / Password sign‑up
  Future<User?> signUpWithEmail(String email, String password) async {
    try {
      final response = await _client.auth.signUp(email: email, password: password);
      return response.user;
    } catch (_) {
      return null;
    }
  }

  /// Google provider sign‑in
  Future<bool> signInWithGoogle() async {
    try {
      return await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb 
            ? Uri.base.origin 
            : 'io.supabase.barroomstrivia://login-callback',
      );
    } catch (e) {
      rethrow;
    }
  }

  /// Apple provider sign‑in
  Future<bool> signInWithApple() async {
    try {
      return await _client.auth.signInWithOAuth(
        OAuthProvider.apple,
        redirectTo: kIsWeb 
            ? Uri.base.origin 
            : 'io.supabase.barroomstrivia://login-callback',
      );
    } catch (e) {
      rethrow;
    }
  }

  /// Send password‑reset email
  Future<void> sendPasswordReset(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email);
    } catch (_) {}
  }

  /// Update user password (for password recovery)
  Future<bool> updateUserPassword(String newPassword) async {
    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
      return true;
    } catch (_) {
      return false;
    }
  }



  static final Map<String, List<Player>> _localPlayersMap = {};
  static final List<Timer> _mockTimers = [];

  static void cancelMockTimers() {
    for (var t in _mockTimers) {
      t.cancel();
    }
    _mockTimers.clear();
  }

  static void syncPlayersFromBroadcast(String roomCode, dynamic playersJson) {
    final normRoom = roomCode.toUpperCase();
    if (playersJson is List) {
      final newList = <Player>[];
      for (var item in playersJson) {
        if (item is Map<String, dynamic>) {
          try {
            newList.add(Player.fromJson(item));
          } catch (_) {}
        }
      }
      _localPlayersMap[normRoom] = newList;
    }
  }

  static const List<String> _mockNicknames = [
    'BeerWhisperer',
    'TriviaNinja',
    'QuizQuark',
    'HopsAndGlory',
    'ProfessorPint',
    'SmartyPints',
    'BrewMasterFlex',
    'MindOverMug',
    'AleChemist',
    'FactChecker',
    'StoutScholars',
    'BrainyBarley',
    'PubEinstein',
    'LagerLegend',
    'QuizCrafter',
  ];

  static void seedMockPlayers({required String roomCode, int count = 15}) {
    final normRoom = roomCode.toUpperCase();
    final list = _localPlayersMap.putIfAbsent(normRoom, () => []);

    for (int i = 0; i < count && i < _mockNicknames.length; i++) {
      final nickname = _mockNicknames[i];
      final idx = list.indexWhere((p) => p.nickname.toLowerCase() == nickname.toLowerCase());
      final mockScore = (15 - i) * 100;

      final mockPlayer = Player(
        id: 'mock-$i-${DateTime.now().millisecondsSinceEpoch}',
        roomCode: normRoom,
        playerUid: 'mock-uid-$i',
        nickname: nickname,
        cumulativeScore: mockScore,
        isConnected: true,
      );

      if (idx >= 0) {
        list[idx] = mockPlayer;
      } else {
        list.add(mockPlayer);
      }
    }

    RealtimeService().broadcastLeaderboardUpdated(
      roomCode: normRoom,
      players: getLocalPlayersJson(normRoom),
    );
  }

  static List<Map<String, dynamic>> getLocalPlayersJson(String roomCode) {
    final normRoom = roomCode.toUpperCase();
    return _localPlayersMap[normRoom]?.map((p) => p.toJson()).toList() ?? [];
  }

  /// Simulates live gameplay for mock players during active questions
  static void simulateMockAnswersForQuestion({
    required String roomCode,
    required String correctOption,
  }) {
    final normRoom = roomCode.toUpperCase();
    final players = _localPlayersMap[normRoom];
    if (players == null || players.isEmpty) return;

    final rand = Random();

    for (int i = 0; i < players.length; i++) {
      final p = players[i];
      if (!p.id.startsWith('mock-')) continue; // Only process mock players

      // Stagger response time between 2 to 20 seconds into the question timer
      final delaySeconds = rand.nextInt(18) + 2;

      final timer = Timer(Duration(seconds: delaySeconds), () {
        // 65% accuracy chance for mock players to earn +100 points
        final isCorrect = rand.nextDouble() < 0.65;
        if (isCorrect) {
          final currentPlayers = _localPlayersMap[normRoom];
          if (currentPlayers == null) return;

          final idx = currentPlayers.indexWhere((item) => item.id == p.id);
          if (idx >= 0) {
            final target = currentPlayers[idx];
            final updatedScore = target.cumulativeScore + 100;
            currentPlayers[idx] = Player(
              id: target.id,
              roomCode: target.roomCode,
              playerUid: target.playerUid,
              nickname: target.nickname,
              cumulativeScore: updatedScore,
              isConnected: true,
            );

            currentPlayers.sort((a, b) => b.cumulativeScore.compareTo(a.cumulativeScore));

            RealtimeService().broadcastLeaderboardUpdated(
              roomCode: normRoom,
              players: getLocalPlayersJson(normRoom),
            );
          }
        }
      });
      _mockTimers.add(timer);
    }
  }

  /// Register player in a room session with nickname
  Future<Player> registerPlayer({
    required String roomCode,
    required String nickname,
  }) async {
    final normRoom = roomCode.toUpperCase();
    final players = _localPlayersMap.putIfAbsent(normRoom, () => []);
    final idx = players.indexWhere((p) => p.nickname.toLowerCase() == nickname.toLowerCase());
    final newPlayer = Player(
      id: 'player-${DateTime.now().millisecondsSinceEpoch}',
      roomCode: normRoom,
      playerUid: 'uid-${nickname.toLowerCase()}',
      nickname: nickname,
      cumulativeScore: 0,
      isConnected: true,
    );
    if (idx >= 0) {
      players[idx] = newPlayer;
    } else {
      players.add(newPlayer);
    }

    final payloadList = getLocalPlayersJson(normRoom);

    // 1. Instantly broadcast leaderboard update locally & across connected tabs
    RealtimeService().broadcastLeaderboardUpdated(roomCode: normRoom, players: payloadList);

    // 2. Non-blocking background sync to remote Supabase DB (does not hold UI)
    _syncPlayerToDbInBackground(normRoom, nickname, newPlayer);

    return newPlayer;
  }

  void _syncPlayerToDbInBackground(String normRoom, String nickname, Player newPlayer) async {
    try {
      final user = await signInAnonymously().timeout(const Duration(milliseconds: 600));
      await _client
          .from('players')
          .upsert(
            {
              'player_uid': user?.id ?? newPlayer.playerUid,
              'room_code': normRoom,
              'nickname': nickname,
              'cumulative_score': 0,
              'is_connected': true,
            },
            onConflict: 'room_code, player_uid',
          )
          .timeout(const Duration(milliseconds: 600));
    } catch (_) {}
  }

  void updateLocalPlayerScore({
    required String roomCode,
    required String nickname,
    required int pointsToAdd,
  }) {
    final normRoom = roomCode.toUpperCase();
    final players = _localPlayersMap[normRoom];
    if (players != null) {
      final idx = players.indexWhere((p) => p.nickname.toLowerCase() == nickname.toLowerCase());
      if (idx >= 0) {
        final existing = players[idx];
        players[idx] = Player(
          id: existing.id,
          roomCode: existing.roomCode,
          playerUid: existing.playerUid,
          nickname: existing.nickname,
          cumulativeScore: existing.cumulativeScore + pointsToAdd,
          isConnected: true,
        );
        RealtimeService().broadcastLeaderboardUpdated(
          roomCode: normRoom,
          players: getLocalPlayersJson(normRoom),
        );
      }
    }
  }

  void resetRoomScores(String roomCode) {
    cancelMockTimers();
    final normRoom = roomCode.toUpperCase();
    final players = _localPlayersMap[normRoom];
    if (players != null) {
      for (int i = 0; i < players.length; i++) {
        final existing = players[i];
        players[i] = Player(
          id: existing.id,
          roomCode: existing.roomCode,
          playerUid: existing.playerUid,
          nickname: existing.nickname,
          cumulativeScore: 0,
          isConnected: true,
        );
      }
    } else {
      _localPlayersMap[normRoom] = [];
    }

    RealtimeService().broadcastLeaderboardUpdated(
      roomCode: normRoom,
      players: getLocalPlayersJson(normRoom),
    );
    _resetRoomScoresInDb(normRoom);
  }

  void _resetRoomScoresInDb(String normRoom) async {
    try {
      await _client
          .from('players')
          .update({'cumulative_score': 0})
          .eq('room_code', normRoom)
          .timeout(const Duration(milliseconds: 600));
    } catch (_) {}
  }

  void clearRoomLeaderboard(String roomCode) {
    cancelMockTimers();
    final normRoom = roomCode.toUpperCase();
    _localPlayersMap[normRoom] = [];
    RealtimeService().broadcastLeaderboardUpdated(
      roomCode: normRoom,
      players: [],
    );
    _clearRoomLeaderboardInDb(normRoom);
  }

  static List<Map<String, dynamic>> getTop3RoundWinners(String roomCode) {
    final normRoom = roomCode.toUpperCase();
    final list = List<Player>.from(_localPlayersMap[normRoom] ?? []);
    list.sort((a, b) => b.cumulativeScore.compareTo(a.cumulativeScore));

    final top3 = list.take(3).map((p) => {
      'nickname': p.nickname,
      'score': p.cumulativeScore,
    }).toList();

    return top3;
  }

  void _clearRoomLeaderboardInDb(String normRoom) async {
    try {
      await _client
          .from('players')
          .delete()
          .eq('room_code', normRoom)
          .timeout(const Duration(milliseconds: 600));
    } catch (_) {}
  }

  /// Submit Answer
  Future<void> submitAnswer({
    required String sessionId,
    required String questionId,
    required String selectedOption,
  }) async {
    try {
      final user = _client.auth.currentUser;
      await _client.from('player_answers').insert({
        'session_id': sessionId,
        'question_id': questionId,
        'player_uid': user?.id ?? 'dev-player',
        'selected_option': selectedOption,
        'submitted_at': DateTime.now().toIso8601String(),
      }).timeout(const Duration(milliseconds: 500));
    } catch (_) {}
  }

  /// Get Game Session by Room Code
  Future<GameSession?> getSessionByRoomCode(String roomCode) async {
    try {
      final response = await _client
          .from('game_sessions')
          .select()
          .eq('room_code', roomCode)
          .maybeSingle()
          .timeout(const Duration(milliseconds: 500));

      if (response == null) {
        return GameSession(
          id: 'dev-session-id',
          roomCode: roomCode,
          status: 'active',
          questionIndex: 0,
          createdAt: DateTime.now(),
        );
      }
      return GameSession.fromJson(response);
    } catch (_) {
      return GameSession(
        id: 'dev-session-id',
        roomCode: roomCode,
        status: 'active',
        questionIndex: 0,
        createdAt: DateTime.now(),
      );
    }
  }

  /// Get Question by ID
  Future<Question?> getQuestionById(String questionId) async {
    try {
      final response = await _client
          .from('questions')
          .select()
          .eq('id', questionId)
          .maybeSingle()
          .timeout(const Duration(milliseconds: 500));

      if (response != null) {
        return Question.fromJson(response);
      }
    } catch (_) {}

    final questions = HomebrewingDatabase.generate500Questions();
    try {
      return questions.firstWhere((q) => q.id == questionId);
    } catch (_) {
      return questions.first;
    }
  }

  /// Get Leaderboard for TV Display
  Future<List<Player>> getLeaderboard(String roomCode) async {
    final normRoom = roomCode.toUpperCase();

    if (_localPlayersMap.containsKey(normRoom)) {
      final localList = List<Player>.from(_localPlayersMap[normRoom]!);
      localList.sort((a, b) => b.cumulativeScore.compareTo(a.cumulativeScore));
      return localList;
    }

    List<Player> dbPlayers = [];
    try {
      final response = await _client
          .from('players')
          .select()
          .eq('room_code', normRoom)
          .order('cumulative_score', ascending: false)
          .limit(100)
          .timeout(const Duration(milliseconds: 500));

      dbPlayers = (response as List).map((json) => Player.fromJson(json)).toList();
      _localPlayersMap[normRoom] = dbPlayers;
    } catch (_) {}

    return dbPlayers;
  }

  /// Host: Create new room session with Dev Fallback
  Future<GameSession> createRoomSession(String roomCode) async {
    try {
      final user = _client.auth.currentUser ?? (await signInAnonymously().timeout(const Duration(milliseconds: 500)));
      final response = await _client
          .from('game_sessions')
          .insert({
            'room_code': roomCode,
            'host_id': user?.id,
            'status': 'lobby',
          })
          .select()
          .single()
          .timeout(const Duration(milliseconds: 500));

      return GameSession.fromJson(response);
    } catch (e) {
      return GameSession(
        id: 'dev-session-id',
        roomCode: roomCode,
        status: 'active',
        questionIndex: 0,
        createdAt: DateTime.now(),
      );
    }
  }

  /// Host/TV: Invoke Edge Function to evaluate answers upon timer expiration
  Future<FunctionResponse?> evaluateAnswersServerSide({
    required String sessionId,
    required String questionId,
  }) async {
    try {
      return await _client.functions.invoke(
        'evaluate_answers',
        body: {
          'session_id': sessionId,
          'question_id': questionId,
        },
      );
    } catch (_) {
      return null;
    }
  }
}
