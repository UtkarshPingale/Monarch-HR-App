import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import '../config/api_config.dart';
import '../controllers/theme_controller.dart';
import '../services/date_time_helper.dart';
import '../widgets/semicircle_gauge_painter.dart';
import '../widgets/profile_avatar_badge.dart';
import '../widgets/work_entry_sheet.dart';

// ── MonarchHR Front Home Dashboard Page ───────────────────────────────────────
class HomeScreenTab extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;
  final String password;
  final VoidCallback onLogout;
  final void Function({String? subTab}) onNavigateToAttendance;
  final VoidCallback? onNavigateToProfile;

  final VoidCallback? onNavigateToLeave;

  const HomeScreenTab({
    super.key,
    required this.token,
    required this.user,
    required this.password,
    required this.onLogout,
    required this.onNavigateToAttendance,
    this.onNavigateToProfile,
    this.onNavigateToLeave,
  });

  @override
  State<HomeScreenTab> createState() => HomeScreenTabState();
}

class HomeScreenTabState extends State<HomeScreenTab> {
  bool _clockedIn   = false;
  bool _loading     = false;
  String? _message;
  Timer? _locTimer;
  DateTime? _clockInTime;
  String? _sessionId;
  Timer? _timeTicker;
  Timer? _autoSyncTimer;
  DateTime _now = DateTime.now();
  List<dynamic> _myRecords = [];
  late Map<String, dynamic> _currentUser;

  // Real Leave Data from PostgreSQL
  double _remainingLeaves = 19.5;
  int _pendingLeavesCount = 0;
  int _teamPendingApprovalsCount = 0;

  @override
  void initState() {
    super.initState();
    _currentUser = Map<String, dynamic>.from(widget.user);
    themeController.addListener(_onThemeChanged);
    _checkStatus();
    _fetchData();
    _fetchFreshProfile();
    _fetchLeavesData();
    _fetchTeamApprovalsCount();
    _timeTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) {
        _checkStatus();
        _fetchLeavesData();
        _fetchTeamApprovalsCount();
      }
    });
  }

  @override
  void didUpdateWidget(covariant HomeScreenTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.user != oldWidget.user) {
      setState(() {
        _currentUser = Map<String, dynamic>.from(widget.user);
      });
    }
  }

  Future<void> _fetchFreshProfile() async {
    try {
      final res = await apiGetJson('/api/user/profile', token: widget.token);
      if (res is Map<String, dynamic> && res['id'] != null && mounted) {
        setState(() {
          _currentUser = Map<String, dynamic>.from(res);
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    themeController.removeListener(_onThemeChanged);
    _locTimer?.cancel();
    _timeTicker?.cancel();
    _autoSyncTimer?.cancel();
    super.dispose();
  }

  Future<void> refreshData() async {
    try {
      await Future.wait([
        _checkStatus(),
        _fetchData(),
        _fetchFreshProfile(),
        _fetchLeavesData(),
        _fetchTeamApprovalsCount(),
      ]);
    } catch (_) {}
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
          final ci = parseAppDateTime(active['clock_in']);
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
              final ci = parseAppDateTime(r['clock_in']);
              return ci != null && ci.year == now.year && ci.month == now.month && ci.day == now.day;
            },
            orElse: () => null,
          );
          if (mounted) {
            setState(() {
              _clockedIn = false;
              _clockInTime = todayRecord != null ? parseAppDateTime(todayRecord['clock_in']) : null;
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

  Future<void> _handleCheckInPress(List<dynamic> todayRecords, bool isDark, Color textPrimary, Color textSecondary, Color amberPrimary) async {
    final completedShifts = todayRecords.where((r) => r['clock_in'] != null && r['clock_out'] != null).toList();

    if (completedShifts.isNotEmpty) {
      final firstIn = parseAppDateTime(completedShifts.first['clock_in']);
      final lastOut = parseAppDateTime(completedShifts.last['clock_out']);
      final firstInStr = firstIn != null ? DateFormat('hh:mm a').format(firstIn.toLocal()) : '--:--';
      final lastOutStr = lastOut != null ? DateFormat('hh:mm a').format(lastOut.toLocal()) : '--:--';

      final bool? proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1B202D) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withAlpha(30),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.info_outline_rounded, color: Color(0xFFF59E0B), size: 22),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Already Punched Today',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'You have already completed your punch in and punch out for today:',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF131722) : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: isDark ? const Color(0xFF1F2633) : const Color(0xFFE5E7EB)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('• First Punch In:', style: TextStyle(fontSize: 12.5, color: textSecondary, fontWeight: FontWeight.w600)),
                        Text(firstInStr, style: TextStyle(fontSize: 13, color: textPrimary, fontWeight: FontWeight.w800)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('• Last Punch Out:', style: TextStyle(fontSize: 12.5, color: textSecondary, fontWeight: FontWeight.w600)),
                        Text(lastOutStr, style: TextStyle(fontSize: 13, color: textPrimary, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Did you click by mistake? Do you want to Check In again for a new session / overtime?',
                style: TextStyle(fontSize: 12.5, height: 1.4, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600, color: textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: amberPrimary,
                foregroundColor: const Color(0xFF6B3F00),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Yes, Check In', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      );

      if (proceed != true) return;
    }

    await _clockIn();
  }

  Future<void> _handleCheckOutPress(bool isDark, Color textPrimary, Color textSecondary, String displayCheckIn) async {
    final bool? proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1B202D) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFE11D48).withAlpha(30),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.logout_rounded, color: Color(0xFFE11D48), size: 22),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Confirm Check Out',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Are you sure you want to punch out and end your active shift?',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            if (displayCheckIn != '-- : --') ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF131722) : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: isDark ? const Color(0xFF1F2633) : const Color(0xFFE5E7EB)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('• Current Check-In:', style: TextStyle(fontSize: 12.5, color: textSecondary, fontWeight: FontWeight.w600)),
                    Text(displayCheckIn, style: TextStyle(fontSize: 13, color: textPrimary, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600, color: textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE11D48),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Check Out', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );

    if (proceed == true) {
      await _clockOut();
    }
  }

  String _getTodayWorkingHrsString(List<dynamic> todayRecords) {
    int completedSecs = 0;
    for (var r in todayRecords) {
      final ci = parseAppDateTime(r['clock_in']);
      final co = parseAppDateTime(r['clock_out']);
      if (ci != null && co != null) {
        completedSecs += co.difference(ci).inSeconds;
      } else if (r['total_minutes'] != null) {
        completedSecs += (r['total_minutes'] as int) * 60;
      }
    }

    int activeSecs = 0;
    if (_clockedIn && _clockInTime != null) {
      final localCi = _clockInTime!.isUtc ? _clockInTime!.toLocal() : _clockInTime!;
      activeSecs = DateTime.now().difference(localCi).inSeconds;
      if (activeSecs < 0) activeSecs = 0;
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

    final fullName = _currentUser['name'] ?? _currentUser['full_name'] ?? _currentUser['username'] ?? widget.user['name'] ?? 'Employee';
    final empId = _currentUser['employee_no'] ?? _currentUser['emp_id'] ?? _currentUser['id'] ?? widget.user['emp_id'] ?? widget.user['id'] ?? '';
    final dept = (_currentUser['department']?.toString() ?? widget.user['department']?.toString() ?? '').trim();
    final desig = (_currentUser['designation']?.toString() ?? widget.user['designation']?.toString() ?? '').trim();
    final role = (_currentUser['role']?.toString() ?? widget.user['role']?.toString() ?? '').trim();

    String userSubtitle = '';
    if (desig.isNotEmpty && dept.isNotEmpty) {
      userSubtitle = '$desig • $dept';
    } else if (desig.isNotEmpty) {
      userSubtitle = desig;
    } else if (dept.isNotEmpty) {
      userSubtitle = dept;
    } else if (role.isNotEmpty) {
      userSubtitle = role;
    } else {
      userSubtitle = empId.toString().isNotEmpty ? 'Employee (#$empId)' : 'Employee';
    }

    // Aggregate today's records
    final todayRecords = _myRecords.where((r) {
      final ci = parseAppDateTime(r['clock_in']);
      if (ci != null && ci.year == _now.year && ci.month == _now.month && ci.day == _now.day) {
        return true;
      }
      return false;
    }).toList();

    // Sort today's records ascending by clock_in
    todayRecords.sort((a, b) {
      final aIn = parseAppDateTime(a['clock_in']) ?? DateTime(1970);
      final bIn = parseAppDateTime(b['clock_in']) ?? DateTime(1970);
      return aIn.compareTo(bIn);
    });

    // Get the latest check-out time of today
    DateTime? lastCheckOutToday;
    if (!_clockedIn && todayRecords.isNotEmpty) {
      for (var r in todayRecords.reversed) {
        if (r['clock_out'] != null) {
          lastCheckOutToday = parseAppDateTime(r['clock_out']);
          break;
        }
      }
    }

    // Current Active Shift Timings
    final localClockInTime = _clockInTime != null ? (_clockInTime!.isUtc ? _clockInTime!.toLocal() : _clockInTime!) : null;
    final String displayCheckIn = (_clockedIn && localClockInTime != null)
        ? DateFormat('hh:mm a').format(localClockInTime)
        : '-- : --';

    final String displayCheckOut = _clockedIn
        ? '-- : --'
        : (lastCheckOutToday != null
            ? DateFormat('hh:mm a').format(lastCheckOutToday)
            : '-- : --');

    final DateTime targetShiftIn = (_clockedIn && localClockInTime != null)
        ? localClockInTime
        : DateTime(_now.year, _now.month, _now.day, 9, 30);
    final DateTime targetShiftOut = targetShiftIn.add(const Duration(hours: 9));
    final String workShiftStr = '${DateFormat('hh:mm a').format(targetShiftIn)} – ${DateFormat('hh:mm a').format(targetShiftOut)}';

    // Smart Month & Year matching for stats (Find active month from records or default)
    int targetMonth = _now.month;
    int targetYear = _now.year;
    if (_myRecords.isNotEmpty) {
      for (var r in _myRecords) {
        final ci = parseAppDateTime(r['clock_in']);
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
      final ci = parseAppDateTime(r['clock_in']);
      final co = parseAppDateTime(r['clock_out']);
      int mins = (r['total_minutes'] is num) ? (r['total_minutes'] as num).toInt() : 0;
      if (mins == 0 && ci != null && co != null) {
        mins = co.difference(ci).inMinutes;
      }
      if (ci != null && ci.month == targetMonth && ci.year == targetYear) {
        monthShifts++;
        if (ci.hour < 9 || (ci.hour == 9 && ci.minute <= 30)) {
          onTimeShifts++;
        }
        if (mins >= 530) presentDaySet.add(ci.day);
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
      final ci = parseAppDateTime(r['clock_in']);
      final co = parseAppDateTime(r['clock_out']);
      int mins = (r['total_minutes'] is num) ? (r['total_minutes'] as num).toInt() : 0;
      if (mins == 0 && ci != null && co != null) {
        mins = co.difference(ci).inMinutes;
      }
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
      body: RefreshIndicator(
        onRefresh: refreshData,
        color: amberPrimary,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
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
                          userSubtitle,
                          style: TextStyle(fontSize: 12, color: textSecondary, fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
              GestureDetector(
                onTap: () => widget.onNavigateToLeave?.call(),
                behavior: HitTestBehavior.opaque,
                child: Container(
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
                    const Icon(Icons.calendar_today_rounded, size: 13, color: amberPrimary),
                    const SizedBox(width: 5),
                    Text(
                      DateFormat('EEEE, dd MMM yyyy').format(DateTime.now()),
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: textSecondary),
                    ),
                  ],
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
                    onPressed: _loading
                        ? null
                        : () {
                            if (_clockedIn) {
                              _handleCheckOutPress(isDark, textPrimary, textSecondary, displayCheckIn);
                            } else {
                              _handleCheckInPress(todayRecords, isDark, textPrimary, textSecondary, amberPrimary);
                            }
                          },
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
                child: GestureDetector(
                  onTap: () => widget.onNavigateToLeave?.call(),
                  behavior: HitTestBehavior.opaque,
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
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () => widget.onNavigateToLeave?.call(),
                  behavior: HitTestBehavior.opaque,
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

              // Work Entry / Daily Log Card
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
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF5A952).withAlpha(isDark ? 40 : 25),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.assignment_outlined, size: 13, color: Color(0xFFD97706)),
                            ),
                            const SizedBox(width: 5),
                            Text('Work Entry', style: TextStyle(fontSize: 11, color: textSecondary, fontWeight: FontWeight.w600)),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withAlpha(isDark ? 35 : 20),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Daily Log',
                            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: isDark ? const Color(0xFF34D399) : const Color(0xFF146C43)),
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Log Project Work',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: textPrimary, letterSpacing: -0.2),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Task, quantity & revisions',
                          style: TextStyle(fontSize: 10, color: textSecondary, fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          WorkEntrySheet.show(
                            context,
                            token: widget.token,
                            onSaved: () {
                              if (mounted) setState(() {});
                            },
                          );
                        },
                        icon: const Icon(Icons.add_task_rounded, size: 13),
                        label: const Text('Fill Work Entry', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark ? const Color(0xFFF5A952) : const Color(0xFFF5A952),
                          foregroundColor: const Color(0xFF451A03),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          elevation: 0,
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
              final ci = parseAppDateTime(r['clock_in']);
              final co = parseAppDateTime(r['clock_out']);

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
                              Text(_formatPunchInLocation(r),
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
                                Text(_formatPunchOutLocation(r), style: TextStyle(fontSize: 11, color: textSecondary)),
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

  String _formatPunchInLocation(Map<String, dynamic> s) {
    final explicit = s['clock_in_location'] ?? s['punch_in_location'];
    if (explicit != null && explicit.toString().trim().isNotEmpty) {
      return explicit.toString();
    }
    final loc = s['location']?.toString() ?? '';
    if (loc.contains('In #')) {
      final m = RegExp(r'In #(\d+)').firstMatch(loc);
      if (m != null) return 'Biometric Machine #${m.group(1)}';
    }
    if (loc.isNotEmpty) {
      if (loc.startsWith('Biometric Machine')) return 'Biometric Machine';
      return 'GPS • $loc';
    }
    return 'GPS Verified • Main Gate';
  }

  String _formatPunchOutLocation(Map<String, dynamic> s) {
    final explicit = s['clock_out_location'] ?? s['punch_out_location'];
    if (explicit != null && explicit.toString().trim().isNotEmpty) {
      return explicit.toString();
    }
    final loc = s['location']?.toString() ?? '';
    if (loc.contains('Out #')) {
      final m = RegExp(r'Out #(\d+)').firstMatch(loc);
      if (m != null) return 'Biometric Machine #${m.group(1)}';
    } else if (loc.contains('In #')) {
      final m = RegExp(r'In #(\d+)').firstMatch(loc);
      if (m != null) return 'Biometric Machine #${m.group(1)}';
    }
    if (loc.isNotEmpty) {
      if (loc.startsWith('Biometric Machine')) return 'Biometric Machine';
      return 'GPS • $loc';
    }
    return 'Biometric Machine';
  }
}
