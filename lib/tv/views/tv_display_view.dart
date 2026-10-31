import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/config/supabase_config.dart';
import '../../shared/models/player.dart';
import '../../shared/models/question.dart';
import '../../shared/data/homebrewing_database.dart';
import '../../shared/data/genre_questions_engine.dart';
import '../../shared/data/trivia_genres.dart';
import '../../shared/data/trivia_repository.dart';
import '../../shared/services/game_engine.dart';
import '../../shared/services/realtime_service.dart';
import '../../shared/services/sound_service.dart';
import '../../shared/services/supabase_service.dart';
import '../../shared/theme/app_theme.dart';
import '../../utils/app_exit.dart';
import '../widgets/leaderboard_widget.dart';
import '../widgets/qr_display_widget.dart';
import '../widgets/timer_ring.dart';

class TvDisplayView extends StatefulWidget {
  final String roomCode;
  final bool autoStart;

  const TvDisplayView({super.key, required this.roomCode, this.autoStart = false});

  @override
  State<TvDisplayView> createState() => _TvDisplayViewState();
}

class _TvDisplayViewState extends State<TvDisplayView> {
  final SupabaseService _supabaseService = SupabaseService();
  final RealtimeService _realtimeService = RealtimeService();

  Question? _currentQuestion;
  String _activeGenre = 'General Trivia';
  List<Player> _leaderboard = [];
  int _remainingSeconds = 60;
  int _totalDuration = 60;
  int? _targetTimerEndsAtMs;
  int _questionIndex = 1;
  int _totalQuestionsInRound = 10;
  int _currentRound = 1;
  Timer? _timer;
  DateTime? _questionStartedAt;
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
  int _interQuestionSecondsRemaining = 15;
  int _totalInterQuestionDuration = 15;
  int _interQuestionTargetEpochMs = 0;
  int _lastTickedSecond = -1;
  Timer? _interQuestionTimer;
  String _gamePlayMode = 'Auto';
  bool _isQuestionTimerRunning = true;

  // Active Advertisement Slides
  int _adSlideIndex = 0;
  Timer? _adSlideTimer;
  int _adSlideDurationSeconds = 60;
  List<Map<String, dynamic>> _customAdSlides = [];

  int get _totalAdSlides {
    if (_customAdSlides.isEmpty) return 3;
    final maxPairs = max(3, _customAdSlides.length);
    return maxPairs * 2;
  }
  List<Map<String, dynamic>> _top3Winners = [];
  bool _showRoundWinnersOverlay = false;
  Timer? _roundWinnersOverlayTimer;
  Timer? _interRoundCountdownTimer;
  int _interRoundDurationSeconds = 120;
  bool _isInterRoundPhase = false;
  int _interRoundSecondsRemaining = 120;
  int _interRoundTargetEpochMs = 0;
  bool _isExitDialogOpen = false;
  bool _isAdSignageModeActive = false;
  bool _isSoundEffectsEnabled = true;
  String? _lastAnswerRevealSoundQuestionId;
  final Set<String> _previousWrongOptions = {};
  static const String _playerBaseUrl = 'https://barroomstrivia.com';

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      _isGameActive = true;
      _isPreGameCountdown = false;
    }
    _loadSettings();
    _initTvSession();
    _startAdSlideTimer();
  }

  String _savedRoomCode = '';

  String get _displayRoomCode {
    if (widget.roomCode.isNotEmpty && widget.roomCode != 'TRIV') {
      return widget.roomCode;
    }
    return _savedRoomCode.isNotEmpty ? _savedRoomCode : 'TRIV';
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedCode = prefs.getString('tv_room_code');
    if (savedCode != null && savedCode.isNotEmpty) {
      if (mounted) setState(() => _savedRoomCode = savedCode);
    }
    final savedSound = prefs.getBool('tv_sound_effects_enabled');
    if (savedSound != null) {
      if (mounted) setState(() => _isSoundEffectsEnabled = savedSound);
      SoundService.isSoundEffectsEnabled = savedSound;
    }
    // Purge any legacy local URL saved in SharedPreferences so it never overrides the public GitHub site
    await prefs.remove('player_base_url');
  }

  String _getPlayUrl() {
    return '$_playerBaseUrl/?view=player&room=$_displayRoomCode';
  }

  // Preserve exact broadcast options so TV display 100% matches player phones and host
  Question? _sanitizeQuestionDistractors(Question? q) => q;

  String _formatIntermissionMinutes(int seconds) {
    if (seconds >= 60 && seconds % 60 == 0) {
      final mins = seconds ~/ 60;
      return '$mins MINUTE${mins > 1 ? 'S' : ''}';
    } else if (seconds >= 60) {
      final mins = seconds ~/ 60;
      final rem = seconds % 60;
      return '$mins MIN $rem SEC';
    }
    return '$seconds SECONDS';
  }


  void _startAdSlideTimer() {
    _adSlideTimer?.cancel();
    final total = _totalAdSlides;
    if (total <= 1) {
      if (_adSlideIndex != 0 && mounted) {
        setState(() => _adSlideIndex = 0);
      }
      return;
    }
    final dur = _adSlideDurationSeconds > 0 ? _adSlideDurationSeconds : 60;
    _adSlideTimer = Timer.periodic(Duration(seconds: dur), (t) {
      final canRotate = ((!_isGameActive || _isGamePaused) && !_isPreGameCountdown) || _isInterRoundPhase || _isAdSignageModeActive || _customAdSlides.isNotEmpty;
      if (canRotate && !_isPreGameCountdown && mounted) {
        setState(() {
          final count = _totalAdSlides;
          _adSlideIndex = count > 0 ? (_adSlideIndex + 1) % count : 0;
        });
      }
    });
  }

  Timer? _tvSessionPollingTimer;

  void _startTvSessionPolling() {
    _tvSessionPollingTimer?.cancel();
    _tvSessionPollingTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted) return;
      try {
        final code = _displayRoomCode;
        final res = await SupabaseConfig.client
            .from('game_sessions')
            .select()
            .or('room_code.eq.$code,room_code.eq.TRIV')
            .maybeSingle()
            .timeout(const Duration(seconds: 1));

        if (res != null && mounted) {
          final isAdMode = res['is_ad_mode_active'] == true;
          if (_isAdSignageModeActive != isAdMode) {
            setState(() {
              _isAdSignageModeActive = isAdMode;
            });
            _startAdSlideTimer();
          }
          if (res['ad_slides'] is List) {
            final rawSlides = res['ad_slides'] as List;
            final parsedSlides = <Map<String, dynamic>>[];
            for (final s in rawSlides) {
              if (s is Map) parsedSlides.add(Map<String, dynamic>.from(s));
            }
            if (_customAdSlides.length != parsedSlides.length || _customAdSlides != parsedSlides) {
              setState(() {
                _customAdSlides = parsedSlides;
                if (_adSlideIndex >= _totalAdSlides) {
                  _adSlideIndex = 0;
                }
              });
              _startAdSlideTimer();
            }
          }
          if (res.containsKey('is_sound_effects_enabled') || res.containsKey('is_sound_enabled')) {
            final soundEnabled = res['is_sound_effects_enabled'] != false && res['is_sound_enabled'] != false;
            if (_isSoundEffectsEnabled != soundEnabled) {
              setState(() {
                _isSoundEffectsEnabled = soundEnabled;
              });
              SoundService.isSoundEffectsEnabled = soundEnabled;
              SharedPreferences.getInstance().then((prefs) {
                prefs.setBool('tv_sound_effects_enabled', soundEnabled);
              }).catchError((_) {});
            }
          }
          final status = res['status'] as String?;
          if (status == 'paused' && !_isGamePaused) {
            _timer?.cancel();
            _preGameTimer?.cancel();
            _resumeTimer?.cancel();
            setState(() {
              _isGamePaused = true;
              _isResumeCountdownActive = false;
            });
            _startAdSlideTimer();
          } else if (status == 'question_active' && _isGamePaused) {
            final qData = res['question_data'];
            final qId = (qData is Map ? qData['id'] : null)?.toString();
            if (qId != null && qId.isNotEmpty && qId != _currentQuestion?.id) {
              setState(() {
                _isGamePaused = false;
              });
            }
          } else if (status == 'pre_game_countdown' && !_isGameActive && !_isPreGameCountdown) {
            final startsAt = res['starts_at'] as int?;
            final now = DateTime.now().millisecondsSinceEpoch;
            final rem = startsAt != null ? ((startsAt - now) / 1000).ceil().clamp(0, 30) : 10;
            setState(() {
              _isPreGameCountdown = true;
              _preGameSeconds = rem > 0 ? rem : 10;
              _isGameActive = false;
              _isTimerExpired = false;
              _isGamePaused = false;
              _isResumeCountdownActive = false;
            });
            _startPreGameTimer();
          } else if (status == 'question_active' && !_isGameActive && !_isPreGameCountdown) {
            // Validate that this question is not already expired
            final rawEnds = res['timer_ends_at'];
            int? timerEndsAt;
            if (rawEnds is num) {
              timerEndsAt = rawEnds.toInt();
            } else if (rawEnds is String) {
              final dt = DateTime.tryParse(rawEnds);
              timerEndsAt = dt?.millisecondsSinceEpoch ?? int.tryParse(rawEnds);
            }
            final now = DateTime.now().millisecondsSinceEpoch;
            if (timerEndsAt != null && timerEndsAt <= now) {
              return;
            }
            final qData = res['question_data'] as Map<String, dynamic>?;
            if (qData != null) {
              final q = Question.fromJson(qData);
              final dur = res['duration_seconds'] as int? ?? 20;
              final rawQ = res['current_question_index'] as int? ?? 1;
              const totalQ = 10;
              final qIdx = ((rawQ - 1) % totalQ) + 1;
              final sessionRound = (res['current_round'] as int?) ??
                  (res['round_number'] as int?) ??
                  ((rawQ - 1) ~/ totalQ) + 1;
              final roundNum = sessionRound;
              final cat = qData['category']?.toString() ?? res['category']?.toString();
              final nowMs = DateTime.now().millisecondsSinceEpoch;
              final targetEndsAt = (timerEndsAt != null && timerEndsAt > nowMs)
                  ? timerEndsAt
                  : (nowMs + dur * 1000);
              final remainingMs = targetEndsAt - nowMs;
              final durationSec = max(0, (remainingMs / 1000).ceil().clamp(0, 180));
              _targetTimerEndsAtMs = targetEndsAt;

              _interQuestionTimer?.cancel();
              setState(() {
                _currentQuestion = _sanitizeQuestionDistractors(q);
                if (cat != null && cat.isNotEmpty) _activeGenre = cat;
                _totalDuration = dur;
                _remainingSeconds = durationSec;
                _questionIndex = qIdx;
                _currentRound = roundNum;
                _totalQuestionsInRound = totalQ;
                _isGameActive = true;
                _isPreGameCountdown = false;
                _isTimerExpired = false;
                _isInterQuestionPhase = false;
                _isGamePaused = false;
                _isResumeCountdownActive = false;
              });
              _startTimer();
            }
          } else if ((status == 'round_summary' || status == 'inter_round') && !_isInterRoundPhase) {
            final rawEnds = res['timer_ends_at'] ?? res['starts_at'];
            int? endsAt;
            if (rawEnds is num) {
              endsAt = rawEnds.toInt();
            } else if (rawEnds is String) {
              final dt = DateTime.tryParse(rawEnds);
              endsAt = dt?.millisecondsSinceEpoch ?? int.tryParse(rawEnds);
            }
            final now = DateTime.now().millisecondsSinceEpoch;
            final remSec = endsAt != null ? max(1, ((endsAt - now) / 1000).ceil()) : 120;
            final targetEpoch = endsAt ?? (now + remSec * 1000);
            final nextR = (res['current_round'] as int?) ?? (res['round_number'] as int?) ?? (_currentRound + 1);

            setState(() {
              _isGameActive = false;
              _currentQuestion = null;
              _isTimerExpired = false;
              _isInterQuestionPhase = false;
              _isInterRoundPhase = true;
              _interRoundSecondsRemaining = remSec;
              _currentRound = nextR;
            });

            _interRoundCountdownTimer?.cancel();
            _interRoundCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
              if (!mounted) {
                timer.cancel();
                return;
              }
              final currentNow = DateTime.now().millisecondsSinceEpoch;
              final rem = ((targetEpoch - currentNow) / 1000).ceil();
              if (rem > 0) {
                if (_interRoundSecondsRemaining != rem) {
                  setState(() => _interRoundSecondsRemaining = rem);
                }
              } else {
                timer.cancel();
                setState(() {
                  _isInterRoundPhase = false;
                  _showRoundWinnersOverlay = false;
                  _isPreGameCountdown = true;
                  _preGameSeconds = 5;
                });
                _startPreGameTimer();
              }
            });
            _startAdSlideTimer();
          }
        }
      } catch (_) {}

      // Keep TV leaderboard updated with newly joined players
      if (mounted) {
        await _loadLeaderboard();
      }
    });
  }

  void _initTvSession() {
    _loadLeaderboard();
    _startTvSessionPolling();

    // Broadcast state sync request immediately to sync with running host
    _realtimeService.broadcastSyncRequest(roomCode: _displayRoomCode, sender: 'tv');

    _realtimeService.joinRoomChannel(
      roomCode: _displayRoomCode,
      onPreGameCountdownBroadcast: (payload) {
        _adSlideTimer?.cancel();
        _interQuestionTimer?.cancel();
        _interRoundCountdownTimer?.cancel();
        _timer?.cancel();
        final startsAtEpochMs = payload['starts_at_epoch_ms'] as int?;
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final remaining = startsAtEpochMs != null
            ? ((startsAtEpochMs - nowMs) / 1000).ceil().clamp(0, 60)
            : (payload['countdown_seconds'] as int? ?? 10);

        final incomingGenre = payload['genre']?.toString() ??
            payload['current_genre']?.toString() ??
            payload['category']?.toString();
        final rNum = (payload['round_number'] as num?)?.toInt() ??
            (payload['roundNumber'] as num?)?.toInt();

        setState(() {
          _isPreGameCountdown = true;
          _isInterRoundPhase = false;
          _preGameSeconds = remaining > 0 ? remaining : 10;
          _isGameActive = false;
          _isTimerExpired = false;
          _isInterQuestionPhase = false;
          _isGamePaused = false;
          _isResumeCountdownActive = false;
          _currentQuestion = null; // Stale question flushed
          _questionIndex = 0;
          if (rNum != null && rNum > 0) {
            _currentRound = rNum;
          }
          if (incomingGenre != null && incomingGenre.isNotEmpty) {
            _activeGenre = incomingGenre;
          }
        });

        _startPreGameTimer();
      },
      onQuestionBroadcast: (payload) async {
        final duration = (payload['duration_seconds'] as num?)?.toInt() ?? 20;
        final rawQIdx = (payload['question_number_in_round'] as num?)?.toInt() ??
            (payload['question_index'] as num?)?.toInt() ?? 1;
        final totalQ = (payload['total_questions'] as num?)?.toInt() ??
            (payload['total_questions_in_round'] as num?)?.toInt() ?? 10;
        final rFromPayload = (payload['round_number'] as num?)?.toInt() ??
            (payload['roundNumber'] as num?)?.toInt();
        final roundNum = (rFromPayload != null && rFromPayload > 0)
            ? max(_currentRound, rFromPayload)
            : _currentRound;
        final qInRound = ((rawQIdx - 1) % totalQ) + 1;
        final cat = payload['category']?.toString() ?? payload['genre']?.toString();
        if (cat != null && cat.isNotEmpty) {
          _activeGenre = cat;
        }
        Question? question;

        try {
          if (payload.containsKey('question_text') ||
              payload.containsKey('text') ||
              payload.containsKey('question') ||
              payload.containsKey('questionData') ||
              payload.containsKey('question_data') ||
              payload.containsKey('option_a') ||
              payload.containsKey('options')) {
            question = Question.fromJson(payload);
          } else {
            final qId = (payload['question_id'] ?? payload['id'])?.toString();
            if (qId != null) {
              question = await _supabaseService.getQuestionById(qId);
            }
          }
        } catch (e) {
          debugPrint('[TV] Error parsing incoming question: $e');
        }

        question ??= TriviaRepository.getQuestionForGenres([_activeGenre], qInRound - 1);

        if (mounted) {
          // If this exact question is already actively playing and counting down on TV, ignore redundant echo
          if (_isGameActive &&
              _timer != null &&
              _timer!.isActive &&
              !_isTimerExpired &&
              !_isInterQuestionPhase &&
              !_isGamePaused &&
              !_isResumeCountdownActive &&
              _currentQuestion != null &&
              (_currentQuestion!.id == question.id || _currentQuestion!.questionText == question.questionText) &&
              _questionIndex == qInRound) {
            return;
          }

          final nowMs = DateTime.now().millisecondsSinceEpoch;
          final mode = (payload['game_play_mode'] ?? payload['gamePlayMode'])?.toString() ?? _gamePlayMode;
          _gamePlayMode = mode;
          final timerState = payload['timer_state']?.toString();
          final questionPhase = payload['question_phase']?.toString();
          final isIdleTimer = timerState == 'idle' || questionPhase == 'reading';

          final rawEndsAt = payload['timer_ends_at_epoch_ms'] ??
              payload['timerEndsAtEpochMs'] ??
              payload['timer_ends_at'] ??
              payload['timerEndsAtMs'];
          final timerEndsAtEpochMs = (rawEndsAt is num)
              ? rawEndsAt.toInt()
              : (rawEndsAt != null ? int.tryParse(rawEndsAt.toString()) : null);

          int targetEndsAt = (timerEndsAtEpochMs != null && timerEndsAtEpochMs > nowMs && !isIdleTimer)
              ? timerEndsAtEpochMs
              : (nowMs + duration * 1000);
          final remainingMs = targetEndsAt - nowMs;
          int durationSec = isIdleTimer ? duration : max(0, (remainingMs / 1000).ceil().clamp(0, 180));
          if (!isIdleTimer && durationSec <= 4 && duration > 4) {
            durationSec = duration;
            targetEndsAt = nowMs + (duration * 1000);
          }
          _targetTimerEndsAtMs = isIdleTimer ? null : targetEndsAt;

          _adSlideTimer?.cancel();
          _preGameTimer?.cancel();
          _interQuestionTimer?.cancel();
          _interRoundCountdownTimer?.cancel();
          _roundWinnersOverlayTimer?.cancel();
          _timer?.cancel();

          setState(() {
            _currentQuestion = question;
            _isInterRoundPhase = false;
            _showRoundWinnersOverlay = false;
            _totalDuration = duration;
            _remainingSeconds = durationSec;
            _questionIndex = qInRound;
            _currentRound = roundNum;
            _totalQuestionsInRound = totalQ;
            _isGameActive = true;
            _isPreGameCountdown = false;
            _isTimerExpired = false;
            _isInterQuestionPhase = false;
            _showRoundWinnersOverlay = false;
            _isGamePaused = false;
            _isResumeCountdownActive = false;
            _isQuestionTimerRunning = !isIdleTimer;
          });

          if (!isIdleTimer) {
            _startTimer();
          }
        }
      },
      onManualTimerStartedBroadcast: (payload) {
        if (!mounted || !_isGameActive) return;
        final rawEndsAt = payload['timer_ends_at_epoch_ms'] ?? payload['timerEndsAtMs'];
        final timerEndsAtEpochMs = (rawEndsAt is num) ? rawEndsAt.toInt() : int.tryParse('$rawEndsAt');
        final duration = (payload['duration_seconds'] as num?)?.toInt() ?? _totalDuration;
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final targetEndsAt = (timerEndsAtEpochMs != null && timerEndsAtEpochMs > nowMs)
            ? timerEndsAtEpochMs
            : (nowMs + duration * 1000);

        _targetTimerEndsAtMs = targetEndsAt;
        final remSec = max(0, ((targetEndsAt - nowMs) / 1000).ceil().clamp(0, 180));

        setState(() {
          _totalDuration = duration;
          _remainingSeconds = remSec;
          _isQuestionTimerRunning = true;
          _isTimerExpired = false;
          _isInterQuestionPhase = false;
        });
        _startTimer();
      },
      onTimerExpiredBroadcast: (payload) {
        _onTimerEnded(payload);
      },
      onGamePausedBroadcast: (payload) {
        if (mounted) {
          final now = DateTime.now().millisecondsSinceEpoch;
          if (_targetTimerEndsAtMs != null && _targetTimerEndsAtMs! > now) {
            _remainingSeconds = ((_targetTimerEndsAtMs! - now) / 1000).ceil();
          } else if (payload['remaining_question_seconds'] != null) {
            final raw = payload['remaining_question_seconds'];
            if (raw is num && raw > 0) {
              _remainingSeconds = raw.toInt();
            }
          }
          _targetTimerEndsAtMs = null;
          _timer?.cancel();
          _preGameTimer?.cancel();
          _resumeTimer?.cancel();
          _interQuestionTimer?.cancel();
          setState(() {
            _isGamePaused = true;
            _isResumeCountdownActive = false;
          });
          _startAdSlideTimer();
        }
      },
      onGameResumingBroadcast: (payload) {
        if (mounted) {
          _targetTimerEndsAtMs = null;
          _timer?.cancel();
          _preGameTimer?.cancel();
          _resumeTimer?.cancel();
          _interQuestionTimer?.cancel();

          if (payload['remaining_question_seconds'] != null) {
            final raw = payload['remaining_question_seconds'];
            if (raw is num && raw > 0) {
              _remainingSeconds = raw.toInt();
            }
          }

          final rawStartsAt = payload['starts_at_epoch_ms'] ?? payload['starts_at'];
          final startsAtEpochMs = (rawStartsAt is num)
              ? rawStartsAt.toInt()
              : (int.tryParse(rawStartsAt?.toString() ?? ''));
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
                if (_currentQuestion != null && !_isTimerExpired && !_isInterQuestionPhase) {
                  final rem = _remainingSeconds > 0 ? _remainingSeconds : 20;
                  _targetTimerEndsAtMs = DateTime.now().millisecondsSinceEpoch + (rem * 1000);
                  _startTimer();
                }
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
            _previousWrongOptions.clear();
            if (mode == 'clear_all') {
              _leaderboard = [];
            }
          });
        }
        if (mode != 'clear_all') {
          _loadLeaderboard();
        }
        _startAdSlideTimer();
      },
      onRoundCompletedBroadcast: (payload) {
        _previousWrongOptions.clear();
        final winners = payload['top_3_winners'] as List? ??
            payload['top3_winners'] as List? ??
            payload['top3Winners'] as List?;
        final rNum = (payload['round_number'] as num?)?.toInt() ??
            (payload['roundNumber'] as num?)?.toInt();
        if (rNum != null) {
          _currentRound = rNum;
        }
        final nextStartsAt = (payload['next_round_starts_at_epoch_ms'] as num?)?.toInt() ??
            (payload['nextRoundStartsAtEpochMs'] as num?)?.toInt() ??
            (payload['starts_at_epoch_ms'] as num?)?.toInt();
        final rawDelay = (payload['delaySeconds'] as num?)?.toInt() ??
            (payload['delay_seconds'] as num?)?.toInt() ??
            (payload['duration_seconds'] as num?)?.toInt() ??
            (payload['inter_round_duration'] as num?)?.toInt() ??
            _interRoundDurationSeconds;
        final delaySec = nextStartsAt != null
            ? (((nextStartsAt - DateTime.now().millisecondsSinceEpoch) / 1000).ceil().clamp(5, 660))
            : (rawDelay > 0 ? rawDelay : 120);

        if (mounted) {
          _timer?.cancel();
          _interQuestionTimer?.cancel();
          _preGameTimer?.cancel();
          _roundWinnersOverlayTimer?.cancel();
          _interRoundCountdownTimer?.cancel();

          final parsed = <Map<String, dynamic>>[];
          if (winners != null) {
            for (var item in winners) {
              if (item is Map) parsed.add(Map<String, dynamic>.from(item));
            }
          }
          final completedR = (payload['completed_round'] as num?)?.toInt() ??
              (payload['round_number'] as num?)?.toInt() ??
              (payload['roundNumber'] as num?)?.toInt() ??
              _currentRound;
          final nextR = (payload['next_round'] as num?)?.toInt() ??
              (payload['nextRound'] as num?)?.toInt() ??
              (completedR + 1);
          final wasAlreadyInInterRound = _isInterRoundPhase && _currentRound == nextR;
          if (nextStartsAt != null && nextStartsAt > DateTime.now().millisecondsSinceEpoch) {
            _interRoundTargetEpochMs = nextStartsAt;
          } else if (!wasAlreadyInInterRound || _interRoundTargetEpochMs <= DateTime.now().millisecondsSinceEpoch) {
            _interRoundTargetEpochMs = DateTime.now().millisecondsSinceEpoch + delaySec * 1000;
          }
          final effectiveRemSec = ((_interRoundTargetEpochMs - DateTime.now().millisecondsSinceEpoch) / 1000).ceil().clamp(1, 600);
          setState(() {
            _isGameActive = false;
            _currentQuestion = null;
            _previousWrongOptions.clear();
            _isTimerExpired = false;
            _isInterQuestionPhase = false;
            _interQuestionSecondsRemaining = 0;
            _isInterRoundPhase = true;
            _interRoundSecondsRemaining = effectiveRemSec;
            _top3Winners = parsed;
            if (!wasAlreadyInInterRound) {
              _showRoundWinnersOverlay = parsed.isNotEmpty;
            }
            _currentRound = nextR;
          });

          if (!wasAlreadyInInterRound && parsed.isNotEmpty) {
            SoundService.playSound('fanfare');
          }

          // Display the Top 3 Winners overlay for 20 seconds, then dismiss it
          // so the ad signage is displayed uncovered for the rest of the intermission
          if (!wasAlreadyInInterRound) {
            _roundWinnersOverlayTimer?.cancel();
            final winnerDisplaySec = effectiveRemSec > 20 ? 20 : effectiveRemSec;
            _roundWinnersOverlayTimer = Timer(Duration(seconds: winnerDisplaySec), () {
              if (mounted && _showRoundWinnersOverlay) {
                setState(() {
                  _showRoundWinnersOverlay = false;
                });
              }
            });
          }

          // Maintain countdown timer for the entire intermission time (e.g. 2 minutes)
          _interRoundCountdownTimer?.cancel();
          _interRoundCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
            if (!mounted) {
              timer.cancel();
              return;
            }
            final now = DateTime.now().millisecondsSinceEpoch;
            final rem = ((_interRoundTargetEpochMs - now) / 1000).ceil();
            if (rem > 0) {
              if (_interRoundSecondsRemaining != rem) {
                setState(() {
                  _interRoundSecondsRemaining = rem;
                });
              }
            } else {
              timer.cancel();
              setState(() {
                _isInterRoundPhase = false;
                _showRoundWinnersOverlay = false;
                _isTimerExpired = false;
                _isInterQuestionPhase = false;
                _isPreGameCountdown = true;
                _preGameSeconds = 5;
              });
              _startPreGameTimer();
            }
          });
          _startAdSlideTimer();
        }
      },
      onLeaderboardUpdatedBroadcast: (payload) {
        final singleNick = payload['nickname']?.toString();
        if (singleNick != null && singleNick.isNotEmpty && !SupabaseService.isMockNickname(singleNick)) {
          final rawScore = payload['score'] ?? payload['cumulative_score'] ?? 0;
          final score = (rawScore is num) ? rawScore.toInt() : (int.tryParse(rawScore.toString()) ?? 0);
          SupabaseService.registerIncomingPlayer(_displayRoomCode, singleNick, score);
          final updated = SupabaseService.mergeLocalPlayers(_displayRoomCode, [
            Player(
              id: singleNick,
              playerUid: 'uid-${singleNick.toLowerCase()}',
              roomCode: _displayRoomCode,
              nickname: singleNick,
              cumulativeScore: score,
              isConnected: true,
            )
          ]);
          if (mounted) {
            setState(() {
              _leaderboard = updated;
            });
          }
          return;
        }

        final pList = payload['players'] ?? payload['leaderboard'];
        if (pList is List && pList.isNotEmpty) {
          final incoming = <Player>[];
          for (var item in pList) {
            if (item is Map) {
              try {
                final map = Map<String, dynamic>.from(item);
                final nick = map['nickname']?.toString() ?? '';
                if (!SupabaseService.isMockNickname(nick)) {
                  incoming.add(Player.fromJson(map));
                }
              } catch (_) {}
            }
          }
          if (incoming.isNotEmpty) {
            SupabaseService.mergeLocalPlayers('TRIV', incoming);
            final merged = SupabaseService.mergeLocalPlayers(_displayRoomCode, incoming);
            if (mounted) {
              setState(() {
                _leaderboard = merged;
              });
            }
            return;
          }
        }
        _loadLeaderboard();
      },
      onRequestStateSyncBroadcast: (payload) {
        if (!mounted) return;
        final sender = payload['sender']?.toString();
        if (sender == 'tv') return;

        if (_isInterRoundPhase || _showRoundWinnersOverlay) {
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          final targetMs = _interRoundTargetEpochMs > nowMs
              ? _interRoundTargetEpochMs
              : (nowMs + (_interRoundSecondsRemaining * 1000));
          final remSec = ((targetMs - nowMs) / 1000).ceil().clamp(1, 600);
          _realtimeService.broadcastRoundCompleted(
            roomCode: _displayRoomCode,
            roundNumber: _currentRound > 1 ? _currentRound - 1 : 1,
            nextRound: _currentRound,
            top3Winners: _top3Winners.isNotEmpty
                ? _top3Winners
                : SupabaseService.getTop3RoundWinners(_displayRoomCode),
            nextRoundStartsAtEpochMs: targetMs,
            delaySeconds: remSec,
          );
        } else if (_isPreGameCountdown) {
          _realtimeService.broadcastGameStarting(
            roomCode: _displayRoomCode,
            startsAtEpochMs: DateTime.now().millisecondsSinceEpoch + ((_preGameSeconds > 0 ? _preGameSeconds : 10) * 1000),
            roundNumber: _currentRound,
            genre: _activeGenre,
          );
        } else if (_isGameActive && _currentQuestion != null) {
          if (!_isTimerExpired && !_isInterQuestionPhase && _remainingSeconds > 0) {
            final targetEndsAt = _targetTimerEndsAtMs ??
                (DateTime.now().millisecondsSinceEpoch + (_remainingSeconds * 1000));
            _realtimeService.broadcastQuestion(
              roomCode: _displayRoomCode,
              questionIndex: ((_currentRound - 1) * _totalQuestionsInRound) + (_questionIndex > 0 ? _questionIndex : 1),
              question: _currentQuestion!,
              durationSeconds: _totalDuration > 0 ? _totalDuration : (_remainingSeconds > 0 ? _remainingSeconds : 20),
              timerEndsAtEpochMs: targetEndsAt,
              roundNumber: _currentRound,
              totalQuestions: _totalQuestionsInRound,
            );
          } else if (_isTimerExpired || _isInterQuestionPhase) {
            _realtimeService.broadcastTimerExpired(
              roomCode: _displayRoomCode,
              correctOption: _currentQuestion!.correctOption,
              nextQuestionStartsAtEpochMs: _interQuestionTargetEpochMs > 0
                  ? _interQuestionTargetEpochMs
                  : (DateTime.now().millisecondsSinceEpoch + ((_interQuestionSecondsRemaining > 0 ? _interQuestionSecondsRemaining : 15) * 1000)),
              gamePlayMode: _gamePlayMode,
              questionId: _currentQuestion!.id,
              questionIndex: _questionIndex,
              roundNumber: _currentRound,
            );
          }
        }
        // Broadcast current active leaderboard to newly joined players so their screens sync instantly
        final currentPlayersJson = SupabaseService.getLocalPlayersJson(_displayRoomCode);
        if (currentPlayersJson.isNotEmpty) {
          _realtimeService.broadcastLeaderboardUpdated(
            roomCode: _displayRoomCode,
            players: currentPlayersJson,
          );
        }
      },
      onAdModeToggledBroadcast: (payload) {
        if (!mounted) return;
        final active = payload['isAdModeActive'] == true ||
            payload['is_ad_mode_active'] == true;
        if (payload['adSlideDurationSeconds'] != null || payload['ad_slide_duration_seconds'] != null) {
          final dur = int.tryParse((payload['adSlideDurationSeconds'] ?? payload['ad_slide_duration_seconds']).toString());
          if (dur != null && dur > 0) _adSlideDurationSeconds = dur;
        }
        setState(() {
          _isAdSignageModeActive = active;
        });
        _startAdSlideTimer();
      },
      onAdSlidesUpdatedBroadcast: (payload) {
        if (!mounted) return;
        final rawSlides = payload['slides'];
        if (rawSlides is List) {
          final parsed = <Map<String, dynamic>>[];
          for (final s in rawSlides) {
            if (s is Map) parsed.add(Map<String, dynamic>.from(s));
          }
          if (payload['adSlideDurationSeconds'] != null || payload['ad_slide_duration_seconds'] != null) {
            final dur = int.tryParse((payload['adSlideDurationSeconds'] ?? payload['ad_slide_duration_seconds']).toString());
            if (dur != null && dur > 0) _adSlideDurationSeconds = dur;
          }
          setState(() {
            _customAdSlides = parsed;
            if (_adSlideIndex >= _totalAdSlides) {
              _adSlideIndex = 0;
            }
            if (payload['isAdModeActive'] != null || payload['is_ad_mode_active'] != null) {
              _isAdSignageModeActive = payload['isAdModeActive'] == true || payload['is_ad_mode_active'] == true;
            }
          });
          _startAdSlideTimer();
        }
      },
      onSoundEffectsToggledBroadcast: (payload) {
        if (!mounted) return;
        final enabled = payload['isSoundEffectsEnabled'] != false &&
            payload['is_sound_effects_enabled'] != false &&
            payload['is_sound_enabled'] != false &&
            payload['sound_effects_enabled'] != false &&
            payload['soundEffectsEnabled'] != false &&
            (payload['isSoundEffectsEnabled'] == true ||
                payload['is_sound_effects_enabled'] == true ||
                payload['is_sound_enabled'] == true ||
                payload['sound_effects_enabled'] == true ||
                payload['soundEffectsEnabled'] == true);
        setState(() {
          _isSoundEffectsEnabled = enabled;
        });
        SoundService.isSoundEffectsEnabled = enabled;
        SharedPreferences.getInstance().then((prefs) {
          prefs.setBool('tv_sound_effects_enabled', enabled);
        }).catchError((_) {});
      },
    );
  }

  void _startRoundQuestionOneAutonomously() async {
    if (!mounted || !_isGameActive) return;

    final prevQuestionId = _currentQuestion?.id;
    await Future.delayed(const Duration(milliseconds: 4500));
    if (!mounted ||
        !_isGameActive ||
        _isPreGameCountdown ||
        _isInterRoundPhase ||
        _showRoundWinnersOverlay ||
        _isGamePaused ||
        (_currentQuestion != null && _currentQuestion?.id != prevQuestionId)) {
      return;
    }

    final question = TriviaRepository.getQuestionForGenres([_activeGenre], 0);
    final duration = _totalDuration > 0 ? _totalDuration : 20;
    final timerEndsAtEpochMs = DateTime.now().millisecondsSinceEpoch + (duration * 1000);

    setState(() {
      _currentQuestion = question;
      _questionIndex = 1;
      _totalDuration = duration;
      _remainingSeconds = duration;
      _targetTimerEndsAtMs = timerEndsAtEpochMs;
      _isTimerExpired = false;
      _isInterQuestionPhase = false;
    });

    _startTimer();

    try {
      await _realtimeService.broadcastQuestion(
        roomCode: _displayRoomCode,
        questionIndex: ((_currentRound - 1) * _totalQuestionsInRound) + 1,
        question: question,
        durationSeconds: duration,
        timerEndsAtEpochMs: timerEndsAtEpochMs,
        roundNumber: _currentRound,
        totalQuestions: _totalQuestionsInRound,
      );
    } catch (e) {
      debugPrint('[TV] Start round Question 1 broadcast error: $e');
    }

    try {
      await SupabaseConfig.client.from('game_sessions').upsert({
        'room_code': _displayRoomCode,
        'status': 'question_active',
        'current_question_index': ((_currentRound - 1) * _totalQuestionsInRound) + 1,
        'current_round': _currentRound,
        'round_number': _currentRound,
        'genre': _activeGenre,
        'duration_seconds': duration,
        'timer_ends_at': DateTime.fromMillisecondsSinceEpoch(timerEndsAtEpochMs).toIso8601String(),
        'question_data': question.toJson(),
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'room_code');
    } catch (_) {}
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
          _isGameActive = true; // Crucial: never revert to waiting carousel!
          _isTimerExpired = false;
          _isInterQuestionPhase = false;
        });

        if (GameEngineManager.instance.isEngineRunning) {
          GameEngineManager.instance.broadcastNextQuestion(roomCode: _displayRoomCode);
        } else {
          _startRoundQuestionOneAutonomously();
        }
      }
    });
  }

  Future<void> _loadLeaderboard() async {
    final players = await _supabaseService.getLeaderboard(_displayRoomCode);
    if (mounted) {
      setState(() {
        _leaderboard = SupabaseService.mergeLocalPlayers(_displayRoomCode, players);
      });
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _questionStartedAt = DateTime.now();
    _lastTickedSecond = -1;
    _isGamePaused = false;
    _isResumeCountdownActive = false;
    _targetTimerEndsAtMs ??= DateTime.now().millisecondsSinceEpoch + ((_remainingSeconds > 0 ? _remainingSeconds : 20) * 1000);
    // Silent countdown: do not play any sound until the last five seconds
    _timer = Timer.periodic(const Duration(milliseconds: 250), (t) {
      if (!mounted) {
        t.cancel();
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
            if (rem <= 5 && rem > 0 && _lastTickedSecond != rem) {
              _lastTickedSecond = rem;
              SoundService.playSound('tick', rem);
            }
          }
        } else {
          t.cancel();
          setState(() {
            _remainingSeconds = 0;
          });
          _onTimerEnded();
        }
      } else {
        if (_remainingSeconds > 0) {
          setState(() {
            _remainingSeconds--;
          });
          if (_remainingSeconds <= 5 && _remainingSeconds > 0 && _lastTickedSecond != _remainingSeconds) {
            _lastTickedSecond = _remainingSeconds;
            SoundService.playSound('tick', _remainingSeconds);
          }
        } else {
          t.cancel();
          _onTimerEnded();
        }
      }
    });
  }

  void _onTimerEnded([Map<String, dynamic>? payload]) async {
    // If receiving a remote timer_expired, guard against stale packets from previous questions
    if (payload != null &&
        _questionStartedAt != null &&
        DateTime.now().difference(_questionStartedAt!).inMilliseconds < 3500) {
      debugPrint('[TV] Ignoring stale timer_expired received within 3.5s of question start');
      return;
    }

    // When the correct question is displayed, play celebratory clapping and cheering sound ONLY ONCE per question
    final currentQId = _currentQuestion?.id ?? 'r${_currentRound}_q$_questionIndex';
    final alreadyRevealed = _isTimerExpired || _isInterQuestionPhase;
    if (!alreadyRevealed && _lastAnswerRevealSoundQuestionId != currentQId) {
      _lastAnswerRevealSoundQuestionId = currentQId;
      SoundService.playSound('clapping_fanfare');
      // SoundService.playSound('buzz');
    }
    _timer?.cancel();
    _interQuestionTimer?.cancel();

    final isRoundEndingQuestion = _questionIndex > 0 && (_questionIndex % _totalQuestionsInRound == 0);
    final reviewSeconds = isRoundEndingQuestion ? 20 : 15;

    final mode = payload?['game_play_mode'] as String? ?? 'Auto';
    final fallbackNext = isRoundEndingQuestion
        ? (DateTime.now().millisecondsSinceEpoch + 20000)
        : (DateTime.now().millisecondsSinceEpoch + 15000);
    final nextStartsAt = (payload?['next_question_starts_at_epoch_ms'] as int?) ??
        (payload?['nextQuestionStartsAtEpochMs'] as int?) ??
        fallbackNext;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final remaining = ((nextStartsAt - nowMs) / 1000).ceil().clamp(1, reviewSeconds);

    // If TV ended timer locally (payload was null), broadcast timer_expired so player screens immediately sync!
    if (payload == null) {
      _realtimeService.broadcastTimerExpired(
        roomCode: _displayRoomCode,
        correctOption: _currentQuestion?.correctOption,
        nextQuestionStartsAtEpochMs: nextStartsAt,
        gamePlayMode: mode,
        questionId: _currentQuestion?.id,
        questionIndex: _questionIndex,
        roundNumber: _currentRound,
      );
    }

    if (mounted) {
      setState(() {
        _isTimerExpired = true;
        _remainingSeconds = 0;
        _isInterQuestionPhase = true;
        _interQuestionSecondsRemaining = remaining;
        _totalInterQuestionDuration = remaining;
        _interQuestionTargetEpochMs = nextStartsAt;
        _gamePlayMode = mode;
        _isGamePaused = false;
        _isResumeCountdownActive = false;
      });
    }

    if (mode == 'Auto') {
      _interQuestionTimer = Timer.periodic(const Duration(milliseconds: 500), (t) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final rem = ((_interQuestionTargetEpochMs - now) / 1000).ceil();
        if (rem > 0) {
          if (mounted && _interQuestionSecondsRemaining != rem) {
            setState(() {
              _interQuestionSecondsRemaining = rem;
            });
            if (rem % 2 == 0) {
              _loadLeaderboard();
            }
          }
        } else {
          _interQuestionTimer?.cancel();
          if (mounted) {
            setState(() {
              _isInterQuestionPhase = false;
              _interQuestionSecondsRemaining = 0;
            });

            if (isRoundEndingQuestion) {
              if (GameEngineManager.instance.isEngineRunning) {
                GameEngineManager.instance.nextQuestionManual(roomCode: _displayRoomCode);
              } else {
                _completeRoundAutonomously();
              }
            } else {
              // Cleanly advance to the next question without state-sync echo looping
              if (GameEngineManager.instance.isEngineRunning) {
                GameEngineManager.instance.nextQuestionManual(roomCode: _displayRoomCode);
              } else {
                _advanceNextQuestionAutonomously();
              }
            }
          }
        }
      });
    }

    await _loadLeaderboard();

    // Re-check leaderboard at staggered intervals so answers submitted at timer expiry appear
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) _loadLeaderboard();
    });
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (mounted) _loadLeaderboard();
    });
    Future.delayed(const Duration(milliseconds: 4000), () {
      if (mounted) _loadLeaderboard();
    });
  }

  void _completeRoundAutonomously() async {
    if (!mounted) return;

    final prevRound = _currentRound;
    await Future.delayed(const Duration(milliseconds: 2500));
    if (!mounted ||
        _isInterRoundPhase ||
        _showRoundWinnersOverlay ||
        _isPreGameCountdown ||
        _currentRound != prevRound) {
      return;
    }

    _timer?.cancel();
    _interQuestionTimer?.cancel();

    // Determine top 3 players & award 20 points to the round winner
    final sorted = List<Player>.from(_leaderboard)
      ..sort((a, b) => b.score.compareTo(a.score));

    if (sorted.isNotEmpty) {
      final winner = sorted.first;
      // Strictly only award round bonus if winner scored points (> 0) and GameEngine hasn't already awarded it
      if (winner.score > 0 && !GameEngineManager.instance.isEngineRunning) {
        final newScore = winner.score + 20;
        SupabaseService.updatePlayerScoreDirectly(
          roomCode: _displayRoomCode,
          nickname: winner.nickname,
          score: newScore,
        );
        _supabaseService.updateLocalPlayerScore(
          roomCode: _displayRoomCode,
          nickname: winner.nickname,
          score: newScore,
          pointsToAdd: 20,
        );
        final wIdx = sorted.indexWhere((p) => p.nickname.toLowerCase() == winner.nickname.toLowerCase());
        if (wIdx >= 0) {
          sorted[wIdx] = Player(
            id: winner.id,
            playerUid: winner.playerUid,
            roomCode: winner.roomCode,
            nickname: winner.nickname,
            cumulativeScore: newScore,
            isConnected: winner.isConnected,
          );
        }
        sorted.sort((a, b) => b.score.compareTo(a.score));
        _leaderboard = sorted;

        _realtimeService.broadcastPlayerScoreUpdated(
          roomCode: _displayRoomCode,
          nickname: winner.nickname,
          score: newScore,
          pointsEarned: 20,
        );
        _realtimeService.broadcastLeaderboardUpdated(
          roomCode: _displayRoomCode,
          players: SupabaseService.getLocalPlayersJson(_displayRoomCode),
        );
      }
    }

    final winners = sorted.take(3).map((p) => {
      'nickname': p.nickname,
      'score': p.score,
    }).toList();

    final allGenres = TriviaGenres.allGenres.where((g) => g != 'Auto Select' && g != 'Random (Mixed)').toList();
    final currIdx = allGenres.indexOf(_activeGenre);
    final nextGenre = allGenres[(currIdx + 1) % allGenres.length];
    final nextRound = _currentRound + 1;
    final interRoundSec = _interRoundDurationSeconds > 0 ? _interRoundDurationSeconds : 120;
    final nextStartsAt = DateTime.now().millisecondsSinceEpoch + (interRoundSec * 1000);
    _interRoundTargetEpochMs = nextStartsAt;

    setState(() {
      _currentQuestion = null;
      _isTimerExpired = false;
      _isInterQuestionPhase = false;
      _isGameActive = false;
      _isInterRoundPhase = true;
      _interRoundSecondsRemaining = interRoundSec;
      _interQuestionSecondsRemaining = 0;
      _top3Winners = winners;
      _showRoundWinnersOverlay = true;
      _questionIndex = 0;
      _currentRound = nextRound;
      _activeGenre = nextGenre;
    });

    try {
      await _realtimeService.broadcastRoundCompleted(
        roomCode: _displayRoomCode,
        top3Winners: winners,
        roundNumber: prevRound,
        nextRound: nextRound,
        nextRoundStartsAtEpochMs: nextStartsAt,
        delaySeconds: interRoundSec,
      );
    } catch (e) {
      debugPrint('[TV] Autocomplete round broadcast error: $e');
    }

    try {
      await SupabaseConfig.client.from('game_sessions').upsert({
        'room_code': _displayRoomCode,
        'status': 'round_summary',
        'current_round': nextRound,
        'round_number': nextRound,
        'current_question_index': (nextRound - 1) * _totalQuestionsInRound,
        'duration_seconds': interRoundSec,
        'starts_at': DateTime.fromMillisecondsSinceEpoch(nextStartsAt).toIso8601String(),
        'timer_ends_at': DateTime.fromMillisecondsSinceEpoch(nextStartsAt).toIso8601String(),
        'genre': nextGenre,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'room_code');
    } catch (_) {}

    // Display Top 3 Winners overlay for 20 seconds, then dismiss so ad signage displays uncovered
    final winnerDisplaySec = interRoundSec > 20 ? 20 : interRoundSec;
    _roundWinnersOverlayTimer?.cancel();
    _roundWinnersOverlayTimer = Timer(Duration(seconds: winnerDisplaySec), () {
      if (mounted && _showRoundWinnersOverlay) {
        setState(() {
          _showRoundWinnersOverlay = false;
        });
      }
    });

    // Run the full intermission countdown between rounds (e.g. 2 minutes / 120s) displaying ad signage with active timer
    _interRoundCountdownTimer?.cancel();
    _interRoundCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final rem = ((nextStartsAt - now) / 1000).ceil();
      if (rem > 0) {
        if (_interRoundSecondsRemaining != rem) {
          setState(() {
            _interRoundSecondsRemaining = rem;
          });
        }
      } else {
        timer.cancel();
        setState(() {
          _isInterRoundPhase = false;
          _showRoundWinnersOverlay = false;
          _isTimerExpired = false;
          _isInterQuestionPhase = false;
          _isPreGameCountdown = true;
          _preGameSeconds = 5;
        });
        _startPreGameTimer();
      }
    });
    _startAdSlideTimer();
  }

  void _advanceNextQuestionAutonomously() async {
    if (!mounted || !_isGameActive || _showRoundWinnersOverlay) return;

    if (_questionIndex > 0 && _questionIndex % _totalQuestionsInRound == 0) {
      _completeRoundAutonomously();
      return;
    }

    final prevQuestionId = _currentQuestion?.id;
    final prevIndex = _questionIndex;
    final prevRound = _currentRound;
    await Future.delayed(const Duration(milliseconds: 4500));
    if (!mounted ||
        !_isGameActive ||
        _isPreGameCountdown ||
        _isInterRoundPhase ||
        _showRoundWinnersOverlay ||
        _isGamePaused ||
        _currentQuestion?.id != prevQuestionId ||
        _questionIndex != prevIndex ||
        _currentRound != prevRound) {
      return;
    }

    final nextIndex = _questionIndex + 1;
    debugPrint('[TV] Autonomously advancing to Question $nextIndex in Round $_currentRound');

    Question question;
    try {
      question = TriviaRepository.getQuestionForGenres([_activeGenre], nextIndex - 1);
    } catch (_) {
      final fallbackList = GenreQuestionsEngine.generateGenreQuestions(_activeGenre);
      final rawQuestion = fallbackList.isNotEmpty
          ? fallbackList[(nextIndex - 1) % fallbackList.length]
          : HomebrewingDatabase.generate500Questions()[(nextIndex - 1) % 500];
      question = _sanitizeQuestionDistractors(rawQuestion) ?? rawQuestion;
    }

    final duration = _totalDuration > 0 ? _totalDuration : 20;
    final timerEndsAtEpochMs = DateTime.now().millisecondsSinceEpoch + (duration * 1000);

    setState(() {
      _currentQuestion = question;
      _questionIndex = nextIndex;
      _totalDuration = duration;
      _remainingSeconds = duration;
      _targetTimerEndsAtMs = timerEndsAtEpochMs;
      _isTimerExpired = false;
      _isInterQuestionPhase = false;
    });

    _startTimer();

    try {
      await _realtimeService.broadcastQuestion(
        roomCode: _displayRoomCode,
        questionIndex: ((_currentRound - 1) * _totalQuestionsInRound) + nextIndex,
        question: question,
        durationSeconds: duration,
        timerEndsAtEpochMs: timerEndsAtEpochMs,
        roundNumber: _currentRound,
        totalQuestions: _totalQuestionsInRound,
      );
    } catch (e) {
      debugPrint('[TV] Safety Net broadcast error: $e');
    }

    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted &&
          _isGameActive &&
          _questionIndex == nextIndex &&
          _currentQuestion?.id == question.id) {
        _realtimeService.broadcastQuestion(
          roomCode: _displayRoomCode,
          questionIndex: ((_currentRound - 1) * _totalQuestionsInRound) + nextIndex,
          question: question,
          durationSeconds: duration,
          timerEndsAtEpochMs: timerEndsAtEpochMs,
          roundNumber: _currentRound,
          totalQuestions: _totalQuestionsInRound,
        );
      }
    });

    try {
      await SupabaseConfig.client.from('game_sessions').upsert({
        'room_code': _displayRoomCode,
        'status': 'question_active',
        'current_question_index': ((_currentRound - 1) * _totalQuestionsInRound) + nextIndex,
        'current_round': _currentRound,
        'round_number': _currentRound,
        'genre': _activeGenre,
        'duration_seconds': duration,
        'timer_ends_at': DateTime.fromMillisecondsSinceEpoch(timerEndsAtEpochMs).toIso8601String(),
        'question_data': question.toJson(),
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'room_code');
    } catch (_) {}
  }

  @override
  void dispose() {
    _tvSessionPollingTimer?.cancel();
    _timer?.cancel();
    _preGameTimer?.cancel();
    _adSlideTimer?.cancel();
    _roundWinnersOverlayTimer?.cancel();
    _interRoundCountdownTimer?.cancel();
    _realtimeService.leaveChannel();
    super.dispose();
  }

  void _showExitApplicationDialog() {
    if (_isExitDialogOpen) return;
    setState(() => _isExitDialogOpen = true);

    bool isCancelFocused = false;
    bool isYesFocused = true;
    bool isHostQrFocused = false;

    void handleConfirmExit(BuildContext dialogContext) {
      if (mounted) setState(() => _isExitDialogOpen = false);
      Navigator.of(dialogContext).pop();
      exitApplication();
    }

    void handleCancelExit(BuildContext dialogContext) {
      if (mounted) setState(() => _isExitDialogOpen = false);
      Navigator.of(dialogContext).pop();
    }

    void handleShowHostQr(BuildContext dialogContext) {
      if (mounted) setState(() => _isExitDialogOpen = false);
      Navigator.of(dialogContext).pop();
      _showHostControlQrDialog();
    }

    void handleFocusedActivate(BuildContext dialogContext) {
      if (isCancelFocused) {
        handleCancelExit(dialogContext);
      } else if (isHostQrFocused) {
        handleShowHostQr(dialogContext);
      } else {
        handleConfirmExit(dialogContext);
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {},
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.select): () => handleFocusedActivate(dialogContext),
            const SingleActivator(LogicalKeyboardKey.enter): () => handleFocusedActivate(dialogContext),
            const SingleActivator(LogicalKeyboardKey.numpadEnter): () => handleFocusedActivate(dialogContext),
            const SingleActivator(LogicalKeyboardKey.gameButtonA): () => handleFocusedActivate(dialogContext),
          },
          child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppTheme.cardSurfaceElevated,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppTheme.neonCyan.withOpacity(0.5),
                width: 2.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.8),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: AppTheme.neonCyan.withOpacity(0.2),
                  blurRadius: 20,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.neonCyan.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.neonCyan.withOpacity(0.5)),
                      ),
                      child: const Icon(
                        Icons.tv_rounded,
                        color: AppTheme.neonCyan,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TV DISPLAY MENU',
                            style: TextStyle(
                              color: AppTheme.neonCyan,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Exit Application',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  'Choose an option below. If the host lost the current game website, select the Host Control QR Code to view the recovery code.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                // Yes and Cancel row placed above Host Control QR Code button (Yes on left, Cancel on right)
                StatefulBuilder(
                  builder: (context, setBtnState) {
                    return FocusTraversalGroup(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  autofocus: true,
                                  onFocusChange: (f) => setBtnState(() {
                                    isYesFocused = f;
                                    if (f) {
                                      isCancelFocused = false;
                                      isHostQrFocused = false;
                                    }
                                  }),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isYesFocused ? AppTheme.neonCyan : Colors.redAccent.withOpacity(0.2),
                                    foregroundColor: isYesFocused ? Colors.black : Colors.redAccent,
                                    side: BorderSide(
                                      color: isYesFocused ? AppTheme.neonCyan : Colors.redAccent,
                                      width: isYesFocused ? 2.5 : 1.5,
                                    ),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    elevation: isYesFocused ? 8 : 0,
                                    shadowColor: isYesFocused ? AppTheme.neonCyan.withOpacity(0.7) : Colors.transparent,
                                  ),
                                  icon: Icon(
                                    Icons.power_settings_new_rounded,
                                    size: 18,
                                    color: isYesFocused ? Colors.black : Colors.redAccent,
                                  ),
                                  label: Text(
                                    'Yes',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: isYesFocused ? Colors.black : Colors.redAccent,
                                    ),
                                  ),
                                  onPressed: () => handleConfirmExit(dialogContext),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton(
                                  onFocusChange: (f) => setBtnState(() {
                                    isCancelFocused = f;
                                    if (f) {
                                      isYesFocused = false;
                                      isHostQrFocused = false;
                                    }
                                  }),
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: isCancelFocused ? AppTheme.neonCyan : Colors.transparent,
                                    foregroundColor: isCancelFocused ? Colors.black : Colors.white70,
                                    side: BorderSide(
                                      color: isCancelFocused ? AppTheme.neonCyan : Colors.white.withOpacity(0.2),
                                      width: isCancelFocused ? 2.0 : 1.0,
                                    ),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    elevation: isCancelFocused ? 6 : 0,
                                  ),
                                  onPressed: () => handleCancelExit(dialogContext),
                                  child: Text(
                                    'Cancel',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: isCancelFocused ? Colors.black : Colors.white70,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          // HOST CONTROL QR CODE BUTTON
                          ElevatedButton.icon(
                            onFocusChange: (f) => setBtnState(() {
                              isHostQrFocused = f;
                              if (f) {
                                isYesFocused = false;
                                isCancelFocused = false;
                              }
                            }),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isHostQrFocused ? AppTheme.neonCyan : AppTheme.neonYellow,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: isHostQrFocused ? 8 : 6,
                              shadowColor: (isHostQrFocused ? AppTheme.neonCyan : AppTheme.neonYellow).withOpacity(0.5),
                            ),
                            icon: const Icon(Icons.qr_code_2_rounded, size: 24, color: Colors.black),
                            label: const Text(
                              'HOST CONTROL QR CODE',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.0,
                              ),
                            ),
                            onPressed: () => handleShowHostQr(dialogContext),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        ),
      ),
    ).then((_) {
      if (mounted) setState(() => _isExitDialogOpen = false);
    });
  }

  Future<void> _showHostControlQrDialog() async {
    bool isGameRunning = _isGameActive ||
        _isPreGameCountdown ||
        _isGamePaused ||
        _isResumeCountdownActive ||
        _isInterQuestionPhase ||
        _showRoundWinnersOverlay ||
        _currentQuestion != null;

    if (!isGameRunning) {
      try {
        final res = await SupabaseConfig.client
            .from('game_sessions')
            .select('status')
            .eq('room_code', _displayRoomCode)
            .maybeSingle()
            .timeout(const Duration(milliseconds: 900));
        if (res != null) {
          final st = res['status'] as String?;
          if (st != null && st != 'idle' && st != 'ended' && st != 'cancelled') {
            isGameRunning = true;
          }
        }
      } catch (_) {}
    }

    if (!mounted) return;

    final hostUrl = '$_playerBaseUrl/?view=host&room=$_displayRoomCode';

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: isGameRunning
            ? _buildActiveHostQrModal(dialogContext, hostUrl)
            : _buildNoActiveGameModal(dialogContext),
      ),
    );
  }

  Widget _buildActiveHostQrModal(BuildContext dialogContext, String hostUrl) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 540),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppTheme.cardSurfaceElevated,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppTheme.neonYellow, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.85),
            blurRadius: 32,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: AppTheme.neonYellow.withOpacity(0.35),
            blurRadius: 30,
            spreadRadius: 2,
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.neonYellow.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.neonYellow, width: 1.5),
                  ),
                  child: const Text('👑', style: TextStyle(fontSize: 26)),
                ),
                const SizedBox(width: 14),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'HOST CONTROLS RECOVERY',
                      style: TextStyle(
                        color: AppTheme.neonYellow,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Current Game Host QR Code',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.neonCyan.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.neonCyan),
                  ),
                  child: Text(
                    'ROOM: $_displayRoomCode',
                    style: const TextStyle(
                      color: AppTheme.neonCyan,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    'ROUND $_currentRound',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Scan this QR code with your phone or tablet camera to reconnect to the live game host controls if you lost your browser window or closed the controls tab.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            // High-Contrast QR Code Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.neonYellow.withOpacity(0.35),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: QrImageView(
                data: hostUrl,
                version: QrVersions.auto,
                size: 200.0,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
                dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.link_rounded, size: 18, color: AppTheme.neonCyan),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      hostUrl,
                      style: const TextStyle(
                        color: AppTheme.neonCyan,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            ElevatedButton.icon(
              autofocus: true,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.neonCyan,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 6,
              ),
              icon: const Icon(Icons.arrow_back_rounded, size: 20, color: Colors.black),
              label: const Text(
                'BACK TO TV DISPLAY',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  letterSpacing: 1.0,
                ),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoActiveGameModal(BuildContext dialogContext) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 480),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppTheme.cardSurfaceElevated,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: AppTheme.neonCyan.withOpacity(0.6),
          width: 2.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.85),
            blurRadius: 32,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: AppTheme.neonCyan.withOpacity(0.2),
            blurRadius: 28,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.neonCyan.withOpacity(0.12),
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.neonCyan.withOpacity(0.5), width: 2),
            ),
            child: const Icon(
              Icons.videogame_asset_off_rounded,
              size: 52,
              color: AppTheme.neonCyan,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'NO CURRENT GAME RUNNING',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'There is no current game running in Room $_displayRoomCode.\n\nStart a new game from the host dashboard or wait for a host to launch a game session.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.white70,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.neonYellow.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.neonYellow.withOpacity(0.4)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info_outline, size: 16, color: AppTheme.neonYellow),
                SizedBox(width: 8),
                Text(
                  'STATUS: WAITING FOR HOST / IDLE',
                  style: TextStyle(
                    color: AppTheme.neonYellow,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            autofocus: true,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.neonCyan,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 6,
            ),
            icon: const Icon(Icons.check_circle_outline, size: 20, color: Colors.black),
            label: const Text(
              'RETURN TO TV DISPLAY',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 15,
                letterSpacing: 1.0,
              ),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (context.mounted) {
          _showExitApplicationDialog();
        }
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _showExitApplicationDialog,
          const SingleActivator(LogicalKeyboardKey.goBack): _showExitApplicationDialog,
        },
        child: Scaffold(
          backgroundColor: AppTheme.darkBackground,
          body: SafeArea(
            child: Stack(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
              child: Column(
                children: [
                  // Top Centered Header Bar with Exit Application
                  SizedBox(
                    height: 42,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Opacity(
                          opacity: (_currentQuestion != null && !_isInterQuestionPhase) ? 0.0 : 1.0,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: const Icon(Icons.arrow_back, color: Colors.white70, size: 24),
                            tooltip: 'Exit Application',
                            onPressed: _showExitApplicationDialog,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
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
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2.0,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        // Placeholder to keep logo centered with spaceBetween
                        const SizedBox(width: 24),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Main TV Stage Grid: Live Round / Paused / Resuming OR Pre-Game Countdown OR Official 4-Page Advertisement Carousel
                  Expanded(
                    child: (_isGamePaused && _isAdSignageModeActive)
                        ? _buildFullscreenSignageDisplay()
                        : ((_isInterRoundPhase || _isAdSignageModeActive || (_customAdSlides.isNotEmpty && !_isGameActive && !_isPreGameCountdown && !_isResumeCountdownActive))
                            ? _buildFullscreenSignageDisplay()
                            : ((_isGameActive || _isGamePaused || _isResumeCountdownActive)
                                ? _buildLiveStageGrid()
                                : (_isPreGameCountdown
                                    ? _buildPreGameCountdownScreen()
                                    : _buildOfficial4PageAdCarousel()))),
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
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppTheme.neonCyan.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: AppTheme.neonCyan, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.neonCyan.withOpacity(0.3),
                                blurRadius: 16,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.timer_rounded, color: AppTheme.neonCyan, size: 22),
                              const SizedBox(width: 8),
                              Text(
                                'NEXT ROUND IN ${_formatIntermissionMinutes(_interRoundSecondsRemaining)}',
                                style: const TextStyle(
                                  color: AppTheme.neonCyan,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        ...List.generate(_top3Winners.length, (idx) {
                          final w = _top3Winners[idx];
                          final badges = ['🥇 1ST PLACE (+20 BONUS)', '🥈 2ND PLACE', '🥉 3RD PLACE'];
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

                // Lowered & Centered Intermission Countdown or Waiting for host banner with generous spacing
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.darkBackground,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _isInterRoundPhase ? AppTheme.neonYellow : AppTheme.neonCyan,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (_isInterRoundPhase ? AppTheme.neonYellow : AppTheme.neonCyan).withValues(alpha: 0.45),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Text(
                      _isInterRoundPhase
                          ? 'NEXT ROUND IN ${_formatIntermissionMinutes(_interRoundSecondsRemaining)}'
                          : 'WAITING FOR HOST TO START GAME',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: _isInterRoundPhase ? AppTheme.neonYellow : Colors.white,
                        letterSpacing: 1.5,
                        shadows: [
                          Shadow(
                            color: _isInterRoundPhase ? AppTheme.neonYellow : AppTheme.neonCyan,
                            blurRadius: 14,
                          ),
                          Shadow(
                            color: _isInterRoundPhase ? AppTheme.neonYellow : AppTheme.neonCyan,
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
                  const SizedBox(height: 12),
                  Text(
                    'ROOM: $_displayRoomCode',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3.5,
                      color: AppTheme.neonYellow,
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

  /// Fullscreen Venue Ad / Sponsor Signage Display Screen
  Widget _buildFullscreenSignageDisplay() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppTheme.neonCyan.withValues(alpha: 0.6), width: 2),
        boxShadow: [
          BoxShadow(
            color: AppTheme.neonCyan.withValues(alpha: 0.2),
            blurRadius: 36,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Stack(
          children: [
            // Fullscreen Animated Slide Content
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 700),
                switchInCurve: Curves.easeInOut,
                switchOutCurve: Curves.easeInOut,
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(opacity: animation, child: child);
                },
                child: KeyedSubtree(
                  key: ValueKey(_adSlideIndex),
                  child: _buildFullscreenAdSlide(_adSlideIndex),
                ),
              ),
            ),

            if (_isInterRoundPhase)
              Positioned(
                top: 24,
                right: 28,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.darkBackground.withOpacity(0.94),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.neonYellow, width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.neonYellow.withOpacity(0.45),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer_rounded, color: AppTheme.neonYellow, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        'NEXT ROUND IN ${_formatIntermissionMinutes(_interRoundSecondsRemaining)}',
                        style: const TextStyle(
                          color: AppTheme.neonYellow,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Selects the appropriate advertisement poster for Signage Mode.
  /// The official default ad is broken up into 3 clean, uncluttered slides:
  /// - Slide 0: "HOW TO PLAY ON YOUR MOBILE PHONE" (Scan QR, Real-Time Buzzer, Win & Rank)
  /// - Slide 1: "HOST YOUR OWN PUB TRIVIA NIGHT" (Automated Host, 30+ Genres, Hook Up Any TV)
  /// - Slide 2: "BAR ROOMS TRIVIA APP" (Google Play App, Features, Instant Web Play)
  ///
  /// When host uploads custom slides, the 3 default slides rotate IN-BETWEEN the host uploaded slides:
  /// Default 0 -> Custom 0 -> Default 1 -> Custom 1 -> Default 2 -> Custom 2 (or loop)
  Widget _buildFullscreenAdSlide(int index) {
    if (_customAdSlides.isEmpty) {
      final defaultIdx = index % 3;
      if (defaultIdx == 0) return _buildFullscreenSlide0();
      if (defaultIdx == 1) return _buildFullscreenSlide1();
      return _buildFullscreenSlide2();
    }
    // Rotate default slides in-between host uploaded slides:
    // Even indices: default slides (0, 1, 2)
    // Odd indices: custom host uploaded slides
    if (index % 2 == 0) {
      final defaultIdx = (index ~/ 2) % 3;
      if (defaultIdx == 0) return _buildFullscreenSlide0();
      if (defaultIdx == 1) return _buildFullscreenSlide1();
      return _buildFullscreenSlide2();
    } else {
      final customIdx = (index ~/ 2) % _customAdSlides.length;
      return _buildCustomAdSlide(_customAdSlides[customIdx]);
    }
  }

  /// Signage Slide 0: How to Play & Join on Mobile Phone (Player Focus)
  Widget _buildFullscreenSlide0() {
    final playUrl = _getPlayUrl();
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 20, 36, 56),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.neonCyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.neonCyan, width: 1.5),
                ),
                child: const Text(
                  '⚡ OFFICIAL BAR & HOME TRIVIA APP • NO APP DOWNLOAD REQUIRED ⚡',
                  style: TextStyle(
                    color: AppTheme.neonCyan,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Text(
                  'FAST 30-SECOND JOIN',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'HOW TO PLAY ON YOUR MOBILE PHONE',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 2,
              shadows: [
                Shadow(
                  color: AppTheme.neonCyan.withValues(alpha: 0.6),
                  blurRadius: 18,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'JOIN THE GAME SHOW IN UNDER 30 SECONDS RIGHT FROM YOUR TABLE!',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.neonYellow),
          ),
          const SizedBox(height: 12),
          Expanded(
            flex: 68,
            child: Row(
              children: [
                Expanded(
                  child: _buildSignageStepCard(
                    '1',
                    '📱',
                    'SCAN THE QR CODE',
                    AppTheme.neonCyan,
                    'PLAY ON ANY PHONE! Open your camera and point it at the TV screen. Tap the link to join instantly without downloading an app.',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSignageStepCard(
                    '2',
                    '⚡',
                    'BUZZ IN & WIN',
                    AppTheme.neonYellow,
                    'REAL-TIME MULTIPLAYER! 4 color-coded answers appear on your phone. Tap fast before the timer hits zero for speed bonus points!',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSignageStepCard(
                    '3',
                    '🏆',
                    'CLIMB THE LIVE TV LEADERBOARD',
                    AppTheme.neonGreen,
                    'LIVE TV LEADERBOARD! Watch standings update in real-time on the big screen! Top 3 players win round championship bonuses.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            flex: 26,
            child: _buildSignageBottomJoinBanner(playUrl, 'NO APPS TO INSTALL • WORKS ON ANY SMARTPHONE CAMERA'),
          ),
        ],
      ),
    );
  }

  /// Signage Slide 1: Host Your Own Pub Trivia Night (Home & Venues)
  Widget _buildFullscreenSlide1() {
    final playUrl = _getPlayUrl();
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 20, 36, 56),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.neonGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.neonGreen, width: 1.5),
                ),
                child: const Text(
                  '🏡 USE AT HOME FOR TRIVIA NIGHT PARTIES & VENUES 🏡',
                  style: TextStyle(
                    color: AppTheme.neonGreen,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Text(
                  '100% AUTOMATED HOST',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'HOST YOUR OWN PUB TRIVIA NIGHT AT HOME & VENUES!',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 2,
              shadows: [
                Shadow(
                  color: AppTheme.neonGreen.withValues(alpha: 0.6),
                  blurRadius: 18,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'BRING THE EXCITEMENT OF PUB TRIVIA HOME! Turn any TV and mobile phones into an interactive game show.',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.neonYellow),
          ),
          const SizedBox(height: 12),
          Expanded(
            flex: 68,
            child: Row(
              children: [
                Expanded(
                  child: _buildSignageFeatureCard(
                    '🤖',
                    'AUTOMATED GAME HOST',
                    AppTheme.neonPurple,
                    'Sit back and enjoy your party! Built-in automated host mode runs rounds, reads questions, and tallies winners hands-free.',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSignageFeatureCard(
                    '🎯',
                    '30+ TRIVIA GENRES',
                    AppTheme.neonGreen,
                    'Pop Culture, 80s/90s Nostalgia, Sports, History, Science, Literature, Riddles & thousands of fresh curated questions!',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSignageFeatureCard(
                    '🏠',
                    'PERFECT FOR PARTIES',
                    AppTheme.neonYellow,
                    'Great for family game nights, house parties, brewery taprooms, birthday bashes, office socials, and holiday events!',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            flex: 26,
            child: _buildSignageBottomJoinBanner(playUrl, 'SCAN TO JOIN NOW • PLAY BAR ROOMS TRIVIA ON ANY PHONE!'),
          ),
        ],
      ),
    );
  }

  /// Signage Slide 2: Official Bar Rooms Trivia App (Google Play Store & Amazon Fire TV Appstore)
  Widget _buildFullscreenSlide2() {
    final playUrl = _getPlayUrl();
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 20, 36, 56),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.neonCyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.neonCyan, width: 1.5),
                ),
                child: const Text(
                  '📲 OFFICIAL APP ON GOOGLE PLAY & AMAZON FIRE TV 📲',
                  style: TextStyle(
                    color: AppTheme.neonCyan,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Text(
                  'FREE FOR ALL DEVICES',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'BAR ROOMS TRIVIA',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 2,
              shadows: [
                Shadow(
                  color: AppTheme.neonCyan.withValues(alpha: 0.6),
                  blurRadius: 18,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'DOWNLOAD THE OFFICIAL APP ON GOOGLE PLAY & AMAZON FIRE TV APPSTORE',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.neonYellow),
          ),
          const SizedBox(height: 12),
          Expanded(
            flex: 68,
            child: Row(
              children: [
                Expanded(
                  flex: 52,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.neonCyan.withValues(alpha: 0.4), width: 1.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: const [
                        Text('⭐ EVERYTHING YOU NEED TO HOST & PLAY', style: TextStyle(color: AppTheme.neonCyan, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1)),
                        Text('✓ 100% Free: Unlimited rounds, games, and connected players', style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600)),
                        Text('✓ Real-Time Multiplayer: Live synchronized countdown timers & buzzers', style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600)),
                        Text('✓ Custom Signage & Ads: Rotate venue specials and party flyers on TV', style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600)),
                        Text('✓ Offline Fallback: Local questions ensure the trivia night never stops', style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  flex: 48,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.neonYellow.withValues(alpha: 0.5), width: 1.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        const Text(
                          'DOWNLOAD FROM APP STORES',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1),
                        ),
                        Row(
                          children: [
                            // Google Play Badge
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white30),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.play_arrow_rounded, color: AppTheme.neonGreen, size: 24),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: const [
                                          Text('GET IT ON', style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w600)),
                                          Text('Google Play', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Amazon Fire TV Badge
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Color(0xFFFF9900).withValues(alpha: 0.6)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.local_fire_department_rounded, color: Color(0xFFFF9900), size: 24),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: const [
                                          Text('AVAILABLE AT', style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w600)),
                                          Text('Amazon Fire TV', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Text(
                          '✓ Search "Bar Rooms Trivia" on Google Play Store',
                          style: TextStyle(color: AppTheme.neonCyan, fontWeight: FontWeight.w700, fontSize: 12.5),
                        ),
                        const Text(
                          '✓ Search "Bar Rooms Trivia" on Amazon Fire TV Appstore',
                          style: TextStyle(color: Color(0xFFFF9900), fontWeight: FontWeight.w700, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            flex: 26,
            child: _buildSignageBottomJoinBanner(playUrl, 'SCAN TO PLAY BAR ROOMS TRIVIA FROM YOUR TABLE!'),
          ),
        ],
      ),
    );
  }

  Widget _buildVenueChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.neonCyan.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.neonCyan.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: const TextStyle(color: AppTheme.neonCyan, fontWeight: FontWeight.w700, fontSize: 11),
      ),
    );
  }

  /// Renders a host-uploaded custom advertisement slide (Base64 image or network URL)
  Widget _buildCustomAdSlide(Map<String, dynamic> slide) {
    final playUrl = _getPlayUrl();
    final dataUrl = slide['dataUrl']?.toString() ??
        slide['data_url']?.toString() ??
        slide['url']?.toString() ??
        slide['image_url']?.toString() ??
        '';
    final slideName = slide['name']?.toString() ?? 'VENUE AD';

    Uint8List? imageBytes;
    if (dataUrl.startsWith('data:image')) {
      try {
        final commaIdx = dataUrl.indexOf(',');
        if (commaIdx != -1) {
          final b64 = dataUrl.substring(commaIdx + 1);
          imageBytes = base64Decode(b64);
        }
      } catch (_) {}
    } else if (!dataUrl.startsWith('http') && dataUrl.length > 50) {
      try {
        imageBytes = base64Decode(dataUrl);
      } catch (_) {}
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 56),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Venue Tag
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.neonCyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.neonCyan, width: 1.5),
                ),
                child: Text(
                  '📢 ${slideName.toUpperCase()} 📢',
                  style: const TextStyle(
                    color: AppTheme.neonCyan,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 1.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Text(
                'FEATURED VENUE PROMOTION',
                style: TextStyle(color: Colors.white60, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Main Slide Image Display
          Expanded(
            flex: 74,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.neonCyan.withValues(alpha: 0.4), width: 1.5),
                ),
                child: imageBytes != null
                    ? Image.memory(
                        imageBytes,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => _buildSlideImageFallback(slideName),
                      )
                    : (dataUrl.startsWith('http')
                        ? Image.network(
                            dataUrl,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => _buildSlideImageFallback(slideName),
                          )
                        : _buildSlideImageFallback(slideName)),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Bottom Join Banner with QR code
          Expanded(
            flex: 26,
            child: _buildSignageBottomJoinBanner(playUrl, 'SCAN TO PLAY BAR ROOMS TRIVIA FROM YOUR TABLE!'),
          ),
        ],
      ),
    );
  }

  Widget _buildSlideImageFallback(String title) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.campaign_rounded, size: 64, color: AppTheme.neonCyan),
          const SizedBox(height: 12),
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }



  /// Helper card for 6-feature grid on Slide 0
  Widget _buildSignageFeatureCard(String icon, String title, Color color, String desc) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Text(icon, style: const TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12.5, letterSpacing: 0.8),
                ),
                const SizedBox(height: 3),
                Text(
                  desc,
                  style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.2),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }



  /// Helper card for 3 step cards on Slide 2
  Widget _buildSignageStepCard(String stepNum, String icon, String title, Color color, String desc) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 1.5),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.1), blurRadius: 16, spreadRadius: 1),
        ],
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
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'STEP $stepNum',
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1),
                ),
              ),
              Text(icon, style: const TextStyle(fontSize: 24)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.8),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Text(
              desc,
              style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  /// Helper banner for bottom of Slides 1, 2, and 3
  Widget _buildSignageBottomJoinBanner(String playUrl, String hookText) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.neonCyan.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: QrImageView(
              data: playUrl,
              version: QrVersions.auto,
              size: 55,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  hookText,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 0.5),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Text('ROOM: ', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12)),
                    Text(
                      _displayRoomCode,
                      style: const TextStyle(color: AppTheme.neonYellow, fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 2),
                    ),
                    const SizedBox(width: 14),
                    const Text('•  Scan with phone camera to join instantly!', style: TextStyle(color: AppTheme.neonCyan, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Mini colored tag chip
  Widget _buildMiniTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 10),
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
            padding: const EdgeInsets.only(left: 24, right: 24, top: 10, bottom: 14),
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
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.neonPurple.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.neonPurple),
                      ),
                      child: Text(
                        _currentQuestion?.category.toUpperCase() ?? 'GENERAL TRIVIA',
                        style: const TextStyle(
                          color: AppTheme.neonPurple,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
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
                    else if (_isGamePaused && !_isResumeCountdownActive && (!_isGameActive || (_timer == null || !_timer!.isActive) || _isTimerExpired))
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
                      ),
                    TimerRing(
                      size: 58,
                      progress: _isInterQuestionPhase
                          ? (_gamePlayMode == 'Manual'
                              ? 1.0
                              : (_interQuestionSecondsRemaining / (_totalInterQuestionDuration > 0 ? _totalInterQuestionDuration : 15.0)).clamp(0.0, 1.0))
                          : (!_isQuestionTimerRunning ? 1.0 : progress),
                      remainingSeconds: _isInterQuestionPhase
                          ? (_gamePlayMode == 'Manual' ? 0 : _interQuestionSecondsRemaining)
                          : (!_isQuestionTimerRunning ? _totalDuration : _remainingSeconds),
                      label: _isInterQuestionPhase
                          ? (_gamePlayMode == 'Manual'
                              ? 'WAIT HOST'
                              : (_questionIndex > 0 && (_questionIndex % _totalQuestionsInRound == 0)
                                  ? 'Round Results'
                                  : 'Next Question'))
                          : (!_isQuestionTimerRunning ? 'READY' : 'SECONDS'),
                      customColor: _isInterQuestionPhase
                          ? AppTheme.neonCyan
                          : (!_isQuestionTimerRunning ? AppTheme.neonGreen : null),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.center,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 950),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              'ROUND $_currentRound • QUESTION ${_questionIndex > 0 ? (((_questionIndex - 1) % _totalQuestionsInRound) + 1) : 1} OUT OF $_totalQuestionsInRound',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.neonCyan,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _currentQuestion?.questionText ??
                                  '🚀 GET READY! QUESTION ${_questionIndex > 0 ? (((_questionIndex - 1) % _totalQuestionsInRound) + 1) : 1} IS STARTING...',
                              textAlign: TextAlign.center,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (_currentQuestion != null) ...[
                  Row(
                    children: [
                      Expanded(child: _buildOptionTile('A', _currentQuestion!.optionA, AppTheme.buttonA)),
                      const SizedBox(width: 14),
                      Expanded(child: _buildOptionTile('B', _currentQuestion!.optionB, AppTheme.buttonB)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _buildOptionTile('C', _currentQuestion!.optionC, AppTheme.buttonC)),
                      const SizedBox(width: 14),
                      Expanded(child: _buildOptionTile('D', _currentQuestion!.optionD, AppTheme.buttonD)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 20),

        Expanded(
          flex: 35,
          child: Column(
            children: [
              QrDisplayWidget(
                roomCode: _displayRoomCode,
                showRoomCode: false,
                compact: true,
              ),
              const SizedBox(height: 12),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: showCorrect ? const Color(0xFF10B981) : color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: Colors.white,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 16,
                fontWeight: showCorrect ? FontWeight.bold : FontWeight.w600,
                color: Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (showCorrect) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'CORRECT',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
