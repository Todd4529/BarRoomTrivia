import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../shared/theme/app_theme.dart';
import '../shared/services/supabase_service.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({Key? key}) : super(key: key);

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();
  final FocusNode _submitFocusNode = FocusNode();
  final FocusNode _googleFocusNode = FocusNode();
  final FocusNode _appleFocusNode = FocusNode();

  bool _isSignUpMode = false;
  bool _loading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _setupFocusListeners();
  }

  void _setupFocusListeners() {
    for (final node in [_emailFocusNode, _passwordFocusNode, _submitFocusNode, _googleFocusNode, _appleFocusNode]) {
      node.addListener(() {
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

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _scrollController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _submitFocusNode.dispose();
    _googleFocusNode.dispose();
    _appleFocusNode.dispose();
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
                    color: AppTheme.neonCyan.withOpacity(0.12),
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
                    color: AppTheme.neonPurple.withOpacity(0.15),
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
                            border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.neonCyan.withOpacity(0.2),
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

                      // Glassmorphic Auth Form Card
                      Container(
                        padding: const EdgeInsets.all(18.0),
                        decoration: BoxDecoration(
                          color: AppTheme.cardSurface.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.08)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.4),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Email Field
                            TextField(
                              controller: _emailCtrl,
                              focusNode: _emailFocusNode,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              onEditingComplete: () {
                                FocusScope.of(context).requestFocus(_passwordFocusNode);
                              },
                              onSubmitted: (_) {
                                FocusScope.of(context).requestFocus(_passwordFocusNode);
                              },
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'Email Address',
                                labelStyle: const TextStyle(color: Colors.white60, fontSize: 13),
                                prefixIcon: const Icon(Icons.email_outlined, color: AppTheme.neonCyan, size: 20),
                                filled: true,
                                fillColor: const Color(0xFF0F172A),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: AppTheme.neonCyan, width: 2.0),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),

                            // Password Field
                            TextField(
                              controller: _passwordCtrl,
                              focusNode: _passwordFocusNode,
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.done,
                              onEditingComplete: _handlePrimarySubmit,
                              onSubmitted: (_) => _handlePrimarySubmit(),
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'Password',
                                labelStyle: const TextStyle(color: Colors.white60, fontSize: 13),
                                prefixIcon: const Icon(Icons.lock_outlined, color: AppTheme.neonCyan, size: 20),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                    color: Colors.white54,
                                    size: 20,
                                  ),
                                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
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
                                  borderSide: const BorderSide(color: AppTheme.neonCyan, width: 2.0),
                                ),
                              ),
                            ),

                            // Forgot Password Link (Only in Sign In mode)
                            if (!_isSignUpMode) ...[
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () async {
                                    final email = _emailCtrl.text.trim();
                                    if (email.isNotEmpty) {
                                      await SupabaseService().sendPasswordReset(email);
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Password reset email sent')),
                                        );
                                      }
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Please enter your email address first')),
                                      );
                                    }
                                  },
                                  child: const Text(
                                    'Forgot password?',
                                    style: TextStyle(color: AppTheme.neonCyan, fontSize: 12),
                                  ),
                                ),
                              ),
                            ] else
                              const SizedBox(height: 10),

                            // Submit Button
                            ElevatedButton(
                              focusNode: _submitFocusNode,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.neonCyan,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                elevation: 4,
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
                            const SizedBox(height: 10),

                            // Divider
                            Row(
                              children: [
                                Expanded(child: Divider(color: Colors.white.withOpacity(0.12))),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 10.0),
                                  child: Text('OR', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                                Expanded(child: Divider(color: Colors.white.withOpacity(0.12))),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // Google Sign-In Button
                            ElevatedButton.icon(
                              focusNode: _googleFocusNode,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                                child: const Icon(Icons.g_mobiledata, color: Color(0xFF4285F4), size: 22),
                              ),
                              label: const Text('Sign in with Google', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                              onPressed: _loading ? null : _signInWithGoogle,
                            ),
                            const SizedBox(height: 8),

                            // Apple Sign-In Button
                            ElevatedButton.icon(
                              focusNode: _appleFocusNode,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: BorderSide(color: Colors.white.withOpacity(0.2)),
                                ),
                              ),
                              icon: const Icon(Icons.apple, color: Colors.white, size: 20),
                              label: const Text('Sign in with Apple', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                              onPressed: _loading ? null : _signInWithApple,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Toggle between Sign In and Sign Up
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _isSignUpMode ? 'Already have an account? ' : "Don't have an account? ",
                            style: const TextStyle(color: Colors.white60, fontSize: 13),
                          ),
                          InkWell(
                            onTap: () => setState(() => _isSignUpMode = !_isSignUpMode),
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
                              child: Text(
                                _isSignUpMode ? 'Sign In' : 'Sign Up',
                                style: const TextStyle(
                                  color: AppTheme.neonCyan,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ],
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
