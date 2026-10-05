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
    required String questionText,
    required this.optionA,
    required this.optionB,
    required this.optionC,
    required this.optionD,
    required this.correctOption,
    this.timeLimitSeconds = 20,
  }) : questionText = cleanQuestionText(questionText);

  /// Strips any question numbers like (#1), (#INDEX), (Focus Point #2), etc.
  static String cleanQuestionText(String raw) {
    var text = raw
        .replaceAll(RegExp(r'\s*\([^)]*#(?:\d+|INDEX)[^)]*\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*#\d+\b'), '')
        .trim();
    return text.replaceAll(RegExp(r'\s+\?'), '?');
  }

  factory Question.fromJson(Map<String, dynamic> json) {
    final inner = (json['questionData'] is Map)
        ? Map<String, dynamic>.from(json['questionData'] as Map)
        : (json['question_data'] is Map)
            ? Map<String, dynamic>.from(json['question_data'] as Map)
            : (json['payload'] is Map)
                ? Map<String, dynamic>.from(json['payload'] as Map)
                : json;

    final opts = (inner['options'] is Map)
        ? Map<String, dynamic>.from(inner['options'] as Map)
        : (json['options'] is Map)
            ? Map<String, dynamic>.from(json['options'] as Map)
            : null;

    final optsList = (inner['options'] is List)
        ? (inner['options'] as List)
        : (json['options'] is List ? (json['options'] as List) : null);

    final optA = inner['option_a'] ?? inner['optionA'] ?? json['option_a'] ?? json['optionA'] ?? opts?['A'] ?? opts?['a'] ?? (optsList != null && optsList.isNotEmpty ? optsList[0] : null) ?? 'Option A';
    final optB = inner['option_b'] ?? inner['optionB'] ?? json['option_b'] ?? json['optionB'] ?? opts?['B'] ?? opts?['b'] ?? (optsList != null && optsList.length > 1 ? optsList[1] : null) ?? 'Option B';
    final optC = inner['option_c'] ?? inner['optionC'] ?? json['option_c'] ?? json['optionC'] ?? opts?['C'] ?? opts?['c'] ?? (optsList != null && optsList.length > 2 ? optsList[2] : null) ?? 'Option C';
    final optD = inner['option_d'] ?? inner['optionD'] ?? json['option_d'] ?? json['optionD'] ?? opts?['D'] ?? opts?['d'] ?? (optsList != null && optsList.length > 3 ? optsList[3] : null) ?? 'Option D';
    final correct = inner['correct_option'] ?? inner['correctOption'] ?? inner['correct'] ?? json['correct_option'] ?? json['correctOption'] ?? json['correct'] ?? 'A';

    return Question(
      id: (inner['id'] ?? inner['question_id'] ?? json['id'] ?? json['question_id'] ?? DateTime.now().millisecondsSinceEpoch.toString()).toString(),
      category: (inner['category'] ?? inner['genre'] ?? json['category'] ?? json['genre'] ?? 'General Knowledge').toString(),
      difficulty: (inner['difficulty'] ?? json['difficulty'] ?? 'Standard').toString(),
      questionText: cleanQuestionText((inner['question_text'] ?? inner['text'] ?? inner['question'] ?? json['question_text'] ?? json['text'] ?? json['question'] ?? '').toString()),
      optionA: optA.toString(),
      optionB: optB.toString(),
      optionC: optC.toString(),
      optionD: optD.toString(),
      correctOption: correct.toString().toUpperCase().trim(),
      timeLimitSeconds: (inner['time_limit_seconds'] ?? inner['duration_seconds'] ?? json['time_limit_seconds'] ?? json['duration_seconds'] as num?)?.toInt() ?? 20,
    );
  }

  List<String> get wrongOptions {
    final map = {'A': optionA, 'B': optionB, 'C': optionC, 'D': optionD};
    return map.entries
        .where((e) => e.key != correctOption.toUpperCase().trim())
        .map((e) => e.value)
        .toList();
  }

  Question copyWith({
    String? id,
    String? category,
    String? difficulty,
    String? questionText,
    String? optionA,
    String? optionB,
    String? optionC,
    String? optionD,
    String? correctOption,
    int? timeLimitSeconds,
  }) {
    return Question(
      id: id ?? this.id,
      category: category ?? this.category,
      difficulty: difficulty ?? this.difficulty,
      questionText: questionText ?? this.questionText,
      optionA: optionA ?? this.optionA,
      optionB: optionB ?? this.optionB,
      optionC: optionC ?? this.optionC,
      optionD: optionD ?? this.optionD,
      correctOption: correctOption ?? this.correctOption,
      timeLimitSeconds: timeLimitSeconds ?? this.timeLimitSeconds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'question_id': id,
      'category': category,
      'genre': category,
      'difficulty': difficulty,
      'text': questionText,
      'question_text': questionText,
      'option_a': optionA,
      'option_b': optionB,
      'option_c': optionC,
      'option_d': optionD,
      'options': {
        'A': optionA,
        'B': optionB,
        'C': optionC,
        'D': optionD,
      },
      'correct': correctOption,
      'correct_option': correctOption,
      'time_limit_seconds': timeLimitSeconds,
    };
  }
}
