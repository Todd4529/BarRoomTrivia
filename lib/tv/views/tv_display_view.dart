import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/models/player.dart';
import '../../shared/models/question.dart';
import '../../shared/services/realtime_service.dart';
import '../../shared/services/supabase_service.dart';
import '../../shared/theme/app_theme.dart';
import '../widgets/leaderboard_widget.dart';
import '../widgets/qr_display_widget.dart';
import '../widgets/timer_ring.dart';

class TvDisplayView extends StatefulWidget {
  final String roomCode;

  const TvDisplayView({super.key, required this.roomCode});

  @override
  State<TvDisplayView> createState() => _TvDisplayViewState();
}

class _TvDisplayViewState extends State<TvDisplayView> {
  final SupabaseService _supabaseService = SupabaseService();
  final RealtimeService _realtimeService = RealtimeService();

  Question? _currentQuestion;
  List<Player> _leaderboard = [];
  int _remainingSeconds = 60;
  int _totalDuration = 60;
  int _questionIndex = 1;
  int _totalQuestionsInRound = 10;
  Timer? _timer;
  bool _isGameActive = false;
  bool _isTimerExpired = false;
  bool _isGamePaused = false;
  bool _isResumeCountdownActive = false;
  int _resumeSecondsRemaining = 10;
  Timer? _resumeTimer;

  bool _isPreGameCountdown = false;
  int _preGameSeconds = 60;
  Timer? _preGameTimer;

  bool _isInterQuestionPhase = false;
  int _interQuestionSecondsRemaining = 30;
  Timer? _interQuestionTimer;
  String _gamePlayMode = 'Auto';

  // Active 4-Page Advertisement Slide Index
  int _adSlideIndex = 0;
  Timer? _adSlideTimer;
  List<Map<String, dynamic>> _top3Winners = [];
  bool _showRoundWinnersOverlay = false;
  String _playerBaseUrl = 'https://todd4529.github.io/BarRoomTrivia';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _initTvSession();
    _startAdSlideTimer();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedBaseUrl = prefs.getString('player_base_url');
    if (savedBaseUrl != null && savedBaseUrl.isNotEmpty) {
      if (mounted) setState(() => _playerBaseUrl = savedBaseUrl);
    } else if (kIsWeb) {
      final origin = Uri.base.origin;
      final path = Uri.base.path.replaceAll(RegExp(r'/+$'), '');
      if (mounted) {
        setState(() => _playerBaseUrl = path.isNotEmpty ? '$origin$path' : origin);
      }
    }
  }

  String _getPlayUrl() {
    final cleanBase = _playerBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return '$cleanBase/?view=player&room=${widget.roomCode}';
  }

  void _showEditPlayerUrlDialog() {
    final controller = TextEditingController(text: _playerBaseUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppTheme.neonCyan, width: 2),
        ),
        title: const Row(
          children: [
            Icon(Icons.qr_code, color: AppTheme.neonCyan),
            SizedBox(width: 10),
            Text(
              'Player Web URL & QR Settings',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the web link players will open when scanning the TV QR code with their mobile phones:',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Player Base URL',
                labelStyle: const TextStyle(color: AppTheme.neonCyan),
                hintText: 'https://todd4529.github.io/BarRoomTrivia',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppTheme.neonCyan, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Sample QR URL: ${controller.text}/?view=player&room=${widget.roomCode}',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.neonCyan,
              foregroundColor: Colors.black,
            ),
            onPressed: () async {
              final newUrl = controller.text.trim();
              if (newUrl.isNotEmpty) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('player_base_url', newUrl);
                if (mounted) setState(() => _playerBaseUrl = newUrl);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save & Update QR', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _startAdSlideTimer() {
    _adSlideTimer?.cancel();
    _adSlideTimer = Timer.periodic(const Duration(seconds: 20), (t) {
      if (!_isGameActive && !_isPreGameCountdown && mounted) {
        setState(() {
          _adSlideIndex = (_adSlideIndex + 1) % 4; // 4 Slides total (20s per slide)
        });
      }
    });
  }

  void _initTvSession() {
    _loadLeaderboard();

    _realtimeService.joinRoomChannel(
      roomCode: widget.roomCode,
      onPreGameCountdownBroadcast: (payload) {
        final startsAtEpochMs = payload['starts_at_epoch_ms'] as int?;
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final remaining = startsAtEpochMs != null
            ? ((startsAtEpochMs - nowMs) / 1000).ceil().clamp(0, 60)
            : 30;

        setState(() {
          _isPreGameCountdown = true;
          _preGameSeconds = remaining > 0 ? remaining : 30;
          _isGameActive = false;
          _isTimerExpired = false;
        });

        _startPreGameTimer();
      },
      onQuestionBroadcast: (payload) async {
        final duration = payload['duration_seconds'] as int? ?? 60;
        final qIdx = payload['question_index'] as int? ?? 1;
        final totalQ = payload['total_questions'] as int? ?? 10;
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
          _interQuestionTimer?.cancel();
          setState(() {
            _currentQuestion = question;
            _totalDuration = duration;
            _remainingSeconds = duration;
            _questionIndex = qIdx;
            _totalQuestionsInRound = totalQ;
            _isGameActive = true;
            _isPreGameCountdown = false;
            _isTimerExpired = false;
            _isInterQuestionPhase = false;
          });
          _startTimer();
        }
      },
      onTimerExpiredBroadcast: (payload) {
        _onTimerEnded(payload);
      },
      onGamePausedBroadcast: (payload) {
        if (mounted) {
          _timer?.cancel();
          _preGameTimer?.cancel();
          _resumeTimer?.cancel();
          setState(() {
            _isGamePaused = true;
            _isResumeCountdownActive = false;
          });
        }
      },
      onGameResumingBroadcast: (payload) {
        if (mounted) {
          _timer?.cancel();
          _preGameTimer?.cancel();
          _resumeTimer?.cancel();

          final startsAtEpochMs = payload['starts_at_epoch_ms'] as int?;
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          final remaining = startsAtEpochMs != null
              ? ((startsAtEpochMs - nowMs) / 1000).ceil().clamp(0, 10)
              : 10;

          setState(() {
            _isGamePaused = false;
            _isResumeCountdownActive = true;
            _resumeSecondsRemaining = remaining > 0 ? remaining : 10;
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
                  _isGameActive = true;
                });
              }
            }
          });
        }
      },
      onGameResetBroadcast: (payload) {
        final mode = payload['reset_mode'] as String? ?? 'keep_scores';
        _timer?.cancel();
        _preGameTimer?.cancel();
        _resumeTimer?.cancel();
        _interQuestionTimer?.cancel();

        if (mounted) {
          setState(() {
            _isGameActive = false;
            _isPreGameCountdown = false;
            _isTimerExpired = false;
            _isGamePaused = false;
            _isResumeCountdownActive = false;
            _isInterQuestionPhase = false;
            _currentQuestion = null;
            if (mode == 'clear_all') {
              _leaderboard = [];
            }
          });
        }
        if (mode != 'clear_all') {
          _loadLeaderboard();
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
        _loadLeaderboard();
      },
    );
  }

  void _startPreGameTimer() {
    _preGameTimer?.cancel();
    _preGameTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_preGameSeconds > 0) {
        setState(() {
          _preGameSeconds--;
        });
      } else {
        _preGameTimer?.cancel();
        setState(() {
          _isPreGameCountdown = false;
        });
      }
    });
  }

  Future<void> _loadLeaderboard() async {
    final players = await _supabaseService.getLeaderboard(widget.roomCode);
    if (mounted) {
      setState(() {
        _leaderboard = players;
      });
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        _timer?.cancel();
        _onTimerEnded();
      }
    });
  }

  void _onTimerEnded([Map<String, dynamic>? payload]) async {
    _timer?.cancel();
    _interQuestionTimer?.cancel();

    final mode = payload?['game_play_mode'] as String? ?? 'Auto';
    final nextStartsAt = payload?['next_question_starts_at_epoch_ms'] as int?;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final remaining = nextStartsAt != null
        ? ((nextStartsAt - nowMs) / 1000).ceil().clamp(1, 30)
        : 30;

    if (mounted) {
      setState(() {
        _isTimerExpired = true;
        _remainingSeconds = 0;
        _isInterQuestionPhase = true;
        _interQuestionSecondsRemaining = remaining;
        _gamePlayMode = mode;
      });
    }

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

    await _loadLeaderboard();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _preGameTimer?.cancel();
    _adSlideTimer?.cancel();
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
            Container(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  // Top Centered Header Bar with Exit to Hub & QR Settings
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white70),
                        tooltip: 'Return to Hub',
                        onPressed: () => context.go('/hub'),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.asset(
                              'assets/images/app_logo.png',
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'BAR ROOMS TRIVIA',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2.0,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings, color: AppTheme.neonCyan),
                        tooltip: 'QR & Player URL Settings',
                        onPressed: _showEditPlayerUrlDialog,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Main TV Stage Grid: Live Round / Paused / Resuming OR Pre-Game Countdown OR Official 4-Page Advertisement Carousel
                  Expanded(
                    child: (_isGameActive || _isGamePaused || _isResumeCountdownActive)
                        ? _buildLiveStageGrid()
                        : (_isPreGameCountdown ? _buildPreGameCountdownScreen() : _buildOfficial4PageAdCarousel()),
                  ),
                ],
              ),
            ),

            if (_showRoundWinnersOverlay && _top3Winners.isNotEmpty)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.85),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(32),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 580),
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: AppTheme.cardSurfaceElevated,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: AppTheme.neonYellow, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.neonYellow.withOpacity(0.4),
                          blurRadius: 36,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.emoji_events_rounded, color: AppTheme.neonYellow, size: 72),
                        const SizedBox(height: 12),
                        const Text(
                          'ROUND COMPLETED!',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2.0,
                            color: AppTheme.neonYellow,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'TOP 3 WINNERS OF THE ROUND',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 24),
                        ...List.generate(_top3Winners.length, (idx) {
                          final w = _top3Winners[idx];
                          final badges = ['🥇 1ST PLACE', '🥈 2ND PLACE', '🥉 3RD PLACE'];
                          final colors = [AppTheme.neonYellow, Colors.grey.shade300, const Color(0xFFCD7F32)];

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            decoration: BoxDecoration(
                              color: colors[idx].withOpacity(0.12),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: colors[idx], width: 1.5),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      badges[idx],
                                      style: TextStyle(
                                        color: colors[idx],
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Text(
                                      (w['nickname'] as String? ?? '').toUpperCase(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 18,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  '${w['score']} pts',
                                  style: TextStyle(
                                    color: colors[idx],
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
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

  /// Official 4-Page Scrolling Advertisement Screen (Active when no game is running)
  Widget _buildOfficial4PageAdCarousel() {
    final playUrl = _getPlayUrl();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppTheme.neonCyan.withValues(alpha: 0.4), width: 2),
        boxShadow: [
          BoxShadow(
            color: AppTheme.neonCyan.withValues(alpha: 0.12),
            blurRadius: 30,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left 65% Stage: Animated 4-Page Ad Content & Bottom Status Badge
          Expanded(
            flex: 65,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 4-Page Animated Ad Content Stage (Pure Fade-In / Fade-Out with Zero Jump)
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 700),
                    switchInCurve: Curves.easeInOut,
                    switchOutCurve: Curves.easeInOut,
                    layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
                      return Stack(
                        alignment: Alignment.centerLeft,
                        children: <Widget>[
                          ...previousChildren,
                          if (currentChild != null) currentChild,
                        ],
                      );
                    },
                    transitionBuilder: (Widget child, Animation<double> animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: child,
                      );
                    },
                    child: SizedBox.expand(
                      key: ValueKey(_adSlideIndex),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _buildAdSlideContent(_adSlideIndex),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Lowered & Centered Waiting for host banner with generous spacing
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.darkBackground,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.neonCyan, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.neonCyan.withValues(alpha: 0.45),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Text(
                      'WAITING FOR HOST TO START GAME',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 1.5,
                        shadows: [
                          Shadow(
                            color: AppTheme.neonCyan,
                            blurRadius: 14,
                          ),
                          Shadow(
                            color: AppTheme.neonCyan,
                            blurRadius: 28,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 28),

          // Right 35% Stage: Permanent Live QR Code & Room Code Card
          Expanded(
            flex: 35,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppTheme.neonCyan, width: 2.5),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'SCAN CAMERA TO JOIN',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      color: AppTheme.neonCyan,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: QrImageView(
                      data: playUrl,
                      version: QrVersions.auto,
                      size: 160.0,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
                      dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'ROOM: ${widget.roomCode}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3.0,
                      color: AppTheme.neonYellow,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    playUrl,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white60,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the 4 Original Advertisement Slides with Clean Scaling
  Widget _buildAdSlideContent(int index) {
    switch (index) {
      case 0:
        // SLIDE 1: WELCOME TO OUR PUB
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.neonPurple.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.neonPurple),
              ),
              child: const Text(
                '🎮 LIVE TRIVIA NIGHT',
                style: TextStyle(
                  color: AppTheme.neonPurple,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'WELCOME TO OUR PUB!',
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Free to Play on Your Mobile Phone • No App Downloads Required',
              style: TextStyle(color: AppTheme.neonCyan, fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Join the fun, answer questions live, and test your trivia skills against everyone in the bar!',
              style: TextStyle(color: Colors.white70, fontSize: 15),
            ),
          ],
        );

      case 1:
        // SLIDE 2: WHAT IS BAR ROOMS TRIVIA?
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.neonYellow.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.neonYellow),
              ),
              child: const Text(
                '🍻 WHAT IS BAR ROOMS TRIVIA?',
                style: TextStyle(
                  color: AppTheme.neonYellow,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'REAL-TIME TRIVIA BUILT FOR BARS',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Compete against everyone in the venue right from your mobile phone!',
              style: TextStyle(color: AppTheme.neonCyan, fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Questions appear live on the big TV and on your device—no paper, no pens, no waiting for manual grading!',
              style: TextStyle(color: Colors.white70, fontSize: 15),
            ),
          ],
        );

      case 2:
        // SLIDE 3: 3 EASY STEPS TO PLAY
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.neonCyan.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.neonCyan),
              ),
              child: const Text(
                '📱 EASY TO PLAY IN 3 STEPS',
                style: TextStyle(
                  color: AppTheme.neonCyan,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'JOIN THE GAME IN SECONDS',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 14),

            // 3 Steps Row
            Row(
              children: [
                _buildStepBox('1', 'Scan QR Code'),
                const SizedBox(width: 10),
                _buildStepBox('2', 'Pick Nickname'),
                const SizedBox(width: 10),
                _buildStepBox('3', 'Answer on Phone'),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Questions & 4 answer options display live right on your mobile screen!',
              style: TextStyle(color: Colors.white70, fontSize: 15),
            ),
          ],
        );

      case 3:
      default:
        // SLIDE 4: LEADERBOARD COMPETITION
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.neonGreen.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.neonGreen),
              ),
              child: const Text(
                '🏆 REAL-TIME COMPETITION',
                style: TextStyle(
                  color: AppTheme.neonGreen,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'CLIMB THE LIVE LEADERBOARD',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Earn points for fast and accurate answers on every question!',
              style: TextStyle(color: AppTheme.neonCyan, fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Real-time scoring updates the TV leaderboard instantly after every round!',
              style: TextStyle(color: Colors.white70, fontSize: 15),
            ),
          ],
        );
    }
  }

  Widget _buildStepBox(String stepNum, String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.darkBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.neonCyan.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(
              color: AppTheme.neonCyan,
              shape: BoxShape.circle,
            ),
            child: Text(
              stepNum,
              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildPreGameCountdownScreen() {
    final playUrl = _getPlayUrl();

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppTheme.neonCyan, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: AppTheme.neonCyan.withValues(alpha: 0.2),
            blurRadius: 30,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            flex: 65,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.neonYellow.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.neonYellow),
                  ),
                  child: const Text(
                    '⚡ GAME IS STARTING VERY SOON!',
                    style: TextStyle(
                      color: AppTheme.neonYellow,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'NEXT ROUND STARTS IN...',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppTheme.cardSurfaceElevated,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppTheme.neonCyan, width: 2),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.timer, color: AppTheme.neonCyan, size: 36),
                          const SizedBox(width: 14),
                          Text(
                            '0:${_preGameSeconds.toString().padLeft(2, '0')}',
                            style: const TextStyle(
                              fontSize: 44,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  'Get your phones out! Scan the QR code now before the next round starts!',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ],
            ),
          ),
          const SizedBox(width: 28),

          Expanded(
            flex: 35,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppTheme.neonCyan, width: 2.5),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'SCAN TO PLAY NOW',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0,
                      color: AppTheme.neonCyan,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: QrImageView(
                      data: playUrl,
                      version: QrVersions.auto,
                      size: 160.0,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
                      dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveStageGrid() {
    final progress = _totalDuration > 0 ? _remainingSeconds / _totalDuration : 0.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 65,
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppTheme.cardSurface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.neonPurple.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.neonPurple),
                      ),
                      child: Text(
                        _currentQuestion?.category.toUpperCase() ?? 'GENERAL TRIVIA',
                        style: const TextStyle(
                          color: AppTheme.neonPurple,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (_isResumeCountdownActive)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.neonGreen.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.neonGreen, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.neonGreen.withOpacity(0.4),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                        child: Text(
                          '▶ RESUMING IN $_resumeSecondsRemaining SECONDS...',
                          style: const TextStyle(
                            color: AppTheme.neonGreen,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            letterSpacing: 1.0,
                          ),
                        ),
                      )
                    else if (_isGamePaused)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.neonYellow.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.neonYellow, width: 2),
                        ),
                        child: const Text(
                          '⏸ GAME PAUSED BY HOST',
                          style: TextStyle(
                            color: AppTheme.neonYellow,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            letterSpacing: 1.0,
                          ),
                        ),
                      )
                    else if (_isInterQuestionPhase)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.neonCyan.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.neonCyan, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.neonCyan.withOpacity(0.35),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                        child: Text(
                          _gamePlayMode == 'Manual'
                              ? 'NEXT QUESTION, WAITING ON HOST'
                              : 'NEXT QUESTION IN ${_interQuestionSecondsRemaining}s',
                          style: const TextStyle(
                            color: AppTheme.neonCyan,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                    TimerRing(
                      progress: progress,
                      remainingSeconds: _remainingSeconds,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Question $_questionIndex out of $_totalQuestionsInRound',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.neonCyan,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _currentQuestion?.questionText ?? 'Waiting for host...',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                if (_currentQuestion != null) ...[
                  Row(
                    children: [
                      Expanded(child: _buildOptionTile('A', _currentQuestion!.optionA, AppTheme.buttonA)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildOptionTile('B', _currentQuestion!.optionB, AppTheme.buttonB)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: _buildOptionTile('C', _currentQuestion!.optionC, AppTheme.buttonC)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildOptionTile('D', _currentQuestion!.optionD, AppTheme.buttonD)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 24),

        Expanded(
          flex: 35,
          child: Column(
            children: [
              QrDisplayWidget(
                roomCode: widget.roomCode,
                showRoomCode: false,
              ),
              const SizedBox(height: 20),
              Expanded(
                child: LeaderboardWidget(players: _leaderboard),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOptionTile(String label, String text, Color color) {
    final bool isCorrectOption = _currentQuestion?.correctOption == label;
    final bool showCorrect = _isTimerExpired && isCorrectOption;

    Color tileBg = color.withOpacity(0.15);
    Color borderColor = color.withOpacity(0.6);
    double borderWidth = 1.5;

    if (_isTimerExpired) {
      if (isCorrectOption) {
        tileBg = const Color(0xFF10B981).withOpacity(0.3); // Bright Emerald Green
        borderColor = const Color(0xFF10B981);
        borderWidth = 3.0;
      } else {
        tileBg = Colors.black38;
        borderColor = Colors.white10;
      }
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: tileBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: showCorrect
            ? [
                BoxShadow(
                  color: const Color(0xFF10B981).withOpacity(0.45),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ]
            : [],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: showCorrect ? const Color(0xFF10B981) : color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: Colors.white,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 18,
                fontWeight: showCorrect ? FontWeight.bold : FontWeight.w600,
                color: Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (showCorrect) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Removed check icon
                  Text(
                    'CORRECT',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
