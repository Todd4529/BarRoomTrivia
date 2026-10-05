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

  static bool isMockNickname(String nickname) {
    if (nickname.isEmpty) return true;
    final lower = nickname.trim().toLowerCase();
    if (lower.startsWith('mock-') || lower.startsWith('mock_') || lower.startsWith('simulatedplayer')) return true;
    if (lower == 'host' || lower == 'host user' || lower == 'todd4529' || lower.startsWith('host-') || lower.startsWith('host_')) return true;
    const banned = [
      'beerwhisperer', 'trivianinja', 'quizquark', 'hopsandglory', 'professorpint',
      'smartypints', 'brewmasterflex', 'mindovermug', 'alechemist', 'factchecker',
      'stoutscholars', 'brainybarley', 'pubeinstein', 'lagerlegend', 'quizcrafter',
      'triviamaster99', 'beerguru', 'pubquizpro', 'brewmaster_joe', 'hopsandbarley',
      'pintsizedgenius', 'whiskeywisdom', 'barstooleinstein', 'ciderseeker',
      'taverntactician', 'player 1', 'player 2', 'champion', 'runner up', 'third place'
    ];
    return banned.any((b) => lower == b || lower.contains(b));
  }

  static List<Player> mergeLocalPlayers(String roomCode, List<Player> incoming) {
    final normRoom = roomCode.toUpperCase();
    final list = _localPlayersMap.putIfAbsent(normRoom, () => []);
    for (final inc in incoming) {
      if (isMockNickname(inc.nickname)) continue;
      final idx = list.indexWhere((p) => p.nickname.toLowerCase() == inc.nickname.toLowerCase());
      if (idx >= 0) {
        final existing = list[idx];
        list[idx] = Player(
          id: existing.id.isNotEmpty ? existing.id : inc.id,
          playerUid: existing.playerUid.isNotEmpty ? existing.playerUid : inc.playerUid,
          roomCode: normRoom,
          nickname: inc.nickname.isNotEmpty ? inc.nickname : existing.nickname,
          cumulativeScore: max(existing.cumulativeScore, inc.cumulativeScore),
          isConnected: inc.isConnected || existing.isConnected,
        );
      } else {
        list.add(Player(
          id: inc.id.isNotEmpty ? inc.id : 'player-${DateTime.now().millisecondsSinceEpoch}',
          playerUid: inc.playerUid.isNotEmpty ? inc.playerUid : 'uid-${DateTime.now().millisecondsSinceEpoch}',
          roomCode: normRoom,
          nickname: inc.nickname,
          cumulativeScore: inc.cumulativeScore,
          isConnected: inc.isConnected,
        ));
      }
    }
    list.sort((a, b) => b.cumulativeScore.compareTo(a.cumulativeScore));
    if (normRoom != 'TRIV') {
      _localPlayersMap['TRIV'] = List<Player>.from(list);
    }
    return List<Player>.from(list);
  }

  static void syncPlayersFromBroadcast(String roomCode, dynamic playersJson) {
    final normRoom = roomCode.toUpperCase();
    if (playersJson is List) {
      final parsedList = <Player>[];
      for (var item in playersJson) {
        if (item is Map) {
          try {
            final p = Player.fromJson(Map<String, dynamic>.from(item));
            if (!isMockNickname(p.nickname)) {
              parsedList.add(p);
            }
          } catch (e) {
            debugPrint('[SupabaseService] Error parsing player: $e');
          }
        }
      }
      if (parsedList.isNotEmpty) {
        mergeLocalPlayers(normRoom, parsedList);
      }
    }
  }

  static void setLocalPlayers(String roomCode, List<Player> players) {
    mergeLocalPlayers(roomCode, players);
  }

  static void updatePlayerScoreDirectly({
    required String roomCode,
    required String nickname,
    required int score,
  }) {
    final normRoom = roomCode.toUpperCase();
    final list = _localPlayersMap.putIfAbsent(normRoom, () => []);
    final idx = list.indexWhere((p) => p.nickname.toLowerCase() == nickname.toLowerCase());
    if (idx >= 0) {
      final p = list[idx];
      list[idx] = Player(
        id: p.id,
        playerUid: p.playerUid,
        roomCode: p.roomCode,
        nickname: p.nickname,
        cumulativeScore: max(p.cumulativeScore, score),
        isConnected: true,
      );
    } else {
      list.add(Player(
        id: nickname,
        playerUid: nickname,
        roomCode: normRoom,
        nickname: nickname,
        cumulativeScore: score,
        isConnected: true,
      ));
    }
    list.sort((a, b) => b.cumulativeScore.compareTo(a.cumulativeScore));
    if (normRoom != 'TRIV') {
      _localPlayersMap['TRIV'] = List<Player>.from(list);
    }
  }

  static void clearLocalPlayers([String? roomCode]) {
    if (roomCode != null) {
      _localPlayersMap.remove(roomCode.toUpperCase());
    } else {
      _localPlayersMap.clear();
    }
  }

  static void registerIncomingPlayer(String roomCode, String nickname, [int score = 0]) {
    if (isMockNickname(nickname)) return;
    final normRoom = roomCode.toUpperCase();
    final list = _localPlayersMap.putIfAbsent(normRoom, () => []);
    final idx = list.indexWhere((p) => p.nickname.toLowerCase() == nickname.toLowerCase());
    if (idx >= 0) {
      final existing = list[idx];
      list[idx] = Player(
        id: existing.id,
        playerUid: existing.playerUid,
        roomCode: normRoom,
        nickname: nickname,
        cumulativeScore: max(existing.cumulativeScore, score),
        isConnected: true,
      );
    } else {
      list.add(Player(
        id: 'player-${DateTime.now().millisecondsSinceEpoch}',
        playerUid: 'uid-${DateTime.now().millisecondsSinceEpoch}',
        roomCode: normRoom,
        nickname: nickname,
        cumulativeScore: score,
        isConnected: true,
      ));
    }
    list.sort((a, b) => b.cumulativeScore.compareTo(a.cumulativeScore));
    if (normRoom != 'TRIV') {
      _localPlayersMap['TRIV'] = List<Player>.from(list);
    }
  }

  static void seedMockPlayers({required String roomCode, int count = 15}) {
    // Disabled: Leaderboard only displays real connected players
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
    if (isMockNickname(nickname)) {
      throw Exception('Please choose a different nickname');
    }
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
        final newScore = existing.cumulativeScore + pointsToAdd;
        players[idx] = Player(
          id: existing.id,
          roomCode: existing.roomCode,
          playerUid: existing.playerUid,
          nickname: existing.nickname,
          cumulativeScore: newScore,
          isConnected: true,
        );
        players.sort((a, b) => b.cumulativeScore.compareTo(a.cumulativeScore));
        if (normRoom != 'TRIV') {
          _localPlayersMap['TRIV'] = List<Player>.from(players);
        }
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

  static List<Map<String, dynamic>> awardRoundWinnerBonusAndGetTop3(String roomCode, [int bonusPoints = 20]) {
    final normRoom = roomCode.toUpperCase();
    final list = _localPlayersMap[normRoom];
    if (list != null && list.isNotEmpty) {
      final validPlayers = list.where((p) => !isMockNickname(p.nickname)).toList();
      if (validPlayers.isNotEmpty) {
        validPlayers.sort((a, b) => b.cumulativeScore.compareTo(a.cumulativeScore));
        final winner = validPlayers.first;
        updatePlayerScoreDirectly(
          roomCode: normRoom,
          nickname: winner.nickname,
          score: winner.cumulativeScore + bonusPoints,
        );
      }
    }
    return getTop3RoundWinners(roomCode);
  }

  static List<Map<String, dynamic>> getTop3RoundWinners(String roomCode) {
    final normRoom = roomCode.toUpperCase();
    final list = List<Player>.from(_localPlayersMap[normRoom] ?? [])
        .where((p) => !isMockNickname(p.nickname))
        .toList();
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

    // 1. Check local in-memory players first for instantaneous response
    final localList = List<Player>.from(_localPlayersMap[normRoom] ?? [])
        .where((p) => !isMockNickname(p.nickname))
        .toList();
    if (localList.isNotEmpty) {
      localList.sort((a, b) => b.cumulativeScore.compareTo(a.cumulativeScore));
      return localList;
    }

    if (normRoom != 'TRIV' && _localPlayersMap.containsKey('TRIV')) {
      final trivList = List<Player>.from(_localPlayersMap['TRIV'] ?? [])
          .where((p) => !isMockNickname(p.nickname))
          .toList();
      if (trivList.isNotEmpty) {
        trivList.sort((a, b) => b.cumulativeScore.compareTo(a.cumulativeScore));
        return trivList;
      }
    }

    // 2. Query remote Supabase DB for registered players if local is empty
    try {
      final res = await _client
          .from('players')
          .select()
          .or('room_code.eq.$normRoom,room_code.eq.TRIV')
          .order('cumulative_score', ascending: false)
          .timeout(const Duration(milliseconds: 300));
      if (res.isNotEmpty) {
        for (final item in res) {
          try {
            final p = Player.fromJson(item);
            if (!isMockNickname(p.nickname)) {
              registerIncomingPlayer(normRoom, p.nickname, p.cumulativeScore);
            }
          } catch (_) {}
        }
      }
    } catch (_) {}

    final finalList = List<Player>.from(_localPlayersMap[normRoom] ?? [])
        .where((p) => !isMockNickname(p.nickname))
        .toList();
    finalList.sort((a, b) => b.cumulativeScore.compareTo(a.cumulativeScore));
    return finalList;
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
