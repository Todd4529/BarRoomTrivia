class GameSession {
  final String id;
  final String roomCode;
  final String? hostId;
  final String status;
  final String? currentQuestionId;
  final int questionIndex;
  final int currentRound;
  final DateTime? timerEndsAt;
  final DateTime createdAt;

  GameSession({
    required this.id,
    required this.roomCode,
    this.hostId,
    required this.status,
    this.currentQuestionId,
    this.questionIndex = 0,
    this.currentRound = 1,
    this.timerEndsAt,
    required this.createdAt,
  });

  factory GameSession.fromJson(Map<String, dynamic> json) {
    return GameSession(
      id: json['id']?.toString() ?? 'dev-session-id',
      roomCode: json['room_code']?.toString() ?? '',
      hostId: json['host_id']?.toString(),
      status: json['status']?.toString() ?? 'lobby',
      currentQuestionId: json['current_question_id']?.toString(),
      questionIndex: (json['question_index'] as num?)?.toInt() ??
          (json['current_question_index'] as num?)?.toInt() ??
          0,
      currentRound: (json['current_round'] as num?)?.toInt() ??
          (json['round_number'] as num?)?.toInt() ??
          1,
      timerEndsAt: json['timer_ends_at'] != null
          ? (json['timer_ends_at'] is num
              ? DateTime.fromMillisecondsSinceEpoch((json['timer_ends_at'] as num).toInt())
              : DateTime.tryParse(json['timer_ends_at'].toString()))
          : null,
      createdAt: json['created_at'] != null
          ? (json['created_at'] is num
              ? DateTime.fromMillisecondsSinceEpoch((json['created_at'] as num).toInt())
              : (DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()))
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'room_code': roomCode,
      'host_id': hostId,
      'status': status,
      'current_question_id': currentQuestionId,
      'question_index': questionIndex,
      'current_round': currentRound,
      'timer_ends_at': timerEndsAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}
