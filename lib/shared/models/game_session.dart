class GameSession {
  final String id;
  final String roomCode;
  final String? hostId;
  final String status;
  final String? currentQuestionId;
  final int questionIndex;
  final DateTime? timerEndsAt;
  final DateTime createdAt;

  GameSession({
    required this.id,
    required this.roomCode,
    this.hostId,
    required this.status,
    this.currentQuestionId,
    this.questionIndex = 0,
    this.timerEndsAt,
    required this.createdAt,
  });

  factory GameSession.fromJson(Map<String, dynamic> json) {
    return GameSession(
      id: json['id'] as String,
      roomCode: json['room_code'] as String,
      hostId: json['host_id'] as String?,
      status: json['status'] as String? ?? 'lobby',
      currentQuestionId: json['current_question_id'] as String?,
      questionIndex: json['question_index'] as int? ?? 0,
      timerEndsAt: json['timer_ends_at'] != null
          ? DateTime.parse(json['timer_ends_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
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
      'timer_ends_at': timerEndsAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}
