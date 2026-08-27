import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../shared/theme/app_theme.dart';

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
  bool _isLoading = false;
  bool _isSuccess = false;
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

    // If deviceToken is present, attempt verification if authenticated or wait for user login
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAuthAndVerify();
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _checkAuthAndVerify() async {
    final token = widget.deviceToken;
    if (token == null || token.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Invalid QR Code. No device pairing token was found in the link.';
      });
      return;
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      // User is already logged in, proceed to verify immediately
      await _verifyDeviceWithBackend(token, user);
    } else {
      // User needs to sign in first
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _verifyDeviceWithBackend(String token, User user) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final session = Supabase.instance.client.auth.currentSession;
      final uri = Uri.parse('${widget.backendBaseUrl.replaceAll(RegExp(r'/+$'), '')}/auth/device/verify');

      final payload = {
        'device_token': token,
        'user_id': user.id,
        'user_info': {
          'email': user.email ?? 'Host User',
          'display_name': user.userMetadata?['display_name'] ?? user.email?.split('@').first ?? 'Host',
        },
        'auth_tokens': {
          'access_token': session?.accessToken ?? '',
        }
      };

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));

      final responseData = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode >= 200 && response.statusCode < 300 && responseData['success'] == true) {
        // Pairing successful!
        setState(() {
          _isLoading = false;
          _isSuccess = true;
        });
        _animController.forward();

        // Brief delay to display success animation, then immediately push router to Host Controls
        await Future.delayed(const Duration(milliseconds: 1200));
        if (mounted) {
          context.go('/host');
        }
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = responseData['error'] ?? 'Device pairing failed. The session may have expired.';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Network error during verification: ${e.toString()}';
      });
    }
  }

  Future<void> _handleQuickAnonymousLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authResponse = await Supabase.instance.client.auth.signInAnonymously();
      final user = authResponse.user;
      if (user != null && widget.deviceToken != null) {
        await _verifyDeviceWithBackend(widget.deviceToken!, user);
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Could not authenticate. Please try standard login.';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Sign in failed: ${e.toString()}';
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
          'TV AUTHENTICATION',
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
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_isSuccess)
                  _buildSuccessCard()
                else if (_isLoading)
                  _buildLoadingCard()
                else if (_errorMessage != null)
                  _buildErrorCard()
                else if (user == null)
                  _buildLoginPromptCard()
                else
                  _buildConfirmPairingCard(user),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingCard() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.neonCyan.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.neonCyan.withOpacity(0.1),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(
            width: 64,
            height: 64,
            child: CircularProgressIndicator(
              strokeWidth: 4,
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.neonCyan),
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'Pairing with TV...',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            widget.userCode != null
                ? 'Authorizing display code: ${widget.userCode}'
                : 'Connecting phone session to big screen...',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.white70,
            ),
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
          border: Border.all(color: const Color(0xFF10B981), width: 2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF10B981).withOpacity(0.2),
              blurRadius: 24,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFF10B981),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check,
                color: Colors.white,
                size: 48,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'TV Paired Successfully!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Launching Host Controls...',
              style: TextStyle(
                fontSize: 16,
                color: AppTheme.neonCyan,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmPairingCard(User user) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.neonCyan.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.tv_rounded,
            color: AppTheme.neonCyan,
            size: 64,
          ),
          const SizedBox(height: 16),
          const Text(
            'Connect TV Display',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
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
                color: Colors.white.withOpacity(0.06),
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
                  color: AppTheme.neonPurple,
                ),
              ),
            ),
          ],
          const SizedBox(height: 28),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.neonCyan,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedCornerShape(14),
            ),
            onPressed: () {
              if (widget.deviceToken != null) {
                _verifyDeviceWithBackend(widget.deviceToken!, user);
              }
            },
            child: const Text(
              'AUTHORIZE & LAUNCH HOST',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginPromptCard() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.neonPurple.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.lock_person_outlined,
            color: AppTheme.neonPurple,
            size: 56,
          ),
          const SizedBox(height: 16),
          const Text(
            'Sign In to Pair TV',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'You must be signed in with your host account to link this TV screen.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.white70),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.neonPurple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedCornerShape(12),
            ),
            onPressed: () {
              context.push('/auth');
            },
            child: const Text(
              'SIGN IN / REGISTER',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.neonCyan,
              side: const BorderSide(color: AppTheme.neonCyan),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedCornerShape(12),
            ),
            onPressed: _handleQuickAnonymousLogin,
            child: const Text(
              'CONTINUE AS GUEST HOST',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.error_outline,
            color: Colors.redAccent,
            size: 56,
          ),
          const SizedBox(height: 16),
          const Text(
            'Pairing Failed',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.redAccent,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _errorMessage ?? 'An error occurred.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Colors.white70),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.cardSurface,
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white30),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedCornerShape(12),
            ),
            onPressed: () => context.go('/hub'),
            child: const Text('BACK TO DASHBOARD'),
          ),
        ],
      ),
    );
  }
}
