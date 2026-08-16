import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../shared/theme/app_theme.dart';
import '../shared/services/supabase_service.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  late final FocusNode _emailFocusNode;
  late final FocusNode _passwordFocusNode;
  late final FocusNode _forgotPasswordFocusNode;
  late final FocusNode _submitFocusNode;
  late final FocusNode _googleFocusNode;
  late final FocusNode _appleFocusNode;
  late final FocusNode _toggleAuthModeFocusNode;

  bool _isSignUpMode = false;
  bool _loading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();

    _emailFocusNode = FocusNode(
      debugLabel: 'EmailFocusNode',
      onKeyEvent: _handleEmailKey,
    );
    _passwordFocusNode = FocusNode(
      debugLabel: 'PasswordFocusNode',
      onKeyEvent: _handlePasswordKey,
    );
    _forgotPasswordFocusNode = FocusNode(
      debugLabel: 'ForgotPasswordFocusNode',
      onKeyEvent: _handleForgotPasswordKey,
    );
    _submitFocusNode = FocusNode(
      debugLabel: 'SubmitFocusNode',
      onKeyEvent: _handleSubmitKey,
    );
    _googleFocusNode = FocusNode(
      debugLabel: 'GoogleFocusNode',
      onKeyEvent: _handleGoogleKey,
    );
    _appleFocusNode = FocusNode(
      debugLabel: 'AppleFocusNode',
      onKeyEvent: _handleAppleKey,
    );
    _toggleAuthModeFocusNode = FocusNode(
      debugLabel: 'ToggleAuthModeFocusNode',
      onKeyEvent: _handleToggleAuthKey,
    );

    _setupFocusListeners();
  }

  void _setupFocusListeners() {
    final allNodes = [
      _emailFocusNode,
      _passwordFocusNode,
      _forgotPasswordFocusNode,
      _submitFocusNode,
      _googleFocusNode,
      _appleFocusNode,
      _toggleAuthModeFocusNode,
    ];

    for (final node in allNodes) {
      node.addListener(() {
        if (mounted) setState(() {});
        if (node.hasFocus && node.context != null) {
          Scrollable.ensureVisible(
            node.context!,
            alignment: 0.5,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
          );
        }
      });
    }
  }

  bool _isDownAction(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final key = event.logicalKey;
    return key == LogicalKeyboardKey.arrowDown ||
        (key == LogicalKeyboardKey.tab && !isShift) ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;
  }

  bool _isUpAction(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final key = event.logicalKey;
    return key == LogicalKeyboardKey.arrowUp || (key == LogicalKeyboardKey.tab && isShift);
  }

  bool _isActivateAction(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final key = event.logicalKey;
    return key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.gameButtonSelect;
  }

  KeyEventResult _handleEmailKey(FocusNode node, KeyEvent event) {
    if (_isDownAction(event)) {
      _passwordFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handlePasswordKey(FocusNode node, KeyEvent event) {
    if (_isUpAction(event)) {
      _emailFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (_isDownAction(event)) {
      if (!_isSignUpMode) {
        _forgotPasswordFocusNode.requestFocus();
      } else {
        _submitFocusNode.requestFocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleForgotPasswordKey(FocusNode node, KeyEvent event) {
    if (_isUpAction(event)) {
      _passwordFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (_isDownAction(event)) {
      _submitFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (_isActivateAction(event)) {
      _handleForgotPassword();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleSubmitKey(FocusNode node, KeyEvent event) {
    if (_isUpAction(event)) {
      if (!_isSignUpMode) {
        _forgotPasswordFocusNode.requestFocus();
      } else {
        _passwordFocusNode.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (_isDownAction(event)) {
      _googleFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (_isActivateAction(event)) {
      if (!_loading) _handlePrimarySubmit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleGoogleKey(FocusNode node, KeyEvent event) {
    if (_isUpAction(event)) {
      _submitFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (_isDownAction(event)) {
      _appleFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (_isActivateAction(event)) {
      if (!_loading) _signInWithGoogle();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleAppleKey(FocusNode node, KeyEvent event) {
    if (_isUpAction(event)) {
      _googleFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (_isDownAction(event)) {
      _toggleAuthModeFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (_isActivateAction(event)) {
      if (!_loading) _signInWithApple();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleToggleAuthKey(FocusNode node, KeyEvent event) {
    if (_isUpAction(event)) {
      _appleFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (_isActivateAction(event)) {
      setState(() => _isSignUpMode = !_isSignUpMode);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _scrollController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _forgotPasswordFocusNode.dispose();
    _submitFocusNode.dispose();
    _googleFocusNode.dispose();
    _appleFocusNode.dispose();
    _toggleAuthModeFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handlePrimarySubmit() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in both email and password')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      if (_isSignUpMode) {
        await SupabaseService().signUpWithEmail(email, password);
      } else {
        await SupabaseService().signInWithEmail(email, password);
      }
      _navigateToHome();
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Authentication error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleForgotPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isNotEmpty) {
      try {
        await SupabaseService().sendPasswordReset(email);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Password reset email sent')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${e.toString()}')),
          );
        }
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your email address first')),
      );
      _emailFocusNode.requestFocus();
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _loading = true);
    try {
      await SupabaseService().signInWithGoogle();
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Google Sign-In: ${e.message}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Google Sign-In failed: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithApple() async {
    setState(() => _loading = true);
    try {
      await SupabaseService().signInWithApple();
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Apple Sign-In: ${e.message}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Apple Sign-In failed: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _navigateToHome() {
    if (mounted) {
      context.go('/hub');
    }
  }

  Widget _buildQuickJumpChip(String label, IconData icon, VoidCallback onTap, bool isCurrent) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isCurrent ? AppTheme.neonCyan.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isCurrent ? AppTheme.neonCyan : Colors.white.withValues(alpha: 0.15),
              width: isCurrent ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: isCurrent ? AppTheme.neonCyan : Colors.white70),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                  color: isCurrent ? AppTheme.neonCyan : Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isLandscape = mediaQuery.size.width > mediaQuery.size.height;

    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      body: Stack(
        children: [
          // Background Glow Accents
          Positioned(
            top: -60,
            left: -60,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.neonCyan.withValues(alpha: 0.12),
                    blurRadius: 100,
                    spreadRadius: 40,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: -60,
            right: -60,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.neonPurple.withValues(alpha: 0.15),
                    blurRadius: 100,
                    spreadRadius: 40,
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: isLandscape ? 560 : 420),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Header Row (Compact on TV / Landscape)
                      if (isLandscape)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.asset(
                                'assets/images/app_logo.png',
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => Container(
                                  width: 44,
                                  height: 44,
                                  color: AppTheme.cardSurface,
                                  child: const Icon(Icons.local_bar, size: 24, color: AppTheme.neonCyan),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'BAR ROOMS TRIVIA',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.8,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        )
                      else ...[
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.neonCyan.withValues(alpha: 0.2),
                                blurRadius: 16,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.asset(
                              'assets/images/app_logo.png',
                              width: 60,
                              height: 60,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Container(
                                width: 60,
                                height: 60,
                                color: AppTheme.cardSurface,
                                child: const Icon(Icons.local_bar, size: 36, color: AppTheme.neonCyan),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'BAR ROOMS TRIVIA',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2.0,
                            color: Colors.white,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        _isSignUpMode ? 'Create your account to start hosting' : 'Sign in to access your host dashboard',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12, color: Colors.white60),
                      ),
                      const SizedBox(height: 12),

                      // Glassmorphic Auth Form Card with Ordered Focus Traversal
                      FocusTraversalGroup(
                        policy: OrderedTraversalPolicy(),
                        child: Container(
                          padding: const EdgeInsets.all(18.0),
                          decoration: BoxDecoration(
                            color: AppTheme.cardSurface.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                blurRadius: 16,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Email Field
                              FocusTraversalOrder(
                                order: const NumericFocusOrder(1.0),
                                child: TextField(
                                  controller: _emailCtrl,
                                  focusNode: _emailFocusNode,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  onEditingComplete: () {
                                    _passwordFocusNode.requestFocus();
                                  },
                                  onSubmitted: (_) {
                                    _passwordFocusNode.requestFocus();
                                  },
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    labelText: 'Email Address',
                                    labelStyle: const TextStyle(color: Colors.white60, fontSize: 13),
                                    prefixIcon: const Icon(Icons.email_outlined, color: AppTheme.neonCyan, size: 20),
                                    suffixIcon: Container(
                                      margin: const EdgeInsets.only(right: 6),
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(8),
                                          onTap: () {
                                            _passwordFocusNode.requestFocus();
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: AppTheme.neonCyan.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: AppTheme.neonCyan.withValues(alpha: 0.4), width: 1),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  'Next',
                                                  style: TextStyle(color: AppTheme.neonCyan, fontSize: 12, fontWeight: FontWeight.bold),
                                                ),
                                                SizedBox(width: 3),
                                                Icon(Icons.arrow_downward, color: AppTheme.neonCyan, size: 14),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    filled: true,
                                    fillColor: const Color(0xFF0F172A),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide.none,
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(color: AppTheme.neonCyan, width: 2.5),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),

                              // Password Field
                              FocusTraversalOrder(
                                order: const NumericFocusOrder(2.0),
                                child: TextField(
                                  controller: _passwordCtrl,
                                  focusNode: _passwordFocusNode,
                                  obscureText: _obscurePassword,
                                  textInputAction: TextInputAction.next,
                                  onEditingComplete: () {
                                    if (!_isSignUpMode) {
                                      _forgotPasswordFocusNode.requestFocus();
                                    } else {
                                      _submitFocusNode.requestFocus();
                                    }
                                  },
                                  onSubmitted: (_) {
                                    if (!_isSignUpMode) {
                                      _forgotPasswordFocusNode.requestFocus();
                                    } else {
                                      _submitFocusNode.requestFocus();
                                    }
                                  },
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    labelText: 'Password',
                                    labelStyle: const TextStyle(color: Colors.white60, fontSize: 13),
                                    prefixIcon: const Icon(Icons.lock_outlined, color: AppTheme.neonCyan, size: 20),
                                    suffixIcon: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: Icon(
                                            _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                            color: Colors.white54,
                                            size: 20,
                                          ),
                                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                          tooltip: _obscurePassword ? 'Show Password' : 'Hide Password',
                                        ),
                                        Container(
                                          margin: const EdgeInsets.only(right: 6),
                                          child: Material(
                                            color: Colors.transparent,
                                            child: InkWell(
                                              borderRadius: BorderRadius.circular(8),
                                              onTap: () {
                                                if (!_isSignUpMode) {
                                                  _forgotPasswordFocusNode.requestFocus();
                                                } else {
                                                  _submitFocusNode.requestFocus();
                                                }
                                              },
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.neonCyan.withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(color: AppTheme.neonCyan.withValues(alpha: 0.4), width: 1),
                                                ),
                                                child: const Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      'Next',
                                                      style: TextStyle(color: AppTheme.neonCyan, fontSize: 12, fontWeight: FontWeight.bold),
                                                    ),
                                                    SizedBox(width: 3),
                                                    Icon(Icons.arrow_downward, color: AppTheme.neonCyan, size: 14),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    filled: true,
                                    fillColor: const Color(0xFF0F172A),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide.none,
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(color: AppTheme.neonCyan, width: 2.5),
                                    ),
                                  ),
                                ),
                              ),

                              // Forgot Password Link (Only in Sign In mode)
                              if (!_isSignUpMode) ...[
                                const SizedBox(height: 4),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: FocusTraversalOrder(
                                    order: const NumericFocusOrder(3.0),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        border: _forgotPasswordFocusNode.hasFocus
                                            ? Border.all(color: AppTheme.neonCyan, width: 2.0)
                                            : null,
                                        color: _forgotPasswordFocusNode.hasFocus
                                            ? AppTheme.neonCyan.withValues(alpha: 0.18)
                                            : null,
                                      ),
                                      child: TextButton(
                                        focusNode: _forgotPasswordFocusNode,
                                        onPressed: _handleForgotPassword,
                                        child: const Text(
                                          'Forgot password?',
                                          style: TextStyle(
                                            color: AppTheme.neonCyan,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ] else
                                const SizedBox(height: 10),

                              // Submit Button
                              FocusTraversalOrder(
                                order: const NumericFocusOrder(4.0),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: _submitFocusNode.hasFocus
                                        ? [
                                            BoxShadow(
                                              color: AppTheme.neonCyan.withValues(alpha: 0.6),
                                              blurRadius: 16,
                                              spreadRadius: 2,
                                            )
                                          ]
                                        : [],
                                  ),
                                  child: ElevatedButton(
                                    focusNode: _submitFocusNode,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.neonCyan,
                                      foregroundColor: Colors.black,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        side: _submitFocusNode.hasFocus
                                            ? const BorderSide(color: Colors.white, width: 2.5)
                                            : BorderSide.none,
                                      ),
                                      elevation: _submitFocusNode.hasFocus ? 8 : 4,
                                    ),
                                    onPressed: _loading ? null : _handlePrimarySubmit,
                                    child: _loading
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black),
                                          )
                                        : Text(
                                            _isSignUpMode ? 'Create Account' : 'Sign In',
                                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                          ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),

                              // Divider
                              Row(
                                children: [
                                  Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.12))),
                                  const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 10.0),
                                    child: Text(
                                      'OR',
                                      style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.12))),
                                ],
                              ),
                              const SizedBox(height: 10),

                              // Google Sign-In Button
                              FocusTraversalOrder(
                                order: const NumericFocusOrder(5.0),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: _googleFocusNode.hasFocus
                                        ? [
                                            BoxShadow(
                                              color: const Color(0xFF4285F4).withValues(alpha: 0.7),
                                              blurRadius: 16,
                                              spreadRadius: 2,
                                            )
                                          ]
                                        : [],
                                  ),
                                  child: ElevatedButton.icon(
                                    focusNode: _googleFocusNode,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: Colors.black,
                                      padding: const EdgeInsets.symmetric(vertical: 11),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        side: _googleFocusNode.hasFocus
                                            ? const BorderSide(color: AppTheme.neonCyan, width: 2.5)
                                            : BorderSide.none,
                                      ),
                                      elevation: _googleFocusNode.hasFocus ? 8 : 2,
                                    ),
                                    icon: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                                      child: const Icon(Icons.g_mobiledata, color: Color(0xFF4285F4), size: 22),
                                    ),
                                    label: const Text('Sign in with Google', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                    onPressed: _loading ? null : _signInWithGoogle,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),

                              // Apple Sign-In Button
                              FocusTraversalOrder(
                                order: const NumericFocusOrder(6.0),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: _appleFocusNode.hasFocus
                                        ? [
                                            BoxShadow(
                                              color: Colors.white.withValues(alpha: 0.5),
                                              blurRadius: 16,
                                              spreadRadius: 2,
                                            )
                                          ]
                                        : [],
                                  ),
                                  child: ElevatedButton.icon(
                                    focusNode: _appleFocusNode,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.black,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 11),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        side: BorderSide(
                                          color: _appleFocusNode.hasFocus ? AppTheme.neonCyan : Colors.white.withValues(alpha: 0.2),
                                          width: _appleFocusNode.hasFocus ? 2.5 : 1.0,
                                        ),
                                      ),
                                      elevation: _appleFocusNode.hasFocus ? 8 : 2,
                                    ),
                                    icon: const Icon(Icons.apple, color: Colors.white, size: 20),
                                    label: const Text('Sign in with Apple', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                    onPressed: _loading ? null : _signInWithApple,
                                  ),
                                ),
                              ),

                              // Quick TV Navigation Jump Bar
                              const SizedBox(height: 12),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  _buildQuickJumpChip(
                                    'Email',
                                    Icons.email,
                                    () => _emailFocusNode.requestFocus(),
                                    _emailFocusNode.hasFocus,
                                  ),
                                  _buildQuickJumpChip(
                                    'Password',
                                    Icons.lock,
                                    () => _passwordFocusNode.requestFocus(),
                                    _passwordFocusNode.hasFocus,
                                  ),
                                  _buildQuickJumpChip(
                                    'Sign In',
                                    Icons.login,
                                    () => _submitFocusNode.requestFocus(),
                                    _submitFocusNode.hasFocus,
                                  ),
                                  _buildQuickJumpChip(
                                    'Google',
                                    Icons.g_mobiledata,
                                    () => _googleFocusNode.requestFocus(),
                                    _googleFocusNode.hasFocus,
                                  ),
                                  _buildQuickJumpChip(
                                    'Apple',
                                    Icons.apple,
                                    () => _appleFocusNode.requestFocus(),
                                    _appleFocusNode.hasFocus,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Toggle between Sign In and Sign Up
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(7.0),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: _toggleAuthModeFocusNode.hasFocus
                                ? Border.all(color: AppTheme.neonCyan, width: 2.0)
                                : null,
                            color: _toggleAuthModeFocusNode.hasFocus
                                ? AppTheme.neonCyan.withValues(alpha: 0.18)
                                : null,
                          ),
                          child: InkWell(
                            focusNode: _toggleAuthModeFocusNode,
                            onTap: () => setState(() => _isSignUpMode = !_isSignUpMode),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _isSignUpMode ? 'Already have an account? ' : "Don't have an account? ",
                                    style: const TextStyle(color: Colors.white60, fontSize: 13),
                                  ),
                                  Text(
                                    _isSignUpMode ? 'Sign In' : 'Sign Up',
                                    style: const TextStyle(
                                      color: AppTheme.neonCyan,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
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
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
