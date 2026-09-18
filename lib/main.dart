import 'package:flutter/material.dart';
import 'controllers/theme_controller.dart';
import 'screens/auth_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AttendanceApp());
}

// ── App Theme & Setup ─────────────────────────────────────────────────────────
class AttendanceApp extends StatefulWidget {
  const AttendanceApp({super.key});

  @override
  State<AttendanceApp> createState() => _AttendanceAppState();
}

class _AttendanceAppState extends State<AttendanceApp> {
  @override
  void initState() {
    super.initState();
    themeController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MonarchHR',
      debugShowCheckedModeBanner: false,
      themeMode: themeController.themeMode,

      // ── LIGHT THEME (MonarchHR Light) ─────────────────────────────────────────
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF8F9FF),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFF5A952),
          brightness: Brightness.light,
        ),
        cardColor: Colors.white,
        fontFamily: 'SF Pro Display',
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF8F9FF),
          foregroundColor: Color(0xFF171C23),
          elevation: 0,
        ),
      ),

      // ── DARK THEME (MonarchHR Dark) ──────────────────────────────────────────
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0C0E14),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFF5A952),
          brightness: Brightness.dark,
        ),
        cardColor: const Color(0xFF131722),
        fontFamily: 'SF Pro Display',
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF131722),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),

      home: const AuthGate(),
    );
  }
}
