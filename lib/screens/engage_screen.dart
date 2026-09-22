import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../controllers/theme_controller.dart';
import '../services/app_update_service.dart';
import '../widgets/profile_avatar_badge.dart';

// ── Tab 4: MonarchHR Employee Profile & Verification Screen ───────────────────
class EngageTab extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;
  final VoidCallback onLogout;
  final void Function(Map<String, dynamic>)? onUserUpdated;

  const EngageTab({
    super.key,
    required this.token,
    required this.user,
    required this.onLogout,
    this.onUserUpdated,
  });

  @override
  State<EngageTab> createState() => _EngageTabState();
}

class _EngageTabState extends State<EngageTab> {
  late Map<String, dynamic> _currentUser;
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _deptCtrl;
  late TextEditingController _desigCtrl;
  DateTime? _joiningDate;

  bool _saving = false;
  bool _dailyReminder = true;
  TimeOfDay _reminderTime = const TimeOfDay(hour: 8, minute: 55);
  bool _geofenceCheckIn = false;

  @override
  void initState() {
    super.initState();
    themeController.addListener(_onThemeChanged);
    _currentUser = Map<String, dynamic>.from(widget.user);
    _initControllers();
    _loadAttendanceSettings();
    _fetchFreshProfile();
  }

  Future<void> _loadAttendanceSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _dailyReminder = prefs.getBool('pref_daily_reminder') ?? true;
          final h = prefs.getInt('pref_reminder_hour') ?? 8;
          final m = prefs.getInt('pref_reminder_minute') ?? 55;
          _reminderTime = TimeOfDay(hour: h, minute: m);
          _geofenceCheckIn = prefs.getBool('pref_geofence_checkin') ?? false;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveDailyReminder(bool val) async {
    setState(() => _dailyReminder = val);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('pref_daily_reminder', val);
    } catch (_) {}
  }

  Future<void> _saveGeofenceCheckIn(bool val) async {
    setState(() => _geofenceCheckIn = val);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('pref_geofence_checkin', val);
    } catch (_) {}
  }

  String _formatTimeOfDay(TimeOfDay tod) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, tod.hour, tod.minute);
    return DateFormat('hh:mm a').format(dt);
  }

  String _getReminderSubtitle() {
    final timeStr = _formatTimeOfDay(_reminderTime);
    if (_reminderTime.hour == 8 && _reminderTime.minute == 55) {
      return 'Ping at $timeStr (5 min prior)';
    }
    return 'Ping at $timeStr (Custom)';
  }

  Future<void> _pickReminderTime() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final picked = await showTimePicker(
      context: context,
      initialTime: _reminderTime,
      helpText: 'SET CHECK-IN REMINDER TIME',
      builder: (ctx, child) {
        final isDark = themeController.isDarkMode;
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFFF5A952),
              brightness: isDark ? Brightness.dark : Brightness.light,
              primary: const Color(0xFFF5A952),
              onPrimary: const Color(0xFF6B3F00),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      setState(() => _reminderTime = picked);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('pref_reminder_hour', picked.hour);
        await prefs.setInt('pref_reminder_minute', picked.minute);
      } catch (_) {}
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Daily Check-in Reminder set to ${_formatTimeOfDay(picked)}'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  void didUpdateWidget(covariant EngageTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.user != oldWidget.user) {
      setState(() {
        _currentUser = Map<String, dynamic>.from(widget.user);
        _initControllers();
      });
    }
  }

  void _initControllers() {
    _nameCtrl = TextEditingController(text: _currentUser['name'] ?? _currentUser['full_name'] ?? '');
    _phoneCtrl = TextEditingController(text: _currentUser['phone_number'] ?? '');
    _emailCtrl = TextEditingController(text: _currentUser['email'] ?? '');
    _deptCtrl = TextEditingController(text: _currentUser['department'] ?? 'Product Engineering');
    _desigCtrl = TextEditingController(text: _currentUser['designation'] ?? 'UI/UX Designer');
    final jStr = (_currentUser['date_of_joining'] ?? _currentUser['joining_date'])?.toString();
    if (jStr != null && jStr.isNotEmpty) {
      _joiningDate = DateTime.tryParse(jStr);
    }
  }

  @override
  void dispose() {
    themeController.removeListener(_onThemeChanged);
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _deptCtrl.dispose();
    _desigCtrl.dispose();
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _fetchFreshProfile() async {
    try {
      final res = await apiGetJson('/api/user/profile', token: widget.token);
      if (res is Map<String, dynamic> && res['id'] != null) {
        if (mounted) {
          setState(() {
            _currentUser = Map<String, dynamic>.from(res);
            _initControllers();
          });
          widget.onUserUpdated?.call(_currentUser);
        }
      }
    } catch (_) {}
  }

  String _cleanPhoneNumber(String input) {
    String digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 12 && digits.startsWith('91')) {
      return digits.substring(2);
    }
    if (digits.length == 11 && digits.startsWith('0')) {
      return digits.substring(1);
    }
    if (digits.length > 10) {
      return digits.substring(digits.length - 10);
    }
    return digits;
  }

  bool _isValidEmail(String email) {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return false;
    return RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(trimmed);
  }

  int get _completenessPercentage {
    int score = 0;
    if (_nameCtrl.text.trim().isNotEmpty) score += 20;
    if ((_currentUser['emp_id'] ?? _currentUser['id'] ?? '').toString().isNotEmpty) score += 20;
    if (_cleanPhoneNumber(_phoneCtrl.text).length == 10) score += 20;
    final hasJoin = _joiningDate != null || ((_currentUser['date_of_joining'] ?? _currentUser['joining_date'])?.toString() ?? '').isNotEmpty;
    if (hasJoin) score += 20;
    if (_deptCtrl.text.trim().isNotEmpty || _desigCtrl.text.trim().isNotEmpty) score += 15;
    if (_isValidEmail(_emailCtrl.text)) score += 5;
    return score;
  }

  bool get _isProfileIncomplete {
    final cleanPhone = _cleanPhoneNumber(_phoneCtrl.text);
    final hasJoinDate = _joiningDate != null || ((_currentUser['date_of_joining'] ?? _currentUser['joining_date'])?.toString() ?? '').isNotEmpty;
    final hasEmail = _isValidEmail(_emailCtrl.text);
    return cleanPhone.length != 10 || !hasJoinDate || !hasEmail;
  }

  Future<void> _saveProfile() async {
    final messenger = ScaffoldMessenger.of(context);
    final rawPhone = _phoneCtrl.text.trim();
    final cleanPhone = _cleanPhoneNumber(rawPhone);
    final email = _emailCtrl.text.trim();

    if (cleanPhone.isNotEmpty && cleanPhone.length != 10) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid 10-digit mobile number (e.g. 8805298005).'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }

    if (email.isNotEmpty && !_isValidEmail(email)) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid email address format (e.g. employee@monarch.com).'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }

    if (cleanPhone.isNotEmpty) {
      _phoneCtrl.text = cleanPhone;
    }

    setState(() => _saving = true);

    try {
      final formattedDate = _joiningDate != null ? DateFormat('yyyy-MM-dd').format(_joiningDate!) : null;
      final payload = {
        'full_name': _nameCtrl.text.trim(),
        'name': _nameCtrl.text.trim(),
        'phone_number': cleanPhone,
        'date_of_joining': formattedDate,
        'joining_date': formattedDate,
        'email': _emailCtrl.text.trim(),
        'department': _deptCtrl.text.trim(),
        'designation': _desigCtrl.text.trim(),
      };

      final res = await apiPut('/api/user/profile', payload, token: widget.token);
      if (res['error'] != null) {
        messenger.showSnackBar(SnackBar(content: Text('Error: ${res['error']}')));
      } else {
        setState(() {
          _currentUser = Map<String, dynamic>.from(res);
        });
        widget.onUserUpdated?.call(_currentUser);
        messenger.showSnackBar(
          SnackBar(
            content: Text(_isProfileIncomplete ? 'Profile updated!' : '🎉 Profile 100% Completed & Verified!'),
            backgroundColor: const Color(0xFF16A34A),
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(const SnackBar(content: Text('Failed to update profile. Check connection.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
    const alertRed = Color(0xFFFF2A55);

    final rawName = _currentUser['name'] ?? _currentUser['full_name'] ?? 'Robert Smith';
    final empId = _currentUser['emp_id'] ?? _currentUser['id'] ?? 'EMP-84920';
    final dept = _currentUser['department'] ?? 'Product Engineering';
    final desig = _currentUser['designation'] ?? 'UI/UX Designer';

    final percentage = _completenessPercentage;
    final isIncomplete = _isProfileIncomplete;
    final hasPhone = _cleanPhoneNumber(_phoneCtrl.text).length == 10;
    final hasJoinDate = _joiningDate != null || ((_currentUser['date_of_joining'] ?? _currentUser['joining_date'])?.toString() ?? '').isNotEmpty;
    final hasValidEmail = _isValidEmail(_emailCtrl.text);

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
                Text('Profile',
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
            isIncomplete: isIncomplete,
            radius: 16,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        children: [
          // ── Profile Hero Card ──────────────────────────────────────────────
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
              border: Border.all(
                color: isIncomplete ? alertRed.withAlpha(90) : borderCol,
                width: isIncomplete ? 1.5 : 1.0,
              ),
            ),
            child: Column(
              children: [
                ProfileAvatarBadge(
                  name: rawName,
                  isIncomplete: isIncomplete,
                  radius: 42,
                  borderWidth: 3.5,
                  fontSize: 34,
                ),
                const SizedBox(height: 14),

                Text(
                  rawName,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: textPrimary, letterSpacing: -0.4),
                ),
                const SizedBox(height: 2),
                Text(
                  '$desig • $dept',
                  style: TextStyle(fontSize: 12, color: textSecondary, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 14),

                // Meta Badges Pill Row
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _pillBadge(Icons.badge_outlined, '#$empId', bgInput, textPrimary),
                    _pillBadge(
                      Icons.event_outlined,
                      _joiningDate != null
                          ? 'Joined ${DateFormat('d MMM yyyy').format(_joiningDate!)}'
                          : '⚠️ Joining Date Missing',
                      _joiningDate != null ? bgInput : (isDark ? const Color(0xFF2B1618) : const Color(0xFFFFE4E6)),
                      _joiningDate != null ? textPrimary : (isDark ? const Color(0xFFF87171) : const Color(0xFF9F1239)),
                    ),
                    _pillBadge(
                      Icons.phone_outlined,
                      _phoneCtrl.text.trim().isNotEmpty
                          ? _phoneCtrl.text.trim()
                          : '⚠️ Phone Missing',
                      _phoneCtrl.text.trim().isNotEmpty ? bgInput : (isDark ? const Color(0xFF2B1618) : const Color(0xFFFFE4E6)),
                      _phoneCtrl.text.trim().isNotEmpty ? textPrimary : (isDark ? const Color(0xFFF87171) : const Color(0xFF9F1239)),
                    ),
                    _pillBadge(
                      Icons.alternate_email_rounded,
                      hasValidEmail
                          ? _emailCtrl.text.trim()
                          : (_emailCtrl.text.trim().isEmpty ? '⚠️ Email Missing (5%)' : '⚠️ Invalid Email'),
                      hasValidEmail ? bgInput : (isDark ? const Color(0xFF2B1618) : const Color(0xFFFFE4E6)),
                      hasValidEmail ? textPrimary : (isDark ? const Color(0xFFF87171) : const Color(0xFF9F1239)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF132A20) : const Color(0xFF9FF1BD).withAlpha(120),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.fiber_manual_record, color: isDark ? const Color(0xFF34D399) : const Color(0xFF146C43), size: 8),
                          const SizedBox(width: 4),
                          Text('Active',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: isDark ? const Color(0xFF34D399) : const Color(0xFF002110))),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // ── Profile Completeness Progress Card ─────────────────────────────
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: isIncomplete
                  ? (isDark ? const Color(0xFF2B181C) : const Color(0xFFFFF1F2))
                  : (isDark ? const Color(0xFF13231D) : const Color(0xFFF0FDF4)),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isIncomplete ? alertRed : const Color(0xFF22C55E),
                width: 1.5,
              ),
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
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isIncomplete ? alertRed.withAlpha(40) : const Color(0xFF22C55E).withAlpha(40),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isIncomplete ? Icons.warning_amber_rounded : Icons.check_circle_rounded,
                            color: isIncomplete ? alertRed : const Color(0xFF16A34A),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isIncomplete ? 'Profile Incomplete' : 'Profile Complete 🎉',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: isIncomplete ? alertRed : const Color(0xFF16A34A),
                              ),
                            ),
                            Text(
                              isIncomplete ? 'Action Required: Complete missing info' : 'All required details verified 100%',
                              style: TextStyle(fontSize: 11, color: textSecondary, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isIncomplete ? alertRed : const Color(0xFF16A34A),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        '$percentage%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Progress Bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: percentage / 100.0,
                    minHeight: 8,
                    backgroundColor: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isIncomplete ? alertRed : const Color(0xFF16A34A),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                if (isIncomplete) ...[
                  Text(
                    'Missing fields required for verification:',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textSecondary),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (!hasPhone)
                        _missingFieldChip('Phone Number (+20%)', Icons.phone_android_rounded),
                      if (!hasJoinDate)
                        _missingFieldChip('Date of Joining (+20%)', Icons.calendar_month_rounded),
                      if (!hasValidEmail)
                        _missingFieldChip('Email Address (+5%)', Icons.alternate_email_rounded),
                    ],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 18),

          // ── Profile Information & Verification Form Card ──────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: bgCard,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: borderCol),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0A171C23),
                  blurRadius: 16,
                  offset: Offset(0, 4),
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
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: bgInput, shape: BoxShape.circle),
                          child: Icon(Icons.person_pin_rounded, color: textPrimary, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Employee Information',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textPrimary, letterSpacing: -0.3)),
                            Text('Update details to reach 100% completion',
                                style: TextStyle(fontSize: 11, color: textSecondary)),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Full Name Field
                _formLabel('FULL NAME', false, textSecondary),
                const SizedBox(height: 6),
                _formTextField(_nameCtrl, 'Enter full name', Icons.person_outline_rounded, bgInput, textPrimary, textSecondary),
                const SizedBox(height: 14),

                // Employee ID (Read-only)
                _formLabel('EMPLOYEE ID (FIXED)', false, textSecondary),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: bgInput.withAlpha(160),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderCol),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.badge_outlined, color: textSecondary, size: 18),
                      const SizedBox(width: 10),
                      Text(empId, style: TextStyle(color: textPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Phone Number Field (REQUIRED / HIGHLIGHTED IF EMPTY)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _formLabel('PHONE NUMBER', true, textSecondary),
                    if (!hasPhone)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFE4E6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('⚠️ Missing', style: TextStyle(color: Color(0xFFE11D48), fontSize: 10, fontWeight: FontWeight.w700)),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                _formTextField(
                  _phoneCtrl,
                  'e.g. +91 9876543210',
                  Icons.phone_iphone_rounded,
                  bgInput,
                  textPrimary,
                  textSecondary,
                  keyboardType: TextInputType.phone,
                  isAlert: !hasPhone,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 14),

                // Date of Joining Field (REQUIRED / HIGHLIGHTED IF EMPTY)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _formLabel('DATE OF JOINING', true, textSecondary),
                    if (!hasJoinDate)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFE4E6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('⚠️ Missing', style: TextStyle(color: Color(0xFFE11D48), fontSize: 10, fontWeight: FontWeight.w700)),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _joiningDate ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setState(() => _joiningDate = picked);
                    }
                  },
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: bgInput,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: !hasJoinDate ? alertRed : borderCol,
                        width: !hasJoinDate ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_month_outlined,
                              color: !hasJoinDate ? alertRed : textSecondary,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _joiningDate != null
                                  ? DateFormat('dd-MM-yyyy').format(_joiningDate!)
                                  : 'Select Joining Date',
                              style: TextStyle(
                                color: _joiningDate != null ? textPrimary : textSecondary,
                                fontSize: 13,
                                fontWeight: _joiningDate != null ? FontWeight.w700 : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        Icon(Icons.edit_calendar_rounded, size: 18, color: textSecondary),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Email Address Field (5% / Email format check)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _formLabel('EMAIL ADDRESS (5%)', true, textSecondary),
                    if (!hasValidEmail)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFE4E6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _emailCtrl.text.trim().isEmpty ? '⚠️ Missing (5%)' : '⚠️ Invalid Email Format',
                          style: const TextStyle(color: Color(0xFFE11D48), fontSize: 10, fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                _formTextField(
                  _emailCtrl,
                  'e.g. employee@monarch.com',
                  Icons.alternate_email_rounded,
                  bgInput,
                  textPrimary,
                  textSecondary,
                  keyboardType: TextInputType.emailAddress,
                  isAlert: !hasValidEmail,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 14),

                // Department & Designation Row
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _formLabel('DEPARTMENT', false, textSecondary),
                          const SizedBox(height: 6),
                          _formTextField(_deptCtrl, 'Department', Icons.business_rounded, bgInput, textPrimary, textSecondary),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _formLabel('DESIGNATION', false, textSecondary),
                          const SizedBox(height: 6),
                          _formTextField(_desigCtrl, 'Designation', Icons.work_outline_rounded, bgInput, textPrimary, textSecondary),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Save Profile Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _saveProfile,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: amberDark),
                          )
                        : const Icon(Icons.check_circle_outline_rounded, size: 18),
                    label: Text(_saving ? 'Saving Changes...' : 'Save & Verify Profile'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: amberPrimary,
                      foregroundColor: amberDark,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      elevation: 0,
                      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Monthly Performance Snapshot (Bento Stat Cluster) ──────────────
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Monthly Performance',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textPrimary, letterSpacing: -0.3)),
                        Text('ATTENDANCE SNAPSHOT',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: textSecondary, letterSpacing: 1.1)),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: bgInput,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('This Month', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textSecondary)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: _bentoTile('98%', 'Present Rate', Icons.verified_rounded, const Color(0xFF10B981), bgInput, textPrimary, textSecondary),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _bentoTile('22', 'Work Days', Icons.calendar_today_rounded, const Color(0xFF3F83F8), bgInput, textPrimary, textSecondary),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _bentoTile('96%', 'Punctuality', Icons.schedule_rounded, const Color(0xFFF59E0B), bgInput, textPrimary, textSecondary),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Shift & Work Details ───────────────────────────────────────────
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
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: bgInput,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.work_history_rounded, color: textPrimary, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Shift & Work Details',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textPrimary, letterSpacing: -0.3)),
                        Text('Assigned corporate workstation & roster',
                            style: TextStyle(fontSize: 11, color: textSecondary)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Regular Shift Row
                _detailRow(
                  Icons.alarm_rounded,
                  'Regular Shift',
                  '09:30 AM - 06:30 PM',
                  const Color(0xFF3F83F8),
                  badge: 'Mon - Fri',
                  bgInput: bgInput,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                  borderCol: borderCol,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Attendance Settings ────────────────────────────────────────────
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
                Text('Attendance Settings',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textPrimary, letterSpacing: -0.3)),
                const SizedBox(height: 2),
                Text('Automation triggers and compliance options',
                    style: TextStyle(fontSize: 11, color: textSecondary)),
                const SizedBox(height: 16),

                // Setting 1: Reminder
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _dailyReminder ? _pickReminderTime : null,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: bgInput, shape: BoxShape.circle),
                                child: Icon(Icons.notifications_active_rounded, color: textPrimary, size: 18),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text('Daily Check-in Reminder',
                                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textPrimary)),
                                        if (_dailyReminder) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: amberPrimary.withAlpha(isDark ? 40 : 25),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: amberPrimary.withAlpha(80)),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.access_time_rounded, size: 11, color: amberDark),
                                                const SizedBox(width: 3),
                                                Text(
                                                  _formatTimeOfDay(_reminderTime),
                                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: amberDark),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _dailyReminder ? _getReminderSubtitle() : 'Disabled',
                                      style: TextStyle(fontSize: 11, color: textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Switch(
                      value: _dailyReminder,
                      activeThumbColor: amberPrimary,
                      onChanged: (val) => _saveDailyReminder(val),
                    ),
                  ],
                ),
                Divider(color: borderCol, height: 20),

                // Setting 2: Geofence
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: bgInput, shape: BoxShape.circle),
                            child: Icon(Icons.location_on_rounded, color: textPrimary, size: 18),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Geofence Auto Check-in',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textPrimary)),
                                const SizedBox(height: 2),
                                Text(
                                  _geofenceCheckIn
                                      ? 'Detect HQ beacon perimeter (Active)'
                                      : 'Detect HQ beacon perimeter (Disabled)',
                                  style: TextStyle(fontSize: 11, color: textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _geofenceCheckIn,
                      activeThumbColor: amberPrimary,
                      onChanged: (val) => _saveGeofenceCheckIn(val),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Log Out Action ────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: widget.onLogout,
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('Log Out of Workspace'),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? const Color(0xFF1F2633) : const Color(0xFFF0F4FD),
                foregroundColor: const Color(0xFFBA1A1A),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 10),

          Center(
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => AppUpdateService.checkForUpdates(context, silent: false),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.system_update_alt_rounded, size: 14, color: textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      'Monarch HR v${AppUpdateService.currentVersionName} (Build ${AppUpdateService.currentVersionCode}) • Check for Updates',
                      style: TextStyle(fontSize: 11, color: textSecondary, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _missingFieldChip(String label, IconData icon) {
    final isDark = themeController.isDarkMode;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2B1618) : const Color(0xFFFFE4E6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? const Color(0xFF3E1D22) : const Color(0xFFFDA4AF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: isDark ? const Color(0xFFF87171) : const Color(0xFFE11D48)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isDark ? const Color(0xFFF87171) : const Color(0xFF9F1239),
            ),
          ),
        ],
      ),
    );
  }

  Widget _formLabel(String label, bool isRequired, Color textSecondary) {
    return RichText(
      text: TextSpan(
        text: label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textSecondary, letterSpacing: 0.8),
        children: isRequired
            ? const [
                TextSpan(text: ' *', style: TextStyle(color: Color(0xFFFF2A55), fontWeight: FontWeight.bold)),
              ]
            : [],
      ),
    );
  }

  Widget _formTextField(
    TextEditingController ctrl,
    String hint,
    IconData icon,
    Color bgInput,
    Color textPrimary,
    Color textSecondary, {
    TextInputType keyboardType = TextInputType.text,
    bool isAlert = false,
    void Function(String)? onChanged,
  }) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: bgInput,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isAlert ? const Color(0xFFFF2A55) : Colors.transparent,
          width: isAlert ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: isAlert ? const Color(0xFFFF2A55) : textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: ctrl,
              keyboardType: keyboardType,
              onChanged: onChanged,
              style: TextStyle(color: textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: textSecondary.withAlpha(150), fontSize: 12),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pillBadge(IconData icon, String text, Color bg, Color textCol) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: textCol),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textCol)),
        ],
      ),
    );
  }

  Widget _bentoTile(String val, String label, IconData icon, Color accent, Color bg, Color textPrimary, Color textSecondary) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: accent.withAlpha(38), shape: BoxShape.circle),
            child: Icon(icon, color: accent, size: 18),
          ),
          const SizedBox(height: 8),
          Text(val, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary)),
          const SizedBox(height: 2),
          Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: textSecondary, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String val, Color color,
      {String? badge, IconData? badgeIcon, required Color bgInput, required Color textPrimary, required Color textSecondary, required Color borderCol}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgInput,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 10, color: textSecondary, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(val, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: textPrimary)),
              ],
            ),
          ),
          if (badge != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: borderCol,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(badge, style: TextStyle(fontSize: 10, color: textSecondary, fontWeight: FontWeight.w600)),
            ),
          if (badgeIcon != null)
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: borderCol,
                shape: BoxShape.circle,
              ),
              child: Icon(badgeIcon, size: 14, color: textPrimary),
            ),
        ],
      ),
    );
  }
}
