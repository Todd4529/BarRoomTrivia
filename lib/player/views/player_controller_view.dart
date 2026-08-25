import 'dart:async';
import 'dart:ui';
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
import '../widgets/answer_button.dart';

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
  String? _selectedOption;
  String? _correctOption;
  bool _inputsLocked = true;
  bool _isReviewPhase = false;
  int _remainingSeconds = 0;
  int _questionNumberInRound = 1;
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
        final timerEndsAtEpochMs = payload['timer_ends_at_epoch_ms'] as int?;
        final qIndex = payload['question_index'] as int? ?? 1;

        Question? question;
        if (payload.containsKey('question_text')) {
          question = Question.fromJson(payload);
        } else {
          final qId = (payload['question_id'] ?? payload['id']) as String?;
          if (qId != null) {
            question = await _supabaseService.getQuestionById(qId);
          }
        }

        if (question != null) {
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          final remainingMs = (timerEndsAtEpochMs ?? (nowMs + 20000)) - nowMs;
          final durationSec = (remainingMs / 1000).ceil().clamp(0, 180);

          _interQuestionTimer?.cancel();
          setState(() {
            _isGamePaused = false;
            _isPreGameCountdown = false;
            _isInterQuestionPhase = false;
            _preGameTimer?.cancel();
            _currentQuestion = question;
            _selectedOption = null;
            _correctOption = null;
            _inputsLocked = false;
            _isReviewPhase = false;
            _isScoredForThisQuestion = false;
            _remainingSeconds = durationSec > 0 ? durationSec : 60;
            _questionNumberInRound = ((qIndex - 1) % 10) + 1;
          });

          _startLocalCountdown();
        }
      },
      onTimerExpiredBroadcast: (payload) {
        _lockInputsAndReveal(payload['correct_option'] as String?);

        final mode = payload['game_play_mode'] as String? ?? 'Auto';
        final nextStartsAt = payload['next_question_starts_at_epoch_ms'] as int?;
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final remaining = nextStartsAt != null
            ? ((nextStartsAt - nowMs) / 1000).ceil().clamp(1, 30)
            : 30;

        setState(() {
          _isInterQuestionPhase = true;
          _interQuestionSecondsRemaining = remaining;
          _gamePlayMode = mode;
        });

        _interQuestionTimer?.cancel();
        if (mode == 'Auto') {
          _interQuestionTimer = Timer.periodic(const Duration(seconds: 1), (t) {
            if (_interQuestionSecondsRemaining > 1) {
              if (mounted) {
                setState(() {
                  _interQuestionSecondsRemaining--;
                });
              }
            } else {
              _interQuestionTimer?.cancel();
              if (mounted) {
                setState(() {
                  _isInterQuestionPhase = false;
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

        setState(() {
          _isGamePaused = false;
          _isPreGameCountdown = true;
          _preGameSecondsRemaining = remainingSec;
        });
        _startPreGameTimer();
      },
      onGamePausedBroadcast: (payload) {
        _localTimer?.cancel();
        _preGameTimer?.cancel();
        _resumeTimer?.cancel();
        setState(() {
          _isGamePaused = true;
          _isResumeCountdownActive = false;
          _isPreGameCountdown = false;
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

        final mode = payload['reset_mode'] as String? ?? 'keep_scores';

        if (mounted) {
          setState(() {
            _currentQuestion = null;
            _selectedOption = null;
            _correctOption = null;
            _inputsLocked = false;
            _isReviewPhase = false;
            _isPreGameCountdown = false;
            _isGamePaused = false;
            _isResumeCountdownActive = false;
            _isInterQuestionPhase = false;

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
        final winners = payload['top_3_winners'] as List?;
        if (mounted && winners != null) {
          setState(() {
            _top3Winners = List<Map<String, dynamic>>.from(winners);
            _showRoundWinnersOverlay = true;
          });
          Future.delayed(const Duration(seconds: 12), () {
            if (mounted) {
              setState(() {
                _showRoundWinnersOverlay = false;
              });
            }
          });
        }
      },
      onLeaderboardUpdatedBroadcast: (payload) {
        if (_player != null && payload['players'] is List) {
          final players = payload['players'] as List;
          final myNick = _player!.nickname.toLowerCase();
          bool foundMe = false;
          for (var p in players) {
            if (p is Map<String, dynamic> && (p['nickname'] as String? ?? '').toLowerCase() == myNick) {
              foundMe = true;
              final newScore = p['cumulative_score'] as int? ?? 0;
              if (mounted) {
                setState(() {
                  _myScore = newScore;
                  _player = Player(
                    id: _player!.id,
                    roomCode: _player!.roomCode,
                    playerUid: _player!.playerUid,
                    nickname: _player!.nickname,
                    cumulativeScore: newScore,
                    isConnected: true,
                  );
                });
              }
              break;
            }
          }
          if (!foundMe && players.isEmpty && mounted) {
            setState(() {
              _player = null;
              _myScore = 0;
              _nicknameController.clear();
            });
          }
        }
      },
    );
  }

  void _startLocalCountdown() {
    _localTimer?.cancel();
    _localTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        _localTimer?.cancel();
        _lockInputsAndReveal(null);
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
      setState(() {
        _inputsLocked = true;
        _isReviewPhase = true;
        _correctOption = serverCorrectOption ?? _currentQuestion?.correctOption;
        if (!_isScoredForThisQuestion && _selectedOption != null && _selectedOption == _correctOption) {
          _isScoredForThisQuestion = true;
          _myScore += 100;
          if (_player != null) {
            _supabaseService.updateLocalPlayerScore(
              roomCode: _player!.roomCode,
              nickname: _player!.nickname,
              pointsToAdd: 100,
            );
          }
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

    try {
      await _supabaseService.submitAnswer(
        sessionId: _gameSession!.id,
        questionId: _currentQuestion!.id,
        selectedOption: option,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _inputsLocked = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _localTimer?.cancel();
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

                if (_showRoundWinnersOverlay && _top3Winners.isNotEmpty)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(0.88),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(20),
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
                              final badges = ['🥇 1ST PLACE', '🥈 2ND PLACE', '🥉 3RD PLACE'];
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
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
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

  Widget _buildActivePlayerScreen() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/images/app_logo.png',
                  width: 32,
                  height: 32,
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
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _player!.nickname.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.neonCyan,
                    ),
                  ),
                  if (_currentQuestion != null)
                    Text(
                      'Question $_questionNumberInRound of 10',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white54,
                      ),
                    )
                  else
                    const Text(
                      'Player Ready',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.neonGreen,
                      ),
                    ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.neonYellow.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.neonYellow),
                ),
                child: Text(
                  '$_myScore PTS',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.neonYellow,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _currentQuestion == null
                ? _buildWaitingOrCountdownCard()
                : _buildQuestionContent(),
          ),
        ],
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
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'CORRECT',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 0.8,
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
