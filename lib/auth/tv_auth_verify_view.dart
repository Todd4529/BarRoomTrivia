import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../shared/config/supabase_config.dart';
import '../shared/services/supabase_service.dart';
import '../shared/theme/app_theme.dart';

/// Mobile Verification & Host Auth View
/// Scanned by the host's phone from the TV QR Code.
/// Allows the host to Sign In or Sign Up directly on their phone.
/// Once authenticated, it broadcasts the session to the TV over Supabase Realtime
/// and advances the phone router directly to the Host Controls.
class TvAuthVerifyView extends StatefulWidget {
  final String? deviceToken;
  final String? userCode;
  final String backendBaseUrl;

  const TvAuthVerifyView({
    super.key,
    required this.deviceToken,
    this.userCode,
    this.backendBaseUrl = 'https://api.barroomstrivia.com',
  });

  @override
  State<TvAuthVerifyView> createState() => _TvAuthVerifyViewState();
}

class _TvAuthVerifyViewState extends State<TvAuthVerifyView> with SingleTickerProviderStateMixin {
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();

  bool _isSignUpMode = false;
  bool _isLoading = false;
  bool _isSuccess = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  late AnimationController _animController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.elasticOut,
    );

    // If user is already authenticated on this phone, verify immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null && widget.deviceToken != null) {
        _verifyDeviceWithSupabase(widget.deviceToken!, user);
      }
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _verifyDeviceWithSupabase(String token, User user) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final session = Supabase.instance.client.auth.currentSession;
      final payload = {
        'device_token': token,
        'user_id': user.id,
        'user_info': {
          'email': user.email ?? 'Host User',
          'display_name': user.userMetadata?['display_name'] ?? user.email?.split('@').first ?? 'Host',
        },
        'auth_tokens': {
          'access_token': session?.accessToken ?? '',
        },
        'timestamp': DateTime.now().toIso8601String(),
      };

      // 1. Broadcast to Supabase Realtime channel for instant TV pickup
      final channelName = 'device_auth_$token';
      final channel = SupabaseConfig.client.channel(channelName);
      await channel.subscribe();
      await channel.sendBroadcastMessage(
        event: 'device_authorized',
        payload: payload,
      );

      // 2. Also broadcast to global room_TRIV channel as redundancy
      final roomChannel = SupabaseConfig.client.channel('room_TRIV');
      await roomChannel.subscribe();
      await roomChannel.sendBroadcastMessage(
        event: 'device_authorized',
        payload: payload,
      );

      // 3. Optional HTTP fallback attempt
      try {
        final uri = Uri.parse('${widget.backendBaseUrl.replaceAll(RegExp(r'/+$'), '')}/auth/device/verify');
        await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        ).timeout(const Duration(milliseconds: 1200));
      } catch (_) {}

      if (mounted) {
        setState(() {
          _isLoading = false;
          _isSuccess = true;
        });
        _animController.forward();

        // Brief delay to show success animation, then advance to Host Controls
        await Future.delayed(const Duration(milliseconds: 1300));
        if (mounted) {
          context.go('/host');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Pairing error: ${e.toString()}';
        });
      }
    }
  }

  Future<void> _handleEmailAuthSubmit() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Please enter both email and password.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final supabaseService = SupabaseService();
      final User? user;

      if (_isSignUpMode) {
        user = await supabaseService.signUpWithEmail(email, password);
      } else {
        user = await supabaseService.signInWithEmail(email, password);
      }

      if (user != null && widget.deviceToken != null) {
        await _verifyDeviceWithSupabase(widget.deviceToken!, user);
      } else if (user != null) {
        if (mounted) context.go('/host');
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Authentication completed. Check your email for confirmation if required.';
        });
      }
    } on AuthException catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.message;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Auth failed: ${e.toString()}';
      });
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await SupabaseService().signInWithGoogle();
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null && widget.deviceToken != null) {
        await _verifyDeviceWithSupabase(widget.deviceToken!, user);
      }
    } on AuthException catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.message;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Google Sign-In failed: ${e.toString()}';
      });
    }
  }

  Future<void> _handleAppleSignIn() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await SupabaseService().signInWithApple();
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null && widget.deviceToken != null) {
        await _verifyDeviceWithSupabase(widget.deviceToken!, user);
      }
    } on AuthException catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.message;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Apple Sign-In failed: ${e.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white70),
          onPressed: () => context.go('/hub'),
        ),
        title: const Text(
          'HOST AUTHENTICATION',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: _isSuccess
                ? _buildSuccessCard()
                : (_isLoading
                    ? _buildLoadingCard()
                    : (user != null ? _buildConnectedUserCard(user) : _buildMobileAuthForm())),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingCard() {
    return Container(
      padding: const EdgeInsets.all(36),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.neonCyan.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.neonCyan.withValues(alpha: 0.15),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              strokeWidth: 4,
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.neonCyan),
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'Connecting with TV...',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 10),
          Text(
            widget.userCode != null
                ? 'Authorizing Display: ${widget.userCode}'
                : 'Broadcasting authentication to big screen...',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessCard() {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppTheme.cardSurface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.neonGreen, width: 2),
          boxShadow: [
            BoxShadow(
              color: AppTheme.neonGreen.withValues(alpha: 0.25),
              blurRadius: 28,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppTheme.neonGreen,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, color: Colors.black, size: 48),
            ),
            const SizedBox(height: 24),
            const Text(
              'TV Connected!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white),
            ),
            const SizedBox(height: 10),
            const Text(
              'Big screen is now waiting for you.\nOpening Host Controls on your phone...',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: AppTheme.neonCyan, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectedUserCard(User user) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.neonCyan.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.tv_rounded, color: AppTheme.neonCyan, size: 60),
          const SizedBox(height: 16),
          const Text(
            'Connect TV Display',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            'Signed in as: ${user.email ?? "Host"}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Colors.white70),
          ),
          if (widget.userCode != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'CODE: ${widget.userCode}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: AppTheme.neonYellow,
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.neonCyan,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () {
              if (widget.deviceToken != null) {
                _verifyDeviceWithSupabase(widget.deviceToken!, user);
              }
            },
            child: const Text(
              'AUTHORIZE BIG SCREEN & LAUNCH HOST',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileAuthForm() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.neonCyan.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.neonCyan.withValues(alpha: 0.1),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.local_bar, color: AppTheme.neonCyan, size: 28),
              const SizedBox(width: 10),
              const Text(
                'BAR ROOMS TRIVIA',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _isSignUpMode ? 'Create Host Account to Connect TV' : 'Sign In as Host to Connect TV',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          if (widget.userCode != null) ...[
            const SizedBox(height: 8),
            Text(
              'Pairing with Code: ${widget.userCode}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppTheme.neonYellow, fontWeight: FontWeight.bold),
            ),
          ],
          if (_errorMessage != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
              ),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          ],
          const SizedBox(height: 20),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Email Address',
              labelStyle: const TextStyle(color: Colors.white60, fontSize: 13),
              prefixIcon: const Icon(Icons.email_outlined, color: AppTheme.neonCyan, size: 20),
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
          TextField(
            controller: _passwordCtrl,
            obscureText: _obscurePassword,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Password',
              labelStyle: const TextStyle(color: Colors.white60, fontSize: 13),
              prefixIcon: const Icon(Icons.lock_outlined, color: AppTheme.neonCyan, size: 20),
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.white54, size: 20),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
              filled: true,
              fillColor: const Color(0xFF0F172A),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.neonCyan, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.neonCyan,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _handleEmailAuthSubmit,
            child: Text(
              _isSignUpMode ? 'CREATE ACCOUNT & PAIR TV' : 'SIGN IN & PAIR TV',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.15))),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10.0),
                child: Text('OR', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.15))),
            ],
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.g_mobiledata, color: Color(0xFF4285F4), size: 24),
            label: const Text('Sign In with Google & Pair TV', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            onPressed: _handleGoogleSignIn,
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.apple, color: Colors.white, size: 20),
            label: const Text('Sign In with Apple & Pair TV', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            onPressed: _handleAppleSignIn,
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => setState(() => _isSignUpMode = !_isSignUpMode),
            child: Text(
              _isSignUpMode ? 'Already have an account? Sign In' : "Don't have an account? Sign Up",
              style: const TextStyle(color: AppTheme.neonCyan, fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
