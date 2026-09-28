import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_update/in_app_update.dart';
import 'shared/config/supabase_config.dart';
import 'shared/theme/app_theme.dart';
import 'tv/views/tv_display_view.dart';
import 'player/views/player_controller_view.dart';
import 'host/views/host_dashboard_view.dart';
import 'onboarding/onboarding_page.dart';
import 'auth/auth_page.dart';
import 'auth/reset_password_page.dart';
import 'auth/tv_auth_verify_view.dart';
import 'auth/tv_qr_auth_view.dart';
import 'shared/services/realtime_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase Flutter SDK
  await SupabaseConfig.initialize();

  runApp(const BarRoomTriviaApp());
}

final GoRouter _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) {
        final view = state.uri.queryParameters['view'];
        final room = state.uri.queryParameters['room'] ??
            state.uri.queryParameters['room_id'];
        if (view == 'player' || (view == null && room != null && state.uri.queryParameters['view'] != 'tv')) {
          return PlayerControllerView(initialRoomCode: room);
        }
        return const InitialRouteDecider();
      },
    ),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingPage(),
    ),
    GoRoute(
      path: '/auth',
      builder: (context, state) => const AuthPage(),
    ),
    GoRoute(
      path: '/hub',
      builder: (context, state) => const MainNavigationHub(),
    ),
    GoRoute(
      path: '/tv',
      builder: (context, state) {
        final roomCode = state.uri.queryParameters['room'] ??
            state.uri.queryParameters['room_id'] ??
            'TRIV';
        final autoStart = state.uri.queryParameters['auto_start'] == 'true';
        return TvDisplayView(roomCode: roomCode, autoStart: autoStart);
      },
    ),
    GoRoute(
      path: '/tv-qr-auth',
      builder: (context, state) => const TvQrAuthView(),
    ),
    GoRoute(
      path: '/tv-auth',
      builder: (context, state) {
        final deviceToken = state.uri.queryParameters['device_token'] ??
            state.uri.queryParameters['token'] ??
            state.uri.queryParameters['code'];
        final userCode = state.uri.queryParameters['user_code'];
        return TvAuthVerifyView(
          deviceToken: deviceToken,
          userCode: userCode,
        );
      },
    ),
    GoRoute(
      path: '/play',
      builder: (context, state) {
        final roomCode = state.uri.queryParameters['room'] ??
            state.uri.queryParameters['room_id'];
        return PlayerControllerView(initialRoomCode: roomCode);
      },
    ),
    GoRoute(
      path: '/host',
      builder: (context, state) => const HostDashboardView(),
    ),
    GoRoute(
      path: '/reset-password',
      builder: (context, state) => const ResetPasswordPage(),
    ),
  ],
);

class InitialRouteDecider extends StatelessWidget {
  const InitialRouteDecider({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isPortraitPhone = size.width < 600 && size.height > size.width;

    if (isPortraitPhone) {
      return FutureBuilder<SharedPreferences>(
        future: SharedPreferences.getInstance(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator()));
          }
          final prefs = snapshot.data!;
          final onboardingDone = prefs.getBool('onboardingCompleted') ?? false;
          final user = Supabase.instance.client.auth.currentUser;
          if (!onboardingDone) {
            return const OnboardingPage();
          } else if (user == null) {
            return const AuthPage();
          } else {
            return const MainNavigationHub();
          }
        },
      );
    }

    // For the initial screen on TV displays, always start on the phone QR pairing page.
    // This forces the admin to sign-in or create an account on their phone.
    return const TvQrAuthView();
  }
}

class BarRoomTriviaApp extends StatefulWidget {
  const BarRoomTriviaApp({super.key});

  @override
  State<BarRoomTriviaApp> createState() => _BarRoomTriviaAppState();
}

class _BarRoomTriviaAppState extends State<BarRoomTriviaApp> {
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        _router.go('/reset-password');
      } else if (data.event == AuthChangeEvent.signedIn) {
        final location = _router.routerDelegate.currentConfiguration.uri.path;
        if (location == '/auth' || location == '/onboarding') {
          _router.go('/hub');
        }
      }
    });
    _checkForUpdate();
  }

  void _checkForUpdate() async {
    if (defaultTargetPlatform == TargetPlatform.android && !kIsWeb) {
      try {
        final updateInfo = await InAppUpdate.checkForUpdate();
        if (updateInfo.updateAvailability == UpdateAvailability.updateAvailable) {
          if (updateInfo.flexibleUpdateAllowed) {
            await InAppUpdate.startFlexibleUpdate();
            await InAppUpdate.completeFlexibleUpdate();
          } else if (updateInfo.immediateUpdateAllowed) {
            await InAppUpdate.performImmediateUpdate();
          }
        }
      } catch (e) {
        debugPrint('In-App Update check skipped or failed: $e');
      }
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Bar Rooms Trivia',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.mouse,
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
          PointerDeviceKind.trackpad,
        },
      ),
      routerConfig: _router,
    );
  }
}

/// Navigation Landing Hub for Target Module Selection
class MainNavigationHub extends StatefulWidget {
  const MainNavigationHub({super.key});

  @override
  State<MainNavigationHub> createState() => _MainNavigationHubState();
}

class _MainNavigationHubState extends State<MainNavigationHub> {
  final RealtimeService _realtimeService = RealtimeService();
  String _targetRoomCode = 'TRIV';

  @override
  void initState() {
    super.initState();
    _loadRoomAndSubscribe();
  }

  Future<void> _loadRoomAndSubscribe() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('tv_room_code');
      if (saved != null && saved.isNotEmpty && mounted) {
        setState(() => _targetRoomCode = saved);
      }
    } catch (_) {}

    if (!mounted) return;
    _realtimeService.joinRoomChannel(
      roomCode: _targetRoomCode,
      onPreGameCountdownBroadcast: (payload) {
        final room = payload['room_code']?.toString() ?? _targetRoomCode;
        if (mounted) {
          context.go('/tv?room=$room&auto_start=true');
        }
      },
      onQuestionBroadcast: (payload) {
        final room = payload['room_code']?.toString() ?? _targetRoomCode;
        if (mounted) {
          context.go('/tv?room=$room&auto_start=true');
        }
      },
      onTimerExpiredBroadcast: (_) {},
    );
  }

  @override
  void dispose() {
    _realtimeService.leaveChannel();
    super.dispose();
  }

  void _handleBackPress() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppTheme.neonCyan.withValues(alpha: 0.3), width: 1.5),
        ),
        title: const Text(
          'Bar Rooms Trivia',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Return to the TV game display or exit the application?',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton.icon(
            autofocus: true,
            icon: const Icon(Icons.tv, size: 18),
            label: const Text('TV DISPLAY'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.neonCyan,
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              if (mounted) context.go('/tv?room=$_targetRoomCode');
            },
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              SystemNavigator.pop();
            },
            child: const Text('EXIT APP', style: TextStyle(color: Colors.redAccent)),
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
        _handleBackPress();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _handleBackPress,
          const SingleActivator(LogicalKeyboardKey.goBack): _handleBackPress,
        },
        child: Scaffold(
          backgroundColor: AppTheme.darkBackground,
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withOpacity(0.12), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.neonCyan.withOpacity(0.15),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.asset(
                        'assets/images/app_logo.png',
                        width: 140,
                        height: 140,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'BAR ROOMS TRIVIA',
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3.0,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 48),
                  Wrap(
                    spacing: 24,
                    runSpacing: 24,
                    alignment: WrapAlignment.center,
                    children: [
                      FocusableTargetCard(
                        title: 'BAR TV DISPLAY',
                        icon: Icons.tv,
                        color: AppTheme.neonCyan,
                        autofocus: true,
                        onTap: () => context.go('/tv?room=$_targetRoomCode'),
                      ),
                      FocusableTargetCard(
                        title: 'HOST CONTROL PANEL',
                        icon: Icons.dashboard,
                        color: AppTheme.neonPurple,
                        autofocus: false,
                        onTap: () => context.go('/host'),
                      ),
                      FocusableTargetCard(
                        title: 'PHONE QR PAIRING',
                        icon: Icons.qr_code_scanner_rounded,
                        color: AppTheme.neonYellow,
                        autofocus: false,
                        onTap: () => context.go('/tv-qr-auth'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FocusableTargetCard extends StatefulWidget {
  final String title;
  final IconData icon;
  final Color color;
  final bool autofocus;
  final VoidCallback onTap;

  const FocusableTargetCard({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    this.autofocus = false,
    required this.onTap,
  });

  @override
  State<FocusableTargetCard> createState() => _FocusableTargetCardState();
}

class _FocusableTargetCardState extends State<FocusableTargetCard> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (focused) {
        setState(() => _isFocused = focused);
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.numpadEnter ||
              key == LogicalKeyboardKey.space ||
              key == LogicalKeyboardKey.gameButtonA) {
            widget.onTap();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 280,
          height: 180,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: _isFocused
                ? widget.color.withValues(alpha: 0.12)
                : AppTheme.cardSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _isFocused
                  ? widget.color.withValues(alpha: 0.65)
                  : widget.color.withValues(alpha: 0.25),
              width: _isFocused ? 2.0 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: _isFocused
                    ? widget.color.withValues(alpha: 0.20)
                    : widget.color.withValues(alpha: 0.04),
                blurRadius: _isFocused ? 14 : 8,
                spreadRadius: _isFocused ? 1 : 0,
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.icon,
                size: 40,
                color: _isFocused ? Colors.white : widget.color,
              ),
              const SizedBox(height: 8),
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: _isFocused ? Colors.white : Colors.white.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(height: 8),
              Opacity(
                opacity: _isFocused ? 1.0 : 0.0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'PRESS ENTER / SELECT',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
