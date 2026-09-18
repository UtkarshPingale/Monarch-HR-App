import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/api_config.dart';
import '../controllers/theme_controller.dart';
import '../widgets/percentage_donut_painter.dart';
import '../widgets/profile_avatar_badge.dart';

// ── Tab 2: MonarchHR Attendance History Screen ────────────────────────────────
class AttendanceInfoTab extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;
  final VoidCallback? onNavigateToProfile;

  const AttendanceInfoTab({
    super.key,
    required this.token,
    required this.user,
    this.onNavigateToProfile,
  });

  @override
  State<AttendanceInfoTab> createState() => AttendanceInfoTabState();
}

class AttendanceInfoTabState extends State<AttendanceInfoTab> {
  List<dynamic> _attendanceRecords = [];
  List<dynamic> _holidays = [];
  List<dynamic> _userLeaves = [];
  List<dynamic> _teamPunchRequests = [];
  bool _loading = true;
  bool _loadingPunchRequests = false;
  bool _actionInProgress = false;
  int _mainTabSegment = 0; // 0 = My Attendance, 1 = Punch Approvals
  String _activeSubTab = 'Day wise'; // 'Day wise', 'Weekly', 'Overview'
  DateTime _selectedMonth = DateTime.now();
  int? _viewingDetailDay; // Null = show calendar, DayNumber = show detail view
  double _remainingDays = 18.0;

  final TextEditingController _leaveTitleCtrl = TextEditingController();
  final TextEditingController _leaveNoteCtrl = TextEditingController();

  DateTime? _getJoiningDate() {
    final joinDateStr = (widget.user['date_of_joining'] ?? widget.user['joining_date'])?.toString();
    if (joinDateStr == null || joinDateStr.trim().isEmpty) return null;
    try {
      return DateTime.parse(joinDateStr.trim().split('T')[0]);
    } catch (_) {
      return null;
    }
  }

  bool get _isLeaderOrManager {
    final role = (widget.user['role'] ?? '').toString().toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
    return role == 'teamleader' || role == 'subteamlead' || role == 'seniorteamlead' || role == 'manager' || role == 'projectmanager' || role == 'admin' || role == 'hr';
  }

  void setSubTab(String tabName) {
    setState(() {
      _activeSubTab = tabName;
      _viewingDetailDay = null;
    });
  }

  bool handleBackPress() {
    if (_mainTabSegment == 1) {
      setState(() => _mainTabSegment = 0);
      return true;
    }
    if (_viewingDetailDay != null) {
      setState(() => _viewingDetailDay = null);
      return true;
    }
    if (_activeSubTab != 'Day wise') {
      setState(() => _activeSubTab = 'Day wise');
      return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    themeController.addListener(_onThemeChanged);
    _loadData();
  }

  @override
  void dispose() {
    themeController.removeListener(_onThemeChanged);
    _leaveTitleCtrl.dispose();
    _leaveNoteCtrl.dispose();
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadData() async {
    try {
      final list = await apiGet('/api/attendance/me', token: widget.token).timeout(const Duration(seconds: 4));
      final holidays = await apiGet('/api/holidays').timeout(const Duration(seconds: 4));
      final leavesRes = await apiGetJson('/api/leaves/me', token: widget.token).timeout(const Duration(seconds: 4));

      if (_isLeaderOrManager) {
        _loadPunchRequests();
      }

      if (mounted) {
        setState(() {
          _attendanceRecords = list;
          _holidays = holidays;
          _userLeaves = (leavesRes is Map && leavesRes['leaves'] is List) ? leavesRes['leaves'] : [];
          if (leavesRes is Map && leavesRes['remaining_days'] != null) {
            _remainingDays = double.tryParse(leavesRes['remaining_days'].toString()) ?? 18.0;
          }
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadPunchRequests() async {
    if (!mounted) return;
    setState(() => _loadingPunchRequests = true);
    try {
      final res = await apiGetJson('/api/team/punch-requests', token: widget.token);
      if (res is Map && res['punch_requests'] is List) {
        if (mounted) {
          setState(() {
            _teamPunchRequests = res['punch_requests'];
            _loadingPunchRequests = false;
          });
        }
      } else {
        if (mounted) setState(() => _loadingPunchRequests = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingPunchRequests = false);
    }
  }

  Future<void> _actionPunchRequest(int attendanceId, String action, {String? reason}) async {
    if (_actionInProgress) return;
    setState(() => _actionInProgress = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final payload = {
        'action': action,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      };
      final res = await apiPost('/api/team/punch-requests/$attendanceId/action', payload, token: widget.token);
      if (res['error'] != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Error: ${res['error']}'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(action == 'approve' ? '✅ Punch request approved successfully!' : '❌ Punch request rejected.'),
            backgroundColor: action == 'approve' ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
          ),
        );
        await _loadPunchRequests();
        await _loadData();
      }
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Failed to update punch request. Please check connection.')),
      );
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  void _showRejectPunchDialog(Map<String, dynamic> punch) {
    final isDark = themeController.isDarkMode;
    final dialogBg = isDark ? const Color(0xFF131722) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF171C23);
    final textSecondary = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF524437);
    final bgInput = isDark ? const Color(0xFF1A1E2B) : const Color(0xFFF0F4FD);
    final borderCol = isDark ? const Color(0xFF1F2633) : const Color(0xFFCBD5E1);

    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: borderCol)),
        title: Row(
          children: [
            const Icon(Icons.cancel_outlined, color: Color(0xFFF87171), size: 22),
            const SizedBox(width: 8),
            Text('Reject Punch Request', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textPrimary)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to reject the out-of-range punch for ${punch['name'] ?? 'Employee'}?',
              style: TextStyle(fontSize: 13, height: 1.4, color: textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              style: TextStyle(fontSize: 13, color: textPrimary),
              decoration: InputDecoration(
                filled: true,
                fillColor: bgInput,
                hintText: 'Reason for rejection (e.g. Unapproved remote location)',
                hintStyle: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderCol)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderCol)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFF5A952), width: 1.5)),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: textSecondary, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              final id = punch['id'];
              if (id != null) {
                _actionPunchRequest(id is int ? id : int.tryParse(id.toString()) ?? 0, 'reject', reason: reasonCtrl.text.trim());
              }
            },
            child: const Text('Reject Punch', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeController.isDarkMode;
    final bgScaffold = isDark ? const Color(0xFF0C0E14) : const Color(0xFFF8F9FF);
    final bgCard = isDark ? const Color(0xFF131722) : Colors.white;
    final bgInput = isDark ? const Color(0xFF1A1E2B) : const Color(0xFFF0F4FD);
    final borderCol = isDark ? const Color(0xFF1F2633) : const Color(0xFFEAEFF8);
    final textPrimary = isDark ? Colors.white : const Color(0xFF171C23);
    final textSecondary = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF524437);
    const amberPrimary = Color(0xFFF5A952);
    const amberDark = Color(0xFF895100);

    final rawName = widget.user['name'] ?? 'Robert Smith';

    // Calculate current week range (Sun 00:00:00 - next Sun 00:00:00)
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final sun = todayMidnight.subtract(Duration(days: todayMidnight.weekday % 7));
    final nextSun = sun.add(const Duration(days: 7));

    // Filter attendance records strictly for current week
    final currentWeekRecords = _attendanceRecords.where((r) {
      final ci = r['clock_in'] != null ? DateTime.tryParse(r['clock_in'].toString()) : null;
      if (ci != null && !ci.isBefore(sun) && ci.isBefore(nextSun)) {
        return true;
      }
      return false;
    }).toList();

    // Compute weekly total hours & overtime from current week records
    int totalMins = 0;
    int overtimeMins = 0;
    for (var r in currentWeekRecords) {
      final mins = r['total_minutes'] as int? ?? 0;
      totalMins += mins;
      if (mins > 540) {
        overtimeMins += (mins - 540);
      }
    }
    final totalHrsStr = '${(totalMins ~/ 60).toString().padLeft(2, '0')}:${(totalMins % 60).toString().padLeft(2, '0')}';
    final overtimeHrsStr = '${(overtimeMins ~/ 60).toString().padLeft(2, '0')}:${(overtimeMins % 60).toString().padLeft(2, '0')}';

    // Map daily minutes for current week (0: Sun, 1: Mon, ... 6: Sat)
    final Map<int, int> weekDailyMins = {};
    for (var r in currentWeekRecords) {
      final ci = r['clock_in'] != null ? DateTime.tryParse(r['clock_in'].toString()) : null;
      final mins = r['total_minutes'] as int? ?? 0;
      if (ci != null) {
        final dayIdx = ci.weekday % 7;
        weekDailyMins[dayIdx] = (weekDailyMins[dayIdx] ?? 0) + mins;
      }
    }

    // Set of holiday date keys YYYY-MM-DD
    final Set<String> holidayDates = {};
    for (var h in _holidays) {
      if (h['date'] != null) {
        holidayDates.add(h['date'].toString().split('T')[0]);
      }
    }

    // Find max worked day for tooltip
    int maxMins = 0;
    int maxDayIdx = -1;
    weekDailyMins.forEach((idx, mins) {
      if (mins > maxMins) {
        maxMins = mins;
        maxDayIdx = idx;
      }
    });

    return PopScope(
      canPop: _viewingDetailDay == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _viewingDetailDay != null) {
          setState(() => _viewingDetailDay = null);
        }
      },
      child: Scaffold(
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
                  Text('MONARCH HR',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: textSecondary, letterSpacing: 1.1)),
                  Text('Attendance History',
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
              name: rawName,
              isIncomplete: (widget.user['phone_number']?.toString() ?? '').trim().isEmpty ||
                  ((widget.user['date_of_joining'] ?? widget.user['joining_date'])?.toString() ?? '').trim().isEmpty ||
                  !RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch((widget.user['email']?.toString() ?? '').trim()),
              radius: 16,
              onTap: widget.onNavigateToProfile,
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                children: [
                  // ── Top Main Switcher for Team Leader & Manager (My Attendance vs Punch Approvals) ──
                  if (_isLeaderOrManager) ...[
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: bgInput,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: borderCol),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _mainTabSegment = 0),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: _mainTabSegment == 0 ? bgCard : Colors.transparent,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: _mainTabSegment == 0
                                      ? [
                                          BoxShadow(
                                            color: Colors.black.withAlpha(isDark ? 50 : 15),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          )
                                        ]
                                      : null,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.calendar_month_rounded,
                                      size: 16,
                                      color: _mainTabSegment == 0 ? amberDark : textSecondary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'My Attendance',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: _mainTabSegment == 0 ? textPrimary : textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() => _mainTabSegment = 1);
                                _loadPunchRequests();
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: _mainTabSegment == 1 ? bgCard : Colors.transparent,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: _mainTabSegment == 1
                                      ? [
                                          BoxShadow(
                                            color: Colors.black.withAlpha(isDark ? 50 : 15),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          )
                                        ]
                                      : null,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.how_to_reg_rounded,
                                      size: 16,
                                      color: _mainTabSegment == 1 ? amberDark : textSecondary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Punch Approvals',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: _mainTabSegment == 1 ? textPrimary : textSecondary,
                                      ),
                                    ),
                                    if (_teamPunchRequests.isNotEmpty) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFF2A55),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          '${_teamPunchRequests.length}',
                                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (_mainTabSegment == 1) ...[
                    _buildPunchApprovalsView(isDark, bgCard, bgInput, bgScaffold, borderCol, textPrimary, textSecondary, amberPrimary, amberDark),
                  ] else ...[
                    // ── Segmented Pill Toggle Switcher (Day wise, Weekly, Overview) ─────
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: bgCard,
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: borderCol),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x0A171C23),
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          )
                        ],
                      ),
                      child: Row(
                        children: [
                          _subTabPill('Day wise', Icons.calendar_today_rounded, amberPrimary, amberDark, isDark, textSecondary),
                          _subTabPill('Weekly', Icons.view_week_rounded, amberPrimary, amberDark, isDark, textSecondary),
                          _subTabPill('Overview', Icons.auto_graph_rounded, amberPrimary, amberDark, isDark, textSecondary),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                  // ── Tab View 1: Day Wise View ────────────────────────────────
                  if (_activeSubTab == 'Day wise') ...[
                    if (_viewingDetailDay == null)
                      _buildDayWiseView(bgCard, borderCol, textPrimary, textSecondary, holidayDates, now, isDark)
                    else
                      _buildDayDetailView(bgCard, bgInput, borderCol, textPrimary, textSecondary, amberPrimary, amberDark, isDark),
                  ],

                  // ── Tab View 2: Weekly View ──────────────────────────────────
                  if (_activeSubTab == 'Weekly') ...[
                    Container(
                      padding: const EdgeInsets.all(20),
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
                          // Top Stats Row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('TOTAL HOURS',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textSecondary, letterSpacing: 1.1)),
                                  const SizedBox(height: 2),
                                  RichText(
                                    text: TextSpan(
                                      style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: textPrimary),
                                      children: [
                                        TextSpan(text: totalHrsStr),
                                        TextSpan(
                                          text: ' hrs',
                                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('OVERTIME',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textSecondary, letterSpacing: 1.1)),
                                  const SizedBox(height: 2),
                                  RichText(
                                    text: TextSpan(
                                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF99461A)),
                                      children: [
                                        TextSpan(text: overtimeHrsStr),
                                        TextSpan(
                                          text: ' hrs',
                                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: textSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),

                          const SizedBox(height: 24),

                          // Weekly Bar Chart Container
                          SizedBox(
                            height: 180,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: ['10h', '08h', '06h', '04h', '02h', '00h'].map((label) {
                                    return Text(label,
                                        style: TextStyle(fontSize: 10, color: textSecondary, fontWeight: FontWeight.w600));
                                  }).toList(),
                                ),
                                const SizedBox(width: 12),

                                Expanded(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: List.generate(7, (idx) {
                                      final dayDate = sun.add(Duration(days: idx));
                                      final dayKey = DateFormat('yyyy-MM-dd').format(dayDate);
                                      final dayMins = weekDailyMins[idx] ?? 0;

                                      final dayName = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][idx];
                                      final isRegisteredHoliday = holidayDates.contains(dayKey);

                                      if (dayMins == 0 && isRegisteredHoliday) {
                                        return _holidayColumn(dayName);
                                      }

                                      double heightFactor = (dayMins / 600.0).clamp(0.08, 1.0);
                                      bool isMaxDay = (idx == maxDayIdx && dayMins > 0);
                                      String? tooltipText = isMaxDay ? '${dayMins ~/ 60}:${(dayMins % 60).toString().padLeft(2, '0')}h' : null;

                                      return _barColumn(
                                        dayName,
                                        heightFactor,
                                        isDark,
                                        isHighlighted: isMaxDay || dayMins > 540,
                                        tooltip: tooltipText,
                                      );
                                    }),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 16),
                          Divider(color: borderCol, height: 1),
                          const SizedBox(height: 12),

                          // Chart Legend Footer
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _legendPill('Regular', const Color(0xFFE8F8F0), const Color(0xFF146C43)),
                              const SizedBox(width: 12),
                              _legendPill('Overtime', const Color(0xFFFFDBCC), const Color(0xFF99461A)),
                              const SizedBox(width: 12),
                              _legendPill('Holiday', const Color(0xFFE0F2FE), const Color(0xFF0284C7)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildDailyShiftList(
                      bgCard,
                      borderCol,
                      textPrimary,
                      textSecondary,
                      records: currentWeekRecords,
                    ),
                  ],

                  // ── Tab View 3: Overview View ────────────────────────────────
                  if (_activeSubTab == 'Overview') ...[
                    _buildOverviewView(bgCard, borderCol, textPrimary, textSecondary, isDark, holidayDates),
                  ],
                ],

                const SizedBox(height: 20),
              ],
              ),
      ),
    );
  }

  Widget _subTabPill(String title, IconData icon, Color amberPrimary, Color amberDark, bool isDark, Color textSecondary) {
    final isSelected = _activeSubTab == title;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _activeSubTab = title;
          _viewingDetailDay = null; // Reset detail view on tab switch
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? amberPrimary : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: isSelected ? amberDark : textSecondary),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? amberDark : textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Month Calendar View for Day Wise (Seamless Table Style) ──────────────────
  Widget _buildDayWiseView(Color bgCard, Color borderCol, Color textPrimary, Color textSecondary, Set<String> holidayDates, DateTime now, bool isDark) {
    final daysInMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0).day;
    final firstDayOfMonth = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final offset = firstDayOfMonth.weekday % 7; // Sunday = 0
    final prevMonthDays = DateTime(_selectedMonth.year, _selectedMonth.month, 0).day;
    final todayMidnight = DateTime(now.year, now.month, now.day);

    final Set<String> attendanceDates = {};
    for (var r in _attendanceRecords) {
      if (r['clock_in'] != null) {
        final dStr = r['clock_in'].toString().split('T')[0];
        attendanceDates.add(dStr);
      } else if (r['date'] != null) {
        attendanceDates.add(r['date'].toString().split('T')[0]);
      }
    }

    final Set<String> leaveDates = {};
    for (var l in _userLeaves) {
      if (l['start_date'] != null) {
        final sStr = l['start_date'].toString().split('T')[0];
        final eStr = (l['end_date'] ?? l['start_date']).toString().split('T')[0];
        try {
          var s = DateTime.parse(sStr);
          var e = DateTime.parse(eStr);
          while (!s.isAfter(e)) {
            leaveDates.add(DateFormat('yyyy-MM-dd').format(s));
            s = s.add(const Duration(days: 1));
          }
        } catch (_) {
          leaveDates.add(sStr);
        }
      }
    }

    final gridBorderCol = isDark ? const Color(0xFF1F2633) : const Color(0xFFE2E8F0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderCol),
      ),
      child: Column(
        children: [
          // Header: Month Navigation & Days Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.chevron_left_rounded, color: textPrimary),
                    onPressed: () {
                      setState(() {
                        _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1, 1);
                      });
                    },
                  ),
                  Text(DateFormat('MMMM yyyy').format(_selectedMonth),
                      style: TextStyle(color: textPrimary, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                  IconButton(
                    icon: Icon(Icons.chevron_right_rounded, color: textPrimary),
                    onPressed: () {
                      setState(() {
                        _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1);
                      });
                    },
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1F2633) : const Color(0xFFF0F4FD),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text('$daysInMonth Days', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textSecondary)),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Legend Status Bar
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              _legendPill('Present (P)', isDark ? const Color(0xFF11221E) : const Color(0xFFE8F8F0), isDark ? const Color(0xFF34D399) : const Color(0xFF146C43)),
              _legendPill('Half (P:A/A:P)', isDark ? const Color(0xFF241C14) : const Color(0xFFFFF3E0), isDark ? const Color(0xFFFBA442) : const Color(0xFF895100)),
              _legendPill('Absent (A)', isDark ? const Color(0xFF2B1618) : const Color(0xFFFFDAD6), isDark ? const Color(0xFFF87171) : const Color(0xFFBA1A1A)),
              _legendPill('Leave', isDark ? const Color(0xFF26151B) : const Color(0xFFFDEBF3), isDark ? const Color(0xFFFB7185) : const Color(0xFFB91C68)),
              _legendPill('Holiday', isDark ? const Color(0xFF132235) : const Color(0xFFE6F4FB), isDark ? const Color(0xFF38BDF8) : const Color(0xFF0C7AA6)),
              _legendPill('Off', isDark ? const Color(0xFF161C28) : const Color(0xFFF0F3F8), isDark ? const Color(0xFF94A3B8) : textSecondary),
            ],
          ),
          const SizedBox(height: 16),

          // Days Header (Sun - Sat)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A1E2B) : const Color(0xFFF0F4FD),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].map((day) {
                return SizedBox(
                  width: 36,
                  child: Text(day,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: textSecondary, fontWeight: FontWeight.w700, fontSize: 12)),
                );
              }).toList(),
            ),
          ),

          // Seamless Flush Table Grid
          ClipRRect(
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: gridBorderCol, width: 0.5),
              ),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  childAspectRatio: 0.74,
                  crossAxisSpacing: 0,
                  mainAxisSpacing: 0,
                ),
                itemCount: offset + daysInMonth,
                itemBuilder: (context, index) {
                  if (index < offset) {
                    final prevDay = prevMonthDays - offset + index + 1;
                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF131722).withAlpha(80) : const Color(0xFFF8FAFC),
                        border: Border.all(color: gridBorderCol.withAlpha(40), width: 0.5),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('$prevDay',
                              style: TextStyle(color: textSecondary.withAlpha(80), fontWeight: FontWeight.w500, fontSize: 11)),
                        ],
                      ),
                    );
                  }

                  final day = index - offset + 1;
                  final dt = DateTime(_selectedMonth.year, _selectedMonth.month, day);
                  final dateKey = DateFormat('yyyy-MM-dd').format(dt);

                  final joinDate = _getJoiningDate();
                  final joinDateMidnight = joinDate != null ? DateTime(joinDate.year, joinDate.month, joinDate.day) : null;
                  final isBeforeJoining = joinDateMidnight != null && dt.isBefore(joinDateMidnight);

                  // If date is before joining date, make the calendar cell completely blank
                  if (isBeforeJoining) {
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _viewingDetailDay = day;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF131722).withAlpha(80) : const Color(0xFFF8FAFC),
                          border: Border.all(color: gridBorderCol.withAlpha(40), width: 0.5),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('$day',
                                style: TextStyle(
                                    color: textSecondary.withAlpha(80),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11)),
                          ],
                        ),
                      ),
                    );
                  }

                  final isToday = (dt.year == now.year && dt.month == now.month && dt.day == now.day);
                  final isPast = dt.isBefore(todayMidnight);

                  final hasLeave = leaveDates.contains(dateKey);
                  final hasHoliday = holidayDates.contains(dateKey);
                  final isSunday = dt.weekday == DateTime.sunday;
                  final satIndex = ((dt.day - 1) ~/ 7) + 1;
                  final isEvenSaturday = dt.weekday == DateTime.saturday && satIndex % 2 == 0;

                  // Find all attendance records for dateKey
                  final dayShifts = _attendanceRecords.where((r) {
                    if (r['clock_in'] != null && r['clock_in'].toString().startsWith(dateKey)) return true;
                    if (r['date'] != null && r['date'].toString().startsWith(dateKey)) return true;
                    return false;
                  }).toList();

                  int totalMins = 0;
                  bool hasSession1 = false; // 09:30 - 13:30
                  bool hasSession2 = false; // 13:31 - 18:30

                  for (var s in dayShifts) {
                    totalMins += (s['total_minutes'] as int? ?? 0);
                    final ci = s['clock_in'] != null ? DateTime.tryParse(s['clock_in'].toString()) : null;
                    final co = s['clock_out'] != null ? DateTime.tryParse(s['clock_out'].toString()) : null;

                    if (ci != null) {
                      if (ci.hour < 13 || (ci.hour == 13 && ci.minute <= 30)) {
                        hasSession1 = true;
                      }
                      if (ci.hour > 13 || (ci.hour == 13 && ci.minute > 30)) {
                        hasSession2 = true;
                      }
                    }
                    if (co != null && (co.hour >= 17)) {
                      hasSession2 = true;
                    }
                  }

                  String mainTag = '--';
                  String subTag = 'PLAN';
                  Color bg = isDark ? const Color(0xFF131823) : Colors.white;
                  Color tagColor = isDark ? const Color(0xFF94A3B8) : textSecondary;

                  if (isToday) {
                    mainTag = 'P';
                    subTag = 'ACTIVE';
                    bg = isDark ? const Color(0xFF261D12) : const Color(0xFFFFF3E0);
                    tagColor = isDark ? const Color(0xFFF5A952) : const Color(0xFF895100);
                  } else if (hasLeave) {
                    mainTag = 'EL';
                    subTag = 'LEAVE';
                    bg = isDark ? const Color(0xFF26151B) : const Color(0xFFFCE4EC);
                    tagColor = isDark ? const Color(0xFFFB7185) : const Color(0xFFB91C68);
                  } else if (hasHoliday) {
                    mainTag = 'H';
                    subTag = 'FEST';
                    bg = isDark ? const Color(0xFF132235) : const Color(0xFFE0F2FE);
                    tagColor = isDark ? const Color(0xFF38BDF8) : const Color(0xFF0C7AA6);
                  } else if (isSunday || isEvenSaturday) {
                    mainTag = 'Off';
                    subTag = 'WEEK';
                    bg = isDark ? const Color(0xFF161C28) : const Color(0xFFF0F3F8);
                    tagColor = isDark ? const Color(0xFF64748B) : textSecondary;
                  } else if (totalMins >= 540 || (hasSession1 && hasSession2)) {
                    mainTag = 'P';
                    subTag = 'GEN';
                    bg = isDark ? const Color(0xFF11221E) : const Color(0xFFE8F5E9);
                    tagColor = isDark ? const Color(0xFF34D399) : const Color(0xFF146C43);
                  } else if (hasSession1 && !hasSession2) {
                    mainTag = 'P:A';
                    subTag = 'HALF';
                    bg = isDark ? const Color(0xFF241C14) : const Color(0xFFFFF3E0);
                    tagColor = isDark ? const Color(0xFFFBA442) : const Color(0xFF895100);
                  } else if (!hasSession1 && hasSession2) {
                    mainTag = 'A:P';
                    subTag = 'HALF';
                    bg = isDark ? const Color(0xFF241C14) : const Color(0xFFFFF3E0);
                    tagColor = isDark ? const Color(0xFFFBA442) : const Color(0xFF895100);
                  } else if (totalMins > 0) {
                    mainTag = 'P:A';
                    subTag = 'HALF';
                    bg = isDark ? const Color(0xFF241C14) : const Color(0xFFFFF3E0);
                    tagColor = isDark ? const Color(0xFFFBA442) : const Color(0xFF895100);
                  } else if (isPast) {
                    mainTag = 'A';
                    subTag = 'ABSENT';
                    bg = isDark ? const Color(0xFF2B1618) : const Color(0xFFFFDAD6);
                    tagColor = isDark ? const Color(0xFFF87171) : const Color(0xFFBA1A1A);
                  }

                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _viewingDetailDay = day; // Closes calendar and opens detail view!
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                      decoration: BoxDecoration(
                        color: bg,
                        border: Border.all(
                          color: isToday
                              ? (isDark ? const Color(0xFFF5A952) : const Color(0xFF895100))
                              : gridBorderCol.withAlpha(isDark ? 80 : 120),
                          width: isToday ? 2.0 : 0.5,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (isToday)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFFF5A952) : const Color(0xFF895100),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '$day',
                                    style: TextStyle(
                                      color: isDark ? const Color(0xFF452600) : Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 10,
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  Icon(
                                    Icons.check,
                                    size: 8,
                                    color: isDark ? const Color(0xFF452600) : Colors.white,
                                  ),
                                ],
                              ),
                            )
                          else
                            Text('$day',
                                style: TextStyle(
                                    color: textPrimary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11)),
                          const SizedBox(height: 2),
                          Text(
                            mainTag,
                            style: TextStyle(color: tagColor, fontWeight: FontWeight.w800, fontSize: 12),
                          ),
                          Text(
                            subTag,
                            style: TextStyle(color: tagColor.withAlpha(220), fontWeight: FontWeight.w700, fontSize: 8, letterSpacing: 0.3),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Detailed Session View (Multiple Shifts Supported for Single Day) ────────
  Widget _buildDayDetailView(Color bgCard, Color bgInput, Color borderCol, Color textPrimary, Color textSecondary, Color amberPrimary, Color amberDark, bool isDark) {
    final selDay = _viewingDetailDay ?? DateTime.now().day;
    final dt = DateTime(_selectedMonth.year, _selectedMonth.month, selDay);
    final dateKey = DateFormat('yyyy-MM-dd').format(dt);
    final headerDateStr = DateFormat('EEEE, d MMMM').format(dt);

    final joinDate = _getJoiningDate();
    final joinDateMidnight = joinDate != null ? DateTime(joinDate.year, joinDate.month, joinDate.day) : null;
    final isBeforeJoining = joinDateMidnight != null && dt.isBefore(joinDateMidnight);

    // ── CASE 0: BEFORE JOINING DATE ──────────────────────────────────────────
    if (isBeforeJoining) {
      final joinDateFormatted = DateFormat('dd MMMM yyyy').format(joinDateMidnight);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: textPrimary),
                onPressed: () => setState(() => _viewingDetailDay = null),
              ),
              Text('Back to Calendar', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textPrimary)),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: bgCard,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: borderCol),
              boxShadow: const [
                BoxShadow(color: Color(0x0F171C23), blurRadius: 16, offset: Offset(0, 6)),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E2430) : const Color(0xFFF0F4FD),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.event_busy_rounded, color: textSecondary, size: 36),
                ),
                const SizedBox(height: 14),
                Text('Prior to Joining Date', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary)),
                const SizedBox(height: 6),
                Text(
                  'Your official joining date is $joinDateFormatted.\nNo attendance was scheduled for $headerDateStr.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: textSecondary, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E2430) : const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('Pre-employment Period', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textSecondary)),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // 1. Collect ALL attendance shift records for this date from PostgreSQL
    final dayShifts = _attendanceRecords.where((r) {
      if (r['clock_in'] != null && r['clock_in'].toString().startsWith(dateKey)) return true;
      if (r['date'] != null && r['date'].toString().startsWith(dateKey)) return true;
      return false;
    }).toList();

    // Sort shift records ascending by clock_in time
    dayShifts.sort((a, b) {
      final aIn = a['clock_in'] != null ? DateTime.parse(a['clock_in'].toString()) : DateTime(1970);
      final bIn = b['clock_in'] != null ? DateTime.parse(b['clock_in'].toString()) : DateTime(1970);
      return aIn.compareTo(bIn);
    });

    // 2. Check if holiday record exists in PostgreSQL
    Map<String, dynamic>? holiday;
    for (var h in _holidays) {
      if (h['date'] != null && h['date'].toString().startsWith(dateKey)) {
        holiday = h;
        break;
      }
    }

    // 3. Check if leave record exists in PostgreSQL
    Map<String, dynamic>? leave;
    for (var l in _userLeaves) {
      if (l['start_date'] != null) {
        final sStr = l['start_date'].toString().split('T')[0];
        final eStr = (l['end_date'] ?? l['start_date']).toString().split('T')[0];
        if (dateKey.compareTo(sStr) >= 0 && dateKey.compareTo(eStr) <= 0) {
          leave = l;
          break;
        }
      }
    }

    final isSunday = dt.weekday == DateTime.sunday;
    final satIndex = ((dt.day - 1) ~/ 7) + 1;
    final isEvenSaturday = dt.weekday == DateTime.saturday && satIndex % 2 == 0;
    final isOffDay = isSunday || isEvenSaturday;

    // ── CASE A: SHIFT ATTENDANCE RECORD(S) EXIST IN POSTGRESQL ─────────────
    if (dayShifts.isNotEmpty) {
      final firstShift = dayShifts.first;
      final lastShift = dayShifts.last;

      final firstCi = firstShift['clock_in'] != null ? DateTime.parse(firstShift['clock_in'].toString()) : null;
      final lastCo = lastShift['clock_out'] != null ? DateTime.parse(lastShift['clock_out'].toString()) : null;

      final ciStr = firstCi != null ? DateFormat('hh:mm').format(firstCi) : '-- : --';
      final ciAmpm = firstCi != null ? DateFormat('a').format(firstCi) : '';

      final coStr = lastCo != null ? DateFormat('hh:mm').format(lastCo) : '-- : --';
      final coAmpm = lastCo != null ? DateFormat('a').format(lastCo) : '';

      int totalMinsAllShifts = 0;
      bool hasSession1 = false;
      bool hasSession2 = false;

      for (var s in dayShifts) {
        totalMinsAllShifts += (s['total_minutes'] as int? ?? 0);
        final ci = s['clock_in'] != null ? DateTime.tryParse(s['clock_in'].toString()) : null;
        final co = s['clock_out'] != null ? DateTime.tryParse(s['clock_out'].toString()) : null;
        if (ci != null) {
          if (ci.hour < 13 || (ci.hour == 13 && ci.minute <= 30)) hasSession1 = true;
          if (ci.hour > 13 || (ci.hour == 13 && ci.minute > 30)) hasSession2 = true;
        }
        if (co != null && co.hour >= 17) hasSession2 = true;
      }

      final isHalfDay = !isOffDay && ((hasSession1 && !hasSession2) || (!hasSession1 && hasSession2) || (totalMinsAllShifts > 0 && totalMinsAllShifts < 540));

      final hrsStr = '${(totalMinsAllShifts ~/ 60).toString().padLeft(2, '0')}:${(totalMinsAllShifts % 60).toString().padLeft(2, '0')}';
      final otMins = totalMinsAllShifts > 540 ? (totalMinsAllShifts - 540) : 0;
      final otStr = '${(otMins ~/ 60).toString().padLeft(2, '0')}:${(otMins % 60).toString().padLeft(2, '0')}';

      int touchpointsCount = 0;
      for (var s in dayShifts) {
        if (s['clock_in'] != null) touchpointsCount++;
        if (s['clock_out'] != null) touchpointsCount++;
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: textPrimary),
                onPressed: () => setState(() => _viewingDetailDay = null),
              ),
              Text('Back to Calendar', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textPrimary)),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: bgCard,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: borderCol),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F171C23),
                  blurRadius: 16,
                  offset: Offset(0, 6),
                )
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('SESSION RECAP',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: textSecondary, letterSpacing: 1.1)),
                          const SizedBox(height: 2),
                          Text(
                            headerDateStr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary, letterSpacing: -0.4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isHalfDay)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF261D12) : const Color(0xFFFFF3E0),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: isDark ? const Color(0xFFF5A952).withAlpha(120) : const Color(0xFFFFCC80)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              hasSession1 && !hasSession2 ? 'Half Day (Session 1)' : (hasSession2 ? 'Half Day (Session 2)' : 'Half Day Shift'),
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: isDark ? const Color(0xFFF5A952) : const Color(0xFF895100)),
                            ),
                            Text('• 0.5 Day Count', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309))),
                          ],
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF132A20) : const Color(0xFF9FF1BD).withAlpha(120),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              lastCo != null ? 'Shift Completed' : 'Shift Active',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: isDark ? const Color(0xFF34D399) : const Color(0xFF002110)),
                            ),
                            Text('• On Time', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: isDark ? const Color(0xFF10B981) : const Color(0xFF146C43))),
                          ],
                        ),
                      ),
                  ],
                ),

                if (isHalfDay) ...[
                  const SizedBox(height: 16),
                  if (leave != null)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF26151B) : const Color(0xFFFCE4EC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: isDark ? const Color(0xFF3F1D27) : const Color(0xFFF48FB1)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.beach_access_rounded, color: isDark ? const Color(0xFFFB7185) : const Color(0xFFB91C68), size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Leave Linked: ${leave['title'] ?? leave['leave_type']}',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: isDark ? const Color(0xFFFB7185) : const Color(0xFF880E4F))),
                                Text('${leave['leave_type'] ?? 'Earned Leave'} • Status: ${leave['status'] ?? 'Approved'}',
                                    style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFFF43F5E) : const Color(0xFFAD1457), fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF241C12) : const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: isDark ? const Color(0xFF3B2A18) : const Color(0xFFFDE68A)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, color: isDark ? const Color(0xFFF5A952) : const Color(0xFFD97706), size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  hasSession1 && !hasSession2
                                      ? 'Session 2 unrecorded. Apply a half-day leave to avoid Loss of Pay.'
                                      : (!hasSession1 && hasSession2
                                          ? 'Session 1 unrecorded. Apply a half-day leave to avoid Loss of Pay.'
                                          : 'Short attendance recorded. You can apply a half-day leave.'),
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? const Color(0xFFFBBF24) : const Color(0xFF92400E)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                _showApplyLeaveModal(
                                  context,
                                  initialDate: dt,
                                  initialToDate: dt,
                                  initialFromSession: hasSession1 ? 'Session 2' : 'Session 1',
                                  initialToSession: hasSession1 ? 'Session 2' : 'Session 1',
                                  isDark: isDark,
                                );
                              },
                              icon: const Icon(Icons.beach_access_rounded, size: 16),
                              label: const Text('Apply Leave for Half Day', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: amberPrimary,
                                foregroundColor: amberDark,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                elevation: 0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],

                const SizedBox(height: 20),

                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1A1E2B) : const Color(0xFFF0F4FD),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.schedule_rounded, size: 14, color: textSecondary),
                                const SizedBox(width: 4),
                                Text('Total Work Hours', style: TextStyle(fontSize: 10, color: textSecondary, fontWeight: FontWeight.w600)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            RichText(
                              text: TextSpan(
                                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: textPrimary),
                                children: [
                                  TextSpan(text: hrsStr),
                                  TextSpan(text: ' hrs', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textSecondary)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(totalMinsAllShifts >= 540 ? Icons.check_rounded : Icons.info_outline_rounded,
                                    size: 12, color: totalMinsAllShifts >= 540 ? const Color(0xFF146C43) : textSecondary),
                                const SizedBox(width: 4),
                                Text(
                                  totalMinsAllShifts >= 540 ? 'Standard hours met' : (isHalfDay ? 'Half day logged' : 'Shift in progress'),
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: totalMinsAllShifts >= 540 ? const Color(0xFF146C43) : textSecondary),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1A1E2B) : const Color(0xFFF0F4FD),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.timer_outlined, size: 14, color: Color(0xFF99461A)),
                                const SizedBox(width: 4),
                                Text('Overtime Earned', style: TextStyle(fontSize: 10, color: textSecondary, fontWeight: FontWeight.w600)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            RichText(
                              text: TextSpan(
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF99461A)),
                                children: [
                                  TextSpan(text: otStr),
                                  TextSpan(text: ' hrs', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textSecondary)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text('Standard: 09:00h', style: TextStyle(fontSize: 10, color: textSecondary, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        Text('First Check In', style: TextStyle(fontSize: 11, color: textSecondary, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 2),
                        Text(ciStr, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textPrimary)),
                        Text('$ciAmpm • On time', style: const TextStyle(fontSize: 10, color: Color(0xFF146C43), fontWeight: FontWeight.w700)),
                      ],
                    ),
                    Container(width: 1, height: 32, color: borderCol),
                    Column(
                      children: [
                        Text('Last Check Out', style: TextStyle(fontSize: 11, color: textSecondary, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 2),
                        Text(coStr, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textPrimary)),
                        Text(lastCo != null ? '$coAmpm • Approved' : 'Active', style: TextStyle(fontSize: 10, color: textSecondary, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Hourly Day Flow (Timeline Touchpoints from PostgreSQL)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: bgCard,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: borderCol),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.alt_route_rounded, color: amberDark, size: 22),
                        const SizedBox(width: 8),
                        Text('Hourly Day Flow',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary, letterSpacing: -0.4)),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1F2633) : const Color(0xFFF0F4FD),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text('$touchpointsCount Touchpoint${touchpointsCount > 1 ? 's' : ''}',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textSecondary)),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                // Multi-shift timeline entries from DB
                ...List.generate(dayShifts.length, (sIdx) {
                  final s = dayShifts[sIdx];
                  final sIn = s['clock_in'] != null ? DateTime.parse(s['clock_in'].toString()) : null;
                  final sOut = s['clock_out'] != null ? DateTime.parse(s['clock_out'].toString()) : null;

                  final inTimeStr = sIn != null ? DateFormat('hh:mm').format(sIn) : '-- : --';
                  final inAmpmStr = sIn != null ? DateFormat('a').format(sIn) : '';

                  final outTimeStr = sOut != null ? DateFormat('hh:mm').format(sOut) : '-- : --';
                  final outAmpmStr = sOut != null ? DateFormat('a').format(sOut) : '';

                  final sessNum = dayShifts.length > 1 ? ' (#${sIdx + 1})' : '';

                  return Column(
                    children: [
                      if (sIdx > 0) const SizedBox(height: 10),
                      _timelineTile(
                        Icons.login_rounded,
                        'Punch In$sessNum',
                        s['location'] != null ? 'GPS • ${s['location']}' : 'GPS Verified • Main Gate',
                        inTimeStr,
                        inAmpmStr,
                        const Color(0xFF9FF1BD),
                        const Color(0xFF146C43),
                        bgInput,
                        textPrimary,
                        textSecondary,
                        statusBadge: _buildShiftStatusBadge(s, isPunchIn: true),
                      ),
                      if (sOut != null) ...[
                        const SizedBox(height: 10),
                        _timelineTile(
                          Icons.logout_rounded,
                          'Punch Out$sessNum',
                          'Biometric + Beacon verified',
                          outTimeStr,
                          outAmpmStr,
                          const Color(0xFFFFDBCC),
                          const Color(0xFF99461A),
                          bgInput,
                          textPrimary,
                          textSecondary,
                          statusBadge: _buildShiftStatusBadge(s, isPunchIn: false),
                        ),
                      ],
                    ],
                  );
                }),
              ],
            ),
          ),
        ],
      );
    }

    // ── CASE B: HOLIDAY RECORD EXISTS ────────────────────────────────────────
    if (holiday != null) {
      final hTitle = holiday['title'] ?? 'Company Holiday';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: textPrimary),
                onPressed: () => setState(() => _viewingDetailDay = null),
              ),
              Text('Back to Calendar', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textPrimary)),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: bgCard,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: borderCol),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF132235) : const Color(0xFFE0F2FE),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.beach_access_rounded, color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7), size: 36),
                ),
                const SizedBox(height: 14),
                Text(hTitle, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: textPrimary)),
                const SizedBox(height: 4),
                Text('Official Public Holiday • $headerDateStr', style: TextStyle(fontSize: 12, color: textSecondary, fontWeight: FontWeight.w500)),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF132235) : const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('Company Holiday', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7))),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // ── CASE C: LEAVE RECORD EXISTS ─────────────────────────────────────────
    if (leave != null) {
      final lTitle = leave['title'] ?? 'Annual Leave';
      final lType = leave['leave_type'] ?? 'Earned Leave';
      final lStatus = leave['status'] ?? 'Approved';
      final daysCount = leave['days_count'] ?? 1.0;
      final fSess = leave['from_session'] ?? 'Session 1';
      final tSess = leave['to_session'] ?? 'Session 2';
      final isHalf = daysCount == 0.5 || (fSess == tSess);
      final lNote = leave['note']?.toString() ?? '';

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: textPrimary),
                onPressed: () => setState(() => _viewingDetailDay = null),
              ),
              Text('Back to Calendar', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textPrimary)),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: bgCard,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: borderCol),
              boxShadow: const [
                BoxShadow(color: Color(0x0F171C23), blurRadius: 16, offset: Offset(0, 6)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF26151B) : const Color(0xFFFFDBCC),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.luggage_rounded, color: isDark ? const Color(0xFFFB7185) : const Color(0xFF99461A), size: 30),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(lTitle, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary)),
                          const SizedBox(height: 2),
                          Text('$lType • $headerDateStr', style: TextStyle(fontSize: 12, color: textSecondary, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: lStatus == 'Approved'
                            ? (isDark ? const Color(0xFF132A20) : const Color(0xFFDCFCE7))
                            : (lStatus == 'Rejected' ? (isDark ? const Color(0xFF2B1618) : const Color(0xFFFFE4E6)) : (isDark ? const Color(0xFF261D12) : const Color(0xFFFEF3C7))),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        lStatus,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: lStatus == 'Approved'
                              ? (isDark ? const Color(0xFF34D399) : const Color(0xFF15803D))
                              : (lStatus == 'Rejected' ? (isDark ? const Color(0xFFF87171) : const Color(0xFFE11D48)) : (isDark ? const Color(0xFFF5A952) : const Color(0xFFB45309))),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1A1E2B) : const Color(0xFFF0F4FD),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Duration', style: TextStyle(fontSize: 12, color: textSecondary, fontWeight: FontWeight.w600)),
                          Text(
                            isHalf ? '0.5 Day ($fSess)' : '$daysCount Day(s) (Full Day)',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: textPrimary),
                          ),
                        ],
                      ),
                      if (lNote.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Divider(color: borderCol, height: 1),
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Note: ', style: TextStyle(fontSize: 12, color: textSecondary, fontWeight: FontWeight.w600)),
                            Expanded(
                              child: Text(lNote, style: TextStyle(fontSize: 12, color: textPrimary, fontWeight: FontWeight.w500)),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      _showApplyLeaveModal(
                        context,
                        initialDate: dt,
                        initialToDate: dt,
                        initialFromSession: 'Session 1',
                        initialToSession: 'Session 2',
                        isDark: isDark,
                      );
                    },
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Apply Additional Leave', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: borderCol),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // ── CASE D: OFF DAY / WEEKEND ────────────────────────────────────────────
    if (isOffDay) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: textPrimary),
                onPressed: () => setState(() => _viewingDetailDay = null),
              ),
              Text('Back to Calendar', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textPrimary)),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: bgCard,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: borderCol),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1F2633) : const Color(0xFFF0F4FD),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.weekend_rounded, color: textSecondary, size: 36),
                ),
                const SizedBox(height: 14),
                Text('Weekly Off / Rest Day', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: textPrimary)),
                const SizedBox(height: 4),
                Text('Non-working day • $headerDateStr', style: TextStyle(fontSize: 12, color: textSecondary, fontWeight: FontWeight.w500)),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1F2633) : const Color(0xFFEAEFF8),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('Off Duty', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: textSecondary)),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // ── CASE E: NO DATA / UNRECORDED WORKING DAY (ABSENT) ─────────────────────
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: textPrimary),
              onPressed: () => setState(() => _viewingDetailDay = null),
            ),
            Text('Back to Calendar', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textPrimary)),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: bgCard,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderCol),
            boxShadow: const [
              BoxShadow(color: Color(0x0F171C23), blurRadius: 16, offset: Offset(0, 6)),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2B1618) : const Color(0xFFFFDAD6),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.event_busy_rounded, color: isDark ? const Color(0xFFF87171) : const Color(0xFFBA1A1A), size: 36),
              ),
              const SizedBox(height: 14),
              Text('Absent (Unrecorded Day)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary)),
              const SizedBox(height: 4),
              Text('No check-in or shift data recorded for $headerDateStr.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: textSecondary, fontWeight: FontWeight.w500)),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    _showApplyLeaveModal(
                      context,
                      initialDate: dt,
                      initialToDate: dt,
                      initialFromSession: 'Session 1',
                      initialToSession: 'Session 2',
                      isDark: isDark,
                    );
                  },
                  icon: const Icon(Icons.edit_calendar_rounded, size: 16),
                  label: const Text('Apply Leave for this Date', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: amberPrimary,
                    foregroundColor: amberDark,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showApplyLeaveModal(
    BuildContext context, {
    required DateTime initialDate,
    DateTime? initialToDate,
    String initialFromSession = 'Session 1',
    String initialToSession = 'Session 2',
    String initialType = 'Earned Leave',
    required bool isDark,
  }) {
    final dialogBg = isDark ? const Color(0xFF131722) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF171C23);
    final textSecondary = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF524437);
    const amberPrimary = Color(0xFFF5A952);
    const amberDark = Color(0xFF895100);

    DateTime fromDate = initialDate;
    DateTime toDate = initialToDate ?? initialDate;
    String fromSession = initialFromSession;
    String toSession = initialToSession;
    String selectedLeaveType = initialType; // 'Earned Leave', 'Loss Of Pay', 'Comp - Off'
    bool submitting = false;

    _leaveTitleCtrl.clear();
    _leaveNoteCtrl.clear();

    double calculateDays(DateTime fDate, String fSess, DateTime tDate, String tSess) {
      final fNorm = DateTime(fDate.year, fDate.month, fDate.day);
      final tNorm = DateTime(tDate.year, tDate.month, tDate.day);

      if (tNorm.isBefore(fNorm)) return 0.5;

      if (fNorm == tNorm) {
        if (fSess == 'Session 1' && tSess == 'Session 1') return 0.5;
        if (fSess == 'Session 2' && tSess == 'Session 2') return 0.5;
        if (fSess == 'Session 1' && tSess == 'Session 2') return 1.0;
        return 0.5;
      }

      int calendarDays = tNorm.difference(fNorm).inDays + 1;
      double days = calendarDays.toDouble();
      if (fSess == 'Session 2') days -= 0.5;
      if (tSess == 'Session 1') days -= 0.5;
      return days < 0.5 ? 0.5 : days;
    }

    String fmtDays(double days) {
      if (days == days.roundToDouble()) {
        return days.toInt().toString();
      }
      return days.toString();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: dialogBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final calculatedDays = calculateDays(fromDate, fromSession, toDate, toSession);
            final daysStr = fmtDays(calculatedDays);
            final isLossOfPay = selectedLeaveType == 'Loss Of Pay';
            final isEarnedLeave = selectedLeaveType == 'Earned Leave';

            return SingleChildScrollView(
              padding: EdgeInsets.only(
                top: 16,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1F2633) : const Color(0xFFDEE2EC),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Apply Leave',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: textPrimary)),
                          Text('Submit your leave request with session details',
                              style: TextStyle(fontSize: 12, color: textSecondary)),
                        ],
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: textSecondary),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // 1. Leave Type Dropdown
                  RichText(
                    text: TextSpan(
                      text: 'Leave type ',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textSecondary),
                      children: const [
                        TextSpan(text: '*', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1A1E2B) : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF3B82F6), width: 1.5),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedLeaveType,
                        isExpanded: true,
                        icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF64748B)),
                        dropdownColor: isDark ? const Color(0xFF1A1E2B) : Colors.white,
                        style: TextStyle(color: textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                        items: ['Earned Leave', 'Loss Of Pay', 'Comp - Off'].map((type) {
                          return DropdownMenuItem<String>(
                            value: type,
                            child: Text(type),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() => selectedLeaveType = val);
                          }
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 2. From Date & Session Row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RichText(
                              text: TextSpan(
                                text: 'From date ',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textSecondary),
                                children: const [
                                  TextSpan(text: '*', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            GestureDetector(
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: fromDate,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2030),
                                );
                                if (picked != null) {
                                  setModalState(() {
                                    fromDate = picked;
                                    if (toDate.isBefore(fromDate)) {
                                      toDate = fromDate;
                                    }
                                  });
                                }
                              },
                              child: Container(
                                height: 46,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1A1E2B) : Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: isDark ? const Color(0xFF2D3748) : const Color(0xFFCBD5E1)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      DateFormat('dd-MM-yyyy').format(fromDate),
                                      style: TextStyle(fontSize: 13, color: textPrimary, fontWeight: FontWeight.w600),
                                    ),
                                    const Icon(Icons.calendar_month_outlined, size: 18, color: Color(0xFF64748B)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 125,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Session',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textSecondary)),
                            const SizedBox(height: 6),
                            Container(
                              height: 46,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1A1E2B) : Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: isDark ? const Color(0xFF2D3748) : const Color(0xFFCBD5E1)),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: fromSession,
                                  isExpanded: true,
                                  icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF64748B)),
                                  dropdownColor: isDark ? const Color(0xFF1A1E2B) : Colors.white,
                                  style: TextStyle(color: textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                                  items: ['Session 1', 'Session 2'].map((sess) {
                                    return DropdownMenuItem<String>(
                                      value: sess,
                                      child: Text(sess),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) setModalState(() => fromSession = val);
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // 3. To Date & Session Row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RichText(
                              text: TextSpan(
                                text: 'To date ',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textSecondary),
                                children: const [
                                  TextSpan(text: '*', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            GestureDetector(
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: toDate.isBefore(fromDate) ? fromDate : toDate,
                                  firstDate: fromDate,
                                  lastDate: DateTime(2030),
                                );
                                if (picked != null) {
                                  setModalState(() => toDate = picked);
                                }
                              },
                              child: Container(
                                height: 46,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1A1E2B) : Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: isDark ? const Color(0xFF2D3748) : const Color(0xFFCBD5E1)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      DateFormat('dd-MM-yyyy').format(toDate),
                                      style: TextStyle(fontSize: 13, color: textPrimary, fontWeight: FontWeight.w600),
                                    ),
                                    const Icon(Icons.calendar_month_outlined, size: 18, color: Color(0xFF64748B)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 125,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Session',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textSecondary)),
                            const SizedBox(height: 6),
                            Container(
                              height: 46,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1A1E2B) : Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: isDark ? const Color(0xFF2D3748) : const Color(0xFFCBD5E1)),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: toSession,
                                  isExpanded: true,
                                  icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF64748B)),
                                  dropdownColor: isDark ? const Color(0xFF1A1E2B) : Colors.white,
                                  style: TextStyle(color: textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                                  items: ['Session 1', 'Session 2'].map((sess) {
                                    return DropdownMenuItem<String>(
                                      value: sess,
                                      child: Text(sess),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) setModalState(() => toSession = val);
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // 4. Dynamic Duration & Balance Info Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isLossOfPay
                          ? (isDark ? const Color(0xFF281E1E) : const Color(0xFFFEF2F2))
                          : (isDark ? const Color(0xFF1E2430) : const Color(0xFFF0FDF4)),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isLossOfPay
                            ? const Color(0xFFFCA5A5)
                            : const Color(0xFF86EFAC),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          isLossOfPay ? Icons.money_off_rounded : Icons.check_circle_outline_rounded,
                          color: isLossOfPay ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    '$daysStr ${calculatedDays == 1.0 || calculatedDays == 0.5 ? 'Day' : 'Days'} ($selectedLeaveType)',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: isLossOfPay ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                                    ),
                                  ),
                                  if (calculatedDays == 0.5) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: amberPrimary.withAlpha(50),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        fromSession == 'Session 1' ? 'Half Day (Morning)' : 'Half Day (Afternoon)',
                                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: amberDark),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                isEarnedLeave
                                    ? 'Will deduct $daysStr day(s) from Earned Leave balance (${fmtDays(_remainingDays)} Days currently available).'
                                    : (isLossOfPay
                                        ? 'Loss of Pay (Will not deduct from leave balance • Unpaid leave).'
                                        : 'Compensatory Off request.'),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // 5. Reason & Notes
                  Text('REASON / PURPOSE',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textSecondary, letterSpacing: 0.8)),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1A1E2B) : const Color(0xFFF0F4FD),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _leaveTitleCtrl,
                      style: TextStyle(color: textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'e.g. Personal Work, Medical Emergency',
                        hintStyle: TextStyle(color: Color(0xFF847465), fontSize: 12),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text('NOTE FOR MANAGER (OPTIONAL)',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textSecondary, letterSpacing: 0.8)),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1A1E2B) : const Color(0xFFF0F4FD),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _leaveNoteCtrl,
                      maxLines: 2,
                      style: TextStyle(color: textPrimary, fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'Provide additional details...',
                        hintStyle: TextStyle(color: Color(0xFF847465), fontSize: 12),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(12),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 6. Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          ),
                          child: Text('Cancel', style: TextStyle(color: textSecondary, fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: submitting
                              ? null
                              : () async {
                                  final messenger = ScaffoldMessenger.of(context);
                                  final navigator = Navigator.of(ctx);
                                  setModalState(() => submitting = true);
                                  try {
                                    final res = await apiPost(
                                      '/api/leaves',
                                      {
                                        'title': _leaveTitleCtrl.text.trim().isEmpty ? selectedLeaveType : _leaveTitleCtrl.text.trim(),
                                        'leave_type': selectedLeaveType,
                                        'start_date': DateFormat('yyyy-MM-dd').format(fromDate),
                                        'end_date': DateFormat('yyyy-MM-dd').format(toDate),
                                        'from_session': fromSession,
                                        'to_session': toSession,
                                        'days_count': calculatedDays,
                                        'note': _leaveNoteCtrl.text.trim(),
                                      },
                                      token: widget.token,
                                    );
                                    if (res['error'] != null) {
                                      messenger.showSnackBar(
                                        SnackBar(content: Text('Error: ${res['error']}')),
                                      );
                                    } else {
                                      navigator.pop();
                                      _loadData();
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text('$selectedLeaveType request ($daysStr ${calculatedDays == 1.0 || calculatedDays == 0.5 ? 'Day' : 'Days'}) submitted!'),
                                        ),
                                      );
                                    }
                                  } catch (_) {
                                    messenger.showSnackBar(
                                      const SnackBar(content: Text('Server connection error.')),
                                    );
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: amberPrimary,
                            foregroundColor: amberDark,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                            elevation: 0,
                          ),
                          child: submitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: amberDark),
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.send_rounded, size: 16),
                                    SizedBox(width: 6),
                                    Text('Submit Request', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _timelineTile(
    IconData icon,
    String title,
    String subtitle,
    String time,
    String ampm,
    Color bgIcon,
    Color iconColor,
    Color bgInput,
    Color textPrimary,
    Color textSecondary, {
    Widget? statusBadge,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgInput,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: bgIcon, shape: BoxShape.circle),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textPrimary)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 11, color: textSecondary, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              Text('$time $ampm', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: textPrimary)),
            ],
          ),
          if (statusBadge != null) ...[
            const SizedBox(height: 8),
            statusBadge,
          ],
        ],
      ),
    );
  }

  Widget _legendPill(String label, Color bg, Color textCol) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: textCol, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: textCol)),
        ],
      ),
    );
  }

  // ── Overview View ───────────────────────────────────────────────────────────
  Widget _buildOverviewView(Color bgCard, Color borderCol, Color textPrimary, Color textSecondary, bool isDark, Set<String> holidayDates) {
    final now = DateTime.now();
    final totalDaysInMonth = DateTime(now.year, now.month + 1, 0).day;

    int presentDays = 0;
    int holidayCountInMonth = 0;
    int totalMinutesWorked = 0;

    final Set<int> presentDaySet = {};

    for (var r in _attendanceRecords) {
      final ci = r['clock_in'] != null ? DateTime.tryParse(r['clock_in'].toString()) : null;
      final mins = r['total_minutes'] as int? ?? 0;

      if (ci != null && ci.month == now.month && ci.year == now.year) {
        if (mins >= 540) {
          presentDaySet.add(ci.day);
          totalMinutesWorked += mins;
        }
      }
    }

    presentDays = presentDaySet.length;

    int workingDaysCount = 0;
    for (int day = 1; day <= totalDaysInMonth; day++) {
      final dt = DateTime(now.year, now.month, day);
      final dateKey = DateFormat('yyyy-MM-dd').format(dt);

      final isSunday = dt.weekday == DateTime.sunday;
      final isEvenSaturday = dt.weekday == DateTime.saturday && (((dt.day - 1) ~/ 7) + 1) % 2 == 0;

      if (holidayDates.contains(dateKey)) {
        holidayCountInMonth++;
      } else if (!isSunday && !isEvenSaturday) {
        workingDaysCount++;
      }
    }

    double attendancePercentage = workingDaysCount > 0
        ? (presentDays / workingDaysCount) * 100
        : 98.0;

    double avgHours = presentDays > 0 ? (totalMinutesWorked / 60) / presentDays : 8.5;
    int avgH = avgHours.floor();
    int avgM = ((avgHours - avgH) * 60).round();
    String avgTimeString = '${avgH.toString().padLeft(2, '0')}:${avgM.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bgCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderCol),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Monthly Attendance',
                      style: TextStyle(color: textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(DateFormat('MMMM y').format(now),
                      style: TextStyle(color: textPrimary, fontWeight: FontWeight.w800, fontSize: 16)),
                ],
              ),
              Text('$workingDaysCount Working days',
                  style: TextStyle(color: textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 24),

          Center(
            child: SizedBox(
              width: 150,
              height: 150,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(150, 150),
                    painter: DynamicPercentagePainter(
                      percentage: attendancePercentage,
                      isDark: isDark,
                    ),
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${attendancePercentage.toStringAsFixed(1)}%',
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w800, color: textPrimary),
                      ),
                      Text(
                        'Attendance',
                        style: TextStyle(fontSize: 10, color: textSecondary, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 2.8,
            children: [
              _statItem('Present (>=9h)', '$presentDays days', const Color(0xFF10B981), textSecondary, textPrimary),
              _statItem('Holidays', '$holidayCountInMonth days', const Color(0xFF0EA5E9), textSecondary, textPrimary),
            ],
          ),
          Divider(color: borderCol, height: 24),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Average Work Hours', style: TextStyle(color: textSecondary, fontSize: 11)),
                  const SizedBox(height: 4),
                  Text(avgTimeString,
                      style: TextStyle(color: textPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
                ],
              ),
              const Text('Calculated from DB',
                  style: TextStyle(color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value, Color color, Color textSecondary, Color textPrimary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 10, height: 4, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: textSecondary, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Text(value, style: TextStyle(color: textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
        ),
      ],
    );
  }

  // ── Daily Shift Breakdown List ──────────────────────────────────────────────
  Widget _buildDailyShiftList(
    Color bgCard,
    Color borderCol,
    Color textPrimary,
    Color textSecondary, {
    List<dynamic>? records,
  }) {
    final displayRecords = records ?? _attendanceRecords;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Daily Breakdown',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary, letterSpacing: -0.4)),
            Text('${displayRecords.length} ${displayRecords.length == 1 ? "shift" : "shifts"} recorded',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textSecondary)),
          ],
        ),
        const SizedBox(height: 12),

        if (displayRecords.isNotEmpty)
          ...displayRecords.map((r) {
            final ci = r['clock_in'] != null ? DateTime.tryParse(r['clock_in'].toString()) : null;
            final co = r['clock_out'] != null ? DateTime.tryParse(r['clock_out'].toString()) : null;
            final mins = r['total_minutes'] as int? ?? 0;

            final dateStr = ci != null ? DateFormat('EEE, d MMM').format(ci) : 'Shift Record';
            final timeIntervalStr = ci != null
                ? '${DateFormat('hh:mm a').format(ci)}${co != null ? ' – ${DateFormat('hh:mm a').format(co)}' : ' – Active'}'
                : 'Recorded Shift';

            final hrs = mins ~/ 60;
            final remainderMins = mins % 60;
            final durationStr = '${hrs}h ${remainderMins}m';

            final isOvertime = mins > 540;
            final isLate = ci != null && (ci.hour > 9 || (ci.hour == 9 && ci.minute > 30));
            final lateMins = ci != null ? ((ci.hour - 9) * 60 + ci.minute - 30) : 0;

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: bgCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isOvertime ? const Color(0xFFFFA276) : borderCol,
                  width: isOvertime ? 1.5 : 1.0,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isOvertime ? const Color(0xFFFFDBCC) : const Color(0xFF9FF1BD).withAlpha(120),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isOvertime ? Icons.timer_outlined : Icons.login_rounded,
                      color: isOvertime ? const Color(0xFF7D3205) : const Color(0xFF1B7047),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(dateStr,
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: textPrimary)),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: isLate
                                    ? const Color(0xFFFFDCBC)
                                    : const Color(0xFF9FF1BD).withAlpha(120),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                isLate ? 'Late ${lateMins}m' : 'On Time',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isLate ? const Color(0xFF683D00) : const Color(0xFF1B7047),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(timeIntervalStr, style: TextStyle(fontSize: 12, color: textSecondary)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(durationStr,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: isOvertime ? const Color(0xFF99461A) : textPrimary)),
                      Text(isOvertime ? 'Overtime +${mins - 540}m' : 'Net Duration',
                          style: TextStyle(fontSize: 10, color: textSecondary, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
            );
          })
        else
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: bgCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderCol),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.history_toggle_off_rounded, size: 36, color: textSecondary),
                  const SizedBox(height: 8),
                  Text('No Attendance Shifts Recorded Yet',
                      style: TextStyle(color: textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Check in on the Dashboard to record your first shift.',
                      style: TextStyle(color: textSecondary, fontSize: 12)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _barColumn(String day, double heightPct, bool isDark, {bool isHighlighted = false, String? tooltip}) {
    final textSecondary = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF524437);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (tooltip != null)
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E2638) : const Color(0xFF2C3138),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(tooltip,
                style: const TextStyle(color: Color(0xFFEDF1FB), fontSize: 9, fontWeight: FontWeight.w800)),
          ),
        Container(
          width: 24,
          height: 110 * heightPct,
          decoration: BoxDecoration(
            color: isHighlighted
                ? (isDark ? const Color(0xFFF5A952) : const Color(0xFF99461A))
                : (isDark ? const Color(0xFF10B981) : const Color(0xFF86D7A5)),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          day,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isHighlighted
                ? (isDark ? const Color(0xFFF5A952) : const Color(0xFF99461A))
                : textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _holidayColumn(String day) {
    final isDark = themeController.isDarkMode;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: 24,
          height: 110,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF132235) : const Color(0xFFFFDAD6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: RotatedBox(
              quarterTurns: 3,
              child: Text(
                'HOLIDAY',
                style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF93000A)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          day,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isDark ? const Color(0xFF38BDF8) : const Color(0xFFBA1A1A),
          ),
        ),
      ],
    );
  }

  Widget _buildShiftStatusBadge(Map<String, dynamic> s, {required bool isPunchIn}) {
    final isDark = themeController.isDarkMode;
    final status = s['approval_status'] ?? 'Approved';
    final inGeofence = isPunchIn ? (s['in_geofence'] == true) : (s['clock_out_in_geofence'] == true);
    final bldg = s['nearest_building'] ?? 'Monarch House (HQ)';
    final dist = isPunchIn ? s['distance_meters'] : s['clock_out_distance_meters'];

    if (status == 'Approved') {
      if (inGeofence || (dist != null && dist <= 20)) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF132A20) : const Color(0xFFDCFCE7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified_rounded, size: 12, color: isDark ? const Color(0xFF34D399) : const Color(0xFF16A34A)),
              const SizedBox(width: 4),
              Text(
                '🏢 In-Office Verified • $bldg (≤ 20m)',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isDark ? const Color(0xFF34D399) : const Color(0xFF15803D),
                ),
              ),
            ],
          ),
        );
      } else {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF132A20) : const Color(0xFFDCFCE7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_rounded, size: 12, color: isDark ? const Color(0xFF34D399) : const Color(0xFF16A34A)),
              const SizedBox(width: 4),
              Text(
                '✅ Approved by ${s['reviewed_by'] ?? 'Supervisor'} (${dist ?? ''}m from $bldg)',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isDark ? const Color(0xFF34D399) : const Color(0xFF15803D),
                ),
              ),
            ],
          ),
        );
      }
    } else if (status == 'Pending Approval') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF261D12) : const Color(0xFFFEF3C7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule_rounded, size: 12, color: isDark ? const Color(0xFFF5A952) : const Color(0xFFD97706)),
            const SizedBox(width: 4),
            Text(
              '⚠️ Out of Range (${dist ?? ''}m from $bldg) • Pending Approval',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isDark ? const Color(0xFFF5A952) : const Color(0xFFB45309),
              ),
            ),
          ],
        ),
      );
    } else if (status == 'Rejected') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2B1618) : const Color(0xFFFFE4E6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cancel_rounded, size: 12, color: isDark ? const Color(0xFFF87171) : const Color(0xFFE11D48)),
            const SizedBox(width: 4),
            Text(
              '❌ Rejected by ${s['reviewed_by'] ?? 'Supervisor'}${s['rejection_reason'] != null && s['rejection_reason'].toString().isNotEmpty ? ' (${s['rejection_reason']})' : ''}',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isDark ? const Color(0xFFF87171) : const Color(0xFFBE123C),
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildPunchApprovalsView(
    bool isDark,
    Color bgCard,
    Color bgInput,
    Color bgScaffold,
    Color borderCol,
    Color textPrimary,
    Color textSecondary,
    Color amberPrimary,
    Color amberDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Geofence Building Info Card ──────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: bgCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderCol),
            boxShadow: const [
              BoxShadow(
                color: Color(0x08171C23),
                blurRadius: 14,
                offset: Offset(0, 4),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: amberPrimary.withAlpha(40),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.radar_rounded, color: amberDark, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Company Geofence Range (20 Meters)',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: textPrimary),
                        ),
                        Text(
                          'Punches logged > 20m from company centers require your approval',
                          style: TextStyle(fontSize: 11, color: textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _buildingChip('🏛️ Monarch House (HQ)', '18.5229, 73.9069', isDark, bgInput, textPrimary, textSecondary),
                  _buildingChip('🏢 KK Empire', '18.5235, 73.9066', isDark, bgInput, textPrimary, textSecondary),
                  _buildingChip('🏰 Morya Palace', '18.5239, 73.9056', isDark, bgInput, textPrimary, textSecondary),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── Punch Requests List Header ─────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Pending Punch Requests (${_teamPunchRequests.length})',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: textPrimary),
            ),
            IconButton(
              icon: Icon(Icons.refresh_rounded, size: 20, color: textSecondary),
              onPressed: _loadingPunchRequests ? null : _loadPunchRequests,
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (_loadingPunchRequests)
          const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
        else if (_teamPunchRequests.isEmpty)
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: bgCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderCol),
            ),
            child: Center(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF132A20) : const Color(0xFFDCFCE7),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.verified_user_rounded, color: isDark ? const Color(0xFF34D399) : const Color(0xFF16A34A), size: 32),
                  ),
                  const SizedBox(height: 12),
                  Text('Zero Pending Punches', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: textPrimary)),
                  const SizedBox(height: 4),
                  Text('All subordinate punches are verified within the 20m office range.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: textSecondary)),
                ],
              ),
            ),
          )
        else
          ...List.generate(_teamPunchRequests.length, (idx) {
            final p = _teamPunchRequests[idx];
            final name = p['name'] ?? 'Employee';
            final role = p['role'] ?? 'Employee';
            final dept = p['department'] ?? 'General';
            final dateStr = p['date'] ?? '';
            final signIn = p['sign_in'];
            final signOut = p['sign_out'];
            final isCheckOut = signOut != null;
            final punchTime = isCheckOut ? signOut : (signIn ?? '--:--');
            final bldg = p['nearest_building'] ?? 'Office';
            final dist = p['distance_meters'];
            final loc = p['location'] ?? 'GPS Coordinates';
            final reqId = p['id'];

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: bgCard,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isDark ? const Color(0xFF3E2D1A) : const Color(0xFFFFA276), width: 1.5),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x08171C23),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // User & Role Row
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: amberPrimary.withAlpha(50),
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : 'U',
                          style: TextStyle(fontWeight: FontWeight.w800, color: isDark ? const Color(0xFFF5A952) : amberDark, fontSize: 14),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: textPrimary)),
                            Text('$role • $dept', style: TextStyle(fontSize: 11, color: textSecondary, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isCheckOut
                              ? (isDark ? const Color(0xFF2B1618) : const Color(0xFFFFE4E6))
                              : (isDark ? const Color(0xFF132A20) : const Color(0xFFDCFCE7)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          isCheckOut ? '🔴 Clock-Out' : '🟢 Clock-In',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: isCheckOut
                                ? (isDark ? const Color(0xFFFB7185) : const Color(0xFFE11D48))
                                : (isDark ? const Color(0xFF34D399) : const Color(0xFF15803D)),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Distance & Warning Alert Banner
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF261D12) : const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? const Color(0xFF3E2D1A) : const Color(0xFFFDE68A)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.location_off_rounded, size: 16, color: isDark ? const Color(0xFFF5A952) : const Color(0xFFD97706)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '⚠️ Out of Range: ${dist != null ? '${dist}m' : '> 20m'} away from $bldg',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: isDark ? const Color(0xFFF5A952) : const Color(0xFFB45309)),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Details Meta Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.calendar_today_rounded, size: 13, color: textSecondary),
                          const SizedBox(width: 4),
                          Text('$dateStr • $punchTime', style: TextStyle(fontSize: 11, color: textSecondary, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      Row(
                        children: [
                          Icon(Icons.gps_fixed_rounded, size: 13, color: textSecondary),
                          const SizedBox(width: 4),
                          Text(loc.length > 20 ? '${loc.substring(0, 18)}...' : loc,
                              style: TextStyle(fontSize: 11, color: textSecondary, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // Actions Row
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _actionInProgress ? null : () => _showRejectPunchDialog(p),
                          icon: const Icon(Icons.close_rounded, size: 16, color: Color(0xFFDC2626)),
                          label: const Text('Reject', style: TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.w700, fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFFCA5A5)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _actionInProgress
                              ? null
                              : () {
                                  if (reqId != null) {
                                    final idInt = reqId is int ? reqId : int.tryParse(reqId.toString()) ?? 0;
                                    _actionPunchRequest(idInt, 'approve');
                                  }
                                },
                          icon: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
                          label: const Text('Approve Punch', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF16A34A),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildingChip(String name, String coords, bool isDark, Color bgInput, Color textPrimary, Color textSecondary) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgInput,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textPrimary)),
          const SizedBox(height: 2),
          Text(coords, style: TextStyle(fontSize: 9, color: textSecondary, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
