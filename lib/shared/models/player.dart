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
    return Player(
      id: json['id'] as String,
      playerUid: json['player_uid'] as String,
      roomCode: json['room_code'] as String,
      nickname: json['nickname'] as String,
      cumulativeScore: json['cumulative_score'] as int? ?? 0,
      isConnected: json['is_connected'] as bool? ?? true,
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
