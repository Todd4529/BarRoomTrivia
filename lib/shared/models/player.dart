class Player {
  final String id;
  final String playerUid;
  final String roomCode;
  final String nickname;
  final int cumulativeScore;
  final bool isConnected;

  Player({
    required this.id,
    required this.playerUid,
    required this.roomCode,
    required this.nickname,
    required this.cumulativeScore,
    required this.isConnected,
  });

  int get score => cumulativeScore;

  factory Player.fromJson(Map<dynamic, dynamic> rawJson) {
    final json = Map<String, dynamic>.from(rawJson);
    final nick = (json['nickname'] ?? json['name'] ?? 'Player').toString();
    final uid = (json['player_uid'] ?? json['id'] ?? nick).toString();
    final room = (json['room_code'] ?? 'TRIV').toString();

    final rawScore = json['cumulative_score'] ?? json['score'] ?? json['points'];
    int score = 0;
    if (rawScore is num) {
      score = rawScore.toInt();
    } else if (rawScore != null) {
      score = int.tryParse(rawScore.toString()) ?? 0;
    }

    final conn = (json['is_connected'] as bool?) ?? true;

    return Player(
      id: (json['id'] ?? uid).toString(),
      playerUid: uid,
      roomCode: room,
      nickname: nick,
      cumulativeScore: score,
      isConnected: conn,
    );
  }

  Player copyWith({
    String? id,
    String? playerUid,
    String? roomCode,
    String? nickname,
    int? cumulativeScore,
    bool? isConnected,
  }) {
    return Player(
      id: id ?? this.id,
      playerUid: playerUid ?? this.playerUid,
      roomCode: roomCode ?? this.roomCode,
      nickname: nickname ?? this.nickname,
      cumulativeScore: cumulativeScore ?? this.cumulativeScore,
      isConnected: isConnected ?? this.isConnected,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'player_uid': playerUid,
      'room_code': roomCode,
      'nickname': nickname,
      'cumulative_score': cumulativeScore,
      'is_connected': isConnected,
    };
  }
}
