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
  void dispose() {
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
    final bgInput = isDark ? const Color(0xFF1A1E2B) : const Color(0xFFF0F4FD);
    final textPrimary = isDark ? Colors.white : const Color(0xFF171C23);
    final textSecondary = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF524437);
    const amberPrimary = Color(0xFFF5A952);
    const amberDark = Color(0xFF895100);

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
                  child: const Icon(Icons.schedule_rounded, color: amberDark, size: 20),
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
              const CircleAvatar(
                radius: 14,
                backgroundColor: amberDark,
                child: Icon(Icons.person, color: Colors.white, size: 16),
              ),
            ],
          ),
          IconButton(
            icon: Icon(
              isDark ? Icons.wb_sunny_outlined : Icons.nightlight_round,
              color: isDark ? amberPrimary : const Color(0xFF2563EB),
              size: 18,
            ),
            onPressed: () => themeController.toggleTheme(),
          ),
          const SizedBox(width: 8),
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
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x0F171C23),
                            blurRadius: 16,
                            offset: Offset(0, 4),
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
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0F171C23),
                      blurRadius: 20,
                      offset: Offset(0, 6),
                    )
                  ],
                  border: Border.all(
                    color: isDark ? const Color(0xFF1F2633) : const Color(0xFFEAEFF8),
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
                      ),
                      child: TextField(
                        controller: _email,
                        style: TextStyle(color: textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                        decoration: InputDecoration(
                          prefixIcon: Icon(Icons.badge_outlined, color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF847465), size: 20),
                          hintText: 'e.g. EMP-84920',
                          hintStyle: const TextStyle(color: Color(0xFF847465), fontSize: 13, fontWeight: FontWeight.w400),
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
                      ),
                      child: TextField(
                        controller: _password,
                        obscureText: _obscurePassword,
                        style: TextStyle(color: textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                        decoration: InputDecoration(
                          prefixIcon: Icon(Icons.lock_outline, color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF847465), size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                              color: const Color(0xFF847465),
                              size: 20,
                            ),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                          hintText: 'Enter your work password',
                          hintStyle: const TextStyle(color: Color(0xFF847465), fontSize: 13, fontWeight: FontWeight.w400),
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
                                checkColor: amberDark,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                onChanged: (val) => setState(() => _rememberDevice = val ?? true),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('Remember device',
                                style: TextStyle(fontSize: 11, color: textSecondary, fontWeight: FontWeight.w500)),
                          ],
                        ),
                        const Text('Forgot password?',
                            style: TextStyle(
                                fontSize: 11, color: amberDark, fontWeight: FontWeight.w700)),
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
                          foregroundColor: const Color(0xFF6B3F00),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30)),
                          elevation: 0,
                          shadowColor: amberPrimary.withAlpha(80),
                        ),
                        child: _loading
                            ? const SizedBox(
                                height: 20, width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5, color: Color(0xFF6B3F00)))
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
                          color: const Color(0xFFBA1A1A).withAlpha(25),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Color(0xFFBA1A1A), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_err!,
                                  style: const TextStyle(color: Color(0xFFBA1A1A), fontSize: 12, fontWeight: FontWeight.w600)),
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
