import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../shared/models/game_session.dart';
import '../../shared/services/game_engine.dart';
import '../../shared/services/realtime_service.dart';
import '../../shared/services/supabase_service.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/data/trivia_repository.dart';
import '../../shared/data/trivia_genres.dart';

class HostDashboardView extends StatefulWidget {
  const HostDashboardView({super.key});

  @override
  State<HostDashboardView> createState() => _HostDashboardViewState();
}

class _HostDashboardViewState extends State<HostDashboardView> {
  final SupabaseService _supabaseService = SupabaseService();
  final RealtimeService _realtimeService = RealtimeService();

  GameSession? _activeSession;
  bool _isCreatingSession = false;
  bool _isEngineRunning = false;
  bool _isGamePaused = false;
  bool _isResumeCountdownActive = false;
  int _resumeSecondsRemaining = 10;
  Timer? _resumeTimer;
  String _selectedDifficulty = 'Standard';
  String _selectedGameMode = 'Auto'; // 'Auto' (default) or 'Manual'
  int _selectedTimerSeconds = 60;
  int _currentQuestionIndex = 0;
  List<String> _selectedGenreQueue = [];

  // 30-Second Pre-Game Countdown & Active Question State
  bool _isPreGameCountdownActive = false;
  int _preGameSecondsRemaining = 30;
  Timer? _preGameTimer;
  int _questionSecondsRemaining = 0;
  int _totalQuestionDuration = 60;
  bool _isReviewPhase = false;
  Timer? _questionCountdownTimer;

  final List<String> _difficulties = ['Kids', 'Beginner', 'Standard', 'Advanced'];
  final List<int> _availableTimerDurations = [10, 15, 20, 30, 45, 60, 90, 120, 180];
  late final PageController _timerPageController;

  @override
  void initState() {
    super.initState();
    final initialIndex = _availableTimerDurations.indexOf(_selectedTimerSeconds);
    _timerPageController = PageController(
      viewportFraction: 0.28,
      initialPage: initialIndex >= 0 ? initialIndex : 5,
    );

    _realtimeService.joinRoomChannel(
      roomCode: 'TRIV',
      onQuestionBroadcast: (payload) {
        final timerEndsAtEpochMs = payload['timer_ends_at_epoch_ms'] as int?;
        final qIndex = payload['question_index'] as int?;
        if (mounted) {
          setState(() {
            if (qIndex != null) _currentQuestionIndex = qIndex;
          });
        }
        if (timerEndsAtEpochMs != null && mounted) {
          _startQuestionCountdown(timerEndsAtEpochMs);
        }
      },
      onTimerExpiredBroadcast: (_) {
        if (mounted) {
          setState(() {
            _questionSecondsRemaining = 0;
            _isReviewPhase = true;
          });
        }
      },
      onGameResetBroadcast: (_) {
        _cancelPreGameCountdown();
        _questionCountdownTimer?.cancel();
        if (mounted) {
          setState(() {
            _isEngineRunning = false;
            _isGamePaused = false;
            _isResumeCountdownActive = false;
            _isPreGameCountdownActive = false;
            _currentQuestionIndex = 0;
            _isReviewPhase = false;
          });
        }
      },
    );

    // Auto-create room session & seed 15 mock players immediately on load
    _createNewSession();
    SupabaseService.seedMockPlayers(roomCode: 'TRIV', count: 15);
  }

  @override
  void dispose() {
    _timerPageController.dispose();
    _preGameTimer?.cancel();
    _questionCountdownTimer?.cancel();
    _realtimeService.leaveChannel();
    super.dispose();
  }

  void _startQuestionCountdown(int timerEndsAtEpochMs) {
    _questionCountdownTimer?.cancel();
    _totalQuestionDuration = _selectedTimerSeconds;
    _isReviewPhase = false;

    _questionCountdownTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final remainingMs = timerEndsAtEpochMs - nowMs;
      final remainingSec = (remainingMs / 1000).ceil();

      if (mounted) {
        setState(() {
          _questionSecondsRemaining = remainingSec > 0 ? remainingSec : 0;
          if (_questionSecondsRemaining == 0) {
            _isReviewPhase = true;
          }
        });
      }

      if (remainingSec <= -5 || !_isEngineRunning) {
        timer.cancel();
      }
    });
  }

  Future<void> _createNewSession() async {
    setState(() {
      _isCreatingSession = true;
    });

    try {
      const roomCode = 'TRIV';
      final session = await _supabaseService.createRoomSession(roomCode);

      setState(() {
        _activeSession = session;
        _isCreatingSession = false;
        _currentQuestionIndex = 0;
      });
    } catch (_) {
      setState(() {
        _activeSession = GameSession(
          id: 'dev-session-id',
          roomCode: 'TRIV',
          status: 'active',
          questionIndex: 0,
          createdAt: DateTime.now(),
        );
        _isCreatingSession = false;
      });
    }
  }

  void _handleStartOrToggleGame() async {
    if (_activeSession == null) {
      await _createNewSession();
    }

    final engine = GameEngineManager.instance;
    if (_isGamePaused || engine.isGamePaused) {
      _resumeGameEngine();
      return;
    }

    if (engine.isEngineRunning || engine.isPreGameCountdownActive) return;

    engine.startPreGame(
      roomCode: _activeSession!.roomCode,
      timerSeconds: _selectedTimerSeconds,
      genres: _selectedGenreQueue,
    );

    _startPreGameTimer();
  }

  void _startPreGameTimer() {
    _preGameTimer?.cancel();
    _preGameTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      final engine = GameEngineManager.instance;
      if (mounted) {
        setState(() {
          _isPreGameCountdownActive = engine.isPreGameCountdownActive;
          _preGameSecondsRemaining = engine.preGameSecondsRemaining;
          _isEngineRunning = engine.isEngineRunning;
        });
      }
      if (!engine.isPreGameCountdownActive && !engine.isEngineRunning) {
        timer.cancel();
      }
    });
  }

  void _cancelPreGameCountdown() {
    GameEngineManager.instance.pauseGame();
    _preGameTimer?.cancel();
    _questionCountdownTimer?.cancel();
    _resumeTimer?.cancel();
    setState(() {
      _isPreGameCountdownActive = false;
      _preGameSecondsRemaining = 30;
      _isEngineRunning = false;
      _isGamePaused = false;
      _isResumeCountdownActive = false;
      _isReviewPhase = false;
      _questionSecondsRemaining = 0;
    });
  }

  void _pauseGameEngine() {
    GameEngineManager.instance.pauseGame();
    _preGameTimer?.cancel();
    _questionCountdownTimer?.cancel();
    _resumeTimer?.cancel();
    setState(() {
      _isEngineRunning = false;
      _isPreGameCountdownActive = false;
      _isGamePaused = true;
      _isResumeCountdownActive = false;
      _isReviewPhase = false;
    });
  }

  void _resumeGameEngine() {
    final engine = GameEngineManager.instance;
    engine.resumeGame(roomCode: _activeSession?.roomCode ?? 'TRIV');

    _resumeTimer?.cancel();
    _resumeTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) {
      if (mounted) {
        setState(() {
          _isGamePaused = engine.isGamePaused;
          _isResumeCountdownActive = engine.isResumeCountdownActive;
          _resumeSecondsRemaining = engine.resumeSecondsRemaining;
          _isEngineRunning = engine.isEngineRunning;
        });
      }
      if (!engine.isResumeCountdownActive && !engine.isGamePaused) {
        timer.cancel();
      }
    });
  }

  Future<void> _broadcastNextQuestion() async {
    if (_activeSession == null) {
      _activeSession = GameSession(
        id: 'dev-session-id',
        roomCode: 'TRIV',
        status: 'active',
        questionIndex: 0,
        createdAt: DateTime.now(),
      );
    }

    final question = TriviaRepository.getQuestionForGenres(_selectedGenreQueue, _currentQuestionIndex);
    final timerEndsAtEpochMs = DateTime.now().millisecondsSinceEpoch + (_selectedTimerSeconds * 1000);

    try {
      await _realtimeService.broadcastQuestion(
        roomCode: _activeSession!.roomCode,
        questionIndex: _currentQuestionIndex + 1,
        question: question,
        durationSeconds: _selectedTimerSeconds,
        timerEndsAtEpochMs: timerEndsAtEpochMs,
      );
    } catch (_) {
      // Dev mode fallback
    }

    setState(() {
      _currentQuestionIndex++;
    });
  }

  void _toggleGenreInQueue(String genre) {
    if (_isEngineRunning || _isPreGameCountdownActive) return;
    setState(() {
      if (_selectedGenreQueue.contains(genre)) {
        _selectedGenreQueue.remove(genre);
      } else {
        if (_selectedGenreQueue.length < 10) {
          _selectedGenreQueue.add(genre);
        }
      }
    });
  }

  /// Mobile-Friendly Bottom Sheet Modal for Browsing All 30 Genres
  void _openGenrePickerModalSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        String searchQuery = "";
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filteredGenres = TriviaGenres.allGenres.where((g) {
              return g.toLowerCase().contains(searchQuery.toLowerCase());
            }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: const BoxDecoration(
                color: AppTheme.cardSurface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'SELECT GENRES (UP TO 10)',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 1.1,
                        ),
                      ),
                      Text(
                        '${_selectedGenreQueue.length}/10 Queued',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.neonCyan,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search 30 genres...',
                      hintStyle: const TextStyle(color: Color(0xFF64748B)),
                      prefixIcon: const Icon(Icons.search, color: AppTheme.neonCyan, size: 20),
                      isDense: true,
                      filled: true,
                      fillColor: AppTheme.darkBackground,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (val) {
                      setModalState(() {
                        searchQuery = val;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: GridView.builder(
                      itemCount: filteredGenres.length,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 2.6,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemBuilder: (context, index) {
                        final genre = filteredGenres[index];
                        final qIndex = _selectedGenreQueue.indexOf(genre);
                        final isQueued = qIndex > -1;
                        final icon = TriviaGenres.getIcon(genre);

                        return GestureDetector(
                          onTap: (_isEngineRunning || _isPreGameCountdownActive)
                              ? null
                              : () {
                                  _toggleGenreInQueue(genre);
                                  setModalState(() {});
                                },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: isQueued ? AppTheme.neonPurple.withOpacity(0.25) : AppTheme.darkBackground,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isQueued ? AppTheme.neonPurple : Colors.white.withOpacity(0.08),
                                width: isQueued ? 1.5 : 1.0,
                              ),
                            ),
                            child: Row(
                              children: [
                                Text(icon, style: const TextStyle(fontSize: 18)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    genre,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isQueued ? FontWeight.bold : FontWeight.normal,
                                      color: isQueued ? Colors.white : const Color(0xFF94A3B8),
                                    ),
                                  ),
                                ),
                                if (isQueued)
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: const BoxDecoration(
                                      color: AppTheme.neonPurple,
                                      shape: BoxShape.circle,
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      '#${qIndex + 1}',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 10,
                                        height: 1.0,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(modalContext),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.neonCyan,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('DONE', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
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
          appBar: AppBar(
            backgroundColor: AppTheme.cardSurface,
            elevation: 0,
            centerTitle: true,
            toolbarHeight: 68,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white70),
              tooltip: 'Return to Hub',
              onPressed: () => context.go('/hub'),
            ),
            title: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(
                        'assets/images/app_logo.png',
                        width: 28,
                        height: 28,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'BAR ROOMS TRIVIA',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        letterSpacing: 1.5,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  'HOST CONTROL',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    letterSpacing: 1.2,
                    color: AppTheme.neonCyan,
                  ),
                ),
              ],
            ),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ACTIVE COUNTDOWN TIMER CARD (PRE-GAME & LIVE QUESTION TIMER)
                  if (_isPreGameCountdownActive || _isEngineRunning) _buildActiveCountdownTimerCard(),
                  _buildGameModeSegmentedControl(),
                  const SizedBox(height: 16),
                  _buildDifficultySegmentedControl(),
                  const SizedBox(height: 16),
                  _buildTimerDurationScrollWheel(),
                  const SizedBox(height: 16),
                  _buildGenreQueueSelector(),
                  const SizedBox(height: 24),
                  _buildActionButtons(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Countdown Timer Widget for Pre-Game & Live Question Countdowns
  Widget _buildActiveCountdownTimerCard() {
    final bool isPreGame = _isPreGameCountdownActive;
    final int displaySeconds = isPreGame ? _preGameSecondsRemaining : _questionSecondsRemaining;
    final int maxSeconds = isPreGame ? 30 : (_totalQuestionDuration > 0 ? _totalQuestionDuration : _selectedTimerSeconds);
    final double progress = (displaySeconds / (maxSeconds > 0 ? maxSeconds : 1)).clamp(0.0, 1.0);

    Color accentColor;
    if (isPreGame) {
      accentColor = AppTheme.neonYellow;
    } else if (_isReviewPhase) {
      accentColor = AppTheme.neonPurple;
    } else if (displaySeconds <= 5) {
      accentColor = Colors.redAccent;
    } else if (displaySeconds <= 10) {
      accentColor = AppTheme.neonYellow;
    } else {
      accentColor = AppTheme.neonCyan;
    }

    String statusTitle;
    if (isPreGame) {
      statusTitle = 'PRE-GAME COUNTDOWN';
    } else if (_isReviewPhase) {
      statusTitle = 'REVIEWING ANSWERS';
    } else {
      statusTitle = 'QUESTION #${_currentQuestionIndex > 0 ? _currentQuestionIndex : 1} TIMER';
    }

    String timerSubtitle;
    if (isPreGame) {
      timerSubtitle = 'Game starts automatically when countdown finishes';
    } else if (_isReviewPhase) {
      timerSubtitle = 'Next question loading shortly...';
    } else {
      timerSubtitle = 'Players are submitting their answers live';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.cardSurfaceElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accentColor.withOpacity(0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.2),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isPreGame ? Icons.timer : (_isReviewPhase ? Icons.done_all : Icons.alarm),
                      color: accentColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statusTitle,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: accentColor,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        timerSubtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (isPreGame)
                GestureDetector(
                  onTap: _cancelPreGameCountdown,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Big Countdown Display & Animated Progress Bar
          Row(
            children: [
              Container(
                width: 84,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.darkBackground,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: accentColor.withOpacity(0.4)),
                ),
                child: Center(
                  child: Text(
                    _isReviewPhase ? '0s' : '${displaySeconds}s',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: accentColor,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'TIME REMAINING',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white.withOpacity(0.5),
                            letterSpacing: 0.8,
                          ),
                        ),
                        Text(
                          '${displaySeconds} / ${maxSeconds}s',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: accentColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 10,
                        backgroundColor: AppTheme.darkBackground,
                        valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGameModeSegmentedControl() {
    final modes = ['Auto', 'Manual'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'GAME PLAY MODE',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: Colors.white70,
                  letterSpacing: 1.1,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.neonCyan.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.neonCyan.withOpacity(0.4)),
                ),
                child: Text(
                  _selectedGameMode.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.neonCyan,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            height: 64,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTheme.darkBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.neonCyan.withOpacity(0.25)),
            ),
            child: Row(
              children: modes.map((mode) {
                final isSelected = _selectedGameMode == mode;
                final label = mode == 'Auto' ? 'AUTO (HANDS-FREE)' : 'MANUAL (HOST DRIVEN)';
                return Expanded(
                  child: GestureDetector(
                    onTap: (_isEngineRunning || _isPreGameCountdownActive)
                        ? null
                        : () {
                            setState(() {
                              _selectedGameMode = mode;
                              GameEngineManager.instance.gamePlayMode = mode;
                            });
                          },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.cardSurfaceElevated : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: isSelected
                            ? Border.all(color: AppTheme.neonCyan, width: 2)
                            : Border.all(color: Colors.transparent),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: AppTheme.neonCyan.withOpacity(0.3),
                                  blurRadius: 8,
                                ),
                              ]
                            : [],
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                          color: isSelected ? Colors.white : Colors.white54,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDifficultySegmentedControl() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'DIFFICULTY LEVEL',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: Colors.white70,
                  letterSpacing: 1.1,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.neonCyan.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.neonCyan.withOpacity(0.4)),
                ),
                child: Text(
                  _selectedDifficulty.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.neonCyan,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            height: 64,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTheme.darkBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.neonCyan.withOpacity(0.25)),
            ),
            child: Row(
              children: _difficulties.map((diff) {
                final isSelected = _selectedDifficulty == diff;
                return Expanded(
                  child: GestureDetector(
                    onTap: (_isEngineRunning || _isPreGameCountdownActive)
                        ? null
                        : () => setState(() => _selectedDifficulty = diff),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.cardSurfaceElevated : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: isSelected
                            ? Border.all(color: AppTheme.neonCyan, width: 2)
                            : null,
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: AppTheme.neonCyan.withOpacity(0.25),
                                  blurRadius: 10,
                                ),
                              ]
                            : [],
                      ),
                      child: Text(
                        diff,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold,
                          color: isSelected ? Colors.white : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimerDurationScrollWheel() {
    final currentIndex = _availableTimerDurations.indexOf(_selectedTimerSeconds);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'QUESTION TIMER DURATION',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: Colors.white70,
                  letterSpacing: 1.1,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.neonCyan.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.neonCyan.withOpacity(0.4)),
                ),
                child: Text(
                  '${_selectedTimerSeconds} SECONDS',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.neonCyan,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          Container(
            height: 64,
            decoration: BoxDecoration(
              color: AppTheme.darkBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.neonCyan.withOpacity(0.25)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, color: AppTheme.neonCyan, size: 28),
                  onPressed: (_isEngineRunning || _isPreGameCountdownActive || currentIndex <= 0)
                      ? null
                      : () {
                          _timerPageController.previousPage(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOut,
                          );
                        },
                ),
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 76,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppTheme.cardSurfaceElevated,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.neonCyan, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.neonCyan.withOpacity(0.25),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                      ),
                      PageView.builder(
                        controller: _timerPageController,
                        itemCount: _availableTimerDurations.length,
                        physics: const BouncingScrollPhysics(),
                        onPageChanged: (index) {
                          if (!_isEngineRunning && !_isPreGameCountdownActive) {
                            setState(() {
                              _selectedTimerSeconds = _availableTimerDurations[index];
                            });
                          }
                        },
                        itemBuilder: (context, index) {
                          final secs = _availableTimerDurations[index];
                          final isSelected = _selectedTimerSeconds == secs;
                          final labelText = '${secs}s';

                          return GestureDetector(
                            onTap: (_isEngineRunning || _isPreGameCountdownActive)
                                ? null
                                : () {
                                    _timerPageController.animateToPage(
                                      index,
                                      duration: const Duration(milliseconds: 200),
                                      curve: Curves.easeOut,
                                    );
                                  },
                            child: AnimatedScale(
                              scale: isSelected ? 1.2 : 0.8,
                              duration: const Duration(milliseconds: 180),
                              child: Center(
                                child: Text(
                                  labelText,
                                  style: TextStyle(
                                    fontSize: isSelected ? 20 : 15,
                                    fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold,
                                    color: isSelected ? Colors.white : const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, color: AppTheme.neonCyan, size: 28),
                  onPressed: (_isEngineRunning || _isPreGameCountdownActive || currentIndex >= _availableTimerDurations.length - 1)
                      ? null
                      : () {
                          _timerPageController.nextPage(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOut,
                          );
                        },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenreQueueSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'GENRE PLAYLIST QUEUE',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: Colors.white70,
                  letterSpacing: 1.1,
                ),
              ),
              if (_selectedGenreQueue.isNotEmpty)
                GestureDetector(
                  onTap: (_isEngineRunning || _isPreGameCountdownActive) ? null : () => setState(() => _selectedGenreQueue.clear()),
                  child: const Text(
                    'Clear All',
                    style: TextStyle(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          if (_selectedGenreQueue.isEmpty)
            const Text(
              'No genres queued yet (Will default to Auto Select rotation)',
              style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8), fontStyle: FontStyle.italic),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _selectedGenreQueue.asMap().entries.map((entry) {
                final idx = entry.key;
                final genre = entry.value;
                final icon = TriviaGenres.getIcon(genre);
                return Chip(
                  avatar: Container(
                    width: 24,
                    height: 24,
                    decoration: const BoxDecoration(
                      color: AppTheme.neonPurple,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '#${idx + 1}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        height: 1.0,
                      ),
                    ),
                  ),
                  label: Text('$icon $genre', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  backgroundColor: AppTheme.darkBackground,
                  deleteIcon: const Icon(Icons.close, size: 14),
                  onDeleted: (_isEngineRunning || _isPreGameCountdownActive) ? null : () => _toggleGenreInQueue(genre),
                );
              }).toList(),
            ),

          const SizedBox(height: 14),

          ElevatedButton.icon(
            onPressed: () => _openGenrePickerModalSheet(context),
            icon: const Icon(Icons.playlist_add_check_rounded, color: AppTheme.neonPurple, size: 22),
            label: Text(
              _selectedGenreQueue.isEmpty
                  ? 'BROWSE & QUEUE GENRES'
                  : 'MANAGE PLAYLIST (${_selectedGenreQueue.length}/10 QUEUED)',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 13,
                letterSpacing: 0.5,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.darkBackground,
              foregroundColor: AppTheme.neonPurple,
              side: BorderSide(color: AppTheme.neonPurple.withOpacity(0.5), width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    final bool isPaused = _isGamePaused || GameEngineManager.instance.isGamePaused;

    String primaryButtonText;
    if (_isResumeCountdownActive) {
      primaryButtonText = 'RESUMING (${_resumeSecondsRemaining}s)';
    } else if (isPaused) {
      primaryButtonText = 'RESUME GAME';
    } else if (_isPreGameCountdownActive) {
      primaryButtonText = 'STARTING (${_preGameSecondsRemaining}s)';
    } else if (_isEngineRunning) {
      primaryButtonText = 'RUNNING';
    } else {
      primaryButtonText = 'START GAME';
    }

    Color primaryBorderColor;
    if (isPaused) {
      primaryBorderColor = AppTheme.neonGreen;
    } else if (_isPreGameCountdownActive) {
      primaryBorderColor = AppTheme.neonYellow;
    } else if (_isEngineRunning) {
      primaryBorderColor = AppTheme.neonCyan.withOpacity(0.3);
    } else {
      primaryBorderColor = AppTheme.neonCyan;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            // START GAME / RESUME GAME BUTTON
            Expanded(
              child: ElevatedButton.icon(
                onPressed: (_isEngineRunning && !isPaused) ? null : _handleStartOrToggleGame,
                icon: Icon(
                  isPaused
                      ? Icons.play_arrow_rounded
                      : (_isPreGameCountdownActive ? Icons.timer : Icons.play_arrow_rounded),
                  color: isPaused ? AppTheme.neonGreen : AppTheme.neonCyan,
                  size: 22,
                ),
                label: Text(
                  primaryButtonText,
                  style: TextStyle(
                    color: isPaused ? AppTheme.neonGreen : Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: 0.5,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.cardSurfaceElevated,
                  disabledBackgroundColor: AppTheme.darkBackground.withOpacity(0.5),
                  foregroundColor: Colors.white,
                  side: BorderSide(
                    color: primaryBorderColor,
                    width: isPaused ? 2.0 : 1.5,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 2,
                ),
              ),
            ),
            const SizedBox(width: 10),

            // PAUSE BUTTON
            Expanded(
              child: ElevatedButton.icon(
                onPressed: (_isEngineRunning || _isPreGameCountdownActive) && !isPaused
                    ? _pauseGameEngine
                    : null,
                icon: const Icon(Icons.pause_rounded, color: AppTheme.neonYellow, size: 22),
                label: const Text(
                  'PAUSE GAME',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: 0.5,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.cardSurfaceElevated,
                  disabledBackgroundColor: AppTheme.darkBackground.withOpacity(0.5),
                  foregroundColor: Colors.white,
                  side: BorderSide(
                    color: (_isEngineRunning || _isPreGameCountdownActive) && !isPaused
                        ? AppTheme.neonYellow
                        : Colors.white.withOpacity(0.1),
                    width: 1.5,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 2,
                ),
              ),
            ),
          ],
        ),
        if (_isEngineRunning && _selectedGameMode == 'Manual' && !isPaused) ...[
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: _isReviewPhase
                ? () {
                    GameEngineManager.instance.nextQuestionManual(roomCode: 'TRIV');
                  }
                : null,
            icon: Icon(
              Icons.skip_next_rounded,
              color: _isReviewPhase ? AppTheme.neonCyan : Colors.white38,
              size: 24,
            ),
            label: Text(
              _isReviewPhase ? 'NEXT QUESTION' : 'WAITING FOR QUESTION TIMER...',
              style: TextStyle(
                color: _isReviewPhase ? Colors.white : Colors.white38,
                fontWeight: FontWeight.w900,
                fontSize: 14,
                letterSpacing: 0.8,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isReviewPhase ? AppTheme.cardSurfaceElevated : AppTheme.darkBackground.withOpacity(0.5),
              disabledBackgroundColor: AppTheme.darkBackground.withOpacity(0.5),
              foregroundColor: Colors.white,
              side: BorderSide(
                color: _isReviewPhase ? AppTheme.neonCyan : Colors.white.withOpacity(0.1),
                width: _isReviewPhase ? 2.0 : 1.0,
              ),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: _isReviewPhase ? 4 : 0,
            ),
          ),
        ],
        const SizedBox(height: 10),

        const SizedBox(height: 10),

        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _showResetSessionConfirmationDialog(context),
                icon: const Icon(Icons.refresh, color: Colors.white54, size: 18),
                label: const Text(
                  'RESET GAME SESSION',
                  style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 11),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.white.withOpacity(0.1)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showResetSessionConfirmationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardSurfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppTheme.neonCyan, width: 1.5),
        ),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: AppTheme.neonYellow, size: 28),
            SizedBox(width: 10),
            Text(
              'RESET GAME SESSION',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 18,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.all(16),
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // OPTION 1: RESET ROUND (KEEP SCORES)
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  GameEngineManager.instance.resetGame(roomCode: 'TRIV', resetMode: 'keep_scores');
                },
                icon: const Icon(Icons.replay_rounded, color: AppTheme.neonCyan, size: 20),
                label: const Text(
                  'RESET ROUND (KEEP SCORES)',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.cardSurface,
                  side: const BorderSide(color: AppTheme.neonCyan),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 8),

              // OPTION 2: RESET SCORES TO ZERO
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  GameEngineManager.instance.resetGame(roomCode: 'TRIV', resetMode: 'zero_scores');
                },
                icon: const Icon(Icons.exposure_zero_rounded, color: AppTheme.neonYellow, size: 20),
                label: const Text(
                  'RESET SCORES TO ZERO',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.cardSurface,
                  side: const BorderSide(color: AppTheme.neonYellow),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 8),

              // OPTION 3: CLEAR LEADERBOARD & REMOVE PLAYERS
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  GameEngineManager.instance.resetGame(roomCode: 'TRIV', resetMode: 'clear_all');
                  _cancelPreGameCountdown();
                  setState(() {
                    _isEngineRunning = false;
                    _isGamePaused = false;
                    _isResumeCountdownActive = false;
                    _isPreGameCountdownActive = false;
                  });
                },
                icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 20),
                label: const Text(
                  'CLEAR LEADERBOARD & PLAYERS',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.cardSurface,
                  side: const BorderSide(color: Colors.redAccent),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 8),

              // CANCEL
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('CANCEL', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
