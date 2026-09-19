import 'package:flutter/material.dart';
import '../config/api_config.dart';
import '../controllers/theme_controller.dart';

// ── Login Screen (MonarchHR Style) ───────────────────────────────────────────
class LoginScreen extends StatefulWidget {
  final void Function(String, Map<String, dynamic>, String) onLogin;

  const LoginScreen({super.key, required this.onLogin});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email    = TextEditingController();
  final _password = TextEditingController();
  bool _loading   = false;
  bool _obscurePassword = true;
  bool _rememberDevice = true;
  String? _err;

  @override
  void initState() {
    super.initState();
    themeController.addListener(_onThemeChanged);
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    themeController.removeListener(_onThemeChanged);
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final empIdVal    = _email.text.trim();
    final passwordVal = _password.text;

    if (empIdVal.isEmpty || passwordVal.isEmpty) {
      setState(() => _err = 'Employee ID and password are required.');
      return;
    }

    setState(() { _loading = true; _err = null; });
    try {
      final res = await apiPost('/api/login', {
        'emp_id':   empIdVal,
        'email':    empIdVal,
        'username': empIdVal,
        'password': passwordVal,
      });
      if (res['error'] != null) {
        setState(() => _err = res['error']);
      } else {
        widget.onLogin(res['token'], res['user'], passwordVal);
      }
    } catch (e) {
      setState(() => _err = 'Cannot reach server. Check your connection.');
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeController.isDarkMode;
    final bgScaffold = isDark ? const Color(0xFF0C0E14) : const Color(0xFFF8F9FF);
    final bgCard = isDark ? const Color(0xFF131722) : Colors.white;
    final bgInput = isDark ? const Color(0xFF1A1F2C) : const Color(0xFFF0F4FD);
    final cardBorder = isDark ? const Color(0xFF1F2637) : const Color(0xFFEAEFF8);
    final inputBorder = isDark ? const Color(0xFF283044) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? Colors.white : const Color(0xFF171C23);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final textHint = isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8);
    final iconColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    const amberPrimary = Color(0xFFF5A952);
    final forgotPasswordColor = isDark ? const Color(0xFFFDBA74) : const Color(0xFFB45309);

    return Scaffold(
      backgroundColor: bgScaffold,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                'https://static.share.market/cube/instrument/icon/PEBYEHT',
                width: 28,
                height: 28,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: amberPrimary.withAlpha(38),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.schedule_rounded, color: amberPrimary, size: 20),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Monarch HR',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary, letterSpacing: -0.5),
            ),
          ],
        ),
        actions: [
          Row(
            children: [
              Text('Sign In', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textSecondary)),
              const SizedBox(width: 6),
              CircleAvatar(
                radius: 14,
                backgroundColor: isDark ? const Color(0xFF2A241A) : const Color(0xFFFDF0DE),
                child: const Icon(Icons.person, color: amberPrimary, size: 16),
              ),
            ],
          ),
          const SizedBox(width: 6),
          Container(
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E2536) : const Color(0xFFEBF1FF),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(
                isDark ? Icons.wb_sunny_rounded : Icons.dark_mode_rounded,
                color: isDark ? const Color(0xFFFBBF24) : const Color(0xFF3B82F6),
                size: 18,
              ),
              onPressed: () => themeController.toggleTheme(),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 10),

              // Hero Circular Logo Badge
              Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: bgCard,
                        border: Border.all(color: cardBorder, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: isDark ? const Color(0x66000000) : const Color(0x0F171C23),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(34),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Image.network(
                            'https://static.share.market/cube/instrument/icon/PEBYEHT',
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(Icons.schedule_rounded, color: amberPrimary, size: 36),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Color(0xFF9FF1BD),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check, color: Color(0xFF1B7047), size: 12),
                      ),
                    )
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Title Greeting
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Welcome back',
                    style: TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w800, color: textPrimary, letterSpacing: -0.5),
                  ),
                  const SizedBox(width: 6),
                  const Text('👋', style: TextStyle(fontSize: 20)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Sign in to track your shifts, attendance, and leave balance effortlessly.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: textSecondary, height: 1.4),
              ),

              const SizedBox(height: 24),

              // Form Container Card
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: bgCard,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: isDark ? const Color(0x66000000) : const Color(0x0F171C23),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    )
                  ],
                  border: Border.all(
                    color: cardBorder,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Employee ID Input
                    Text('EMPLOYEE ID',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700, color: textSecondary, letterSpacing: 0.8)),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: bgInput,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: inputBorder, width: 1),
                      ),
                      child: TextField(
                        controller: _email,
                        style: TextStyle(color: textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                        decoration: InputDecoration(
                          prefixIcon: Icon(Icons.badge_outlined, color: iconColor, size: 20),
                          hintText: 'e.g. EMP-84920',
                          hintStyle: TextStyle(color: textHint, fontSize: 13, fontWeight: FontWeight.w400),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Password Input
                    Text('PASSWORD',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700, color: textSecondary, letterSpacing: 0.8)),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: bgInput,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: inputBorder, width: 1),
                      ),
                      child: TextField(
                        controller: _password,
                        obscureText: _obscurePassword,
                        style: TextStyle(color: textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                        decoration: InputDecoration(
                          prefixIcon: Icon(Icons.lock_outline, color: iconColor, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                              color: iconColor,
                              size: 20,
                            ),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                          hintText: 'Enter your work password',
                          hintStyle: TextStyle(color: textHint, fontSize: 13, fontWeight: FontWeight.w400),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Utilities Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: Checkbox(
                                value: _rememberDevice,
                                activeColor: amberPrimary,
                                checkColor: const Color(0xFF451A03),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                onChanged: (val) => setState(() => _rememberDevice = val ?? true),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('Remember device',
                                style: TextStyle(fontSize: 11, color: textSecondary, fontWeight: FontWeight.w500)),
                          ],
                        ),
                        Text('Forgot password?',
                            style: TextStyle(
                                fontSize: 11, color: forgotPasswordColor, fontWeight: FontWeight.w700)),
                      ],
                    ),

                    const SizedBox(height: 22),

                    // Main Sign In Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: amberPrimary,
                          foregroundColor: const Color(0xFF451A03),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30)),
                          elevation: 0,
                          shadowColor: const Color(0x4DF5A952),
                        ),
                        child: _loading
                            ? const SizedBox(
                                height: 20, width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5, color: Color(0xFF451A03)))
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('Sign In to Workspace',
                                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                                  SizedBox(width: 8),
                                  Icon(Icons.arrow_forward_rounded, size: 18),
                                ],
                              ),
                      ),
                    ),

                    if (_err != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0x99450A0A) : const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? const Color(0xFF991B1B) : const Color(0xFFFCA5A5),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline,
                                color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFFDC2626), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_err!,
                                  style: TextStyle(
                                      color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
