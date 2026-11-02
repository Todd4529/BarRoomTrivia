import 'dart:async';
import '../config/supabase_config.dart';
import '../data/trivia_repository.dart';
import '../data/trivia_genres.dart';
import '../models/question.dart';
import 'realtime_service.dart';
import 'supabase_service.dart';

class GameEngineManager {
  static final GameEngineManager instance = GameEngineManager._internal();
  GameEngineManager._internal();

  final RealtimeService _realtimeService = RealtimeService();
  final SupabaseService _supabaseService = SupabaseService();

  bool isPreGameCountdownActive = false;
  int preGameSecondsRemaining = 30;
  bool isEngineRunning = false;
  bool isGamePaused = false;
  bool isResumeCountdownActive = false;
  int resumeSecondsRemaining = 10;

  int selectedTimerSeconds = 90;
  int currentQuestionIndex = 0;
  int currentRound = 1;
  int interRoundDurationSeconds = 120;
  List<String> selectedGenres = [];
  String gamePlayMode = 'Auto'; // 'Auto' (default) or 'Manual'

  Question? activeQuestion;
  int activeQuestionTimerEndsAtEpochMs = 0;
  int remainingQuestionSeconds = 90;
  bool isQuestionTimerRunning = false;
  bool isReviewPhase = false;
  bool isRoundCompletedWaitingForNext = false;

  int get displayRemainingSeconds {
    if (!isQuestionTimerRunning) return remainingQuestionSeconds;
    final now = DateTime.now().millisecondsSinceEpoch;
    final rem = ((activeQuestionTimerEndsAtEpochMs - now) / 1000).ceil();
    return rem > 0 ? rem : 0;
  }

  Timer? _preGameTimer;
  Timer? _questionTimer;
  Timer? _resumeTimer;

  void startPreGame({
    required String roomCode,
    required int timerSeconds,
    List<String> genres = const [],
    int durationSeconds = 30,
    bool isNewGame = false,
    int? roundNumber,
  }) {
    if (isPreGameCountdownActive || isEngineRunning) return;

    if (isNewGame || roundNumber == 1) {
      currentRound = 1;
      currentQuestionIndex = 0;
    } else if (roundNumber != null && roundNumber > 0) {
      currentRound = roundNumber;
      currentQuestionIndex = 0;
    } else {
      currentQuestionIndex = 0;
    }

    selectedTimerSeconds = timerSeconds;
    selectedGenres = List.from(genres);
    isPreGameCountdownActive = true;
    isGamePaused = false;
    isResumeCountdownActive = false;
    isQuestionTimerRunning = false;
    isReviewPhase = false;
    isRoundCompletedWaitingForNext = false;
    preGameSecondsRemaining = durationSeconds;

    final startsAtEpochMs = DateTime.now().millisecondsSinceEpoch + (durationSeconds * 1000);

    _realtimeService.broadcastGameStarting(
      roomCode: roomCode,
      startsAtEpochMs: startsAtEpochMs,
      roundNumber: currentRound,
      genre: selectedGenres.isNotEmpty ? selectedGenres.first : null,
    );

    try {
      SupabaseConfig.client.from('game_sessions').upsert({
        'room_code': roomCode.toUpperCase().trim(),
        'status': 'pre_game_countdown',
        'starts_at': startsAtEpochMs,
        'current_question_index': 0,
        'current_round': currentRound,
        'round_number': currentRound,
        'genre': selectedGenres.isNotEmpty ? selectedGenres.first : 'General Trivia',
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}

    _preGameTimer?.cancel();
    _preGameTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (preGameSecondsRemaining > 1) {
        preGameSecondsRemaining--;
        _realtimeService.broadcastGameStarting(
          roomCode: roomCode,
          startsAtEpochMs: DateTime.now().millisecondsSinceEpoch + (preGameSecondsRemaining * 1000),
          roundNumber: currentRound,
          genre: selectedGenres.isNotEmpty ? selectedGenres.first : null,
        );
      } else {
        timer.cancel();
        isPreGameCountdownActive = false;
        isEngineRunning = true;
        broadcastNextQuestion(roomCode: roomCode);
      }
    });
  }

  void broadcastNextQuestion({required String roomCode}) {
    if (!isEngineRunning) return;
    isGamePaused = false;
    isResumeCountdownActive = false;
    isReviewPhase = false;
    isRoundCompletedWaitingForNext = false;

    final question = TriviaRepository.getQuestionForGenres(selectedGenres, currentQuestionIndex);
    activeQuestion = question;
    remainingQuestionSeconds = gamePlayMode == 'Manual' ? 20 : selectedTimerSeconds;

    final cumulativeIndex = ((currentRound - 1) * 10) + currentQuestionIndex + 1;

    if (gamePlayMode == 'Manual') {
      // In Manual Mode, host starts in READING phase: hold the timer until host triggers 'START TIMER'
      isQuestionTimerRunning = false;
      activeQuestionTimerEndsAtEpochMs = 0;

      try {
        SupabaseConfig.client.from('game_sessions').upsert({
          'room_code': roomCode.toUpperCase().trim(),
          'status': 'active_reading',
          'current_question_index': cumulativeIndex,
          'current_round': currentRound,
          'round_number': currentRound,
          'duration_seconds': 20,
          'timer_ends_at': null,
          'game_play_mode': 'Manual',
          'category': question.category,
          'genre': question.category,
          'question_data': {
            ...question.toJson(),
            'round_number': currentRound,
            'question_number_in_round': ((currentQuestionIndex) % 10) + 1,
          },
          'updated_at': DateTime.now().toIso8601String(),
        });
      } catch (_) {}

      _realtimeService.broadcastQuestion(
        roomCode: roomCode,
        questionIndex: cumulativeIndex,
        question: question,
        durationSeconds: 20,
        timerEndsAtEpochMs: 0,
        roundNumber: currentRound,
        totalQuestions: 10,
        gamePlayMode: 'Manual',
        questionPhase: 'reading',
        timerState: 'idle',
      );

      _questionTimer?.cancel();
      currentQuestionIndex++;
      return;
    }

    // In Auto Mode: start countdown immediately
    isQuestionTimerRunning = true;
    final timerEndsAtEpochMs = DateTime.now().millisecondsSinceEpoch + (selectedTimerSeconds * 1000);
    activeQuestionTimerEndsAtEpochMs = timerEndsAtEpochMs;

    try {
      SupabaseConfig.client.from('game_sessions').upsert({
        'room_code': roomCode.toUpperCase().trim(),
        'status': 'question_active',
        'current_question_index': cumulativeIndex,
        'current_round': currentRound,
        'round_number': currentRound,
        'duration_seconds': selectedTimerSeconds,
        'timer_ends_at': timerEndsAtEpochMs,
        'game_play_mode': 'Auto',
        'category': question.category,
        'genre': question.category,
        'question_data': {
          ...question.toJson(),
          'round_number': currentRound,
          'question_number_in_round': ((currentQuestionIndex) % 10) + 1,
        },
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}

    _realtimeService.broadcastQuestion(
      roomCode: roomCode,
      questionIndex: cumulativeIndex,
      question: question,
      durationSeconds: selectedTimerSeconds,
      timerEndsAtEpochMs: timerEndsAtEpochMs,
      roundNumber: currentRound,
      totalQuestions: 10,
      gamePlayMode: 'Auto',
      questionPhase: 'countdown',
      timerState: 'running',
    );

    // Simulate active gameplay for mock players during this question
    SupabaseService.simulateMockAnswersForQuestion(
      roomCode: roomCode,
      correctOption: question.correctOption,
    );

    currentQuestionIndex++;

    _questionTimer?.cancel();
    _questionTimer = Timer(Duration(seconds: selectedTimerSeconds), () {
      _handleQuestionTimerExpiration(roomCode: roomCode, question: question);
    });
  }

  /// Manually starts countdown in Manual Mode (automatically 20 seconds)
  void startManualTimer({required String roomCode}) {
    if (!isEngineRunning || activeQuestion == null || isQuestionTimerRunning) return;

    final question = activeQuestion!;
    isQuestionTimerRunning = true;
    isReviewPhase = false;
    const manualTimerSeconds = 20;
    final timerEndsAtEpochMs = DateTime.now().millisecondsSinceEpoch + (manualTimerSeconds * 1000);
    activeQuestionTimerEndsAtEpochMs = timerEndsAtEpochMs;
    remainingQuestionSeconds = manualTimerSeconds;

    _realtimeService.broadcastManualTimerStarted(
      roomCode: roomCode,
      timerEndsAtEpochMs: timerEndsAtEpochMs,
      durationSeconds: manualTimerSeconds,
      questionIndex: currentQuestionIndex,
      roundNumber: currentRound,
    );

    // Simulate mock player answers during manual timer countdown
    SupabaseService.simulateMockAnswersForQuestion(
      roomCode: roomCode,
      correctOption: question.correctOption,
    );

    _questionTimer?.cancel();
    _questionTimer = Timer(const Duration(seconds: manualTimerSeconds), () {
      _handleQuestionTimerExpiration(roomCode: roomCode, question: question);
    });
  }

  /// Manually skips or expires the active timer in Manual Mode
  void expireTimerManual({required String roomCode}) {
    if (!isEngineRunning || activeQuestion == null) return;
    _questionTimer?.cancel();
    _handleQuestionTimerExpiration(roomCode: roomCode, question: activeQuestion!);
  }

  void _handleQuestionTimerExpiration({required String roomCode, required Question question}) {
    if (!isEngineRunning) return;
    isQuestionTimerRunning = false;
    isReviewPhase = true;

    final isRoundEnding = currentQuestionIndex >= 10;
    final reviewSeconds = isRoundEnding ? 20 : 15;
    final nextTargetEpochMs = DateTime.now().millisecondsSinceEpoch + (reviewSeconds * 1000);

    _realtimeService.broadcastTimerExpired(
      roomCode: roomCode,
      correctOption: question.correctOption,
      nextQuestionStartsAtEpochMs: nextTargetEpochMs,
      gamePlayMode: gamePlayMode,
      questionId: question.id,
      questionIndex: currentQuestionIndex,
      roundNumber: currentRound,
    );

    if (isRoundEnding) {
      if (gamePlayMode == 'Auto') {
        // Display Question 10 correct answer for 20 seconds before proceeding to round summary
        _questionTimer = Timer(Duration(seconds: reviewSeconds), () {
          if (isEngineRunning) {
            _advanceToRoundCompletion(roomCode: roomCode);
          }
        });
      }
    } else {
      if (gamePlayMode == 'Auto') {
        // 15-Second Review phase before proceeding to next question automatically in Auto mode
        _questionTimer = Timer(Duration(seconds: reviewSeconds), () {
          if (isEngineRunning) {
            broadcastNextQuestion(roomCode: roomCode);
          }
        });
      }
    }
  }

  void _advanceToRoundCompletion({required String roomCode}) {
    currentQuestionIndex = 0;
    isReviewPhase = false;
    final top3 = SupabaseService.awardRoundWinnerBonusAndGetTop3(roomCode, 20);
    final interRoundSecs = interRoundDurationSeconds > 0 ? interRoundDurationSeconds : 120;
    final nextRoundStartsAtEpochMs = DateTime.now().millisecondsSinceEpoch + (interRoundSecs * 1000);
    final nextRound = currentRound + 1;

    try {
      SupabaseConfig.client.from('game_sessions').upsert({
        'room_code': roomCode.toUpperCase().trim(),
        'status': 'round_summary',
        'current_round': nextRound,
        'round_number': currentRound,
        'starts_at': nextRoundStartsAtEpochMs,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}

    _realtimeService.broadcastRoundCompleted(
      roomCode: roomCode,
      top3Winners: top3,
      roundNumber: currentRound,
      nextRound: nextRound,
      nextRoundStartsAtEpochMs: nextRoundStartsAtEpochMs,
      delaySeconds: interRoundSecs,
    );

    _realtimeService.broadcastLeaderboardUpdated(
      roomCode: roomCode,
      players: SupabaseService.getLocalPlayersJson(roomCode),
    );

    currentRound = nextRound;

    // Rotate to the next genre for the upcoming round
    if (selectedGenres.length > 1) {
      final completedGenre = selectedGenres.removeAt(0);
      selectedGenres.add(completedGenre);
    } else if (selectedGenres.isEmpty) {
      selectedGenres = List.from(TriviaGenres.allGenres.where((g) => g != 'Auto Select' && g != 'Random (Mixed)'));
    }

    if (gamePlayMode == 'Auto') {
      // Schedule inter-round delay before Question 1 of next round in Auto Mode
      _questionTimer = Timer(Duration(seconds: interRoundSecs), () {
        if (isEngineRunning) {
          isEngineRunning = false;
          startPreGame(
            roomCode: roomCode,
            timerSeconds: selectedTimerSeconds,
            genres: selectedGenres,
            durationSeconds: 10,
          );
        }
      });
    } else {
      // Manual mode: hold on round summary until host taps 'START NEXT ROUND'
      isRoundCompletedWaitingForNext = true;
    }
  }

  void nextQuestionManual({required String roomCode}) {
    if (!isEngineRunning) return;
    _questionTimer?.cancel();
    isReviewPhase = false;
    if (currentQuestionIndex >= 10) {
      _advanceToRoundCompletion(roomCode: roomCode);
    } else {
      broadcastNextQuestion(roomCode: roomCode);
    }
  }

  void startNextRoundManual({required String roomCode}) {
    _questionTimer?.cancel();
    isRoundCompletedWaitingForNext = false;
    isEngineRunning = false;
    startPreGame(
      roomCode: roomCode,
      timerSeconds: selectedTimerSeconds,
      genres: selectedGenres,
      durationSeconds: 10,
    );
  }

  void pauseGame({String roomCode = 'TRIV'}) {
    _preGameTimer?.cancel();
    _questionTimer?.cancel();
    _resumeTimer?.cancel();

    if (isEngineRunning && activeQuestion != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final remaining = ((activeQuestionTimerEndsAtEpochMs - now) / 1000).ceil();
      remainingQuestionSeconds = remaining > 0 ? remaining : selectedTimerSeconds;
    }

    isPreGameCountdownActive = false;
    isEngineRunning = false;
    isGamePaused = true;
    isResumeCountdownActive = false;

    try {
      SupabaseConfig.client.from('game_sessions').upsert({
        'room_code': roomCode.toUpperCase().trim(),
        'status': 'paused',
        'remaining_question_seconds': remainingQuestionSeconds,
        'current_round': currentRound,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}

    _realtimeService.broadcastGamePaused(
      roomCode: roomCode,
      remainingQuestionSeconds: remainingQuestionSeconds,
      roundNumber: currentRound,
      questionIndex: currentQuestionIndex,
    );
  }

  void resumeGame({String roomCode = 'TRIV'}) {
    if (!isGamePaused) return;

    isResumeCountdownActive = true;
    resumeSecondsRemaining = 10;

    final startsAtEpochMs = DateTime.now().millisecondsSinceEpoch + 10 * 1000;

    try {
      SupabaseConfig.client.from('game_sessions').upsert({
        'room_code': roomCode.toUpperCase().trim(),
        'status': 'question_active',
        'current_round': currentRound,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}

    _realtimeService.broadcastGameResuming(
      roomCode: roomCode,
      startsAtEpochMs: startsAtEpochMs,
      remainingQuestionSeconds: remainingQuestionSeconds > 0 ? remainingQuestionSeconds : selectedTimerSeconds,
      roundNumber: currentRound,
      questionIndex: currentQuestionIndex,
    );

    _resumeTimer?.cancel();
    _resumeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (resumeSecondsRemaining > 1) {
        resumeSecondsRemaining--;
      } else {
        timer.cancel();
        isResumeCountdownActive = false;
        isGamePaused = false;
        isEngineRunning = true;

        if (activeQuestion != null) {
          _resumeCurrentQuestion(roomCode: roomCode);
        } else {
          broadcastNextQuestion(roomCode: roomCode);
        }
      }
    });
  }

  void _resumeCurrentQuestion({required String roomCode}) {
    if (!isEngineRunning || activeQuestion == null) return;

    final question = activeQuestion!;
    final durationSec = remainingQuestionSeconds > 0 ? remainingQuestionSeconds : selectedTimerSeconds;
    final timerEndsAtEpochMs = DateTime.now().millisecondsSinceEpoch + (durationSec * 1000);
    activeQuestionTimerEndsAtEpochMs = timerEndsAtEpochMs;

    final cumulativeIndex = ((currentRound - 1) * 10) + (currentQuestionIndex > 0 ? currentQuestionIndex : 1);
    _realtimeService.broadcastQuestion(
      roomCode: roomCode,
      questionIndex: cumulativeIndex,
      question: question,
      durationSeconds: durationSec,
      timerEndsAtEpochMs: timerEndsAtEpochMs,
      roundNumber: currentRound,
      totalQuestions: 10,
    );

    _questionTimer?.cancel();
    _questionTimer = Timer(Duration(seconds: durationSec), () {
      _handleQuestionTimerExpiration(roomCode: roomCode, question: question);
    });
  }

  void resetGame({String roomCode = 'TRIV', String resetMode = 'keep_scores'}) {
    _preGameTimer?.cancel();
    _questionTimer?.cancel();
    _resumeTimer?.cancel();

    isEngineRunning = false;
    isPreGameCountdownActive = false;
    isGamePaused = false;
    isResumeCountdownActive = false;
    currentQuestionIndex = 0;
    currentRound = 1;
    activeQuestion = null;

    if (resetMode == 'zero_scores') {
      _supabaseService.resetRoomScores(roomCode);
    } else if (resetMode == 'clear_all') {
      _supabaseService.clearRoomLeaderboard(roomCode);
    }

    _realtimeService.broadcastGameReset(
      roomCode: roomCode,
      resetMode: resetMode,
    );

    if (resetMode == 'keep_scores' || resetMode == 'zero_scores') {
      startPreGame(roomCode: roomCode, timerSeconds: selectedTimerSeconds, genres: selectedGenres);
    }
  }
}
