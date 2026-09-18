import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_screen.dart';
import 'main_navigation_shell.dart';

// ── Auth Gate ─────────────────────────────────────────────────────────────────
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _checking = true;
  String? _token;
  Map<String, dynamic>? _user;
  String? _password;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final t = prefs.getString('token');
    final u = prefs.getString('user');
    final p = prefs.getString('password');
    if (t != null && u != null) {
      setState(() {
        _token = t;
        _user = jsonDecode(u);
        _password = p;
      });
    }
    setState(() => _checking = false);
  }

  void _onLogin(String token, Map<String, dynamic> user, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    await prefs.setString('user', jsonEncode(user));
    await prefs.setString('password', password);
    setState(() {
      _token = token;
      _user = user;
      _password = password;
    });
  }

  void _onLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    setState(() {
      _token = null;
      _user = null;
      _password = null;
    });
  }

  void _onUserUpdated(Map<String, dynamic> updatedUser) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user', jsonEncode(updatedUser));
    setState(() {
      _user = updatedUser;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_token == null) return LoginScreen(onLogin: _onLogin);
    return MainNavigationContainer(
      token: _token!,
      user: _user!,
      password: _password ?? '',
      onLogout: _onLogout,
      onUserUpdated: _onUserUpdated,
    );
  }
}
