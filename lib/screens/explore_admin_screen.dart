import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/api_config.dart';
import '../controllers/theme_controller.dart';
import '../services/date_time_helper.dart';
import '../widgets/profile_avatar_badge.dart';

// ── Tab 3: MonarchHR Leave Management & Admin Dashboard for SUMIT ──────────────
class ExploreTab extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;
  final String password;
  final VoidCallback onLogout;
  final VoidCallback? onNavigateToProfile;

  const ExploreTab({
    super.key,
    required this.token,
    required this.user,
    required this.password,
    required this.onLogout,
    this.onNavigateToProfile,
  });

  @override
  State<ExploreTab> createState() => ExploreTabState();
}

class ExploreTabState extends State<ExploreTab> {
  List<dynamic> _usersList = [];
  List<dynamic> _leavesList = [];
  List<dynamic> _holidaysList = [];
  double _totalAllotted = 25.0;
  double _usedDays = 5.5;
  double _remainingDays = 19.5;
  bool _loadingLeaves = false;
  bool _loadingUsers = false;
  String _activeFilter = 'All';

  // Team Hierarchy & Approvals State
  Map<String, dynamic>? _teamHierarchy;
  List<dynamic> _teamLeavesList = [];
  bool _loadingTeam = false;
  int _mainTabSegment = 0; // 0: My Leaves, 1: Team & Approvals
  String _teamSubFilter = 'All'; // 'All', 'Pending', 'Approved', 'Rejected'
  String _teamAttendanceDeptFilter = 'All';
  String _teamAttendanceRoleFilter = 'All'; // 'All', 'Team Leader', 'Employee'
  Timer? _autoSyncTimer;
  double _leavesDragDeltaX = 0;

  bool get _isManager {
    final r = (widget.user['role'] ?? '').toString().toLowerCase();
    return r.contains('manager') || r.contains('director') || r.contains('hr');
  }

  bool get _isTeamLeader {
    final r = (widget.user['role'] ?? '').toString().toLowerCase();
    return r.contains('lead') || r.contains('tl') || r.contains('head');
  }

  bool get _isAdmin {
    final r = (widget.user['role'] ?? '').toString().toLowerCase();
    return r == 'admin';
  }

  bool get _isPrivileged => _isManager || _isTeamLeader || _isAdmin;

  final _holidayTitleCtrl = TextEditingController();
  final _holidayDateCtrl  = TextEditingController();
  final _holidayDayCtrl   = TextEditingController();

  final _leaveTitleCtrl = TextEditingController(text: 'Family Vacation');
  final _leaveNoteCtrl  = TextEditingController();

  @override
  void initState() {
    super.initState();
    themeController.addListener(_onThemeChanged);
    _fetchLeaves();
    _fetchHolidays();
    if (widget.user['role'] == 'admin') {
      _fetchAdminUsers();
    }
    if (_isPrivileged) {
      _fetchTeamData();
    }
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) {
        _fetchLeaves();
        if (_isPrivileged) {
          _fetchTeamData();
        }
      }
    });
  }

  @override
  void dispose() {
    themeController.removeListener(_onThemeChanged);
    _holidayTitleCtrl.dispose();
    _holidayDateCtrl.dispose();
    _holidayDayCtrl.dispose();
    _leaveTitleCtrl.dispose();
    _leaveNoteCtrl.dispose();
    _autoSyncTimer?.cancel();
    super.dispose();
  }

  Future<void> refreshData() async {
    try {
      await Future.wait([
        _fetchLeaves(),
        _fetchHolidays(),
        if (widget.user['role'] == 'admin') _fetchAdminUsers(),
        if (_isPrivileged) _fetchTeamData(),
      ]);
    } catch (_) {}
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  String _fmtDays(double v) {
    return v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);
  }

  Future<void> _fetchLeaves() async {
    try {
      final res = await apiGetJson('/api/leaves/me', token: widget.token).timeout(const Duration(seconds: 3));
      if (res is Map && mounted) {
        setState(() {
          _totalAllotted = double.tryParse(res['total_allotted']?.toString() ?? '') ?? 25.0;
          _usedDays = double.tryParse(res['used_days']?.toString() ?? '') ?? 5.5;
          _remainingDays = double.tryParse(res['remaining_days']?.toString() ?? '') ?? 19.5;
          _leavesList = res['leaves'] is List ? res['leaves'] : [];
          _loadingLeaves = false;
        });
      } else {
        if (mounted) setState(() => _loadingLeaves = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingLeaves = false);
    }
  }

  Future<void> _fetchHolidays() async {
    try {
      final list = await apiGet('/api/holidays');
      if (mounted) {
        setState(() {
          _holidaysList = list;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchAdminUsers() async {
    setState(() => _loadingUsers = true);
    try {
      final list = await apiGet('/api/admin/users', token: widget.token);
      if (mounted) setState(() => _usersList = list);
    } catch (_) {}
    if (mounted) setState(() => _loadingUsers = false);
  }

  Future<void> _fetchTeamData() async {
    if (!_isPrivileged) return;
    setState(() => _loadingTeam = true);
    try {
      final hierarchyRes = await apiGetJson('/api/team/hierarchy', token: widget.token);
      final leavesRes = await apiGetJson('/api/team/leaves', token: widget.token);
      if (mounted) {
        setState(() {
          if (hierarchyRes is Map<String, dynamic>) {
            _teamHierarchy = hierarchyRes;
          }
          if (leavesRes is List) {
            _teamLeavesList = leavesRes;
          }
          _loadingTeam = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingTeam = false);
    }
  }

  Future<void> _actionTeamLeave(int leaveId, String action, {String note = ''}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await apiPost('/api/team/leaves/$leaveId/action', {
        'action': action,
        'note': note,
      }, token: widget.token);
      if (res['error'] != null) {
        messenger.showSnackBar(SnackBar(content: Text('Error: ${res['error']}')));
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(action == 'approve' ? '✅ Leave approved successfully!' : '❌ Leave rejected.'),
            backgroundColor: action == 'approve' ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
          ),
        );
        _fetchTeamData();
        _fetchLeaves();
      }
    } catch (e) {
      messenger.showSnackBar(const SnackBar(content: Text('Failed to update leave status.')));
    }
  }

  void _showSubordinateAttendanceDialog(Map<String, dynamic> member, bool isDark) {
    final empId = member['emp_id'] ?? member['id'];
    final name = member['name'] ?? member['full_name'] ?? 'Team Member';
    final dialogBg = isDark ? const Color(0xFF131722) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF171C23);
    final textSecondary = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF524437);

    showDialog(
      context: context,
      builder: (ctx) {
        return FutureBuilder(
          future: apiGet('/api/team/attendance?employee_id=$empId', token: widget.token),
          builder: (context, snapshot) {
            final logs = (snapshot.data is List) ? (snapshot.data as List) : [];
            return AlertDialog(
              backgroundColor: dialogBg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: const Color(0xFF3F83F8).withAlpha(40),
                    child: Text(
                      name[0].toUpperCase(),
                      style: const TextStyle(color: Color(0xFF3F83F8), fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: TextStyle(color: textPrimary, fontSize: 15, fontWeight: FontWeight.w800)),
                        Text('Attendance Logs (#$empId)', style: TextStyle(color: textSecondary, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 380,
                child: snapshot.connectionState == ConnectionState.waiting
                    ? const Center(child: CircularProgressIndicator())
                    : logs.isEmpty
                        ? Center(
                            child: Text('No attendance records found for this team member.',
                                style: TextStyle(color: textSecondary, fontSize: 13)),
                          )
                        : ListView.separated(
                            itemCount: logs.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = logs[index];
                              final dateStr = item['date'] ?? 'N/A';
                              final signIn = item['sign_in'] ?? '--:--';
                              final signOut = item['sign_out'] ?? 'Active Shift';
                              final totalMins = item['total_minutes'];

                              return Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF1A1E2B) : const Color(0xFFF0F4FD),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(Icons.access_time_rounded, color: Color(0xFF3F83F8), size: 18),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(dateStr, style: TextStyle(color: textPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
                                          const SizedBox(height: 2),
                                          Text('In: $signIn  •  Out: $signOut',
                                              style: TextStyle(color: textSecondary, fontSize: 11, fontWeight: FontWeight.w500)),
                                        ],
                                      ),
                                    ),
                                    if (totalMins != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF10B981).withAlpha(30),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          '${(totalMins / 60).toStringAsFixed(1)}h',
                                          style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmWithdrawLeave(Map<String, dynamic> req, bool isDark) async {
    final leaveId = req['id'];
    final title = req['title'] ?? 'Leave Request';
    final startDate = req['start_date'] != null ? DateFormat('d MMM yyyy').format(DateTime.parse(req['start_date'].toString().split('T')[0])) : '';
    final endDate = req['end_date'] != null ? DateFormat('d MMM yyyy').format(DateTime.parse(req['end_date'].toString().split('T')[0])) : startDate;
    final dateStr = startDate == endDate ? startDate : '$startDate - $endDate';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1B202D) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.undo_rounded, color: Color(0xFFEA580C)),
            SizedBox(width: 8),
            Text('Withdraw Leave', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ],
        ),
        content: Text(
          'Are you sure you want to withdraw your $title for $dateStr?\n\nThis will cancel your leave request and restore your balance.',
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEA580C),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Withdraw', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final res = await apiPost('/api/leaves/$leaveId/withdraw', {}, token: widget.token);
        if (res['error'] != null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: ${res['error']}')),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Leave request withdrawn successfully!')),
            );
            _fetchLeaves();
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to withdraw leave: $e')),
          );
        }
      }
    }
  }

  void _showApplyLeaveModal(bool isDark, {Map<String, dynamic>? editingLeave}) {
    final bool isEditing = editingLeave != null;
    final dialogBg = isDark ? const Color(0xFF131722) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF171C23);
    final textSecondary = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF524437);
    const amberPrimary = Color(0xFFF5A952);
    const amberDark = Color(0xFF895100);

    DateTime fromDate = DateTime.now();
    DateTime toDate = DateTime.now();
    if (isEditing && editingLeave['start_date'] != null) {
      fromDate = DateTime.tryParse(editingLeave['start_date'].toString().split('T')[0]) ?? DateTime.now();
      toDate = editingLeave['end_date'] != null
          ? (DateTime.tryParse(editingLeave['end_date'].toString().split('T')[0]) ?? fromDate)
          : fromDate;
    }

    String fromSession = 'Session 1';
    String toSession = 'Session 2';
    String selectedLeaveType = isEditing && editingLeave['leave_type'] != null
        ? editingLeave['leave_type'].toString()
        : 'Earned Leave'; // 'Earned Leave', 'Loss Of Pay', 'Comp - Off'
    bool submitting = false;

    _leaveTitleCtrl.text = isEditing ? (editingLeave['title'] ?? '') : '';
    _leaveNoteCtrl.text = isEditing ? (editingLeave['note'] ?? '') : '';

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
            final daysStr = _fmtDays(calculatedDays);
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
                          Text(isEditing ? 'Edit Leave' : 'Apply Leave',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: textPrimary)),
                          Text(isEditing ? 'Update your leave request details' : 'Submit your leave request with session details',
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

                  // ── 1. Leave Type Dropdown (Matches Screenshot) ─────────────────
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

                  // ── 2. From Date & Session Row (Matches Screenshot) ──────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // From Date Box
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

                      // From Session Box
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

                  // ── 3. To Date & Session Row (Matches Screenshot) ────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // To Date Box
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

                      // To Session Box
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

                  // ── 4. Dynamic Duration & Balance Info Card ──────────────────────
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
                                    ? 'Will deduct $daysStr day(s) from Earned Leave balance (${_fmtDays(_remainingDays)} Days currently available).'
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

                  // ── 5. Reason & Notes ───────────────────────────────────────────
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
                        hintText: 'e.g. Family Vacation or Medical Emergency',
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

                  // ── 6. Action Buttons ───────────────────────────────────────────
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
                                    final payload = {
                                      'title': _leaveTitleCtrl.text.trim().isEmpty ? selectedLeaveType : _leaveTitleCtrl.text.trim(),
                                      'leave_type': selectedLeaveType,
                                      'start_date': DateFormat('yyyy-MM-dd').format(fromDate),
                                      'end_date': DateFormat('yyyy-MM-dd').format(toDate),
                                      'from_session': fromSession,
                                      'to_session': toSession,
                                      'days_count': calculatedDays,
                                      'note': _leaveNoteCtrl.text.trim(),
                                    };

                                    final res = isEditing
                                        ? await apiPut('/api/leaves/${editingLeave['id']}', payload, token: widget.token)
                                        : await apiPost('/api/leaves', payload, token: widget.token);

                                    if (res['error'] != null) {
                                      messenger.showSnackBar(
                                        SnackBar(content: Text('Error: ${res['error']}')),
                                      );
                                    } else {
                                      navigator.pop();
                                      _fetchLeaves();
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text(isEditing
                                              ? 'Leave application updated ($daysStr ${calculatedDays == 1.0 || calculatedDays == 0.5 ? 'Day' : 'Days'})!'
                                              : '$selectedLeaveType request ($daysStr ${calculatedDays == 1.0 || calculatedDays == 0.5 ? 'Day' : 'Days'}) submitted!'),
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
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(isEditing ? 'Save Changes' : 'Submit Request', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                                    const SizedBox(width: 6),
                                    Icon(isEditing ? Icons.check_rounded : Icons.arrow_forward_rounded, size: 16),
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

  void _showAddHolidayDialog(bool isDark) {
    _holidayTitleCtrl.clear();
    _holidayDateCtrl.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _holidayDayCtrl.text = DateFormat('EEEE').format(DateTime.now());

    final dialogBg = isDark ? const Color(0xFF131722) : Colors.white;
    final textCol = isDark ? Colors.white : const Color(0xFF111827);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: dialogBg,
        title: Text('Add Holiday', style: TextStyle(color: textCol, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _holidayTitleCtrl,
              style: TextStyle(color: textCol),
              decoration: const InputDecoration(labelText: 'Holiday Title', labelStyle: TextStyle(color: Color(0xFF6B7280))),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _holidayDateCtrl,
              style: TextStyle(color: textCol),
              decoration: const InputDecoration(labelText: 'Date (YYYY-MM-DD)', labelStyle: TextStyle(color: Color(0xFF6B7280))),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _holidayDayCtrl,
              style: TextStyle(color: textCol),
              decoration: const InputDecoration(labelText: 'Weekday (e.g. Friday)', labelStyle: TextStyle(color: Color(0xFF6B7280))),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF6B7280))),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_holidayTitleCtrl.text.isNotEmpty && _holidayDateCtrl.text.isNotEmpty) {
                await apiPost('/api/admin/holidays', {
                  'title': _holidayTitleCtrl.text.trim(),
                  'date': _holidayDateCtrl.text.trim(),
                  'weekday': _holidayDayCtrl.text.trim(),
                }, token: widget.token);
                if (mounted) {
                  Navigator.pop(context);
                  _fetchHolidays();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Holiday added successfully!')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3F83F8)),
            child: const Text('Add', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showUserAttendanceDialog(Map<String, dynamic> u, bool isDark) async {
    final dialogBg = isDark ? const Color(0xFF131722) : Colors.white;
    final textCol = isDark ? Colors.white : const Color(0xFF111827);
    final empId = u['emp_id'] ?? u['id'];

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: dialogBg,
        title: Row(
          children: [
            const Icon(Icons.edit_calendar_rounded, color: Color(0xFF3F83F8), size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Attendance Logs: ${u['full_name'] ?? empId}',
                style: TextStyle(color: textCol, fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: FutureBuilder<List<dynamic>>(
          future: apiGet('/api/admin/attendance/$empId', token: widget.token),
          builder: (ctx, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()));
            }
            final list = snapshot.data ?? [];
            if (list.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text('No attendance records found for $empId', style: const TextStyle(color: Color(0xFF6B7280))),
              );
            }
            return SizedBox(
              width: double.maxFinite,
              height: 350,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: list.length,
                itemBuilder: (_, idx) {
                  final rec = list[idx];
                  final dStr = rec['date'] ?? 'Record';
                  final ciStr = formatAppTime(rec['clock_in']);
                  final coStr = formatAppTime(rec['clock_out']);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1A1E2B) : const Color(0xFFF0F4FD),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(dStr, style: TextStyle(color: textCol, fontWeight: FontWeight.w800, fontSize: 13)),
                            Text('In: $ciStr  •  Out: $coStr', style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11)),
                          ],
                        ),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _showEditAttendanceDialog(rec, isDark, u);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF5A952),
                            foregroundColor: const Color(0xFF895100),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            minimumSize: Size.zero,
                          ),
                          child: const Text('Overwrite', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Color(0xFF6B7280))),
          ),
        ],
      ),
    );
  }

  void _showEditAttendanceDialog(Map<String, dynamic> rec, bool isDark, Map<String, dynamic> user) {
    final dialogBg = isDark ? const Color(0xFF131722) : Colors.white;
    final textCol = isDark ? Colors.white : const Color(0xFF111827);

    final dateCtrl = TextEditingController(text: rec['date'] ?? DateFormat('yyyy-MM-dd').format(DateTime.now()));
    final ciDt = parseAppDateTime(rec['clock_in']);
    final coDt = parseAppDateTime(rec['clock_out']);
    final ciCtrl = TextEditingController(
      text: ciDt != null ? DateFormat('HH:mm:ss').format(ciDt) : '09:30:00',
    );
    final coCtrl = TextEditingController(
      text: coDt != null ? DateFormat('HH:mm:ss').format(coDt) : '18:30:00',
    );

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: dialogBg,
        title: Text('Overwrite Attendance #${rec['id']}', style: TextStyle(color: textCol, fontWeight: FontWeight.w800, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: dateCtrl,
              style: TextStyle(color: textCol),
              decoration: const InputDecoration(labelText: 'Date (YYYY-MM-DD)', labelStyle: TextStyle(color: Color(0xFF6B7280))),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ciCtrl,
              style: TextStyle(color: textCol),
              decoration: const InputDecoration(labelText: 'Sign In Time (HH:MM:SS)', labelStyle: TextStyle(color: Color(0xFF6B7280))),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: coCtrl,
              style: TextStyle(color: textCol),
              decoration: const InputDecoration(labelText: 'Sign Out Time (HH:MM:SS)', labelStyle: TextStyle(color: Color(0xFF6B7280))),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF6B7280))),
          ),
          ElevatedButton(
            onPressed: () async {
              await apiPut('/api/admin/attendance/${rec['id']}', {
                'date': dateCtrl.text.trim(),
                'sign_in': ciCtrl.text.trim(),
                'sign_out': coCtrl.text.trim(),
              }, token: widget.token);

              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Attendance overwritten successfully in PostgreSQL!')),
                );
                _showUserAttendanceDialog(user, isDark);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF5A952), foregroundColor: const Color(0xFF895100)),
            child: const Text('Save Overwrite', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  void _showEditUserDialog(Map<String, dynamic> u, bool isDark) {
    final nameCtrl = TextEditingController(text: u['full_name'] ?? '');
    final deptCtrl = TextEditingController(text: u['department'] ?? '');
    final desigCtrl = TextEditingController(text: u['designation'] ?? '');
    final phoneCtrl = TextEditingController(text: u['phone_number'] ?? '');

    final dialogBg = isDark ? const Color(0xFF131722) : Colors.white;
    final textCol = isDark ? Colors.white : const Color(0xFF111827);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: dialogBg,
        title: Text('Edit User: ${u['emp_id']}', style: TextStyle(color: textCol, fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: TextStyle(color: textCol),
                decoration: const InputDecoration(labelText: 'Full Name', labelStyle: TextStyle(color: Color(0xFF6B7280))),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: deptCtrl,
                style: TextStyle(color: textCol),
                decoration: const InputDecoration(labelText: 'Department', labelStyle: TextStyle(color: Color(0xFF6B7280))),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: desigCtrl,
                style: TextStyle(color: textCol),
                decoration: const InputDecoration(labelText: 'Designation', labelStyle: TextStyle(color: Color(0xFF6B7280))),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: phoneCtrl,
                style: TextStyle(color: textCol),
                decoration: const InputDecoration(labelText: 'Phone', labelStyle: TextStyle(color: Color(0xFF6B7280))),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF6B7280))),
          ),
          ElevatedButton(
            onPressed: () async {
              String rawPhone = phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
              if (rawPhone.length == 12 && rawPhone.startsWith('91')) {
                rawPhone = rawPhone.substring(2);
              } else if (rawPhone.length == 11 && rawPhone.startsWith('0')) {
                rawPhone = rawPhone.substring(1);
              } else if (rawPhone.length > 10) {
                rawPhone = rawPhone.substring(rawPhone.length - 10);
              }
              await apiPut('/api/admin/users/${u['id']}', {
                'full_name': nameCtrl.text.trim(),
                'department': deptCtrl.text.trim(),
                'designation': desigCtrl.text.trim(),
                'phone_number': rawPhone,
              }, token: widget.token);
              if (mounted) {
                Navigator.pop(context);
                _fetchAdminUsers();
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3F83F8)),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
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
    final borderCol = isDark ? const Color(0xFF1F2633) : const Color(0xFFEAEFF8);
    final textPrimary = isDark ? Colors.white : const Color(0xFF171C23);
    final textSecondary = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF524437);
    const amberPrimary = Color(0xFFF5A952);
    const amberDark = Color(0xFF895100);

    final rawName = widget.user['name'] ?? 'Robert Smith';
    final isAdmin = widget.user['role'] == 'admin';

    final filteredRequests = _leavesList.where((req) {
      final st = req['status']?.toString().toLowerCase() ?? '';
      if (_activeFilter == 'All') return true;
      if (_activeFilter == 'Pending') return st.contains('pending');
      if (_activeFilter == 'Approved') return st.contains('approved');
      if (_activeFilter == 'Rejected') return st.contains('rejected');
      return false;
    }).toList();

    int flexUsed = (_usedDays * 10).round().clamp(1, 250);
    int flexRemaining = (_remainingDays * 10).round().clamp(1, 250);

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
                Text('MONARCH HR',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: textSecondary, letterSpacing: 1.1)),
                Text('Leave Management',
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
      body: (_loadingLeaves && _mainTabSegment == 0) || (_loadingTeam && _mainTabSegment == 1)
          ? const Center(child: CircularProgressIndicator())
          : GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: (_) => _leavesDragDeltaX = 0,
              onHorizontalDragUpdate: (details) => _leavesDragDeltaX += details.delta.dx,
              onHorizontalDragEnd: (details) {
                final velocity = details.primaryVelocity ?? 0;
                final isSwipeLeft = velocity < -180 || _leavesDragDeltaX < -50;
                final isSwipeRight = velocity > 180 || _leavesDragDeltaX > 50;
                if (!isSwipeLeft && !isSwipeRight) return;

                if (_isPrivileged) {
                  if (isSwipeLeft && _mainTabSegment == 0) {
                    setState(() => _mainTabSegment = 1);
                    _fetchTeamData();
                  } else if (isSwipeRight && _mainTabSegment == 1) {
                    setState(() => _mainTabSegment = 0);
                  }
                } else {
                  final filters = ['All', 'Pending', 'Approved', 'Rejected'];
                  final currentIndex = filters.indexOf(_activeFilter);
                  if (currentIndex != -1) {
                    if (isSwipeLeft && currentIndex < filters.length - 1) {
                      setState(() => _activeFilter = filters[currentIndex + 1]);
                    } else if (isSwipeRight && currentIndex > 0) {
                      setState(() => _activeFilter = filters[currentIndex - 1]);
                    }
                  }
                }
              },
              child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              children: [
                // ── Privileged Role Tab Switcher (Manager / Team Leader / Admin) ──
                if (_isPrivileged) ...[
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1A1E2B) : const Color(0xFFF0F4FD),
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
                                    Icons.beach_access_rounded,
                                    size: 16,
                                    color: _mainTabSegment == 0 ? const Color(0xFF3F83F8) : textSecondary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'My Leaves',
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
                              _fetchTeamData();
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
                                    _isManager ? Icons.corporate_fare_rounded : Icons.groups_rounded,
                                    size: 16,
                                    color: _mainTabSegment == 1 ? amberDark : textSecondary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _isManager ? 'Team & Approvals' : 'Team Hub',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: _mainTabSegment == 1 ? textPrimary : textSecondary,
                                    ),
                                  ),
                                  if ((_teamHierarchy?['pending_approvals_count'] ?? 0) > 0) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFF2A55),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        '${_teamHierarchy!['pending_approvals_count']}',
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
                  _buildTeamManagementView(isDark, bgCard, bgScaffold, borderCol, textPrimary, textSecondary, amberPrimary, amberDark),
                ] else ...[
                // ── Annual Leave Overview Hero Card ────────────────────────────────
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('BALANCE STATUS',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textSecondary, letterSpacing: 1.1)),
                              const SizedBox(height: 2),
                              Text('Annual Leave Overview',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary, letterSpacing: -0.4)),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF9FF1BD).withAlpha(120),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.celebration_rounded, color: Color(0xFF1B7047), size: 14),
                                const SizedBox(width: 4),
                                Text('${_fmtDays(_remainingDays)} Days Left',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF002110))),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 18),

                      // Unified Progress Bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          height: 10,
                          color: isDark ? const Color(0xFF1F2633) : const Color(0xFFEAEFF8),
                          child: Row(
                            children: [
                              Expanded(flex: flexUsed, child: Container(color: amberPrimary)),
                              Expanded(flex: flexRemaining, child: Container(color: Colors.transparent)),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 18),

                      // 3 Breakdown Sub-Cards
                      Row(
                        children: [
                          Expanded(
                            child: _leaveTypeCard('Annual Allotted', _fmtDays(_totalAllotted), '${_fmtDays(_totalAllotted)}d / Year', amberPrimary, isDark, textPrimary, textSecondary),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _leaveTypeCard('Days Taken', _fmtDays(_usedDays), 'Used', const Color(0xFFFFA276), isDark, textPrimary, textSecondary),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _leaveTypeCard('Available', _fmtDays(_remainingDays), 'Remaining', const Color(0xFF86D7A5), isDark, textPrimary, textSecondary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── Planning Away Banner Card ──────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: bgCard,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: borderCol),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: amberPrimary.withAlpha(38),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.flight_takeoff_rounded, color: amberDark, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Planning away?',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: textPrimary)),
                            const SizedBox(height: 2),
                            Text('Submit your request easily',
                                style: TextStyle(fontSize: 11, color: textSecondary, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => _showApplyLeaveModal(isDark),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Apply Leave'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: amberPrimary,
                          foregroundColor: const Color(0xFF6B3F00),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          elevation: 0,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── Recent Applications Section ────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Recent Applications',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary, letterSpacing: -0.4)),
                    Text('${filteredRequests.length} records',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textSecondary)),
                  ],
                ),
                const SizedBox(height: 12),

                // Filter Tray
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['All', 'Pending', 'Approved', 'Rejected'].map((filter) {
                      final isSel = _activeFilter == filter;
                      return GestureDetector(
                        onTap: () => setState(() => _activeFilter = filter),
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSel ? amberPrimary : bgCard,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: isSel ? amberPrimary : borderCol),
                          ),
                          child: Text(
                            filter,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isSel ? const Color(0xFF6B3F00) : textSecondary,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 14),

                // Leave Request Cards List
                if (filteredRequests.isNotEmpty)
                  ...filteredRequests.map((req) {
                    final status = req['status']?.toString() ?? 'Pending Review';
                    final isPending = status.toLowerCase().contains('pending');
                    final isApproved = status.toLowerCase().contains('approved');
                    final daysCount = req['days_count'] ?? 1;

                    final startDate = req['start_date'] != null ? DateFormat('d MMM yyyy').format(DateTime.parse(req['start_date'])) : '22 Apr 2026';
                    final endDate = req['end_date'] != null ? DateFormat('d MMM yyyy').format(DateTime.parse(req['end_date'])) : startDate;
                    final dateRangeStr = startDate == endDate ? startDate : '$startDate - $endDate';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: bgCard,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: borderCol),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isPending ? const Color(0xFFFFDBCC) : const Color(0xFF9FF1BD).withAlpha(120),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isPending ? Icons.luggage_outlined : Icons.check_circle_outline,
                                  color: isPending ? const Color(0xFF7D3205) : const Color(0xFF1B7047),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(req['title']?.toString() ?? 'Leave Request',
                                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: textPrimary)),
                                    const SizedBox(height: 2),
                                    Text('${req['leave_type'] ?? 'Earned Leave'} • ${_fmtDays(double.tryParse(daysCount.toString()) ?? 1.0)} ${(double.tryParse(daysCount.toString()) ?? 1.0) == 1.0 || (double.tryParse(daysCount.toString()) ?? 1.0) == 0.5 ? 'Day' : 'Days'}',
                                        style: TextStyle(fontSize: 11, color: textSecondary, fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isPending
                                      ? (isDark ? const Color(0xFF261D12) : const Color(0xFFFFDCBC))
                                      : (isApproved
                                          ? (isDark ? const Color(0xFF132A20) : const Color(0xFF9FF1BD).withAlpha(120))
                                          : (isDark ? const Color(0xFF2B1618) : const Color(0xFFFFDAD6))),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Text(
                                  status,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: isPending
                                        ? const Color(0xFF683D00)
                                        : (isApproved ? const Color(0xFF1B7047) : const Color(0xFFBA1A1A)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1A1E2B) : const Color(0xFFF0F4FD),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.calendar_today_rounded, size: 12, color: textSecondary),
                                    const SizedBox(width: 6),
                                    Text(dateRangeStr,
                                        style: TextStyle(fontSize: 11, color: textSecondary, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                                Text(
                                  req['applied_at'] != null
                                      ? DateFormat('d MMM').format(DateTime.parse(req['applied_at']))
                                      : 'Recorded',
                                  style: TextStyle(fontSize: 11, color: textSecondary, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                          if (status.toLowerCase() == 'pending review') ...[
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                InkWell(
                                  onTap: () => _showApplyLeaveModal(isDark, editingLeave: req),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF3B82F6).withAlpha(isDark ? 35 : 20),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: const Color(0xFF3B82F6).withAlpha(80)),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.edit_outlined, size: 13, color: Color(0xFF3B82F6)),
                                        SizedBox(width: 4),
                                        Text(
                                          'Edit',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF3B82F6),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                InkWell(
                                  onTap: () => _confirmWithdrawLeave(req, isDark),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEA580C).withAlpha(isDark ? 35 : 20),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: const Color(0xFFEA580C).withAlpha(80)),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.undo_rounded, size: 13, color: Color(0xFFEA580C)),
                                        SizedBox(width: 4),
                                        Text(
                                          'Withdraw Leave',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFFEA580C),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
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
                      child: Text('No leave records found under this filter',
                          style: TextStyle(color: textSecondary, fontSize: 13)),
                    ),
                  ),

                const SizedBox(height: 24),

                // ── Upcoming Holidays Section ──────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.beach_access_rounded, color: amberDark, size: 20),
                        const SizedBox(width: 6),
                        Text('Upcoming Holidays',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary, letterSpacing: -0.4)),
                      ],
                    ),
                    InkWell(
                      onTap: () => _showAllHolidaysMonthWiseModal(isDark),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: amberPrimary.withAlpha(45),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: amberPrimary.withAlpha(90)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.calendar_month_rounded, size: 14, color: amberDark),
                            SizedBox(width: 4),
                            Text('More Holidays',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: amberDark)),
                            SizedBox(width: 2),
                            Icon(Icons.chevron_right_rounded, size: 14, color: amberDark),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                Builder(builder: (context) {
                  final nowStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
                  var upcoming = _holidaysList.where((h) {
                    final d = h['date']?.toString() ?? '';
                    return d.compareTo(nowStr) >= 0;
                  }).toList();
                  if (upcoming.isEmpty && _holidaysList.isNotEmpty) {
                    upcoming = _holidaysList.take(2).toList();
                  }
                  final displayHolidays = upcoming.take(2).toList();

                  if (displayHolidays.isEmpty) {
                    return GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.2,
                      children: [
                        _holidayTile('Anant Chaturdashi', '25 September 2026', 'Public', const Color(0xFF9FF1BD), bgCard, borderCol, textPrimary, textSecondary),
                        _holidayTile('Gandhi Jayanti', '02 October 2026', 'Company', const Color(0xFFFFDBCC), bgCard, borderCol, textPrimary, textSecondary),
                      ],
                    );
                  }

                  return GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.2,
                    children: displayHolidays.map((h) {
                      final title = h['title'] ?? 'Holiday';
                      final dateStr = h['date']?.toString() ?? '';
                      DateTime? parsedDt;
                      try { parsedDt = DateTime.parse(dateStr); } catch (_) {}
                      final formattedDate = parsedDt != null ? DateFormat('dd MMMM yyyy').format(parsedDt) : dateStr;
                      final weekday = h['weekday'] ?? (parsedDt != null ? DateFormat('EEEE').format(parsedDt) : '');
                      return _holidayTile(title, '$formattedDate\n$weekday', 'Public', const Color(0xFF9FF1BD), bgCard, borderCol, textPrimary, textSecondary);
                    }).toList(),
                  );
                }),

                if (isAdmin) ...[
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: bgCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF3F83F8)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.admin_panel_settings_rounded, color: Color(0xFF3F83F8), size: 24),
                            const SizedBox(width: 8),
                            Text('Admin Management (SUMIT)',
                                style: TextStyle(color: textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => _showAddHolidayDialog(isDark),
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('Add Holiday'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF3F83F8),
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('User Accounts Directory',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textPrimary)),
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, color: Color(0xFF3F83F8)),
                        onPressed: _fetchAdminUsers,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  if (_loadingUsers)
                    const Center(child: CircularProgressIndicator())
                  else
                    ..._usersList.map((u) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: bgCard,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: borderCol),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: const Color(0xFF3F83F8).withAlpha(38),
                                  child: Text(
                                    (u['full_name'] ?? 'U')[0].toUpperCase(),
                                    style: const TextStyle(color: Color(0xFF3F83F8), fontWeight: FontWeight.w700),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        u['full_name'] ?? u['username'] ?? 'User',
                                        style: TextStyle(color: textPrimary, fontWeight: FontWeight.w700, fontSize: 14),
                                      ),
                                      Text(
                                        'Emp ID: ${u['emp_id'] ?? u['id']} | ${u['role'] ?? 'employee'}',
                                        style: TextStyle(color: textSecondary, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit_rounded, color: Color(0xFF3F83F8), size: 18),
                                  onPressed: () => _showEditUserDialog(u, isDark),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () => _showUserAttendanceDialog(u, isDark),
                                icon: const Icon(Icons.edit_calendar_rounded, size: 14),
                                label: const Text('View / Overwrite Attendance'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFF5A952),
                                  foregroundColor: const Color(0xFF895100),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  elevation: 0,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
                ], // Close the else ...[ block for My Leaves

                const SizedBox(height: 20),
              ],
            ),
          ),
    );
  }

  // ── Team Leadership & Approval Hub View ─────────────────────────────────────
  Widget _buildTeamManagementView(
    bool isDark,
    Color bgCard,
    Color bgScaffold,
    Color borderCol,
    Color textPrimary,
    Color textSecondary,
    Color amberPrimary,
    Color amberDark,
  ) {
    final deptName = _teamHierarchy?['department'] ?? widget.user['department'] ?? 'General';
    final isMgr = _isManager;

    final members = (_teamHierarchy?['all_members'] is List)
        ? (_teamHierarchy!['all_members'] as List)
        : (_teamHierarchy?['members'] is List)
            ? (_teamHierarchy!['members'] as List)
            : [];

    final teamLeaders = (_teamHierarchy?['team_leaders'] is List)
        ? (_teamHierarchy!['team_leaders'] as List)
        : [];

    final departments = (_teamHierarchy?['departments'] is List)
        ? (_teamHierarchy!['departments'] as List)
        : [];

    final pendingCount = _teamHierarchy?['pending_approvals_count'] ?? 0;
    final totalMembers = members.length;
    final presentMembers = members.where((m) => m['today_status'] == 'Clocked In' || m['today_status'] == 'Clocked Out').length;

    // Extract unique departments from all members & departments list
    final Set<String> allDeptSet = {'All'};
    for (var m in members) {
      final d = m['department']?.toString().trim();
      if (d != null && d.isNotEmpty) {
        allDeptSet.add(d);
      }
    }
    for (var d in departments) {
      final dName = (d is Map ? d['department'] ?? d['name'] : d)?.toString().trim();
      if (dName != null && dName.isNotEmpty) {
        allDeptSet.add(dName);
      }
    }
    final allDeptList = allDeptSet.toList();

    // Filter members according to selected role and department
    final filteredMembers = members.where((m) {
      final role = (m['role'] ?? '').toString().toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
      final isTL = role == 'teamleader' || role == 'subteamlead' || role == 'seniorteamlead' || role == 'lead' || role == 'tl';
      final isEmp = role == 'employee' || (!isTL && role != 'manager' && role != 'admin' && role != 'projectmanager');

      // 1. Role filter
      if (_teamAttendanceRoleFilter == 'Team Leader' && !isTL) return false;
      if (_teamAttendanceRoleFilter == 'Employee' && !isEmp) return false;

      // 2. Department filter
      if (_teamAttendanceDeptFilter != 'All') {
        final mDept = (m['department'] ?? '').toString().trim();
        if (mDept.toLowerCase() != _teamAttendanceDeptFilter.toLowerCase()) return false;
      }

      return true;
    }).toList();

    final filteredTeamLeaves = _teamLeavesList.where((req) {
      final st = (req['status'] ?? '').toString().toLowerCase();
      if (_teamSubFilter == 'All') return true;
      if (_teamSubFilter == 'Pending') return st.contains('pending');
      if (_teamSubFilter == 'Approved') return st.contains('approved');
      if (_teamSubFilter == 'Rejected') return st.contains('rejected');
      return false;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Hierarchy Header Hero Card ───────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: bgCard,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderCol),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0F171C23),
                blurRadius: 20,
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
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (isMgr ? const Color(0xFF3F83F8) : amberPrimary).withAlpha(40),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isMgr ? Icons.corporate_fare_rounded : Icons.supervisor_account_rounded,
                          color: isMgr ? const Color(0xFF2563EB) : amberDark,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isMgr ? '👔 Manager Operations' : '👥 Team Leader Portal',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textPrimary, letterSpacing: -0.3),
                          ),
                          Text(
                            isMgr
                                ? 'Full Organization & Team Leader Oversight'
                                : 'Department: $deptName • Level 2 Approval',
                            style: TextStyle(fontSize: 11, color: textSecondary, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    color: const Color(0xFF3F83F8),
                    onPressed: _fetchTeamData,
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Stat Bento Cluster
              Row(
                children: [
                  Expanded(
                    child: _teamStatTile(
                      isMgr ? '${teamLeaders.length} Leads' : '$totalMembers Members',
                      isMgr ? 'Team Leaders' : 'Subordinates',
                      Icons.people_alt_rounded,
                      const Color(0xFF3F83F8),
                      isDark,
                      textPrimary,
                      textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _teamStatTile(
                      '$presentMembers/$totalMembers',
                      'Present Today',
                      Icons.how_to_reg_rounded,
                      const Color(0xFF10B981),
                      isDark,
                      textPrimary,
                      textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _teamStatTile(
                      '$pendingCount Pending',
                      'Leave Action',
                      Icons.pending_actions_rounded,
                      pendingCount > 0 ? const Color(0xFFFF2A55) : const Color(0xFF6B7280),
                      isDark,
                      textPrimary,
                      textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ── SECTION 1: Subordinate Leave Approvals / Status Oversight ──────────
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isMgr ? 'Leave Requests Status' : 'Leave Request Approvals',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textPrimary, letterSpacing: -0.3),
                        ),
                        Text(
                          isMgr
                              ? 'Monitor leave status across all departments'
                              : 'Review pending leaves from employees in $deptName',
                          style: TextStyle(fontSize: 11, color: textSecondary),
                        ),
                      ],
                    ),
                  ),
                  if (pendingCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF2A55),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isMgr ? '$pendingCount Pending' : '$pendingCount Action Needed',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),

              // Filter Chips (Only for Manager who monitors all statuses; TL only has pending requests)
              if (isMgr) ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['All', 'Pending', 'Approved', 'Rejected'].map((filter) {
                      final isSel = _teamSubFilter == filter;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => setState(() => _teamSubFilter = filter),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: isSel ? amberPrimary : (isDark ? const Color(0xFF1A1E2B) : const Color(0xFFF0F4FD)),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              filter,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isSel ? amberDark : textSecondary,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              if (filteredTeamLeaves.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1A1E2B) : const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.done_all_rounded, size: 36, color: const Color(0xFF10B981).withAlpha(160)),
                      const SizedBox(height: 8),
                      Text(
                        isMgr ? 'No Leave Records' : 'All Caught Up!',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isMgr
                            ? 'There are no leave requests matching this filter.'
                            : 'No pending leave requests requiring your review.',
                        style: TextStyle(fontSize: 11, color: textSecondary),
                      ),
                    ],
                  ),
                )
              else
                ...filteredTeamLeaves.map((leave) => _buildTeamLeaveCard(
                      leave,
                      isDark,
                      bgCard,
                      borderCol,
                      textPrimary,
                      textSecondary,
                      canAction: !isMgr,
                    )),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ── SECTION 2: Team Punch In & Out Live Monitor ──────────────────────
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Team Attendance & Punches',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textPrimary, letterSpacing: -0.3)),
                        Text('Live punch in/out status for today (${DateFormat('d MMM yyyy').format(DateTime.now())})',
                            style: TextStyle(fontSize: 11, color: textSecondary)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: amberPrimary.withAlpha(40),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${filteredMembers.length} of ${members.length}',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: amberDark),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // ── Filter 1: Role Selector (All / Team Leader / Employee) ─────
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _roleFilterChip('All', '👥 All Roles (${members.length})', isDark, bgCard, borderCol, textPrimary, textSecondary, amberPrimary, amberDark),
                    const SizedBox(width: 8),
                    _roleFilterChip('Team Leader', '👔 Team Leaders', isDark, bgCard, borderCol, textPrimary, textSecondary, amberPrimary, amberDark),
                    const SizedBox(width: 8),
                    _roleFilterChip('Employee', '👤 Employees', isDark, bgCard, borderCol, textPrimary, textSecondary, amberPrimary, amberDark),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // ── Filter 2: Department Selector (All / Dept 1 / Dept 2 ...) ──
              if (allDeptList.length > 1) ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: allDeptList.map((dept) {
                      final isSel = _teamAttendanceDeptFilter.toLowerCase() == dept.toLowerCase();
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: GestureDetector(
                          onTap: () => setState(() => _teamAttendanceDeptFilter = dept),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: isSel
                                  ? (isDark ? const Color(0xFF1E293B) : const Color(0xFFE0F2FE))
                                  : (isDark ? const Color(0xFF141824) : const Color(0xFFF1F5F9)),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSel ? const Color(0xFF0284C7) : borderCol,
                                width: isSel ? 1.2 : 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.business_rounded,
                                  size: 13,
                                  color: isSel ? const Color(0xFF0284C7) : textSecondary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  dept,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isSel ? FontWeight.w800 : FontWeight.w500,
                                    color: isSel ? (isDark ? Colors.white : const Color(0xFF0284C7)) : textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // Members List
              if (filteredMembers.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1A1E2B) : const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.person_off_rounded, size: 36, color: textSecondary.withAlpha(120)),
                      const SizedBox(height: 8),
                      Text('No Members Found', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textPrimary)),
                      const SizedBox(height: 2),
                      Text('No team members match the selected filter.', style: TextStyle(fontSize: 11, color: textSecondary)),
                    ],
                  ),
                )
              else
                ...filteredMembers.map((m) => _buildMemberPunchTile(m, isDark, bgCard, borderCol, textPrimary, textSecondary)),
            ],
          ),
        ),

        // ── SECTION 3: Department Summary (for Manager / Admin) ──────────────
        if (isMgr && departments.isNotEmpty) ...[
          const SizedBox(height: 20),
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
                Text('Department Overview',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textPrimary, letterSpacing: -0.3)),
                Text('Team Leader breakdown across all corporate units',
                    style: TextStyle(fontSize: 11, color: textSecondary)),
                const SizedBox(height: 14),
                ...departments.map((dept) => _buildDepartmentCard(dept, isDark, bgCard, borderCol, textPrimary, textSecondary)),
              ],
            ),
          ),
        ],

        const SizedBox(height: 20),
      ],
    );
  }

  Widget _roleFilterChip(
    String roleKey,
    String label,
    bool isDark,
    Color bgCard,
    Color borderCol,
    Color textPrimary,
    Color textSecondary,
    Color amberPrimary,
    Color amberDark,
  ) {
    final isSel = _teamAttendanceRoleFilter == roleKey;
    return GestureDetector(
      onTap: () => setState(() => _teamAttendanceRoleFilter = roleKey),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSel ? amberPrimary : (isDark ? const Color(0xFF141824) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSel ? amberDark : borderCol,
            width: isSel ? 1.2 : 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
            color: isSel ? amberDark : textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _teamStatTile(String val, String label, IconData icon, Color iconColor, bool isDark, Color textPrimary, Color textSecondary) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1E2B) : const Color(0xFFF0F4FD),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(height: 6),
          Text(val, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: textPrimary), maxLines: 1),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 10, color: textSecondary, fontWeight: FontWeight.w600), maxLines: 1),
        ],
      ),
    );
  }

  Widget _buildTeamLeaveCard(
    Map<String, dynamic> leave,
    bool isDark,
    Color bgCard,
    Color borderCol,
    Color textPrimary,
    Color textSecondary, {
    bool canAction = true,
  }) {
    final status = (leave['status'] ?? 'Pending Review').toString();
    final isPending = status == 'Pending Review';
    final isApproved = status == 'Approved';

    final applicantName = leave['employee_name'] ?? 'Employee';
    final applicantRole = leave['role'] ?? 'Employee';
    final dept = leave['department'] ?? 'General';
    final leaveType = (leave['leave_type'] ?? 'Earned Leave').toString();
    final daysCount = (leave['days_count'] is num) ? (leave['days_count'] as num).toDouble() : (double.tryParse(leave['days_count']?.toString() ?? '1.0') ?? 1.0);
    final startDate = (leave['start_date'] ?? '').toString();
    final endDate = (leave['end_date'] ?? startDate).toString();
    final title = (leave['title'] ?? '').toString().trim();
    final note = (leave['note'] ?? '').toString().trim();
    final leaveId = leave['id'];

    // ── Safe Date Formatting ─────────────────────────────────────────────────
    DateTime? sDt;
    DateTime? eDt;
    try {
      if (startDate.isNotEmpty) sDt = DateTime.parse(startDate.split('T')[0]);
    } catch (_) {}
    try {
      if (endDate.isNotEmpty) eDt = DateTime.parse(endDate.split('T')[0]);
    } catch (_) {}

    String formattedDateStr = '';
    if (sDt != null && eDt != null) {
      final sStr = DateFormat('yyyy-MM-dd').format(sDt);
      final eStr = DateFormat('yyyy-MM-dd').format(eDt);
      if (sStr == eStr) {
        formattedDateStr = DateFormat('EEEE, d MMMM yyyy').format(sDt);
      } else {
        formattedDateStr = '${DateFormat('d MMM yyyy').format(sDt)}  ➔  ${DateFormat('d MMM yyyy').format(eDt)}';
      }
    } else if (sDt != null) {
      formattedDateStr = DateFormat('EEEE, d MMMM yyyy').format(sDt);
    } else {
      formattedDateStr = '$startDate to $endDate';
    }

    // ── Duration Text ────────────────────────────────────────────────────────
    String durationStr = '';
    if (daysCount == 1.0) {
      durationStr = '1 Day (Full Day)';
    } else if (daysCount == 0.5) {
      durationStr = '0.5 Day (Half Day)';
    } else {
      final countInt = (daysCount == daysCount.roundToDouble()) ? daysCount.toInt().toString() : daysCount.toString();
      durationStr = '$countInt Days';
    }

    // ── Leave Type Colors ────────────────────────────────────────────────────
    final lTypeLower = leaveType.toLowerCase();
    Color typeBg;
    Color typeColor;

    if (lTypeLower.contains('loss') || lTypeLower.contains('lop') || lTypeLower.contains('unpaid')) {
      typeBg = isDark ? const Color(0xFF2E1A1A) : const Color(0xFFFFECEB);
      typeColor = isDark ? const Color(0xFFFF6B6B) : const Color(0xFFC92A2A);
    } else if (lTypeLower.contains('comp') || lTypeLower.contains('co')) {
      typeBg = isDark ? const Color(0xFF201B2E) : const Color(0xFFF3E8FF);
      typeColor = isDark ? const Color(0xFFA855F7) : const Color(0xFF7E22CE);
    } else {
      typeBg = isDark ? const Color(0xFF26151B) : const Color(0xFFFCE4EC);
      typeColor = isDark ? const Color(0xFFFB7185) : const Color(0xFFB91C68);
    }

    final hasDistinctTitle = title.isNotEmpty && title.toLowerCase() != leaveType.toLowerCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B26) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isPending
              ? (isDark ? const Color(0xFFF5A952).withAlpha(120) : const Color(0xFFFDE68A))
              : borderCol,
          width: isPending ? 1.5 : 1.0,
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withAlpha(8),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Applicant & Status Header ────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: const Color(0xFF3F83F8).withAlpha(30),
                      child: Text(
                        applicantName.isNotEmpty ? applicantName[0].toUpperCase() : 'E',
                        style: const TextStyle(color: Color(0xFF3F83F8), fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            applicantName,
                            style: TextStyle(color: textPrimary, fontWeight: FontWeight.w800, fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          const SizedBox(height: 1),
                          Text(
                            '$applicantRole • $dept',
                            style: TextStyle(color: textSecondary, fontSize: 11, fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isPending
                      ? (isDark ? const Color(0xFF261D12) : const Color(0xFFFEF3C7))
                      : isApproved
                          ? (isDark ? const Color(0xFF132A20) : const Color(0xFFD1FAE5))
                          : (isDark ? const Color(0xFF2B1618) : const Color(0xFFFEE2E2)),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isPending
                        ? (isDark ? const Color(0xFFF5A952).withAlpha(100) : const Color(0xFFFCD34D))
                        : isApproved
                            ? (isDark ? const Color(0xFF34D399).withAlpha(100) : const Color(0xFF86EFAC))
                            : (isDark ? const Color(0xFFF87171).withAlpha(100) : const Color(0xFFFCA5A5)),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isPending
                            ? const Color(0xFFD97706)
                            : isApproved
                                ? const Color(0xFF16A34A)
                                : const Color(0xFFDC2626),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      status,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: isPending
                            ? (isDark ? const Color(0xFFF5A952) : const Color(0xFF92400E))
                            : isApproved
                                ? (isDark ? const Color(0xFF34D399) : const Color(0xFF065F46))
                                : (isDark ? const Color(0xFFF87171) : const Color(0xFF991B1B)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Leave Information & Dates Card ───────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF11151E) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? const Color(0xFF1E2638) : const Color(0xFFE2E8F0),
                width: 0.8,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date Row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6).withAlpha(isDark ? 35 : 20),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.calendar_month_rounded, size: 16, color: Color(0xFF3B82F6)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'LEAVE DATE',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: textSecondary,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            formattedDateStr,
                            style: TextStyle(
                              color: textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Badges: Leave Type & Duration
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: typeBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: typeColor.withAlpha(60)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.flight_takeoff_rounded, size: 11, color: typeColor),
                          const SizedBox(width: 4),
                          Text(
                            leaveType,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: typeColor),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E2638) : const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.schedule_rounded, size: 11, color: textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            durationStr,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textPrimary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Purpose / Title ──────────────────────────────────────────────────
          if (hasDistinctTitle) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Purpose: ',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textSecondary),
                ),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textPrimary),
                  ),
                ),
              ],
            ),
          ],

          // ── Note / Comments ──────────────────────────────────────────────────
          if (note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF141924) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderCol.withAlpha(70)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.format_quote_rounded, size: 14, color: textSecondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      note,
                      style: TextStyle(color: textSecondary, fontStyle: FontStyle.italic, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Action Buttons for Team Leader ───────────────────────────────────
          if (canAction && isPending) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _actionTeamLeave(leaveId, 'approve'),
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Approve'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                      textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final reasonCtrl = TextEditingController();
                      final dialogBg = isDark ? const Color(0xFF131722) : Colors.white;
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: dialogBg,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: borderCol)),
                          title: Text('Reject Leave Request', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: textPrimary)),
                          content: TextField(
                            controller: reasonCtrl,
                            style: TextStyle(color: textPrimary, fontSize: 13),
                            decoration: InputDecoration(
                              labelText: 'Rejection Reason (Optional)',
                              labelStyle: TextStyle(color: textSecondary),
                              filled: true,
                              fillColor: isDark ? const Color(0xFF1A1E2B) : const Color(0xFFF0F4FD),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderCol)),
                            ),
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: textSecondary))),
                            ElevatedButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _actionTeamLeave(leaveId, 'reject', note: reasonCtrl.text.trim());
                              },
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                              child: const Text('Confirm Reject', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                      side: const BorderSide(color: Color(0xFFDC2626)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMemberPunchTile(Map<String, dynamic> member, bool isDark, Color bgCard, Color borderCol, Color textPrimary, Color textSecondary) {
    final name = member['name'] ?? member['full_name'] ?? 'Member';
    final role = member['role'] ?? 'Employee';
    final dept = member['department'] ?? 'General';
    final todayStatus = member['today_status'] ?? 'Not Clocked In';
    final signIn = member['sign_in'];
    final signOut = member['sign_out'];

    Color statusColor = textSecondary;
    Color statusBg = isDark ? const Color(0xFF1E2433) : const Color(0xFFF3F4F6);
    if (todayStatus == 'Clocked In') {
      statusColor = isDark ? const Color(0xFF34D399) : const Color(0xFF10B981);
      statusBg = isDark ? const Color(0xFF132A20) : const Color(0xFFD1FAE5);
    } else if (todayStatus == 'Clocked Out') {
      statusColor = isDark ? const Color(0xFF38BDF8) : const Color(0xFF3B82F6);
      statusBg = isDark ? const Color(0xFF132235) : const Color(0xFFDBEAFE);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1E2B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderCol),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFFF5A952).withAlpha(40),
            child: Text(
              name[0].toUpperCase(),
              style: TextStyle(color: isDark ? const Color(0xFFF5A952) : const Color(0xFF895100), fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TextStyle(color: textPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
                Text('$role • $dept', style: TextStyle(color: textSecondary, fontSize: 10, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                if (signIn != null)
                  Text(
                    signOut != null ? 'Shift: $signIn - $signOut' : 'In: $signIn (Active Shift)',
                    style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w700),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  todayStatus,
                  style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () => _showSubordinateAttendanceDialog(member, isDark),
                child: const Text(
                  'View Logs →',
                  style: TextStyle(color: Color(0xFF3F83F8), fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDepartmentCard(Map<String, dynamic> dept, bool isDark, Color bgCard, Color borderCol, Color textPrimary, Color textSecondary) {
    final name = dept['department'] ?? 'General';
    final total = dept['total_count'] ?? 0;
    final present = dept['present_count'] ?? 0;
    final leaders = (dept['team_leaders'] is List) ? (dept['team_leaders'] as List) : [];
    final leaderName = leaders.isNotEmpty ? (leaders[0]['name'] ?? 'Assigned') : 'No Lead Assigned';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1E2B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderCol),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF3F83F8).withAlpha(30),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.domain_rounded, color: Color(0xFF3F83F8), size: 16),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: TextStyle(color: textPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
                  Text('TL: $leaderName', style: TextStyle(color: textSecondary, fontSize: 11)),
                ],
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withAlpha(30),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$present / $total Present',
              style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _leaveTypeCard(String title, String val, String limit, Color dotColor, bool isDark, Color textPrimary, Color textSecondary) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1E2B) : const Color(0xFFF0F4FD),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
              Text(limit, style: TextStyle(fontSize: 10, color: textSecondary, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 6),
          Text(val, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: textPrimary)),
          const SizedBox(height: 2),
          Text(title, style: TextStyle(fontSize: 11, color: textSecondary, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  void _showAllHolidaysMonthWiseModal(bool isDark) {
    final dialogBg = isDark ? const Color(0xFF131722) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF171C23);
    final textSecondary = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF524437);
    final bgCard = isDark ? const Color(0xFF1A1E2B) : const Color(0xFFF8FAFC);
    final borderCol = isDark ? const Color(0xFF2D3748) : const Color(0xFFE2E8F0);
    const amberPrimary = Color(0xFFF5A952);
    const amberDark = Color(0xFF895100);

    // Group holidays by month (1 to 12)
    final Map<int, List<Map<String, dynamic>>> monthHolidays = {};
    for (int i = 1; i <= 12; i++) {
      monthHolidays[i] = [];
    }

    for (var h in _holidaysList) {
      if (h is Map) {
        final dStr = h['date']?.toString();
        if (dStr != null) {
          try {
            final dt = DateTime.parse(dStr);
            if (dt.month >= 1 && dt.month <= 12) {
              monthHolidays[dt.month]!.add(Map<String, dynamic>.from(h));
            }
          } catch (_) {}
        }
      }
    }

    final monthNames = [
      '',
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: dialogBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollCtrl) {
            return Column(
              children: [
                const SizedBox(height: 12),
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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: amberPrimary.withAlpha(40),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.beach_access_rounded, color: amberDark, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('All Holidays List (Month Wise)',
                                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: textPrimary)),
                              Text('Full Company Annual Calendar 2026',
                                  style: TextStyle(fontSize: 12, color: textSecondary, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ],
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: textSecondary),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                Divider(color: borderCol, height: 1),
                Expanded(
                  child: ListView.builder(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.all(20),
                    itemCount: 12,
                    itemBuilder: (context, idx) {
                      final monthNum = idx + 1;
                      final monthName = monthNames[monthNum];
                      final list = monthHolidays[monthNum] ?? [];

                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: bgCard,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: list.isNotEmpty ? amberPrimary.withAlpha(80) : borderCol,
                            width: list.isNotEmpty ? 1.2 : 0.8,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Month Header
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: list.isNotEmpty ? const Color(0xFFE0F2FE) : (isDark ? const Color(0xFF2D3748) : const Color(0xFFE2E8F0)),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        monthName.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.6,
                                          color: list.isNotEmpty ? const Color(0xFF0284C7) : textSecondary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text('2026', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textSecondary)),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: list.isNotEmpty ? const Color(0xFFDCFCE7) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    list.isNotEmpty ? '${list.length} Holiday${list.length > 1 ? 's' : ''}' : '0 Holidays',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: list.isNotEmpty ? const Color(0xFF15803D) : textSecondary.withAlpha(120),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            if (list.isEmpty)
                              // Empty state for months with no holiday
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF131722) : Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: borderCol.withAlpha(60)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.calendar_today_outlined, size: 16, color: textSecondary.withAlpha(120)),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'No holidays in $monthName (Regular working month)',
                                        style: TextStyle(fontSize: 12, color: textSecondary.withAlpha(160), fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              // List of holidays for this month
                              ...list.map((h) {
                                final title = h['title'] ?? 'Holiday';
                                final dStr = h['date']?.toString() ?? '';
                                DateTime? dt;
                                try { dt = DateTime.parse(dStr); } catch (_) {}
                                final weekdayStr = h['weekday'] ?? (dt != null ? DateFormat('EEEE').format(dt) : '');

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF131722) : Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: borderCol),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 54,
                                        padding: const EdgeInsets.symmetric(vertical: 6),
                                        decoration: BoxDecoration(
                                          color: isDark ? const Color(0xFF261D12) : const Color(0xFFFFF3E0),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: isDark ? const Color(0xFF3E2D1A) : const Color(0xFFFFCC80)),
                                        ),
                                        child: Column(
                                          children: [
                                            Text(
                                              dt != null ? '${dt.day}' : '--',
                                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: isDark ? const Color(0xFFF5A952) : const Color(0xFF895100)),
                                            ),
                                            Text(
                                              dt != null ? DateFormat('MMM').format(dt).toUpperCase() : '',
                                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: isDark ? const Color(0xFFF5A952) : const Color(0xFFB45309)),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: textPrimary)),
                                            const SizedBox(height: 2),
                                            Text('$weekdayStr • Public Holiday', style: TextStyle(fontSize: 11, color: textSecondary, fontWeight: FontWeight.w500)),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: isDark ? const Color(0xFF132A20) : const Color(0xFFDCFCE7),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          'OFF',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            color: isDark ? const Color(0xFF34D399) : const Color(0xFF15803D),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _holidayTile(String title, String date, String type, Color bgBadge, Color bgCard, Color borderCol, Color textPrimary, Color textSecondary) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderCol),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: bgBadge,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.nature_people_rounded, size: 16, color: Color(0xFF1B7047)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: borderCol,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(type, style: TextStyle(fontSize: 10, color: textSecondary, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textPrimary)),
              const SizedBox(height: 2),
              Text(date, style: TextStyle(fontSize: 10, color: textSecondary)),
            ],
          ),
        ],
      ),
    );
  }
}
