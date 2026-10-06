import 'dart:async';
import 'package:flutter/material.dart';
import '../config/api_config.dart';
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
  int _pendingPunchCount = 0;
  Timer? _punchCheckTimer;
  final GlobalKey<HomeScreenTabState> _homeKey = GlobalKey<HomeScreenTabState>();
  final GlobalKey<AttendanceInfoTabState> _attendanceKey = GlobalKey<AttendanceInfoTabState>();
  final GlobalKey<ExploreTabState> _exploreKey = GlobalKey<ExploreTabState>();

  bool get _isLeaderOrManager {
    final role = (widget.user['role'] ?? '').toString().toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
    return role == 'teamleader' ||
        role == 'subteamlead' ||
        role == 'seniorteamlead' ||
        role == 'seniorteamleader' ||
        role == 'manager' ||
        role == 'projectmanager' ||
        role == 'admin' ||
        role == 'hr' ||
        role.contains('leader') ||
        role.contains('lead');
  }

  @override
  void initState() {
    super.initState();
    themeController.addListener(_onThemeChange);
    _fetchPendingPunchCount();
    _punchCheckTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _fetchPendingPunchCount();
    });
  }

  @override
  void dispose() {
    themeController.removeListener(_onThemeChange);
    _punchCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchPendingPunchCount() async {
    if (!_isLeaderOrManager) return;
    try {
      final res = await apiGetJson('/api/team/punch-requests', token: widget.token).timeout(const Duration(seconds: 5));
      if (res is Map && res['punch_requests'] is List) {
        final count = (res['punch_requests'] as List).length;
        if (mounted && _pendingPunchCount != count) {
          setState(() => _pendingPunchCount = count);
        }
      }
    } catch (_) {}
  }

  void _onThemeChange() {
    if (mounted) setState(() {});
  }

  void _switchTab(int index) {
    if (_currentIndex != index) {
      setState(() => _currentIndex = index);
    }
    // Instant data refresh on active tab switch
    if (index == 0) {
      _homeKey.currentState?.refreshData();
    } else if (index == 1) {
      _attendanceKey.currentState?.refreshData();
    } else if (index == 2) {
      _exploreKey.currentState?.refreshData();
    }
    _fetchPendingPunchCount();
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
        key: _homeKey,
        token: widget.token,
        user: widget.user,
        password: widget.password,
        onLogout: widget.onLogout,
        onNavigateToLeave: () => _switchTab(2),
        onNavigateToAttendance: ({String? subTab}) {
          _switchTab(1);
          if (subTab != null) {
            _attendanceKey.currentState?.setSubTab(subTab);
          }
        },
        onNavigateToProfile: () => _switchTab(3),
      ),
      AttendanceInfoTab(
        key: _attendanceKey,
        token: widget.token,
        user: widget.user,
        onNavigateToProfile: () => _switchTab(3),
        onPunchRequestsUpdated: (count) {
          if (mounted && _pendingPunchCount != count) {
            setState(() => _pendingPunchCount = count);
          }
        },
      ),
      ExploreTab(
        key: _exploreKey,
        token: widget.token,
        user: widget.user,
        password: widget.password,
        onLogout: widget.onLogout,
        onNavigateToProfile: () => _switchTab(3),
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
          _switchTab(0);
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
                  _navItem(0, Icons.home_rounded, 'Home', amberPrimary, isDark, navBg: navBg),
                  _navItem(
                    1,
                    Icons.calendar_month_rounded,
                    'History',
                    amberPrimary,
                    isDark,
                    badgeCount: _pendingPunchCount,
                    navBg: navBg,
                  ),
                  _navItem(2, Icons.beach_access_rounded, 'Leave', amberPrimary, isDark, navBg: navBg),
                  _navItem(
                    3,
                    Icons.person_rounded,
                    'Profile',
                    amberPrimary,
                    isDark,
                    hasAlert: isProfileIncomplete,
                    navBg: navBg,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(
    int index,
    IconData icon,
    String label,
    Color accent,
    bool isDark, {
    bool hasAlert = false,
    int badgeCount = 0,
    required Color navBg,
  }) {
    final isSelected = _currentIndex == index;
    final selectedBg = isSelected ? accent : Colors.transparent;
    final selectedFg = isSelected ? const Color(0xFF6B3F00) : (isDark ? const Color(0xFF9CA3AF) : const Color(0xFF524437));

    return GestureDetector(
      onTap: () => _switchTab(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selectedBg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 20, color: selectedFg),
                if (!isSelected && (hasAlert || badgeCount > 0))
                  Positioned(
                    top: badgeCount > 0 ? -4 : -2,
                    right: badgeCount > 0 ? -6 : -3,
                    child: badgeCount > 0
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF2A55),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: navBg, width: 1.5),
                            ),
                            child: Text(
                              badgeCount > 99 ? '99+' : '$badgeCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.w900,
                                height: 1.0,
                              ),
                            ),
                          )
                        : Container(
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
              if (badgeCount > 0) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF2A55),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    badgeCount > 99 ? '99+' : '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
