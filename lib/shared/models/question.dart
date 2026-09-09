class Question {
  final String id;
  final String category;
  final String difficulty;
  final String questionText;
  final String optionA;
  final String optionB;
  final String optionC;
  final String optionD;
  final String correctOption;
  final int timeLimitSeconds;

  Question({
    required this.id,
    required this.category,
    this.difficulty = 'Standard',
    required this.questionText,
    required this.optionA,
    required this.optionB,
    required this.optionC,
    required this.optionD,
    required this.correctOption,
    this.timeLimitSeconds = 20,
  });

  factory Question.fromJson(Map<String, dynamic> json) {
    final opts = json['options'] as Map<String, dynamic>?;
    return Question(
      id: (json['id'] ?? json['question_id'] ?? DateTime.now().millisecondsSinceEpoch.toString()).toString(),
      category: (json['category'] ?? 'General Knowledge').toString(),
      difficulty: (json['difficulty'] ?? 'Standard').toString(),
      questionText: (json['question_text'] ?? json['text'] ?? json['question'] ?? '').toString(),
      optionA: (json['option_a'] ?? opts?['A'] ?? opts?['a'] ?? 'Option A').toString(),
      optionB: (json['option_b'] ?? opts?['B'] ?? opts?['b'] ?? 'Option B').toString(),
      optionC: (json['option_c'] ?? opts?['C'] ?? opts?['c'] ?? 'Option C').toString(),
      optionD: (json['option_d'] ?? opts?['D'] ?? opts?['d'] ?? 'Option D').toString(),
      correctOption: (json['correct_option'] ?? json['correct'] ?? 'A').toString().toUpperCase().trim(),
      timeLimitSeconds: (json['time_limit_seconds'] ?? json['duration_seconds'] as num?)?.toInt() ?? 20,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'category': category,
      'difficulty': difficulty,
      'question_text': questionText,
      'option_a': optionA,
      'option_b': optionB,
      'option_c': optionC,
      'option_d': optionD,
      'correct_option': correctOption,
      'time_limit_seconds': timeLimitSeconds,
    };
  }
}
