import 'dart:async';
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

  int selectedTimerSeconds = 60;
  int currentQuestionIndex = 0;
  int currentRound = 1;
  List<String> selectedGenres = [];
  String gamePlayMode = 'Auto'; // 'Auto' (default) or 'Manual'

  Question? activeQuestion;
  int activeQuestionTimerEndsAtEpochMs = 0;
  int remainingQuestionSeconds = 60;

  Timer? _preGameTimer;
  Timer? _questionTimer;
  Timer? _resumeTimer;

  void startPreGame({
    required String roomCode,
    required int timerSeconds,
    List<String> genres = const [],
    int durationSeconds = 30,
  }) {
    if (isPreGameCountdownActive || isEngineRunning) return;

    selectedTimerSeconds = timerSeconds;
    selectedGenres = List.from(genres);
    isPreGameCountdownActive = true;
    isGamePaused = false;
    isResumeCountdownActive = false;
    preGameSecondsRemaining = durationSeconds;

    final startsAtEpochMs = DateTime.now().millisecondsSinceEpoch + (durationSeconds * 1000);

    _realtimeService.broadcastGameStarting(
      roomCode: roomCode,
      startsAtEpochMs: startsAtEpochMs,
    );

    _preGameTimer?.cancel();
    _preGameTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (preGameSecondsRemaining > 1) {
        preGameSecondsRemaining--;
        _realtimeService.broadcastGameStarting(
          roomCode: roomCode,
          startsAtEpochMs: DateTime.now().millisecondsSinceEpoch + (preGameSecondsRemaining * 1000),
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

    final question = TriviaRepository.getQuestionForGenres(selectedGenres, currentQuestionIndex);
    activeQuestion = question;
    final timerEndsAtEpochMs = DateTime.now().millisecondsSinceEpoch + (selectedTimerSeconds * 1000);
    activeQuestionTimerEndsAtEpochMs = timerEndsAtEpochMs;
    remainingQuestionSeconds = selectedTimerSeconds;

    _realtimeService.broadcastQuestion(
      roomCode: roomCode,
      questionIndex: currentQuestionIndex + 1,
      question: question,
      durationSeconds: selectedTimerSeconds,
      timerEndsAtEpochMs: timerEndsAtEpochMs,
      roundNumber: currentRound,
    );

    // Simulate active gameplay for mock players during this question
    SupabaseService.simulateMockAnswersForQuestion(
      roomCode: roomCode,
      correctOption: question.correctOption,
    );

    currentQuestionIndex++;

    _questionTimer?.cancel();
    _questionTimer = Timer(Duration(seconds: selectedTimerSeconds), () {
      if (!isEngineRunning) return;

      final nextQuestionStartsAtEpochMs = DateTime.now().millisecondsSinceEpoch + (15 * 1000);
      _realtimeService.broadcastTimerExpired(
        roomCode: roomCode,
        correctOption: question.correctOption,
        nextQuestionStartsAtEpochMs: nextQuestionStartsAtEpochMs,
        gamePlayMode: gamePlayMode,
      );

      // Check if 10-question round has completed
      if (currentQuestionIndex >= 10) {
        currentQuestionIndex = 0;
        final top3 = SupabaseService.awardRoundWinnerBonusAndGetTop3(roomCode, 20);
        final nextRoundStartsAtEpochMs = DateTime.now().millisecondsSinceEpoch + (15 * 1000);

        _realtimeService.broadcastRoundCompleted(
          roomCode: roomCode,
          top3Winners: top3,
          roundNumber: currentRound,
          nextRoundStartsAtEpochMs: nextRoundStartsAtEpochMs,
        );

        _realtimeService.broadcastLeaderboardUpdated(
          roomCode: roomCode,
          players: SupabaseService.getLocalPlayersJson(roomCode),
        );

        currentRound++;

        // Rotate to the next genre for the upcoming round
        if (selectedGenres.length > 1) {
          final completedGenre = selectedGenres.removeAt(0);
          selectedGenres.add(completedGenre);
        } else if (selectedGenres.isEmpty) {
          selectedGenres = List.from(TriviaGenres.allGenres.where((g) => g != 'Auto Select' && g != 'Random (Mixed)'));
        }

        // Schedule inter-round delay before Question 1 of next round
        _questionTimer = Timer(const Duration(seconds: 15), () {
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
      } else if (gamePlayMode == 'Auto') {
        // 15-Second Review phase before proceeding to next question automatically in Auto mode
        _questionTimer = Timer(const Duration(seconds: 15), () {
          if (isEngineRunning) {
            broadcastNextQuestion(roomCode: roomCode);
          }
        });
      }
    });
  }

  void nextQuestionManual({required String roomCode}) {
    if (!isEngineRunning) return;
    _questionTimer?.cancel();
    broadcastNextQuestion(roomCode: roomCode);
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
    _realtimeService.broadcastGamePaused(roomCode: roomCode);
  }

  void resumeGame({String roomCode = 'TRIV'}) {
    if (!isGamePaused) return;

    isResumeCountdownActive = true;
    resumeSecondsRemaining = 10;

    final startsAtEpochMs = DateTime.now().millisecondsSinceEpoch + 10 * 1000;
    _realtimeService.broadcastGameResuming(
      roomCode: roomCode,
      startsAtEpochMs: startsAtEpochMs,
      remainingQuestionSeconds: remainingQuestionSeconds > 0 ? remainingQuestionSeconds : selectedTimerSeconds,
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

    _realtimeService.broadcastQuestion(
      roomCode: roomCode,
      questionIndex: currentQuestionIndex > 0 ? currentQuestionIndex : 1,
      question: question,
      durationSeconds: durationSec,
      timerEndsAtEpochMs: timerEndsAtEpochMs,
    );

    _questionTimer?.cancel();
    _questionTimer = Timer(Duration(seconds: durationSec), () {
      if (!isEngineRunning) return;

      final nextQuestionStartsAtEpochMs = DateTime.now().millisecondsSinceEpoch + (15 * 1000);
      _realtimeService.broadcastTimerExpired(
        roomCode: roomCode,
        correctOption: question.correctOption,
        nextQuestionStartsAtEpochMs: nextQuestionStartsAtEpochMs,
        gamePlayMode: gamePlayMode,
      );

      if (gamePlayMode == 'Auto') {
        _questionTimer = Timer(const Duration(seconds: 15), () {
          if (isEngineRunning) {
            broadcastNextQuestion(roomCode: roomCode);
          }
        });
      }
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
