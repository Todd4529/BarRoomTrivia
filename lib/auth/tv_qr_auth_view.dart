import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../shared/config/supabase_config.dart';
import '../shared/theme/app_theme.dart';

/// Pure Android TV & Big-Screen QR Code Authentication Screen
/// Displays a high-contrast QR code and listens for mobile host sign-in.
/// Once the host signs in on mobile, the TV automatically advances to the
/// "Waiting for Host to Start a Game" stage.
class TvQrAuthView extends StatefulWidget {
  const TvQrAuthView({super.key});

  @override
  State<TvQrAuthView> createState() => _TvQrAuthViewState();
}

class _TvQrAuthViewState extends State<TvQrAuthView> with SingleTickerProviderStateMixin {
  late String _deviceToken;
  late String _userCode;
  late String _qrAuthUrl;

  RealtimeChannel? _authChannel;
  Timer? _countdownTimer;
  int _remainingSeconds = 300; // 5-minute TTL
  bool _isAuthorized = false;
  String _authorizedUserName = '';
  bool _isRefreshing = false;

  final FocusNode _refreshFocusNode = FocusNode(debugLabel: 'RefreshFocusNode');

  late AnimationController _animController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );

    _generateNewPairingSession();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _authChannel?.unsubscribe();
    _countdownTimer?.cancel();
    _animController.dispose();
    _refreshFocusNode.dispose();
    super.dispose();
  }

  void _generateNewPairingSession() {
    final random = Random();
    final randomDigits = 1000 + random.nextInt(9000);
    _userCode = 'TRIV-$randomDigits';
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomHex = random.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    _deviceToken = 'tv_${timestamp}_$randomHex';

    // Universal pairing URL (opens mobile auth view with token & code)
    _qrAuthUrl = 'https://todd4529.github.io/BarRoomTrivia/?view=auth&device_token=$_deviceToken&user_code=$_userCode';

    _remainingSeconds = 300;
    _subscribeToPairingChannel();
    _startCountdown();
  }

  void _subscribeToPairingChannel() {
    _authChannel?.unsubscribe();

    try {
      final channelName = 'device_auth_$_deviceToken';
      _authChannel = SupabaseConfig.client.channel(channelName);

      _authChannel!
          .onBroadcast(
            event: 'device_authorized',
            callback: (payload) {
              _handleDeviceAuthorized(payload);
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('Error subscribing to TV auth channel: $e');
    }
  }

  void _handleDeviceAuthorized(Map<String, dynamic> payload) async {
    if (_isAuthorized) return;

    setState(() {
      _isAuthorized = true;
      final userInfo = payload['user_info'] as Map<String, dynamic>?;
      _authorizedUserName = userInfo?['display_name'] ?? userInfo?['email'] ?? 'Host';
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboardingCompleted', true);
    await prefs.setString('tv_authorized_user', _authorizedUserName);
    await prefs.setString('tv_authorized_id', payload['user_id']?.toString() ?? '');

    // Brief delay to display connected state, then transition to Waiting for Host TV stage
    await Future.delayed(const Duration(milliseconds: 1400));
    if (mounted) {
      context.go('/tv?room=TRIV');
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_remainingSeconds > 0) {
        setState(() => _remainingSeconds--);
      } else {
        timer.cancel();
        _handleRefresh();
      }
    });
  }

  void _handleRefresh() {
    setState(() => _isRefreshing = true);
    _generateNewPairingSession();
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _isRefreshing = false);
    });
  }

  String _formatTimer(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isLandscape = size.width > size.height;

    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      body: SafeArea(
        child: _isAuthorized
            ? _buildAuthorizedCelebration()
            : (isLandscape ? _buildLandscapeTvLayout() : _buildPortraitLayout()),
      ),
    );
  }

  Widget _buildAuthorizedCelebration() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppTheme.neonGreen.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.neonGreen, width: 3),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.neonGreen.withValues(alpha: 0.4),
                  blurRadius: 32,
                  spreadRadius: 6,
                ),
              ],
            ),
            child: const Icon(Icons.check_circle, size: 96, color: AppTheme.neonGreen),
          ),
          const SizedBox(height: 32),
          const Text(
            'HOST SIGNED IN!',
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w900,
              letterSpacing: 3.0,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Welcome, $_authorizedUserName! Waiting for host to start a game...',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.neonCyan,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLandscapeTvLayout() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 56.0, vertical: 28.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left Column: Branding & Mobile Sign-In Steps
          Expanded(
            flex: 6,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.neonCyan.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.neonCyan, width: 2),
                        ),
                        child: const Icon(Icons.tv, color: AppTheme.neonCyan, size: 36),
                      ),
                      const SizedBox(width: 16),
                      const Text(
                        'BAR ROOMS TRIVIA',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.5,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Host Sign-In Required',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '1. Open your phone camera or QR scanner\n'
                    '2. Point your camera at the QR code on the right\n'
                    '3. Sign in or Sign up on your phone\n'
                    '4. This TV will automatically connect and wait for you to start the game!',
                    style: TextStyle(
                      fontSize: 18,
                      height: 1.7,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 32),
                  // D-Pad Remote Refresh Button
                  Focus(
                    focusNode: _refreshFocusNode,
                    autofocus: true,
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent) {
                        final key = event.logicalKey;
                        if (key == LogicalKeyboardKey.select ||
                            key == LogicalKeyboardKey.enter ||
                            key == LogicalKeyboardKey.space ||
                            key == LogicalKeyboardKey.gameButtonA) {
                          _handleRefresh();
                          return KeyEventResult.handled;
                        }
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Builder(
                      builder: (context) {
                        final isFocused = Focus.of(context).hasFocus;
                        return OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: isFocused ? AppTheme.neonPurple.withValues(alpha: 0.3) : Colors.transparent,
                            foregroundColor: isFocused ? Colors.white : AppTheme.neonPurple,
                            side: BorderSide(
                              color: isFocused ? AppTheme.neonYellow : AppTheme.neonPurple,
                              width: isFocused ? 2.5 : 1.5,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _handleRefresh,
                          icon: const Icon(Icons.refresh, size: 20),
                          label: Text(
                            _isRefreshing ? 'REFRESHING...' : 'REFRESH QR CODE',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                              color: isFocused ? Colors.white : AppTheme.neonPurple,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Icon(Icons.fiber_manual_record, size: 14, color: AppTheme.neonGreen),
                      const SizedBox(width: 8),
                      const Text(
                        'Waiting for host phone sign-in  •  Expires in: ',
                        style: TextStyle(fontSize: 14, color: Colors.white54),
                      ),
                      Text(
                        _formatTimer(_remainingSeconds),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.neonYellow,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 48),
          // Right Column: Big High-Contrast QR Code & Manual Pairing Code
          Expanded(
            flex: 4,
            child: Center(
              child: ScaleTransition(
                scale: _pulseAnimation,
                child: Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: AppTheme.cardSurface,
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: AppTheme.neonCyan.withValues(alpha: 0.5), width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.neonCyan.withValues(alpha: 0.25),
                        blurRadius: 32,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'SCAN WITH PHONE',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.0,
                          color: AppTheme.neonCyan,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: QrImageView(
                          data: _qrAuthUrl,
                          version: QrVersions.auto,
                          size: 220,
                          backgroundColor: Colors.white,
                          eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
                          dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'DISPLAY PAIRING CODE:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          color: Colors.white54,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        _userCode,
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 3.5,
                          color: AppTheme.neonYellow,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPortraitLayout() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'BAR ROOMS TRIVIA',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 2.0, color: Colors.white),
            ),
            const SizedBox(height: 8),
            const Text(
              'Scan to Sign In as Host',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.neonCyan),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: QrImageView(
                data: _qrAuthUrl,
                version: QrVersions.auto,
                size: 220,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _userCode,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppTheme.neonYellow, letterSpacing: 3),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              focusNode: _refreshFocusNode,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.neonPurple,
                side: const BorderSide(color: AppTheme.neonPurple),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onPressed: _handleRefresh,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('REFRESH QR CODE'),
            ),
          ],
        ),
      ),
    );
  }
}
