import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'shared/config/supabase_config.dart';
import 'shared/theme/app_theme.dart';
import 'tv/views/tv_display_view.dart';
import 'player/views/player_controller_view.dart';
import 'host/views/host_dashboard_view.dart';
import 'onboarding/onboarding_page.dart';
import 'auth/auth_page.dart';
import 'auth/reset_password_page.dart';
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
      builder: (context, state) => const InitialRouteDecider(),
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
        return TvDisplayView(roomCode: roomCode);
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
      }
    });
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
class MainNavigationHub extends StatelessWidget {
  const MainNavigationHub({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
              const SizedBox(height: 8),
              const Text(
                'Cross-Platform',
                style: TextStyle(color: Colors.white54, fontSize: 18),
              ),
              const SizedBox(height: 48),
              Wrap(
                spacing: 24,
                runSpacing: 24,
                alignment: WrapAlignment.center,
                children: [
                  _buildTargetCard(
                    context,
                    title: 'BAR TV DISPLAY',
                    icon: Icons.tv,
                    color: AppTheme.neonCyan,
                    onTap: () => context.go('/tv?room=TRIV'),
                  ),
                  _buildTargetCard(
                    context,
                    title: 'HOST CONTROL PANEL',
                    icon: Icons.dashboard,
                    color: AppTheme.neonPurple,
                    onTap: () => context.go('/host'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTargetCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 280,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: AppTheme.cardSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.4), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 16,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
