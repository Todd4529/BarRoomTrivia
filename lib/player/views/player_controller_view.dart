import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../shared/models/game_session.dart';
import '../../shared/models/player.dart';
import '../../shared/models/question.dart';
import '../../shared/services/realtime_service.dart';
import '../../shared/services/supabase_service.dart';
import '../../shared/theme/app_theme.dart';
import '../widgets/real_hourglass_widget.dart';

class PlayerControllerView extends StatefulWidget {
  final String? initialRoomCode;

  const PlayerControllerView({super.key, this.initialRoomCode});

  @override
  State<PlayerControllerView> createState() => _PlayerControllerViewState();
}

class _PlayerControllerViewState extends State<PlayerControllerView> {
  final SupabaseService _supabaseService = SupabaseService();
  final RealtimeService _realtimeService = RealtimeService();

  final TextEditingController _nicknameController = TextEditingController();
  final TextEditingController _roomCodeController = TextEditingController();

  Player? _player;
  GameSession? _gameSession;
  bool _isAuthenticating = false;

  // Realtime Question State
  Question? _currentQuestion;
  DateTime? _questionStartedAt;
  String? _currentQuestionId;
  String? _selectedOption;
  String? _correctOption;
  bool _inputsLocked = true;
  bool _isReviewPhase = false;
  int _remainingSeconds = 0;
  int? _targetTimerEndsAtMs;
  int _questionNumberInRound = 1;
  int _currentRound = 1;
  int _myScore = 0;
  Timer? _localTimer;
  Timer? _preGameTimer;
  bool _isPreGameCountdown = false;
  int _preGameSecondsRemaining = 30;
  bool _isGamePaused = false;
  bool _isResumeCountdownActive = false;
  int _resumeSecondsRemaining = 10;
  Timer? _resumeTimer;
  bool _isInterQuestionPhase = false;
  int _interQuestionSecondsRemaining = 30;
  Timer? _interQuestionTimer;
  String _gamePlayMode = 'Auto';
  bool _isScoredForThisQuestion = false;
  List<Map<String, dynamic>> _top3Winners = [];
  bool _showRoundWinnersOverlay = false;
  bool _isInterRoundPhase = false;
  int _interRoundSecondsRemaining = 15;
  Timer? _interRoundTimer;
  bool _showResultOverlay = false;
  Timer? _resultOverlayTimer;

  @override
  void initState() {
    super.initState();
    // Default room code for auto-join in development
    _roomCodeController.text = 'TRIV';
    if (widget.initialRoomCode != null && widget.initialRoomCode!.isNotEmpty) {
      _roomCodeController.text = widget.initialRoomCode!.toUpperCase();
    }
  }

  Future<void> _joinGame() async {
    final roomCode = _roomCodeController.text.trim().toUpperCase();
    final nickname = _nicknameController.text.trim();

    if (roomCode.isEmpty || nickname.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter both Room Code and Nickname')),
      );
      return;
    }

    setState(() {
      _isAuthenticating = true;
    });

    try {
      final session = await _supabaseService.getSessionByRoomCode(roomCode);
      final player = await _supabaseService.registerPlayer(
        roomCode: roomCode,
        nickname: nickname,
      );

      // Instantly broadcast player_joined across MQTT and local bus so TV display sees them
      _realtimeService.broadcastPlayerJoined(
        roomCode: roomCode,
        nickname: nickname,
      );
      Future.delayed(const Duration(milliseconds: 400), () {
        _realtimeService.broadcastPlayerJoined(
          roomCode: roomCode,
          nickname: nickname,
        );
      });
      Future.delayed(const Duration(milliseconds: 1200), () {
        _realtimeService.broadcastPlayerJoined(
          roomCode: roomCode,
          nickname: nickname,
        );
      });

      if (mounted) {
        setState(() {
          _gameSession = session ??
              GameSession(
                id: 'dev-session-id',
                roomCode: roomCode,
                status: 'active',
                questionIndex: 0,
                createdAt: DateTime.now(),
              );
          _player = player;
          _myScore = player.cumulativeScore;
          _isAuthenticating = false;
        });

        _listenToGameEvents(roomCode);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAuthenticating = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
        );
      }
    }
  }

  void _listenToGameEvents(String roomCode) {
    _realtimeService.joinRoomChannel(
      roomCode: roomCode,
      onQuestionBroadcast: (payload) async {
        final rawTimerEnds = payload['timer_ends_at_epoch_ms'] ??
            payload['timerEndsAtMs'] ??
            payload['timer_ends_at'] ??
            payload['timerEndsAtEpochMs'];
        final timerEndsAtEpochMs = (rawTimerEnds is num)
            ? rawTimerEnds.toInt()
            : int.tryParse('$rawTimerEnds');
        final qIndex = (payload['question_index'] as num?)?.toInt() ?? 1;

        Question? question;
        if (payload.containsKey('question_text') ||
            payload.containsKey('text') ||
            payload.containsKey('question') ||
            payload.containsKey('questionData') ||
            payload.containsKey('question_data') ||
            payload.containsKey('option_a') ||
            payload.containsKey('options')) {
          question = Question.fromJson(payload);
        } else {
          final qId = (payload['question_id'] ?? payload['id']) as String?;
          if (qId != null) {
            question = await _supabaseService.getQuestionById(qId);
          }
        }

        if (question != null) {
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          final fallbackDuration = (payload['duration_seconds'] as num?)?.toInt() ??
              (payload['durationSeconds'] as num?)?.toInt() ??
              (payload['time_limit_seconds'] as num?)?.toInt() ??
              20;

          final targetEndsAt = (timerEndsAtEpochMs != null && timerEndsAtEpochMs > nowMs)
              ? timerEndsAtEpochMs
              : (nowMs + fallbackDuration * 1000);
          _targetTimerEndsAtMs = targetEndsAt;

          final remainingMs = targetEndsAt - nowMs;
          int durationSec = max(0, (remainingMs / 1000).ceil().clamp(0, 180));

          // Check if this broadcast is simply a state-sync or re-broadcast of the active question
          final isSameQuestion = _currentQuestion != null &&
              (_currentQuestion!.id == question.id ||
                  (_currentQuestion!.questionText.isNotEmpty &&
                      _currentQuestion!.questionText == question.questionText));

          if (isSameQuestion && _selectedOption != null) {
            // Player already locked in their answer! Keep their answer and locked inputs intact.
            setState(() {
              _remainingSeconds = durationSec;
              final rFromPayload = (payload['round_number'] as num?)?.toInt() ??
                  (payload['roundNumber'] as num?)?.toInt();
              if (rFromPayload != null && rFromPayload > 0) {
                _currentRound = max(_currentRound, rFromPayload);
              }
            });
            return;
          }

          _questionStartedAt = DateTime.now();
          _currentQuestionId = question.id;
          _localTimer?.cancel();
          _interQuestionTimer?.cancel();
          _interRoundTimer?.cancel();
          _resultOverlayTimer?.cancel();
          setState(() {
            _isGamePaused = false;
            _isPreGameCountdown = false;
            _isInterQuestionPhase = false;
            _isInterRoundPhase = false;
            _showResultOverlay = false;
            _showRoundWinnersOverlay = false;
            _preGameTimer?.cancel();
            _currentQuestion = question;
            _selectedOption = null;
            _correctOption = null;
            _inputsLocked = false;
            _isReviewPhase = false;
            _isScoredForThisQuestion = false;
            final rFromPayload = (payload['round_number'] as num?)?.toInt() ??
                (payload['roundNumber'] as num?)?.toInt();
            if (rFromPayload != null && rFromPayload > 0) {
              _currentRound = max(_currentRound, rFromPayload);
            }
            _remainingSeconds = durationSec;
            _questionNumberInRound = ((qIndex - 1) % 10) + 1;
          });

          _startLocalCountdown();
        }
      },
      onTimerExpiredBroadcast: (payload) {
        _lockInputsAndReveal(payload['correct_option'] as String?);

        final mode = payload['game_play_mode'] as String? ?? 'Auto';
        final nextStartsAt = (payload['next_question_starts_at_epoch_ms'] as int?) ??
            (payload['nextQuestionStartsAtEpochMs'] as int?) ??
            (DateTime.now().millisecondsSinceEpoch + 15000);
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final remaining = ((nextStartsAt - nowMs) / 1000).ceil().clamp(1, 15);

        setState(() {
          _isInterQuestionPhase = true;
          _interQuestionSecondsRemaining = remaining;
          _gamePlayMode = mode;
        });

        _interQuestionTimer?.cancel();
        if (mode == 'Auto') {
          _interQuestionTimer = Timer.periodic(const Duration(milliseconds: 500), (t) {
            final now = DateTime.now().millisecondsSinceEpoch;
            final rem = ((nextStartsAt - now) / 1000).ceil();
            if (rem > 0) {
              if (mounted) {
                if (_interQuestionSecondsRemaining != rem || (rem <= 5 && _showResultOverlay)) {
                  setState(() {
                    _interQuestionSecondsRemaining = rem;
                    if (rem <= 5 && _showResultOverlay) {
                      _showResultOverlay = false;
                    }
                  });
                }
              }
            } else {
              _interQuestionTimer?.cancel();
              if (mounted) {
                setState(() {
                  _isInterQuestionPhase = false;
                  _interQuestionSecondsRemaining = 0;
                  _showResultOverlay = false;
                });
              }
            }
          });
        }
      },
      onPreGameCountdownBroadcast: (payload) {
        final startsAt = payload['starts_at_epoch_ms'] as int? ?? (DateTime.now().millisecondsSinceEpoch + 30000);
        final now = DateTime.now().millisecondsSinceEpoch;
        final diffMs = startsAt - now;
        final remainingSec = (diffMs / 1000).ceil().clamp(1, 30);
        final rFromPayload = (payload['round_number'] as num?)?.toInt() ??
            (payload['roundNumber'] as num?)?.toInt();
        if (rFromPayload != null && rFromPayload > 0) {
          _currentRound = max(_currentRound, rFromPayload);
        }

        _interRoundTimer?.cancel();
        setState(() {
          _isGamePaused = false;
          _isPreGameCountdown = true;
          _isInterRoundPhase = false;
          _showResultOverlay = false;
          _showRoundWinnersOverlay = false;
          _isInterQuestionPhase = false;
          _currentQuestion = null;
          _selectedOption = null;
          _correctOption = null;
          _inputsLocked = false;
          _isReviewPhase = false;
          _isScoredForThisQuestion = false;
          _preGameSecondsRemaining = remainingSec;
        });
        _startPreGameTimer();
      },
      onGamePausedBroadcast: (payload) {
        _localTimer?.cancel();
        _preGameTimer?.cancel();
        _resumeTimer?.cancel();
        _interRoundTimer?.cancel();
        setState(() {
          _isGamePaused = true;
          _isResumeCountdownActive = false;
          _isPreGameCountdown = false;
          _isInterRoundPhase = false;
          _showResultOverlay = false;
          _inputsLocked = true;
        });
      },
      onGameResumingBroadcast: (payload) {
        _localTimer?.cancel();
        _preGameTimer?.cancel();
        _resumeTimer?.cancel();

        final startsAt = payload['starts_at_epoch_ms'] as int? ?? (DateTime.now().millisecondsSinceEpoch + 10000);
        final now = DateTime.now().millisecondsSinceEpoch;
        final remainingSec = ((startsAt - now) / 1000).ceil().clamp(1, 10);
        final remainingQuestionSec = payload['remaining_question_seconds'] as int? ?? 60;

        setState(() {
          _isGamePaused = false;
          _isResumeCountdownActive = true;
          _resumeSecondsRemaining = remainingSec;
          _remainingSeconds = remainingQuestionSec;
          _inputsLocked = true;
        });

        _resumeTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          if (_resumeSecondsRemaining > 1) {
            if (mounted) {
              setState(() {
                _resumeSecondsRemaining--;
              });
            }
          } else {
            _resumeTimer?.cancel();
            if (mounted) {
              setState(() {
                _isResumeCountdownActive = false;
                _inputsLocked = false;
              });
              _startLocalCountdown();
            }
          }
        });
      },
      onGameResetBroadcast: (payload) {
        _localTimer?.cancel();
        _preGameTimer?.cancel();
        _resumeTimer?.cancel();
        _interQuestionTimer?.cancel();
        _interRoundTimer?.cancel();

        final mode = payload['reset_mode'] as String? ?? 'keep_scores';

        if (mounted) {
          setState(() {
            _currentQuestion = null;
            _selectedOption = null;
            _correctOption = null;
            _inputsLocked = false;
            _isReviewPhase = false;
            _showResultOverlay = false;
            _showRoundWinnersOverlay = false;
            _isPreGameCountdown = false;
            _isGamePaused = false;
            _isResumeCountdownActive = false;
            _isInterQuestionPhase = false;
            _isInterRoundPhase = false;

            if (mode == 'zero_scores') {
              _myScore = 0;
              if (_player != null) {
                _player = Player(
                  id: _player!.id,
                  roomCode: _player!.roomCode,
                  playerUid: _player!.playerUid,
                  nickname: _player!.nickname,
                  cumulativeScore: 0,
                  isConnected: true,
                );
              }
            } else if (mode == 'clear_all') {
              _player = null;
              _myScore = 0;
              _nicknameController.clear();
            }
          });
        }
      },
      onRoundCompletedBroadcast: (payload) {
        if (!mounted) return;
        _localTimer?.cancel();
        _interQuestionTimer?.cancel();
        _preGameTimer?.cancel();
        _resumeTimer?.cancel();
        _interRoundTimer?.cancel();

        List<Map<String, dynamic>> parsedWinners = [];
        try {
          final rawList = payload['top_3_winners'] as List? ??
              payload['top3_winners'] as List? ??
              payload['top3Winners'] as List?;
          if (rawList != null) {
            for (var item in rawList) {
              if (item is Map) {
                parsedWinners.add(Map<String, dynamic>.from(item));
              }
            }
          }
        } catch (_) {}

        if (parsedWinners.isEmpty && _player != null) {
          final top3 = SupabaseService.getTop3RoundWinners(_player!.roomCode);
          parsedWinners = List<Map<String, dynamic>>.from(top3);
        }

        final nextStartsAt = (payload['next_round_starts_at_epoch_ms'] as num?)?.toInt() ??
            (payload['nextRoundStartsAtEpochMs'] as num?)?.toInt();
        final delaySec = nextStartsAt != null
            ? (((nextStartsAt - DateTime.now().millisecondsSinceEpoch) / 1000).ceil().clamp(5, 660))
            : (payload['delaySeconds'] as num?)?.toInt() ?? 60;
        final completedR = (payload['completed_round'] as num?)?.toInt() ??
            (payload['round_number'] as num?)?.toInt() ??
            (payload['roundNumber'] as num?)?.toInt() ??
            _currentRound;
        final nextR = (payload['next_round'] as num?)?.toInt() ??
            (payload['nextRound'] as num?)?.toInt() ??
            (completedR + 1);
        _currentRound = max(_currentRound, nextR);

        if (parsedWinners.isNotEmpty && _player != null) {
          final winnerName = parsedWinners.first['nickname']?.toString().toLowerCase();
          if (winnerName == _player!.nickname.toLowerCase()) {
            final winnerScore = (parsedWinners.first['score'] as num?)?.toInt() ?? (_myScore + 20);
            if (winnerScore > _myScore) {
              _myScore = winnerScore;
              _player = Player(
                id: _player!.id,
                roomCode: _player!.roomCode,
                playerUid: _player!.playerUid,
                nickname: _player!.nickname,
                cumulativeScore: _myScore,
                isConnected: true,
              );
            }
          }
        }

        setState(() {
          _isInterRoundPhase = true;
          _interRoundSecondsRemaining = delaySec;
          _top3Winners = parsedWinners;
          _showRoundWinnersOverlay = parsedWinners.isNotEmpty;
          _showResultOverlay = false;
          _isInterQuestionPhase = false;
          _currentQuestion = null;
          _selectedOption = null;
          _correctOption = null;
          _inputsLocked = true;
          _isReviewPhase = false;
          _isScoredForThisQuestion = false;
        });

        _interRoundTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          }
          if (_interRoundSecondsRemaining > 1) {
            setState(() {
              _interRoundSecondsRemaining--;
            });
          } else {
            timer.cancel();
            if (mounted) {
              setState(() {
                _interRoundSecondsRemaining = 0;
                _isInterRoundPhase = false;
                _showRoundWinnersOverlay = false;
              });
            }
          }
        });
      },
      onLeaderboardUpdatedBroadcast: (payload) {
        if (_player != null) {
          final myNick = _player!.nickname.toLowerCase();

          // 1. Check if payload contains a list of players
          final rawList = payload['players'] ?? payload['leaderboard'];
          if (rawList is List && rawList.isNotEmpty) {
            for (var item in rawList) {
              if (item is Map) {
                final nick = (item['nickname'] ?? item['name'] ?? '').toString().toLowerCase();
                if (nick == myNick) {
                  final rawScore = item['cumulative_score'] ?? item['score'] ?? item['points'];
                  final incomingScore = (rawScore is num)
                      ? rawScore.toInt()
                      : (int.tryParse(rawScore?.toString() ?? '') ?? 0);
                  final syncedScore = max(_myScore, incomingScore);
                  if (mounted && (_myScore != syncedScore || _player!.cumulativeScore != syncedScore)) {
                    setState(() {
                      _myScore = syncedScore;
                      _player = _player!.copyWith(cumulativeScore: syncedScore);
                    });
                  }
                  return;
                }
              }
            }
          }

          // 2. Check if payload is a single player score update
          final singleNick = (payload['nickname'] ?? '').toString().toLowerCase();
          if (singleNick.isNotEmpty && singleNick == myNick) {
            final rawScore = payload['score'] ?? payload['cumulative_score'] ?? payload['points'];
            final incomingScore = (rawScore is num)
                ? rawScore.toInt()
                : (int.tryParse(rawScore?.toString() ?? '') ?? 0);
            final syncedScore = max(_myScore, incomingScore);
            if (mounted && (_myScore != syncedScore || _player!.cumulativeScore != syncedScore)) {
              setState(() {
                _myScore = syncedScore;
                _player = _player!.copyWith(cumulativeScore: syncedScore);
              });
            }
          }
        }
      },
      onRequestStateSyncBroadcast: (payload) {
        if (_player != null && mounted) {
          _realtimeService.broadcastPlayerJoined(
            roomCode: _player!.roomCode,
            nickname: _player!.nickname,
            score: _myScore,
          );
        }
      },
    );
  }

  void _startLocalCountdown() {
    _localTimer?.cancel();
    _localTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_targetTimerEndsAtMs != null) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final rem = ((_targetTimerEndsAtMs! - now) / 1000).ceil();
        if (rem > 0) {
          if (_remainingSeconds != rem) {
            setState(() {
              _remainingSeconds = rem;
            });
          }
        } else {
          timer.cancel();
          setState(() {
            _remainingSeconds = 0;
          });
          _lockInputsAndReveal(null);
        }
      } else {
        if (_remainingSeconds > 0) {
          setState(() {
            _remainingSeconds--;
          });
        } else {
          timer.cancel();
          _lockInputsAndReveal(null);
        }
      }
    });
  }

  // Pre‑game countdown timer for players
  void _startPreGameTimer() {
    _preGameTimer?.cancel();
    _preGameTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_preGameSecondsRemaining > 0) {
        setState(() {
          _preGameSecondsRemaining--;
        });
      } else {
        timer.cancel();
        setState(() {
          _isPreGameCountdown = false;
        });
      }
    });
  }

  void _lockInputsAndReveal(String? serverCorrectOption) {
    if (mounted) {
      final correct = serverCorrectOption ?? _currentQuestion?.correctOption;
      final wasCorrect = _selectedOption != null && _selectedOption == correct;

      setState(() {
        _inputsLocked = true;
        _isReviewPhase = true;
        _isInterQuestionPhase = true;
        _showResultOverlay = true;
        _correctOption = correct;
        if (!_isScoredForThisQuestion && wasCorrect) {
          _isScoredForThisQuestion = true;
          _myScore += 10;
          if (_player != null) {
            _player = _player!.copyWith(cumulativeScore: _myScore);
            _supabaseService.updateLocalPlayerScore(
              roomCode: _player!.roomCode,
              nickname: _player!.nickname,
              score: _myScore,
              pointsToAdd: 10,
            );
          }
        }
      });

      _resultOverlayTimer?.cancel();
      // Display result overlay for 5 seconds (or until tapped), then transition immediately to countdown timer screen
      _resultOverlayTimer = Timer(const Duration(seconds: 5), () {
        if (mounted && _showResultOverlay) {
          setState(() {
            _showResultOverlay = false;
          });
        }
      });
    }
  }

  Future<void> _submitAnswer(String option) async {
    if (_inputsLocked || _currentQuestion == null || _gameSession == null) return;

    setState(() {
      _selectedOption = option;
      _inputsLocked = true;
    });

    if (_player != null) {
      _realtimeService.broadcastAnswerSubmitted(
        roomCode: _player!.roomCode,
        nickname: _player!.nickname,
        selectedOption: option,
      );
    }

    try {
      await _supabaseService.submitAnswer(
        sessionId: _gameSession!.id,
        questionId: _currentQuestion!.id,
        selectedOption: option,
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _resultOverlayTimer?.cancel();
    _localTimer?.cancel();
    _interQuestionTimer?.cancel();
    _interRoundTimer?.cancel();
    _preGameTimer?.cancel();
    _resumeTimer?.cancel();
    _nicknameController.dispose();
    _roomCodeController.dispose();
    _realtimeService.leaveChannel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (context.mounted) {
          context.go('/hub');
        }
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (context.mounted) context.go('/hub');
          },
          const SingleActivator(LogicalKeyboardKey.goBack): () {
            if (context.mounted) context.go('/hub');
          },
        },
        child: Scaffold(
          backgroundColor: AppTheme.darkBackground,
          body: SafeArea(
            child: Stack(
              children: [
                _player == null
                    ? _buildNicknamePrompt()
                    : _buildActivePlayerScreen(),

                if (_showResultOverlay && _currentQuestion != null)
                  _buildResultOverlay(),

                if (_showRoundWinnersOverlay && _top3Winners.isNotEmpty)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(0.88),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.only(top: 126, left: 20, right: 20, bottom: 20),
                      child: SingleChildScrollView(
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 420),
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: AppTheme.cardSurfaceElevated,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: AppTheme.neonYellow, width: 2.5),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.neonYellow.withOpacity(0.35),
                                blurRadius: 28,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.emoji_events_rounded, color: AppTheme.neonYellow, size: 56),
                              const SizedBox(height: 10),
                              const Text(
                                'ROUND COMPLETED!',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                  color: AppTheme.neonYellow,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'TOP 3 WINNERS OF THE ROUND',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0,
                                  color: Colors.white70,
                                ),
                              ),
                              const SizedBox(height: 20),
                              ...List.generate(_top3Winners.length, (idx) {
                                final w = _top3Winners[idx];
                                final badges = ['🥇 1ST PLACE (+20 BONUS)', '🥈 2ND PLACE', '🥉 3RD PLACE'];
                                final colors = [AppTheme.neonYellow, Colors.grey.shade300, const Color(0xFFCD7F32)];

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: colors[idx].withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: colors[idx], width: 1.5),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            badges[idx],
                                            style: TextStyle(
                                              color: colors[idx],
                                              fontWeight: FontWeight.w900,
                                              fontSize: 12,
                                            ),
                                          ),
                                          Text(
                                            (w['nickname'] as String? ?? '').toUpperCase(),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        '${w['score']} pts',
                                        style: TextStyle(
                                          color: colors[idx],
                                          fontWeight: FontWeight.w900,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                              const SizedBox(height: 16),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                decoration: BoxDecoration(
                                  color: AppTheme.darkBackground,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: AppTheme.neonYellow, width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.neonYellow.withOpacity(0.35),
                                      blurRadius: 16,
                                    ),
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    const Text(
                                      'NEXT ROUND STARTING IN.....',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w900,
                                        color: AppTheme.neonYellow,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '${_interRoundSecondsRemaining ~/ 60}:${(_interRoundSecondsRemaining % 60).toString().padLeft(2, '0')}',
                                      style: const TextStyle(
                                        fontSize: 34,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        letterSpacing: 2.0,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                // Top sticky header: "BAR ROOMS TRIVIA" title & logo, plus sticker card (name, counter, points).
                // Sits as the top layer in Stack so it is never scrolled out of view and remains visible on pop-ups.
                if (_player != null)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _buildStickyTopHeader(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultOverlay() {
    final wasCorrect = _selectedOption != null && _selectedOption == _correctOption;
    final correctOpt = _correctOption ?? _currentQuestion?.correctOption ?? 'A';
    String correctText = '';
    if (correctOpt == 'A') {
      correctText = _currentQuestion?.optionA ?? '';
    } else if (correctOpt == 'B') {
      correctText = _currentQuestion?.optionB ?? '';
    } else if (correctOpt == 'C') {
      correctText = _currentQuestion?.optionC ?? '';
    } else if (correctOpt == 'D') {
      correctText = _currentQuestion?.optionD ?? '';
    }

    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (mounted) {
            _resultOverlayTimer?.cancel();
            setState(() {
              _showResultOverlay = false;
              _isInterQuestionPhase = true;
            });
          }
        },
        child: Container(
          color: Colors.black.withOpacity(0.85),
          alignment: Alignment.center,
          padding: const EdgeInsets.only(top: 126, left: 20, right: 20, bottom: 20),
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              SingleChildScrollView(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 400),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                decoration: BoxDecoration(
                  color: AppTheme.cardSurface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: wasCorrect ? const Color(0xFF10B981) : Colors.redAccent,
                    width: 2.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (wasCorrect ? const Color(0xFF10B981) : Colors.redAccent).withOpacity(0.35),
                      blurRadius: 28,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      wasCorrect ? '🎉' : '❌',
                      style: const TextStyle(fontSize: 54),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      wasCorrect ? 'CORRECT! YOU GOT IT!' : 'OOPS! YOU MISSED IT!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: wasCorrect ? const Color(0xFF10B981) : Colors.redAccent,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: (wasCorrect ? const Color(0xFF10B981) : Colors.redAccent).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: wasCorrect ? const Color(0xFF10B981) : Colors.redAccent,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        wasCorrect ? '+10 PTS' : '0 PTS',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: wasCorrect ? const Color(0xFF10B981) : Colors.redAccent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'CORRECT ANSWER:',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: Colors.white60,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$correctOpt) $correctText',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: wasCorrect ? const Color(0xFF10B981) : AppTheme.neonGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.neonCyan.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.neonCyan),
                      ),
                      child: Text(
                        _gamePlayMode == 'Manual'
                            ? '⏳ Next Question, waiting on host...'
                            : '⏳ Next Question in ${_interQuestionSecondsRemaining}s...',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.neonCyan,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

              // Short celebration explosion on correct!
              if (wasCorrect)
                const Positioned.fill(
                  child: CelebrationExplosion(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNicknamePrompt() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 440),
          padding: const EdgeInsets.all(32.0),
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppTheme.neonCyan.withOpacity(0.3), width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 30,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    'assets/images/app_logo.png',
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'BAR ROOMS TRIVIA',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Join Anytime • Instant Real-Time Scoring',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _nicknameController,
                maxLength: 15,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
                decoration: InputDecoration(
                  labelText: 'NICKNAME',
                  labelStyle: const TextStyle(color: AppTheme.neonPink),
                  prefixIcon: const Icon(Icons.person, color: AppTheme.neonPink),
                  filled: true,
                  fillColor: Colors.black26,
                  counterStyle: const TextStyle(color: Colors.white38),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isAuthenticating ? null : _joinGame,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.neonCyan,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  elevation: 8,
                ),
                child: _isAuthenticating
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black),
                      )
                    : const Text(
                        'ENTER GAME',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStickyTopHeader() {
    return Container(
      key: const Key('sticky-player-top-header'),
      color: AppTheme.darkBackground,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/images/app_logo.png',
                  width: 30,
                  height: 30,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'BAR ROOMS TRIVIA',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildStickyPlayerHeaderCard(),
        ],
      ),
    );
  }

  Widget _buildStickyPlayerHeaderCard() {
    return Container(
      key: const Key('sticky-player-header-card'),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardSurfaceElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.neonCyan.withOpacity(0.6),
          width: 2.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.7),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: AppTheme.neonCyan.withOpacity(0.25),
            blurRadius: 14,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/images/app_logo.png',
                    width: 34,
                    height: 34,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _player!.nickname.toUpperCase(),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.neonCyan,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _currentQuestion != null
                            ? 'Round $_currentRound • Question $_questionNumberInRound of 10'
                            : 'Player Ready',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _currentQuestion != null
                              ? Colors.white70
                              : AppTheme.neonGreen,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.neonYellow.withOpacity(0.18),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.neonYellow, width: 1.8),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.neonYellow.withOpacity(0.25),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Text(
              '$_myScore PTS',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: AppTheme.neonYellow,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivePlayerScreen() {
    return Padding(
      padding: const EdgeInsets.only(top: 126, left: 16, right: 16, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _isInterRoundPhase
                ? _buildInterRoundCard()
                : (_isInterQuestionPhase
                    ? _buildInterQuestionCountdownScreen()
                    : (_currentQuestion == null
                        ? _buildWaitingOrCountdownCard()
                        : _buildQuestionContent())),
          ),
        ],
      ),
    );
  }

  Widget _buildInterRoundCard() {
    return Center(
      child: SingleChildScrollView(
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppTheme.neonYellow,
              width: 2.0,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.neonYellow.withOpacity(0.25),
                blurRadius: 28,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppTheme.neonYellow.withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.neonYellow,
                    width: 2.5,
                  ),
                ),
                child: const Icon(
                  Icons.hourglass_top_rounded,
                  size: 56,
                  color: AppTheme.neonYellow,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'ROUND COMPLETED!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: AppTheme.neonYellow,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Get Ready for Round $_currentRound',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white70,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                decoration: BoxDecoration(
                  color: AppTheme.darkBackground,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppTheme.neonYellow, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.neonYellow.withOpacity(0.35),
                      blurRadius: 18,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const Text(
                      'NEXT ROUND STARTING IN.....',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.neonYellow,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_interRoundSecondsRemaining ~/ 60}:${(_interRoundSecondsRemaining % 60).toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 2.0,
                      ),
                    ),
                  ],
                ),
              ),
              if (_top3Winners.isNotEmpty) ...[
                const SizedBox(height: 22),
                const Text(
                  'TOP PLAYERS THIS ROUND',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Colors.white60,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                ...List.generate(_top3Winners.length.clamp(0, 3), (idx) {
                  final w = _top3Winners[idx];
                  final badges = ['🥇', '🥈', '🥉'];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${badges[idx]} ${(w['nickname'] as String? ?? '').toUpperCase()}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          '${w['score']} pts',
                          style: const TextStyle(
                            color: AppTheme.neonYellow,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInterQuestionCountdownScreen() {
    final nextQNum = _questionNumberInRound < 10 ? _questionNumberInRound + 1 : 1;
    final isLastQ = _questionNumberInRound >= 10;
    return Center(
      child: SingleChildScrollView(
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppTheme.neonCyan.withOpacity(0.8),
              width: 2.0,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.neonCyan.withOpacity(0.25),
                blurRadius: 28,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppTheme.neonCyan.withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.neonCyan,
                    width: 2.5,
                  ),
                ),
                child: const Icon(
                  Icons.timer_outlined,
                  size: 56,
                  color: AppTheme.neonCyan,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _gamePlayMode == 'Manual'
                    ? 'WAITING ON HOST'
                    : 'NEXT QUESTION IN',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                  color: AppTheme.neonCyan,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _gamePlayMode == 'Manual'
                    ? 'GET READY!'
                    : '$_interQuestionSecondsRemaining SECS',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: Text(
                  isLastQ
                      ? 'Round $_currentRound Final Question Completed'
                      : 'Round $_currentRound • Preparing Question $nextQNum of 10',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWaitingOrCountdownCard() {
    return Center(
      child: SingleChildScrollView(
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: (_isPreGameCountdown || _isGamePaused)
                  ? AppTheme.neonYellow.withOpacity(0.6)
                  : AppTheme.neonCyan.withOpacity(0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: (_isPreGameCountdown || _isGamePaused)
                    ? AppTheme.neonYellow.withOpacity(0.15)
                    : AppTheme.neonCyan.withOpacity(0.1),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: (_isPreGameCountdown || _isGamePaused || _isResumeCountdownActive)
                      ? (_isResumeCountdownActive ? AppTheme.neonGreen.withOpacity(0.15) : AppTheme.neonYellow.withOpacity(0.15))
                      : AppTheme.neonCyan.withOpacity(0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: (_isPreGameCountdown || _isGamePaused || _isResumeCountdownActive)
                        ? (_isResumeCountdownActive ? AppTheme.neonGreen : AppTheme.neonYellow)
                        : AppTheme.neonCyan.withOpacity(0.5),
                    width: 2,
                  ),
                ),
                child: _isResumeCountdownActive
                    ? const Icon(Icons.play_circle_fill_rounded, size: 54, color: AppTheme.neonGreen)
                    : (_isGamePaused
                        ? const Icon(Icons.pause_circle_filled_rounded, size: 54, color: AppTheme.neonYellow)
                        : (_isPreGameCountdown
                            ? const Icon(Icons.timer, size: 54, color: AppTheme.neonYellow)
                            : const RealHourglassWidget(size: 64))),
              ),
              const SizedBox(height: 20),
              Text(
                _isResumeCountdownActive
                    ? 'Resuming in $_resumeSecondsRemaining seconds...'
                    : (_isGamePaused
                        ? 'Game Paused'
                        : (_isPreGameCountdown
                            ? 'Game Starting Soon!'
                            : 'Waiting for Host to Start a Game')),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1.3,
                ),
              ),
              if (_isGamePaused) ...[
                const SizedBox(height: 12),
                const Text(
                  'The host has paused the game session. Stay on this screen—we will resume shortly!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ] else if (_isResumeCountdownActive) ...[
                const SizedBox(height: 12),
                const Text(
                  'Get ready! The round is resuming now.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.neonGreen, fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ] else if (_isPreGameCountdown) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.darkBackground,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.neonYellow, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.neonYellow.withOpacity(0.3),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'NEXT ROUND STARTS IN',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.neonYellow,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '0:${_preGameSecondsRemaining.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 2.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                const SizedBox(height: 12),
                const Text(
                  'You are connected and ready! Questions will appear here as soon as the host begins.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 14),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuestionContent() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.neonPurple.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.neonPurple),
                ),
                child: Text(
                  _currentQuestion?.category.toUpperCase() ?? '',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.neonPurple,
                  ),
                ),
              ),
              Row(
                children: [
                  if (_isResumeCountdownActive)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.neonGreen.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.neonGreen),
                      ),
                      child: Text(
                        '▶ RESUMING (${_resumeSecondsRemaining}s)',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.neonGreen,
                        ),
                      ),
                    )
                  else if (_isGamePaused)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.neonYellow.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.neonYellow),
                      ),
                      child: const Text(
                        '⏸ PAUSED',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.neonYellow,
                        ),
                      ),
                    )
                  else if (_isInterQuestionPhase)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.neonCyan.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.neonCyan),
                      ),
                      child: Text(
                        _gamePlayMode == 'Manual'
                            ? 'NEXT QUESTION, WAITING ON HOST'
                            : 'NEXT QUESTION IN ${_interQuestionSecondsRemaining}s',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.neonCyan,
                        ),
                      ),
                    )
                  else ...[
                    Icon(
                      _inputsLocked ? Icons.lock : Icons.timer,
                      size: 16,
                      color: _inputsLocked ? Colors.red : AppTheme.neonGreen,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _inputsLocked ? 'LOCKED' : '${_remainingSeconds}s',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _inputsLocked ? Colors.red : AppTheme.neonGreen,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _currentQuestion?.questionText ?? '',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildAnswerOptionCard(
                          'A',
                          _currentQuestion?.optionA ?? 'Option A',
                          AppTheme.buttonA,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _buildAnswerOptionCard(
                          'B',
                          _currentQuestion?.optionB ?? 'Option B',
                          AppTheme.buttonB,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildAnswerOptionCard(
                          'C',
                          _currentQuestion?.optionC ?? 'Option C',
                          AppTheme.buttonC,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _buildAnswerOptionCard(
                          'D',
                          _currentQuestion?.optionD ?? 'Option D',
                          AppTheme.buttonD,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnswerOptionCard(String letter, String text, Color accentColor) {
    final isSelected = _selectedOption == letter;
    final isCorrect = _isReviewPhase && _correctOption == letter;
    final isWrong = _isReviewPhase && isSelected && _correctOption != letter;

    Color bg = accentColor;
    if (_inputsLocked && !isSelected && !_isReviewPhase) {
      bg = Colors.grey.shade800;
    }
    if (isCorrect) {
      bg = const Color(0xFF10B981);
    } else if (isWrong) {
      bg = Colors.redAccent;
    } else if (_isReviewPhase && !isCorrect && !isSelected) {
      bg = Colors.grey.shade900;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: (_inputsLocked || _currentQuestion == null) ? null : () => _submitAnswer(letter),
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isCorrect
                  ? Colors.white
                  : (isSelected ? Colors.white : Colors.transparent),
              width: isCorrect ? 4 : (isSelected ? 3.5 : 1),
            ),
            boxShadow: (isCorrect || isSelected)
                ? [
                    BoxShadow(
                      color: bg.withOpacity(0.55),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    letter,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  // Removed check and x icons
                ],
              ),
              const SizedBox(height: 4),
              Text(
                text,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              if (isCorrect) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.65),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: const Text(
                    '✅ CORRECT',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class CelebrationExplosion extends StatefulWidget {
  final VoidCallback? onComplete;

  const CelebrationExplosion({super.key, this.onComplete});

  @override
  State<CelebrationExplosion> createState() => _CelebrationExplosionState();
}

class _CelebrationExplosionState extends State<CelebrationExplosion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_ExplosionParticle> _particles;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    final rng = Random();
    const colors = [
      Color(0xFF10B981), // Emerald Green
      Color(0xFF00E5FF), // Neon Cyan
      Color(0xFFFFD700), // Gold
      Color(0xFFFF007A), // Hot Pink
      Color(0xFFFF9100), // Vivid Amber
      Color(0xFF7C4DFF), // Purple
      Color(0xFFFFFFFF), // White
    ];

    _particles = List.generate(55, (index) {
      final angle = rng.nextDouble() * 2 * pi;
      final speed = 120.0 + rng.nextDouble() * 260.0;
      final size = 6.0 + rng.nextDouble() * 8.0;
      final color = colors[rng.nextInt(colors.length)];
      final rotationSpeed = (rng.nextDouble() - 0.5) * 8.0;
      final shapeType = index % 3; // 0 = rect/confetti ribbon, 1 = circle, 2 = diamond
      return _ExplosionParticle(
        angle: angle,
        speed: speed,
        size: size,
        color: color,
        rotationSpeed: rotationSpeed,
        shapeType: shapeType,
      );
    });

    _controller.forward().then((_) {
      if (mounted) {
        widget.onComplete?.call();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            size: Size.infinite,
            painter: _ExplosionPainter(
              particles: _particles,
              progress: _controller.value,
            ),
          );
        },
      ),
    );
  }
}

class _ExplosionParticle {
  final double angle;
  final double speed;
  final double size;
  final Color color;
  final double rotationSpeed;
  final int shapeType;

  _ExplosionParticle({
    required this.angle,
    required this.speed,
    required this.size,
    required this.color,
    required this.rotationSpeed,
    required this.shapeType,
  });
}

class _ExplosionPainter extends CustomPainter {
  final List<_ExplosionParticle> particles;
  final double progress;

  _ExplosionPainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1.0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final t = Curves.easeOutCubic.transform(progress);
    final opacity = (1.0 - Curves.easeInQuad.transform(progress)).clamp(0.0, 1.0);

    for (final p in particles) {
      final distance = p.speed * t;
      final dx = center.dx + cos(p.angle) * distance;
      final dy = center.dy + sin(p.angle) * distance + (progress * progress * 90.0);

      final paint = Paint()
        ..color = p.color.withOpacity((opacity * (p.color.opacity)).clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;

      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(progress * p.rotationSpeed * pi);

      if (p.shapeType == 0) {
        // Confetti Ribbon / Rect
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: p.size * 1.5, height: p.size * 0.7),
            const Radius.circular(2),
          ),
          paint,
        );
      } else if (p.shapeType == 1) {
        // Circle particle
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      } else {
        // Diamond star particle
        final path = Path()
          ..moveTo(0, -p.size)
          ..lineTo(p.size * 0.6, 0)
          ..lineTo(0, p.size)
          ..lineTo(-p.size * 0.6, 0)
          ..close();
        canvas.drawPath(path, paint);
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ExplosionPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
