import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../shared/theme/app_theme.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final FocusNode _mainButtonFocus = FocusNode(debugLabel: 'OnboardingMainButton');
  final FocusNode _skipButtonFocus = FocusNode(debugLabel: 'OnboardingSkipButton');
  final FocusNode _tvModeFocus = FocusNode(debugLabel: 'OnboardingTvModeButton');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mainButtonFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _mainButtonFocus.dispose();
    _skipButtonFocus.dispose();
    _tvModeFocus.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding({String destination = '/hub'}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboardingCompleted', true);
    if (mounted) {
      context.go(destination);
    }
  }

  void _nextPage() {
    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _completeOnboarding(destination: '/hub');
    }
  }

  void _prevPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTvScreen = size.width > 800 && size.width > size.height;

    return FocusScope(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowRight) {
            _nextPage();
            return KeyEventResult.handled;
          } else if (key == LogicalKeyboardKey.arrowLeft) {
            _prevPage();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (index) => setState(() => _currentPage = index),
                  children: [
                    _buildFirstPage(isTvScreen),
                    _buildPage(
                      title: 'Host Controls',
                      description: 'Start, pause, and manage genre queues in real time from any phone or browser.',
                      icon: Icons.dashboard,
                      color: AppTheme.neonPurple,
                      isTvScreen: isTvScreen,
                    ),
                    _buildPage(
                      title: 'Join as a Player',
                      description: 'Players scan the on-screen QR code to play with no app install required.',
                      icon: Icons.phone_iphone,
                      color: AppTheme.neonPink,
                      isTvScreen: isTvScreen,
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  3,
                  (index) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _currentPage == index ? 12 : 8,
                    height: _currentPage == index ? 12 : 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _currentPage == index ? AppTheme.neonCyan : Colors.white30,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    children: [
                      // Main Remote-Focusable Advance Button
                      Focus(
                        focusNode: _mainButtonFocus,
                        autofocus: true,
                        onKeyEvent: (node, event) {
                          if (event is KeyDownEvent) {
                            final key = event.logicalKey;
                            if (key == LogicalKeyboardKey.select ||
                                key == LogicalKeyboardKey.enter ||
                                key == LogicalKeyboardKey.numpadEnter ||
                                key == LogicalKeyboardKey.space ||
                                key == LogicalKeyboardKey.gameButtonA) {
                              _nextPage();
                              return KeyEventResult.handled;
                            }
                          }
                          return KeyEventResult.ignored;
                        },
                        child: Builder(
                          builder: (context) {
                            final isFocused = Focus.of(context).hasFocus;
                            return SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isFocused ? Colors.white : AppTheme.neonCyan,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  elevation: isFocused ? 12 : 4,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    side: BorderSide(
                                      color: isFocused ? AppTheme.neonYellow : Colors.transparent,
                                      width: isFocused ? 3 : 0,
                                    ),
                                  ),
                                ),
                                onPressed: _nextPage,
                                child: Text(
                                  _currentPage == 2 ? 'Get Started' : 'Next (or Press Enter)',
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Focus(
                            focusNode: _skipButtonFocus,
                            onKeyEvent: (node, event) {
                              if (event is KeyDownEvent) {
                                final key = event.logicalKey;
                                if (key == LogicalKeyboardKey.select ||
                                    key == LogicalKeyboardKey.enter ||
                                    key == LogicalKeyboardKey.space) {
                                  _completeOnboarding(destination: '/hub');
                                  return KeyEventResult.handled;
                                }
                              }
                              return KeyEventResult.ignored;
                            },
                            child: Builder(
                              builder: (context) {
                                final isFocused = Focus.of(context).hasFocus;
                                return TextButton(
                                  style: TextButton.styleFrom(
                                    foregroundColor: isFocused ? AppTheme.neonYellow : Colors.white70,
                                  ),
                                  onPressed: () => _completeOnboarding(destination: '/hub'),
                                  child: Text(
                                    'Skip Intro',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: isFocused ? FontWeight.bold : FontWeight.normal,
                                      decoration: isFocused ? TextDecoration.underline : TextDecoration.none,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 20),
                          Focus(
                            focusNode: _tvModeFocus,
                            onKeyEvent: (node, event) {
                              if (event is KeyDownEvent) {
                                final key = event.logicalKey;
                                if (key == LogicalKeyboardKey.select ||
                                    key == LogicalKeyboardKey.enter ||
                                    key == LogicalKeyboardKey.space) {
                                  _completeOnboarding(destination: '/tv?room=TRIV');
                                  return KeyEventResult.handled;
                                }
                              }
                              return KeyEventResult.ignored;
                            },
                            child: Builder(
                              builder: (context) {
                                final isFocused = Focus.of(context).hasFocus;
                                return TextButton.icon(
                                  style: TextButton.styleFrom(
                                    foregroundColor: isFocused ? AppTheme.neonCyan : Colors.white60,
                                  ),
                                  onPressed: () => _completeOnboarding(destination: '/tv?room=TRIV'),
                                  icon: const Icon(Icons.tv, size: 18),
                                  label: Text(
                                    'Quick TV Display',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: isFocused ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFirstPage(bool isTvScreen) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.neonCyan.withValues(alpha: 0.25), Colors.black],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.neonCyan.withValues(alpha: 0.25),
                      blurRadius: 24,
                      spreadRadius: 3,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset(
                    'assets/images/app_logo.png',
                    width: isTvScreen ? 120 : 110,
                    height: isTvScreen ? 120 : 110,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.local_bar,
                      size: 80,
                      color: AppTheme.neonCyan,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'BAR ROOMS TRIVIA',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.5,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 32.0),
                child: Text(
                  'Live Interactive Trivia for Bars, Venues & Players.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPage({
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required bool isTvScreen,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.25), Colors.black],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: isTvScreen ? 88 : 80, color: color),
              const SizedBox(height: 20),
              Text(
                title,
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Text(
                  description,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
