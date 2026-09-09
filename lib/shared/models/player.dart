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

  factory Player.fromJson(Map<String, dynamic> json) {
    final nick = (json['nickname'] ?? json['name'] ?? 'Player').toString();
    final uid = (json['player_uid'] ?? json['id'] ?? nick).toString();
    final room = (json['room_code'] ?? 'TRIV').toString();
    final score = (json['cumulative_score'] ?? json['score'] as num?)?.toInt() ?? 0;
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
