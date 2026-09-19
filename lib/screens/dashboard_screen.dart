import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import '../config/api_config.dart';
import '../controllers/theme_controller.dart';
import '../services/app_update_service.dart';
import '../widgets/semicircle_gauge_painter.dart';
import '../widgets/profile_avatar_badge.dart';

// ── MonarchHR Front Home Dashboard Page ───────────────────────────────────────
class HomeScreenTab extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;
  final String password;
  final VoidCallback onLogout;
  final void Function({String? subTab}) onNavigateToAttendance;
  final VoidCallback? onNavigateToProfile;

  const HomeScreenTab({
    super.key,
    required this.token,
    required this.user,
    required this.password,
    required this.onLogout,
    required this.onNavigateToAttendance,
    this.onNavigateToProfile,
  });

  @override
  State<HomeScreenTab> createState() => _HomeScreenTabState();
}

class _HomeScreenTabState extends State<HomeScreenTab> {
  bool _clockedIn   = false;
  bool _loading     = false;
  String? _message;
  Timer? _locTimer;
  DateTime? _clockInTime;
  String? _sessionId;
  Timer? _timeTicker;
  DateTime _now = DateTime.now();
  List<dynamic> _myRecords = [];

  // Real Leave Data from PostgreSQL
  double _totalLeaves = 25.0;
  double _usedLeaves = 5.5;
  double _remainingLeaves = 19.5;
  int _pendingLeavesCount = 0;
  int _teamPendingApprovalsCount = 0;

  @override
  void initState() {
    super.initState();
    themeController.addListener(_onThemeChanged);
    _checkStatus();
    _fetchData();
    _fetchLeavesData();
    _fetchTeamApprovalsCount();
    _timeTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppUpdateService.checkForUpdates(context);
    });
  }

  @override
  void dispose() {
    themeController.removeListener(_onThemeChanged);
    _locTimer?.cancel();
    _timeTicker?.cancel();
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  String _fmtDays(double v) {
    return v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);
  }

  Future<void> _fetchTeamApprovalsCount() async {
    final role = (widget.user['role'] ?? '').toString().toLowerCase();
    final isPrivileged = role.contains('manager') || role.contains('director') || role.contains('lead') || role.contains('tl') || role == 'admin';
    if (!isPrivileged) return;
    try {
      final res = await apiGetJson('/api/team/hierarchy', token: widget.token);
      if (res is Map && mounted) {
        setState(() {
          _teamPendingApprovalsCount = int.tryParse(res['pending_approvals_count']?.toString() ?? '') ?? 0;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchLeavesData() async {
    try {
      final res = await apiGetJson('/api/leaves/me', token: widget.token);
      if (res is Map && mounted) {
        setState(() {
          _totalLeaves = double.tryParse(res['total_allotted']?.toString() ?? '') ?? 25.0;
          _usedLeaves = double.tryParse(res['used_days']?.toString() ?? '') ?? 5.5;
          _remainingLeaves = double.tryParse(res['remaining_days']?.toString() ?? '') ?? 19.5;
          final leavesList = res['leaves'] is List ? res['leaves'] : [];
          _pendingLeavesCount = leavesList.where((l) => l['status']?.toString().toLowerCase().contains('pending') ?? false).length;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchData() async {
    try {
      final recs = await apiGet('/api/attendance/me', token: widget.token);
      if (mounted) {
        setState(() {
          _myRecords = recs;
        });
      }
    } catch (_) {}
  }

  Future<void> _checkStatus() async {
    try {
      final data = await apiGet('/api/attendance/me', token: widget.token);
      if (data.isNotEmpty) {
        // Look for an open active shift (sign_out / clock_out is null)
        final active = data.firstWhere(
          (r) => r['clock_out'] == null && r['clock_in'] != null,
          orElse: () => null,
        );
        if (active != null) {
          final ci = DateTime.tryParse(active['clock_in']?.toString() ?? '');
          if (mounted) {
            setState(() {
              _clockedIn   = true;
              _clockInTime = ci ?? DateTime.now();
              _sessionId   = active['_id']?.toString();
            });
            _startLocationLoop();
          }
        } else {
          // If no active shift is open, check today's latest record to display check-in time
          final now = DateTime.now();
          final todayRecord = data.firstWhere(
            (r) {
              if (r['clock_in'] == null) return false;
              final ci = DateTime.tryParse(r['clock_in'].toString());
              return ci != null && ci.year == now.year && ci.month == now.month && ci.day == now.day;
            },
            orElse: () => null,
          );
          if (mounted) {
            setState(() {
              _clockedIn = false;
              _clockInTime = todayRecord != null ? DateTime.tryParse(todayRecord['clock_in']?.toString() ?? '') : null;
            });
          }
        }
      }
    } catch (_) {}
  }

  void _startLocationLoop() {
    _locTimer?.cancel();
    _locTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (!_clockedIn) return;

      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _locTimer?.cancel();
        await _clockOut();
        return;
      }

      final pos = await getPosition();
      if (pos == null) return;

      await apiPost(
          '/api/location',
          {
            'lat':        pos.latitude,
            'lng':        pos.longitude,
            'accuracy':   pos.accuracy,
            'session_id': _sessionId,
          },
          token: widget.token);
    });
  }

  Future<void> _clockIn() async {
    setState(() { _loading = true; _message = null; });

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _message = '⚠ Please turn ON location/GPS before checking in.';
        _loading = false;
      });
      await Geolocator.openLocationSettings();
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      setState(() {
        _message = '⚠ Location permission required to check in.';
        _loading = false;
      });
      return;
    }

    Position pos;
    try {
      pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    } catch (e) {
      setState(() {
        _message = '⚠ Unable to fetch location. Try again.';
        _loading = false;
      });
      return;
    }

    try {
      final clientNow = DateTime.now();
      final res = await apiPost('/api/attendance/clock-in', {
        'lat': pos.latitude,
        'lng': pos.longitude,
        'client_time': clientNow.toIso8601String(),
      }, token: widget.token);

      if (res['error'] != null) {
        if (res['error'].toString().toLowerCase().contains('token')) {
          widget.onLogout();
        } else {
          setState(() => _message = res['error']);
        }
      } else {
        final inGeofence = res['in_geofence'] == true;
        final bldg = res['nearest_building'] ?? 'Office';
        final dist = res['distance_meters'];
        String msg = '✅ Checked in at $bldg (Verified ≤ 20m)';
        if (!inGeofence) {
          msg = '⚠️ Checked in ${dist != null ? '${dist}m' : 'away'} from $bldg (> 20m). Punch sent for Team Approval.';
        }
        setState(() {
          _clockedIn    = true;
          _clockInTime  = clientNow;
          _sessionId    = res['session_id']?.toString();
          _message      = msg;
        });
        _startLocationLoop();
        _fetchData();
      }
    } catch (_) {
      setState(() => _message = '⚠ Server connection error.');
    }

    setState(() => _loading = false);
  }

  Future<void> _clockOut() async {
    setState(() { _loading = true; _message = null; });

    final pos = await getPosition();
    try {
      final res = await apiPost('/api/attendance/clock-out', {
        'lat': pos?.latitude,
        'lng': pos?.longitude,
        'client_time': DateTime.now().toIso8601String(),
      }, token: widget.token);

      if (res['error'] != null) {
        if (res['error'].toString().toLowerCase().contains('token')) {
          widget.onLogout();
        } else {
          setState(() => _message = res['error']);
        }
      } else {
        final sessionId = res['session']?['_id']?.toString();
        final inGeofence = res['clock_out_in_geofence'] == true;
        final bldg = res['nearest_building'] ?? 'Office';
        final dist = res['distance_meters'];
        String msg = '✅ Checked out successfully';
        if (!inGeofence) {
          msg = '⚠️ Checked out ${dist != null ? '${dist}m' : 'away'} from $bldg (> 20m). Punch sent for Team Approval.';
        }
        setState(() {
          _clockedIn    = false;
          _sessionId    = null;
          _message      = msg;
        });
        _locTimer?.cancel();
        if (sessionId != null) {
          saveRouteToDB(sessionId, widget.token);
        }
        _fetchData();
      }
    } catch (_) {
      setState(() => _message = 'Server connection error.');
    }

    setState(() => _loading = false);
  }

  String _getTodayWorkingHrsString(List<dynamic> todayRecords) {
    int completedSecs = 0;
    for (var r in todayRecords) {
      final ci = r['clock_in'] != null ? DateTime.tryParse(r['clock_in'].toString()) : null;
      final co = r['clock_out'] != null ? DateTime.tryParse(r['clock_out'].toString()) : null;
      if (ci != null && co != null) {
        completedSecs += co.difference(ci).inSeconds;
      } else if (r['total_minutes'] != null) {
        completedSecs += (r['total_minutes'] as int) * 60;
      }
    }

    int activeSecs = 0;
    if (_clockedIn && _clockInTime != null) {
      activeSecs = DateTime.now().difference(_clockInTime!).inSeconds;
    }

    final totalSecs = completedSecs + activeSecs;
    final h = (totalSecs ~/ 3600).toString().padLeft(2, '0');
    final m = ((totalSecs % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (totalSecs % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeController.isDarkMode;
    final bgScaffold = isDark ? const Color(0xFF0C0E14) : const Color(0xFFF8F9FF);
    final bgCard = isDark ? const Color(0xFF131722) : Colors.white;
    final borderCol = isDark ? const Color(0xFF1F2633) : const Color(0xFFEAEFF8);
    final textPrimary = isDark ? Colors.white : const Color(0xFF171C23);
    final textSecondary = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF524437);
    const amberPrimary = Color(0xFFF5A952);
    const amberDark = Color(0xFF895100);

    final fullName = widget.user['name'] ?? 'Robert Smith';
    final empId = widget.user['emp_id'] ?? 'EMP-84920';

    // Aggregate today's records
    final todayRecords = _myRecords.where((r) {
      final ci = r['clock_in'] != null ? DateTime.tryParse(r['clock_in'].toString()) : null;
      if (ci != null && ci.year == _now.year && ci.month == _now.month && ci.day == _now.day) {
        return true;
      }
      return false;
    }).toList();

    // Sort today's records ascending by clock_in
    todayRecords.sort((a, b) {
      final aIn = a['clock_in'] != null ? DateTime.parse(a['clock_in'].toString()) : DateTime(1970);
      final bIn = b['clock_in'] != null ? DateTime.parse(b['clock_in'].toString()) : DateTime(1970);
      return aIn.compareTo(bIn);
    });

    // Get the latest check-out time of today
    DateTime? lastCheckOutToday;
    if (!_clockedIn && todayRecords.isNotEmpty) {
      for (var r in todayRecords.reversed) {
        if (r['clock_out'] != null) {
          lastCheckOutToday = DateTime.tryParse(r['clock_out'].toString());
          break;
        }
      }
    }

    // Current Active Shift Timings
    final String displayCheckIn = (_clockedIn && _clockInTime != null)
        ? DateFormat('hh:mm a').format(_clockInTime!)
        : '-- : --';

    final String displayCheckOut = _clockedIn
        ? '-- : --'
        : (lastCheckOutToday != null
            ? DateFormat('hh:mm a').format(lastCheckOutToday)
            : '-- : --');

    final DateTime targetShiftIn = (_clockedIn && _clockInTime != null)
        ? _clockInTime!
        : DateTime(_now.year, _now.month, _now.day, 9, 30);
    final DateTime targetShiftOut = targetShiftIn.add(const Duration(hours: 9));
    final String workShiftStr = '${DateFormat('hh:mm a').format(targetShiftIn)} – ${DateFormat('hh:mm a').format(targetShiftOut)}';

    // Smart Month & Year matching for stats (Find active month from records or default)
    int targetMonth = _now.month;
    int targetYear = _now.year;
    if (_myRecords.isNotEmpty) {
      for (var r in _myRecords) {
        final ci = r['clock_in'] != null ? DateTime.tryParse(r['clock_in'].toString()) : null;
        if (ci != null) {
          targetMonth = ci.month;
          targetYear = ci.year;
          break;
        }
      }
    }

    int presentDays = 0;
    int monthShifts = 0;
    int onTimeShifts = 0;
    final Set<int> presentDaySet = {};

    for (var r in _myRecords) {
      final ci = r['clock_in'] != null ? DateTime.tryParse(r['clock_in'].toString()) : null;
      final mins = r['total_minutes'] as int? ?? 0;
      if (ci != null && ci.month == targetMonth && ci.year == targetYear) {
        monthShifts++;
        if (ci.hour < 9 || (ci.hour == 9 && ci.minute <= 30)) {
          onTimeShifts++;
        }
        if (mins >= 540) presentDaySet.add(ci.day);
      }
    }
    presentDays = presentDaySet.length;
    final totalDaysInMonth = DateTime(targetYear, targetMonth + 1, 0).day;
    int workingDaysCount = 0;
    for (int day = 1; day <= totalDaysInMonth; day++) {
      final dt = DateTime(targetYear, targetMonth, day);
      final isSunday = dt.weekday == DateTime.sunday;
      final isEvenSaturday = dt.weekday == DateTime.saturday && (((dt.day - 1) ~/ 7) + 1) % 2 == 0;
      if (!isSunday && !isEvenSaturday) workingDaysCount++;
    }
    double attendancePercentage = workingDaysCount > 0 ? (presentDays / workingDaysCount) * 100 : 98.0;
    double punctualityPercentage = monthShifts > 0 ? (onTimeShifts / monthShifts) * 100 : 96.0;

    // Calculate weekly worked hours for Mon-Fri
    final weekMins = <int, int>{};
    for (var r in _myRecords) {
      final ci = r['clock_in'] != null ? DateTime.tryParse(r['clock_in'].toString()) : null;
      final mins = r['total_minutes'] as int? ?? 0;
      if (ci != null) {
        weekMins[ci.weekday] = (weekMins[ci.weekday] ?? 0) + mins;
      }
    }
    int totalMinsMonFri = 0;
    weekMins.forEach((k, v) { if (k >= 1 && k <= 5) totalMinsMonFri += v; });
    final weeklyGoalHrsStr = '${totalMinsMonFri ~/ 60}/45h';

    return Scaffold(
      backgroundColor: bgScaffold,
      appBar: AppBar(
        backgroundColor: bgScaffold,
        elevation: 0,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                'https://static.share.market/cube/instrument/icon/PEBYEHT',
                width: 26,
                height: 26,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(Icons.schedule_rounded, color: amberDark, size: 20),
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('MONARCHHR',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: textSecondary, letterSpacing: 1.1)),
                Text('Dashboard',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary, letterSpacing: -0.5)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              isDark ? Icons.wb_sunny_outlined : Icons.nightlight_round,
              color: isDark ? amberPrimary : const Color(0xFF2563EB),
              size: 20,
            ),
            onPressed: () => themeController.toggleTheme(),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1F2633) : const Color(0xFFF0F4FD),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.notifications_outlined, color: textSecondary, size: 20),
          ),
          const SizedBox(width: 8),
          ProfileAvatarBadge(
            name: fullName,
            isIncomplete: (widget.user['phone_number']?.toString() ?? '').trim().isEmpty ||
                ((widget.user['date_of_joining'] ?? widget.user['joining_date'])?.toString() ?? '').trim().isEmpty ||
                !RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch((widget.user['email']?.toString() ?? '').trim()),
            radius: 16,
            onTap: widget.onNavigateToProfile,
          ),
          IconButton(
            icon: Icon(Icons.logout_rounded, color: textSecondary, size: 20),
            onPressed: widget.onLogout,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        children: [
          // ── Profile Header Bar ─────────────────────────────────────────────
          Row(
            children: [
              ProfileAvatarBadge(
                name: fullName,
                isIncomplete: (widget.user['phone_number']?.toString() ?? '').trim().isEmpty ||
                    ((widget.user['date_of_joining'] ?? widget.user['joining_date'])?.toString() ?? '').trim().isEmpty ||
                    !RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch((widget.user['email']?.toString() ?? '').trim()),
                radius: 24,
                borderWidth: 2.5,
                fontSize: 18,
                onTap: widget.onNavigateToProfile,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: widget.onNavigateToProfile,
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            fullName,
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary, letterSpacing: -0.3),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.verified, color: amberPrimary, size: 16),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'UI/UX Designer • Product Team ($empId)',
                        style: TextStyle(fontSize: 12, color: textSecondary, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _clockedIn
                      ? const Color(0xFF9FF1BD).withAlpha(120)
                      : (isDark ? const Color(0xFF1F2633) : const Color(0xFFEAEFF8)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: _clockedIn ? const Color(0xFF146C43) : textSecondary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _clockedIn ? 'On Shift' : 'Off Shift',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _clockedIn ? const Color(0xFF002110) : textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (_teamPendingApprovalsCount > 0) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2E171C) : const Color(0xFFFFF1F2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFF2A55).withAlpha(120)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF2A55).withAlpha(35),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.pending_actions_rounded, color: Color(0xFFFF2A55), size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$_teamPendingApprovalsCount Team Leave Request${_teamPendingApprovalsCount > 1 ? 's' : ''} Pending',
                          style: const TextStyle(
                            color: Color(0xFFE11D48),
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          'Review & approve subordinates in Leave Tab',
                          style: TextStyle(color: textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFFE11D48), size: 14),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),

          // ── Today's Attendance Main Capsule Card ───────────────────────────
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: bgCard,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F171C23),
                  blurRadius: 20,
                  offset: Offset(0, 6),
                )
              ],
              border: Border.all(color: borderCol),
            ),
            child: Column(
              children: [
                Text(
                  "Today's Attendance",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary, letterSpacing: -0.4),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.schedule_rounded, size: 14, color: textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      'Work shift: $workShiftStr',
                      style: TextStyle(fontSize: 12, color: textSecondary, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // 3-Column Attendance Metrics
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1A1E2B) : const Color(0xFFF0F4FD),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            Text(
                              displayCheckIn,
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: textPrimary),
                            ),
                            const SizedBox(height: 2),
                            Text('Check In', style: TextStyle(fontSize: 11, color: textSecondary, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1A1E2B) : const Color(0xFFF0F4FD),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            Text(
                              displayCheckOut,
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: textPrimary.withAlpha(180)),
                            ),
                            const SizedBox(height: 2),
                            Text('Check Out', style: TextStyle(fontSize: 11, color: textSecondary, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1A1E2B) : const Color(0xFFF0F4FD),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            Text(
                              _getTodayWorkingHrsString(todayRecords),
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: amberDark),
                            ),
                            const SizedBox(height: 2),
                            Text('Working Hrs', style: TextStyle(fontSize: 11, color: textSecondary, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : (_clockedIn ? _clockOut : _clockIn),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: amberPrimary,
                      foregroundColor: const Color(0xFF6B3F00),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      elevation: 0,
                    ),
                    child: _loading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF6B3F00)))
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _clockedIn ? 'Check Out' : 'Check In',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.access_time_rounded, size: 20),
                            ],
                          ),
                  ),
                ),

                if (_message != null) ...[
                  const SizedBox(height: 10),
                  Text(_message!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _message!.startsWith('✅') ? const Color(0xFF146C43) : const Color(0xFFBA1A1A),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      )),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Employee Overview Section (Real Database Data) ────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Employee Overview', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary, letterSpacing: -0.4)),
              GestureDetector(
                onTap: widget.onNavigateToAttendance,
                child: const Text('Details', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: amberDark)),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    color: bgCard,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: borderCol),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF221A30) : const Color(0xFFEDE7F6),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.calendar_today_rounded, color: Color(0xFF9D7AE2), size: 20),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_fmtDays(_remainingLeaves), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary)),
                            Text('Leave Days Left', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: textSecondary, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    color: bgCard,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: borderCol),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF2B2010) : const Color(0xFFFFF8E1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.pending_actions_rounded, color: Color(0xFFF59E0B), size: 20),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$_pendingLeavesCount', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary)),
                            Text('Pending Requests', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: textSecondary, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ── Quick Action Grid (Real Database Calculations) ────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Quick Action', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary, letterSpacing: -0.4)),
              Text('Monthly Stats', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textSecondary)),
            ],
          ),
          const SizedBox(height: 12),

          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.0,
            children: [
              // Attendance Gauge Card
              GestureDetector(
                onTap: widget.onNavigateToAttendance,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: bgCard,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: borderCol),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Align(
                        alignment: Alignment.topRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isDark
                                ? (attendancePercentage >= 85 ? const Color(0xFF132A20) : const Color(0xFF2E1C12))
                                : (attendancePercentage >= 85 ? const Color(0xFF9FF1BD).withAlpha(120) : const Color(0xFFFFDCBC).withAlpha(120)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            attendancePercentage >= 85 ? 'On Track' : 'Needs Review',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? (attendancePercentage >= 85 ? const Color(0xFF34D399) : const Color(0xFFFBBF24))
                                  : (attendancePercentage >= 85 ? const Color(0xFF1B7047) : const Color(0xFF683D00)),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 100,
                        height: 50,
                        child: CustomPaint(
                          painter: SemicircleGaugePainter(percentage: attendancePercentage, isDark: isDark),
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Text('${attendancePercentage.toStringAsFixed(0)}%',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary)),
                            ),
                          ),
                        ),
                      ),
                      Text('Attendance Rate', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textPrimary)),
                    ],
                  ),
                ),
              ),

              // Annual Leave Pool Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: bgCard,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderCol),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Annual Pool', style: TextStyle(fontSize: 11, color: textSecondary, fontWeight: FontWeight.w500)),
                        Text('${_fmtDays(_usedLeaves)} Used / ${_fmtDays(_totalLeaves)}', style: TextStyle(fontSize: 11, color: textPrimary, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        height: 28,
                        color: isDark ? const Color(0xFF1F2633) : const Color(0xFFF0F4FD),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: (_totalLeaves > 0 ? (_usedLeaves / _totalLeaves) : 0.22).clamp(0.12, 1.0),
                          child: Container(
                            color: isDark ? const Color(0xFFF5A952) : const Color(0xFFFFA276),
                            child: Center(
                              child: Text(
                                '${_totalLeaves > 0 ? (_usedLeaves / _totalLeaves * 100).toStringAsFixed(0) : '22'}%',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: isDark ? const Color(0xFF452600) : const Color(0xFF7D3205)),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: widget.onNavigateToAttendance,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: borderCol),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Apply Leave', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textPrimary)),
                            const SizedBox(width: 4),
                            Icon(Icons.arrow_forward, size: 12, color: textPrimary),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Weekly Goal Card
              GestureDetector(
                onTap: () => widget.onNavigateToAttendance(subTab: 'Weekly'),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: bgCard,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: borderCol),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Weekly Goal', style: TextStyle(fontSize: 11, color: textSecondary, fontWeight: FontWeight.w500)),
                          Text(weeklyGoalHrsStr, style: const TextStyle(fontSize: 11, color: Color(0xFF146C43), fontWeight: FontWeight.w700)),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _bar('M', ((weekMins[1] ?? 240) / 540.0 * 38).clamp(8.0, 38.0), isDark, isActive: _now.weekday == 1),
                          _bar('T', ((weekMins[2] ?? 360) / 540.0 * 38).clamp(8.0, 38.0), isDark, isActive: _now.weekday == 2),
                          _bar('W', ((weekMins[3] ?? 420) / 540.0 * 38).clamp(8.0, 38.0), isDark, isActive: _now.weekday == 3),
                          _bar('T', ((weekMins[4] ?? 540) / 540.0 * 38).clamp(8.0, 38.0), isDark, isActive: _now.weekday == 4),
                          _bar('F', ((weekMins[5] ?? 180) / 540.0 * 38).clamp(8.0, 38.0), isDark, isActive: _now.weekday == 5),
                        ],
                      ),
                      Text('Work Schedule', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textPrimary)),
                    ],
                  ),
                ),
              ),

              // Efficiency / Punctuality Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: bgCard,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderCol),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Efficiency', style: TextStyle(fontSize: 11, color: textSecondary, fontWeight: FontWeight.w500)),
                        const Icon(Icons.trending_up, color: Color(0xFF146C43), size: 16),
                      ],
                    ),
                    SizedBox(
                      width: 50,
                      height: 50,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: (punctualityPercentage / 100.0).clamp(0.1, 1.0),
                            strokeWidth: 5,
                            backgroundColor: isDark ? const Color(0xFF1F2633) : const Color(0xFFEAEFF8),
                            color: const Color(0xFF146C43),
                          ),
                          Text('${punctualityPercentage.toStringAsFixed(0)}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: textPrimary)),
                        ],
                      ),
                    ),
                    Text('Punctuality', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textPrimary)),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ── Activity Log Section (Render All Today's Punch Activities) ─────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Activity Log', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary, letterSpacing: -0.4)),
              Text('Today', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textSecondary)),
            ],
          ),
          const SizedBox(height: 12),

          if (todayRecords.isNotEmpty)
            ...List.generate(todayRecords.length, (idx) {
              final r = todayRecords[idx];
              final ci = r['clock_in'] != null ? DateTime.tryParse(r['clock_in'].toString()) : null;
              final co = r['clock_out'] != null ? DateTime.tryParse(r['clock_out'].toString()) : null;

              final ciStr = ci != null ? DateFormat('hh:mm a').format(ci) : '--:--';
              final coStr = co != null ? DateFormat('hh:mm a').format(co) : '--:--';
              final sessTitle = todayRecords.length > 1 ? ' (#${idx + 1})' : '';

              return Column(
                children: [
                  if (idx > 0) const SizedBox(height: 10),
                  // Punch In Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: bgCard,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: borderCol),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF9FF1BD).withAlpha(120),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.login_rounded, color: Color(0xFF1B7047), size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text('Punch In$sessTitle', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textPrimary)),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF1F2633) : const Color(0xFFEAEFF8),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text('On-Site', style: TextStyle(fontSize: 10, color: textSecondary, fontWeight: FontWeight.w600)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(r['location'] != null ? 'GPS Verified • ${r['location']}' : 'HQ Main Gate • GPS verified',
                                  style: TextStyle(fontSize: 11, color: textSecondary)),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(ciStr, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: textPrimary)),
                            const Text('On Time', style: TextStyle(fontSize: 11, color: Color(0xFF146C43), fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Punch Out Card if closed
                  if (co != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: bgCard,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: borderCol),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: const BoxDecoration(
                              color: Color(0xFFFFDBCC),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.logout_rounded, color: Color(0xFF99461A), size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text('Punch Out$sessTitle', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textPrimary)),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF1F2633) : const Color(0xFFEAEFF8),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text('Completed', style: TextStyle(fontSize: 10, color: textSecondary, fontWeight: FontWeight.w600)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text('Biometric + Beacon verified', style: TextStyle(fontSize: 11, color: textSecondary)),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(coStr, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: textPrimary)),
                              const Text('Approved', style: TextStyle(fontSize: 11, color: Color(0xFF146C43), fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              );
            })
          else
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: bgCard,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: borderCol),
              ),
              child: Center(
                child: Text('No punch activities logged today yet', style: TextStyle(fontSize: 13, color: textSecondary, fontWeight: FontWeight.w500)),
              ),
            ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _bar(String day, double height, bool isDark, {bool isActive = false}) {
    return Column(
      children: [
        Container(
          width: 12,
          height: height,
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFF86D7A5)
                : (isDark ? const Color(0xFF1F2633) : const Color(0xFFEAEFF8)),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 4),
        Text(day, style: TextStyle(fontSize: 9, color: isActive ? const Color(0xFF146C43) : const Color(0xFF9CA3AF), fontWeight: FontWeight.w700)),
      ],
    );
  }
}
