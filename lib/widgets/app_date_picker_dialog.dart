import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../controllers/theme_controller.dart';

enum _PickerViewMode { day, month, year }

Future<DateTime?> showAppDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) async {
  DateTime clampedInitial = initialDate;
  if (clampedInitial.isBefore(firstDate)) clampedInitial = firstDate;
  if (clampedInitial.isAfter(lastDate)) clampedInitial = lastDate;

  return showDialog<DateTime>(
    context: context,
    builder: (ctx) => _AppDatePickerDialog(
      initialDate: clampedInitial,
      firstDate: firstDate,
      lastDate: lastDate,
    ),
  );
}

class _AppDatePickerDialog extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  const _AppDatePickerDialog({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  @override
  State<_AppDatePickerDialog> createState() => _AppDatePickerDialogState();
}

class _AppDatePickerDialogState extends State<_AppDatePickerDialog> {
  late DateTime _selectedDate;
  late int _displayYear;
  late int _displayMonth;
  _PickerViewMode _viewMode = _PickerViewMode.day;
  final ScrollController _yearScrollController = ScrollController();

  static const List<String> _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  static const List<String> _shortMonthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    _displayYear = widget.initialDate.year;
    _displayMonth = widget.initialDate.month;
  }

  @override
  void dispose() {
    _yearScrollController.dispose();
    super.dispose();
  }

  void _scrollToSelectedYear() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_yearScrollController.hasClients) return;
      final startYear = widget.firstDate.year;
      final index = _displayYear - startYear;
      if (index >= 0) {
        final row = index ~/ 3;
        final targetOffset = (row * 56.0) - 100.0;
        _yearScrollController.jumpTo(
          targetOffset.clamp(0.0, _yearScrollController.position.maxScrollExtent),
        );
      }
    });
  }

  bool _isMonthDisabled(int year, int month) {
    final startOfTargetMonth = DateTime(year, month, 1);
    final endOfTargetMonth = DateTime(year, month + 1, 0, 23, 59, 59);
    if (endOfTargetMonth.isBefore(widget.firstDate)) return true;
    if (startOfTargetMonth.isAfter(widget.lastDate)) return true;
    return false;
  }

  bool _isDayDisabled(int year, int month, int day) {
    final dt = DateTime(year, month, day);
    final dtStart = DateTime(dt.year, dt.month, dt.day);
    final firstStart = DateTime(widget.firstDate.year, widget.firstDate.month, widget.firstDate.day);
    final lastEnd = DateTime(widget.lastDate.year, widget.lastDate.month, widget.lastDate.day);
    if (dtStart.isBefore(firstStart)) return true;
    if (dtStart.isAfter(lastEnd)) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeController.isDarkMode;

    final bgCard = isDark ? const Color(0xFF161B26) : const Color(0xFFFAF5F0);
    final bgHeader = isDark ? const Color(0xFF131722) : const Color(0xFFF3ECE4);
    final textPrimary = isDark ? Colors.white : const Color(0xFF2C241D);
    final textSecondary = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF7A6D63);
    final borderCol = isDark ? const Color(0xFF242C3D) : const Color(0xFFE5DDD4);
    const primaryAmber = Color(0xFFF5A952);
    final primaryAccent = isDark ? const Color(0xFFF5A952) : const Color(0xFF895100);
    final primaryPillBg = isDark ? const Color(0xFFF5A952) : const Color(0xFF7C4A03);
    final primaryPillText = isDark ? const Color(0xFF1A1308) : Colors.white;

    return Dialog(
      backgroundColor: bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: "Select date" + Formatted selected date
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              color: bgHeader,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select date',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    DateFormat('EEE, MMM d, yyyy').format(_selectedDate),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),

            // Mode Selector Bar (e.g. "September 2026 ▾" or breadcrumb)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: borderCol, width: 1)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Month/Year Switcher Button
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      setState(() {
                        if (_viewMode == _PickerViewMode.day) {
                          _viewMode = _PickerViewMode.year;
                          _scrollToSelectedYear();
                        } else if (_viewMode == _PickerViewMode.year) {
                          _viewMode = _PickerViewMode.month;
                        } else {
                          _viewMode = _PickerViewMode.day;
                        }
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _viewMode == _PickerViewMode.year
                                ? 'Select Year'
                                : _viewMode == _PickerViewMode.month
                                    ? '$_displayYear (Select Month)'
                                    : '${_monthNames[_displayMonth - 1]} $_displayYear',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: textPrimary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            _viewMode == _PickerViewMode.day
                                ? Icons.arrow_drop_down_rounded
                                : Icons.arrow_drop_up_rounded,
                            color: primaryAccent,
                            size: 22,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Chevrons for Month navigation in Day mode, or Year navigation in Month mode
                  if (_viewMode == _PickerViewMode.day)
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left_rounded, size: 22),
                          color: textPrimary,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          onPressed: () {
                            setState(() {
                              if (_displayMonth == 1) {
                                if (_displayYear > widget.firstDate.year) {
                                  _displayYear--;
                                  _displayMonth = 12;
                                }
                              } else {
                                _displayMonth--;
                              }
                            });
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right_rounded, size: 22),
                          color: textPrimary,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          onPressed: () {
                            setState(() {
                              if (_displayMonth == 12) {
                                if (_displayYear < widget.lastDate.year) {
                                  _displayYear++;
                                  _displayMonth = 1;
                                }
                              } else {
                                _displayMonth++;
                              }
                            });
                          },
                        ),
                      ],
                    )
                  else if (_viewMode == _PickerViewMode.month)
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left_rounded, size: 22),
                          color: textPrimary,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          onPressed: _displayYear > widget.firstDate.year
                              ? () => setState(() => _displayYear--)
                              : null,
                        ),
                        Text(
                          '$_displayYear',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textSecondary),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right_rounded, size: 22),
                          color: textPrimary,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          onPressed: _displayYear < widget.lastDate.year
                              ? () => setState(() => _displayYear++)
                              : null,
                        ),
                      ],
                    ),
                ],
              ),
            ),

            // Body: Switch between Year -> Month -> Day views
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _viewMode == _PickerViewMode.year
                    ? _buildYearPicker(primaryPillBg, primaryPillText, textPrimary, textSecondary)
                    : _viewMode == _PickerViewMode.month
                        ? _buildMonthPicker(primaryPillBg, primaryPillText, textPrimary, textSecondary, isDark)
                        : _buildDayPicker(primaryPillBg, primaryPillText, textPrimary, textSecondary, isDark),
              ),
            ),

            // Bottom Dialog Action Buttons
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: borderCol, width: 1)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    style: TextButton.styleFrom(
                      foregroundColor: textSecondary,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(_selectedDate),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryAmber,
                      foregroundColor: const Color(0xFF1A1308),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                    child: const Text('OK', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 1. Year Grid Picker
  Widget _buildYearPicker(Color pillBg, Color pillText, Color textPrimary, Color textSecondary) {
    final startYear = widget.firstDate.year;
    final endYear = widget.lastDate.year;
    final years = List<int>.generate(endYear - startYear + 1, (i) => startYear + i);

    return GridView.builder(
      controller: _yearScrollController,
      key: const ValueKey('year_grid'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 2.1,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: years.length,
      itemBuilder: (context, idx) {
        final year = years[idx];
        final isSelected = year == _displayYear;

        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            setState(() {
              _displayYear = year;
              // Transition sequentially to Month selection as requested!
              _viewMode = _PickerViewMode.month;
            });
          },
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected ? pillBg : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? pillBg : textSecondary.withAlpha(50),
                width: 1,
              ),
            ),
            child: Text(
              '$year',
              style: TextStyle(
                fontSize: 15,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? pillText : textPrimary,
              ),
            ),
          ),
        );
      },
    );
  }

  // 2. Month Grid Picker (Jan..Dec)
  Widget _buildMonthPicker(Color pillBg, Color pillText, Color textPrimary, Color textSecondary, bool isDark) {
    return GridView.builder(
      key: const ValueKey('month_grid'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.9,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: 12,
      itemBuilder: (context, idx) {
        final monthNumber = idx + 1;
        final isSelected = _displayYear == _selectedDate.year && monthNumber == _selectedDate.month;
        final isDisabled = _isMonthDisabled(_displayYear, monthNumber);

        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: isDisabled
              ? null
              : () {
                  setState(() {
                    _displayMonth = monthNumber;
                    // Transition sequentially to Day view!
                    _viewMode = _PickerViewMode.day;
                  });
                },
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected ? pillBg : (isDark ? const Color(0xFF1E2534) : const Color(0xFFEDE5DC)),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? pillBg : Colors.transparent,
                width: 1,
              ),
            ),
            child: Text(
              _shortMonthNames[idx],
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isDisabled
                    ? textSecondary.withAlpha(80)
                    : (isSelected ? pillText : textPrimary),
              ),
            ),
          ),
        );
      },
    );
  }

  // 3. Day Grid Calendar Picker
  Widget _buildDayPicker(Color pillBg, Color pillText, Color textPrimary, Color textSecondary, bool isDark) {
    final firstDayOfMonth = DateTime(_displayYear, _displayMonth, 1);
    final daysInMonth = DateTime(_displayYear, _displayMonth + 1, 0).day;
    final startWeekday = firstDayOfMonth.weekday % 7; // 0: Sun, 1: Mon...
    final totalCells = startWeekday + daysInMonth;
    final now = DateTime.now();

    const weekdays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    return Column(
      key: const ValueKey('day_view'),
      children: [
        // Weekday labels
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: weekdays.map((w) {
              return SizedBox(
                width: 32,
                child: Text(
                  w,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: textSecondary,
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        // Days Grid
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.1,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemCount: totalCells,
            itemBuilder: (context, index) {
              if (index < startWeekday) {
                return const SizedBox.shrink();
              }

              final day = index - startWeekday + 1;
              final cellDate = DateTime(_displayYear, _displayMonth, day);
              final isSelected = cellDate.year == _selectedDate.year &&
                  cellDate.month == _selectedDate.month &&
                  cellDate.day == _selectedDate.day;
              final isToday = cellDate.year == now.year &&
                  cellDate.month == now.month &&
                  cellDate.day == now.day;
              final isDisabled = _isDayDisabled(_displayYear, _displayMonth, day);

              return InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: isDisabled
                    ? null
                    : () {
                        setState(() {
                          _selectedDate = cellDate;
                        });
                      },
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected ? pillBg : Colors.transparent,
                    shape: BoxShape.circle,
                    border: isToday && !isSelected
                        ? Border.all(color: const Color(0xFFF5A952), width: 1.5)
                        : null,
                  ),
                  child: Text(
                    '$day',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w800 : (isToday ? FontWeight.w700 : FontWeight.w500),
                      color: isDisabled
                          ? textSecondary.withAlpha(80)
                          : (isSelected ? pillText : textPrimary),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
