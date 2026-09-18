import 'package:flutter/material.dart';
import '../controllers/theme_controller.dart';
import 'dashboard_screen.dart';
import 'attendance_info_screen.dart';
import 'explore_admin_screen.dart';
import 'engage_screen.dart';

// ── Main Navigation Shell (PulseWork 4 Floating Tabs) ──────────────────────────
class MainNavigationContainer extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;
  final String password;
  final VoidCallback onLogout;
  final void Function(Map<String, dynamic>)? onUserUpdated;

  const MainNavigationContainer({
    super.key,
    required this.token,
    required this.user,
    required this.password,
    required this.onLogout,
    this.onUserUpdated,
  });

  @override
  State<MainNavigationContainer> createState() => _MainNavigationContainerState();
}

class _MainNavigationContainerState extends State<MainNavigationContainer> {
  int _currentIndex = 0;
  final GlobalKey<AttendanceInfoTabState> _attendanceKey = GlobalKey<AttendanceInfoTabState>();

  @override
  void initState() {
    super.initState();
    themeController.addListener(_onThemeChange);
  }

  @override
  void dispose() {
    themeController.removeListener(_onThemeChange);
    super.dispose();
  }

  void _onThemeChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeController.isDarkMode;
    final navBg = isDark ? const Color(0xFF131722) : Colors.white;
    final navBorder = isDark ? const Color(0xFF1F2633) : const Color(0xFFEAEFF8);
    const amberPrimary = Color(0xFFF5A952);

    final phoneNum = widget.user['phone_number']?.toString() ?? '';
    final joinDate = (widget.user['date_of_joining'] ?? widget.user['joining_date'])?.toString() ?? '';
    final email = widget.user['email']?.toString() ?? '';
    final isValidEmail = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(email.trim());
    final isProfileIncomplete = phoneNum.trim().isEmpty || joinDate.trim().isEmpty || !isValidEmail;

    final screens = [
      HomeScreenTab(
        token: widget.token,
        user: widget.user,
        password: widget.password,
        onLogout: widget.onLogout,
        onNavigateToAttendance: ({String? subTab}) {
          setState(() {
            _currentIndex = 1;
            if (subTab != null) {
              _attendanceKey.currentState?.setSubTab(subTab);
            }
          });
        },
        onNavigateToProfile: () => setState(() => _currentIndex = 3),
      ),
      AttendanceInfoTab(
        key: _attendanceKey,
        token: widget.token,
        user: widget.user,
        onNavigateToProfile: () => setState(() => _currentIndex = 3),
      ),
      ExploreTab(
        token: widget.token,
        user: widget.user,
        password: widget.password,
        onLogout: widget.onLogout,
        onNavigateToProfile: () => setState(() => _currentIndex = 3),
      ),
      EngageTab(
        token: widget.token,
        user: widget.user,
        onLogout: widget.onLogout,
        onUserUpdated: widget.onUserUpdated,
      ),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        // Level 3: Check if History tab is viewing detail day screen
        if (_currentIndex == 1 && _attendanceKey.currentState != null) {
          if (_attendanceKey.currentState!.handleBackPress()) {
            return; // Handled back press inside History tab!
          }
        }

        // Level 2: If on non-Home tab, navigate back to Home tab (index 0)
        if (_currentIndex != 0) {
          setState(() => _currentIndex = 0);
          return;
        }

        // Level 1: Already on Home tab -> pop app / exit
        Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF0C0E14) : const Color(0xFFF8F9FF),
        body: IndexedStack(
          index: _currentIndex,
          children: screens,
        ),
        bottomNavigationBar: Container(
          color: isDark ? const Color(0xFF0C0E14) : const Color(0xFFF8F9FF),
          child: SafeArea(
            top: false,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: navBg,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: navBorder),
                boxShadow: [
                  BoxShadow(
                    color: isDark ? Colors.black.withAlpha(90) : const Color(0x14171C23),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  )
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _navItem(0, Icons.home_rounded, 'Home', amberPrimary, isDark),
                  _navItem(1, Icons.calendar_month_rounded, 'History', amberPrimary, isDark),
                  _navItem(2, Icons.beach_access_rounded, 'Leave', amberPrimary, isDark),
                  _navItem(3, Icons.person_rounded, 'Profile', amberPrimary, isDark, hasAlert: isProfileIncomplete),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label, Color accent, bool isDark, {bool hasAlert = false}) {
    final isSelected = _currentIndex == index;
    final selectedBg = isSelected ? accent : Colors.transparent;
    final selectedFg = isSelected ? const Color(0xFF6B3F00) : (isDark ? const Color(0xFF9CA3AF) : const Color(0xFF524437));

    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selectedBg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 20, color: selectedFg),
                if (hasAlert && !isSelected)
                  Positioned(
                    top: -2,
                    right: -3,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF2A55),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            if (isSelected) ...[
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: selectedFg, fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ],
        ),
      ),
    );
  }
}
