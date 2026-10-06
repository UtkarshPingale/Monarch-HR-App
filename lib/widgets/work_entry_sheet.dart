import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/api_config.dart';
import '../controllers/theme_controller.dart';
import 'app_date_picker_dialog.dart';

class WorkEntrySheet extends StatefulWidget {
  final String? token;
  final VoidCallback? onSaved;

  const WorkEntrySheet({super.key, this.token, this.onSaved});

  static Future<void> show(BuildContext context, {String? token, VoidCallback? onSaved}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => WorkEntrySheet(token: token, onSaved: onSaved),
    );
  }

  @override
  State<WorkEntrySheet> createState() => _WorkEntrySheetState();
}

class _WorkEntrySheetState extends State<WorkEntrySheet> {
  DateTime _workDate = DateTime.now();

  // Project Selection
  String _selectedProjectId = '';
  String _selectedProjectName = '';
  List<Map<String, String>> _projects = [];

  // Department & Task Hierarchy
  String _selectedDepartment = 'Engineering';
  List<String> _departments = [
    'Engineering',
    'Railway Engineering',
    'Highway Engineering',
    'GIS',
    'Geospatial Technology',
    'Geotech',
    'CAD',
    'Drone',
    'IT Department',
    'Field COE',
    'Project',
    'Traffic & Safety',
    'Admin',
    'Finance & Accounts',
  ];

  String _selectedTask = 'Subgrade Preparation & Excavation';
  Map<String, List<String>> _tasksByDept = {
    'Civil & Infrastructure': [
      'Subgrade Preparation & Excavation',
      'Pavement Base & Subbase Laying',
      'Drainage & Culvert Construction',
      'Concrete Pouring & Curing',
      'Earthwork & Grading',
    ],
    'Survey & GIS Mapping': [
      'Topographic Survey & Contour Mapping',
      'Boundary Demarcation & Geotagging',
      'Drone Aerial Photogrammetry',
      'As-Built Verification Survey',
      'Control Point Establishment',
    ],
    'Structural & Architectural': [
      'Structural Drafting & Detailing',
      'Column & Beam Rebar Inspection',
      'Foundation Pile Load Testing',
      'Facade & Finishing Execution',
    ],
    'Electrical & MEP': [
      'Underground Cable Trenching',
      'Substation Panel Installation',
      'HVAC Ducting & Plumbing Run',
    ],
    'Project Management & QA': [
      'Quality Control & Material Testing',
      'Safety & Compliance Audit',
      'Daily Progress Report Compilation',
    ],
  };

  String _selectedSubtask = 'Trench Trenching Section B (Chainage 12+400)';
  Map<String, List<String>> _subtasksByTask = {
    'Subgrade Preparation & Excavation': [
      'Trench Trenching Section B (Chainage 12+400)',
      'Soil Compaction Testing Layer 2',
      'Excavation for Retaining Wall Footing',
      'Boulder Clearing & Site Leveling',
    ],
    'Topographic Survey & Contour Mapping': [
      'Total Station Grid Observation (5m interval)',
      'Benchmark Level Verification with DGPS',
      'Cadastral Boundary Superimposition',
    ],
    'Pavement Base & Subbase Laying': [
      'GSB Laying & Compaction Chainage 4+200',
      'WMM Base Course Spreading',
      'Bituminous Concrete Surface Dressing',
    ],
  };

  // Output & Effort
  final TextEditingController _qtyCtrl = TextEditingController(text: '');
  String _selectedUnit = 'KM';
  List<String> _units = ['KM', 'M', 'Nos', 'Ton', 'SqM', 'CuM', 'Hrs', 'Points', 'Sheets', 'Days'];

  final TextEditingController _hoursCtrl = TextEditingController(text: '');
  final TextEditingController _minutesCtrl = TextEditingController(text: '');

  // Revision
  String _selectedRevision = 'Rev 0 — Initial Working Execution';
  List<String> _revisions = [
    'Rev 0 — Initial Working Execution',
    'Rev 1 — Client Feedback Iteration',
    'Rev 2 — Quality Review Revision',
    'Rev 3 — Final Site Alignment',
    'New',
    'Final',
  ];

  // Remarks (MANDATORY)
  final TextEditingController _remarksCtrl = TextEditingController(text: '');

  final List<String> _quickChips = [
    '+ Delayed by weather',
    '+ Milestone reached',
    '+ Equipment issue',
    '+ Client site visit',
    '+ QA Approved',
  ];

  bool _isSaving = false;
  bool _isLoadingOptions = false;

  @override
  void initState() {
    super.initState();
    _loadLiveFormOptions();
  }

  Future<void> _loadLiveFormOptions() async {
    setState(() => _isLoadingOptions = true);
    try {
      final res = await apiGetJson('/api/work-entries/form-options', token: widget.token);
      if (res is Map && mounted) {
        if (res['projects'] is List && (res['projects'] as List).isNotEmpty) {
          final pList = (res['projects'] as List)
              .map((p) => {
                    'id': (p['id'] ?? '').toString().trim(),
                    'name': (p['name'] ?? p['project_name'] ?? p['id'] ?? '').toString().trim(),
                  })
              .where((p) =>
                  p['id']!.isNotEmpty &&
                  !p['id']!.startsWith('\$') &&
                  !p['id']!.startsWith('.') &&
                  !p['id']!.toUpperCase().contains('RECYCLE') &&
                  !p['id']!.toUpperCase().contains('SYSTEM VOLUME') &&
                  !p['id']!.toUpperCase().contains('DO NOT TOUCH') &&
                  !p['id']!.toUpperCase().contains('REFERENCE PLEASE') &&
                  !p['name']!.toUpperCase().contains('DO NOT TOUCH') &&
                  !p['name']!.toUpperCase().contains('REFERENCE PLEASE'))
              .toList();

          final seen = <String>{};
          final uniqueP = <Map<String, String>>[];
          for (final p in pList) {
            if (!seen.contains(p['id'])) {
              seen.add(p['id']!);
              uniqueP.add(p);
            }
          }
          if (uniqueP.isNotEmpty) {
            _projects = uniqueP;
            if (_selectedProjectId.isEmpty || !_projects.any((p) => p['id'] == _selectedProjectId)) {
              _selectedProjectId = _projects.first['id']!;
              _selectedProjectName = _projects.first['name']!;
            }
          }
        }

        if (res['departments'] is List && (res['departments'] as List).isNotEmpty) {
          final dList = (res['departments'] as List).map((d) => d.toString()).toSet().toList();
          _departments = dList;
          if (!_departments.contains(_selectedDepartment)) {
            _selectedDepartment = _departments.first;
          }
        }

        if (res['tasks_by_dept'] is Map && (res['tasks_by_dept'] as Map).isNotEmpty) {
          final Map<String, List<String>> newTasks = {};
          (res['tasks_by_dept'] as Map).forEach((k, v) {
            if (v is List) {
              newTasks[k.toString()] = v.map((e) => e.toString()).toSet().toList();
            }
          });
          _tasksByDept = newTasks;
          final available = _tasksByDept[_selectedDepartment] ?? [];
          if (available.isNotEmpty) {
            _selectedTask = available.first;
          }
        }

        if (res['subtasks_by_task'] is Map && (res['subtasks_by_task'] as Map).isNotEmpty) {
          final Map<String, List<String>> newSubs = {};
          (res['subtasks_by_task'] as Map).forEach((k, v) {
            if (v is List) {
              newSubs[k.toString()] = v.map((e) => e.toString()).toSet().toList();
            }
          });
          _subtasksByTask = newSubs;
          final availableSubs = _subtasksByTask[_selectedTask] ?? [];
          if (availableSubs.isNotEmpty) {
            _selectedSubtask = availableSubs.first;
          }
        }

        if (res['units'] is List && (res['units'] as List).isNotEmpty) {
          _units = (res['units'] as List).map((u) => u.toString()).toSet().toList();
        }

        if (res['revisions'] is List && (res['revisions'] as List).isNotEmpty) {
          _revisions = (res['revisions'] as List).map((r) => r.toString()).toSet().toList();
        }
      }
    } catch (_) {
      // Graceful fallback to embedded PMS options
    } finally {
      if (mounted) setState(() => _isLoadingOptions = false);
    }
  }



  @override
  void dispose() {
    _qtyCtrl.dispose();
    _hoursCtrl.dispose();
    _minutesCtrl.dispose();
    _remarksCtrl.dispose();
    super.dispose();
  }

  void _addQuickChip(String chipText) {
    final clean = chipText.replaceAll('+ ', '').trim();
    final current = _remarksCtrl.text.trim();
    if (current.isEmpty) {
      _remarksCtrl.text = clean;
    } else if (!current.contains(clean)) {
      _remarksCtrl.text = '$current. $clean.';
    }
    setState(() {});
  }

  int get _parsedHours => int.tryParse(_hoursCtrl.text.trim()) ?? 0;
  int get _parsedMinutes => int.tryParse(_minutesCtrl.text.trim()) ?? 0;

  Future<void> _pickDate() async {
    final picked = await showAppDatePicker(
      context: context,
      initialDate: _workDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() => _workDate = picked);
    }
  }

  Future<void> _saveWorkEntry() async {
    final qty = double.tryParse(_qtyCtrl.text.trim()) ?? 0.0;
    final hrs = _parsedHours;
    final mins = _parsedMinutes;
    final remarksText = _remarksCtrl.text.trim();

    // Mandatory project check with automatic fallback
    if (_selectedProjectId.trim().isEmpty && _selectedProjectName.trim().isEmpty) {
      if (_projects.isNotEmpty) {
        _selectedProjectId = _projects.first['id'] ?? '';
        _selectedProjectName = _projects.first['name'] ?? _selectedProjectId;
      }
    }

    if (_selectedProjectId.trim().isEmpty && _selectedProjectName.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Please select or type a Project.'),
          backgroundColor: Color(0xFFBA1A1A),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Mandatory remarks check
    if (remarksText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Remarks are mandatory. Please provide details of the work completed.'),
          backgroundColor: Color(0xFFBA1A1A),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (hrs == 0 && mins == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Please enter hours or minutes spent on this task.'),
          backgroundColor: Color(0xFFBA1A1A),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final payload = {
        'work_date': DateFormat('yyyy-MM-dd').format(_workDate),
        'project_id': _selectedProjectId.isNotEmpty ? _selectedProjectId : _selectedProjectName,
        'project_name': _selectedProjectName.isNotEmpty ? _selectedProjectName : _selectedProjectId,
        'department': _selectedDepartment,
        'task': _selectedTask,
        'subtask': _selectedSubtask,
        'quantity': qty,
        'unit': _selectedUnit,
        'hours': hrs,
        'minutes': mins,
        'revision': _selectedRevision,
        'remarks': remarksText,
      };

      final res = await apiPost('/api/work-entries', payload, token: widget.token);
      if (mounted) {
        setState(() => _isSaving = false);
        if (res['success'] == true) {
          Navigator.of(context).pop();
          widget.onSaved?.call();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Work Entry saved for ${_selectedProjectName.isNotEmpty ? _selectedProjectName : _selectedProjectId} (${hrs}h ${mins}m)',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF16A34A),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res['error']?.toString() ?? 'Could not save work entry'),
              backgroundColor: const Color(0xFFBA1A1A),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving work entry: $e'), backgroundColor: const Color(0xFFBA1A1A)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeController.isDarkMode;
    final bgSheet = isDark ? const Color(0xFF131722) : const Color(0xFFFBF9F4);
    final bgCard = isDark ? const Color(0xFF1E2536) : Colors.white;
    final bgInput = isDark ? const Color(0xFF161B28) : const Color(0xFFF3F4F6);
    final textPrimary = isDark ? Colors.white : const Color(0xFF1E293B);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final borderCol = isDark ? const Color(0xFF2A3449) : const Color(0xFFE2E8F0);
    const amberPrimary = Color(0xFFF5A952);
    const amberDark = Color(0xFF451A03);

    final currentTasks = _tasksByDept[_selectedDepartment] ?? ['General Site Work'];
    final currentSubtasks = _subtasksByTask[_selectedTask] ?? [
      'Execution & Baseline Verification',
      'Field Inspection & Documentation',
      'Material Handling & QA Signoff'
    ];

    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: screenHeight * 0.90,
        ),
        decoration: BoxDecoration(
          color: bgSheet,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: const [
            BoxShadow(color: Color(0x33000000), blurRadius: 30, offset: Offset(0, -6)),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              // Handle Bar
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: textSecondary.withAlpha(70),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),

              if (_isLoadingOptions)
                const LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(amberPrimary),
                ),

              // Scrollable Content
              Expanded(
                child: ListView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  children: [
                  // ── Top Card: WORK DATE & PROJECT ID ─────────────────────────
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: bgCard,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: borderCol),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withAlpha(isDark ? 30 : 6), blurRadius: 12, offset: const Offset(0, 3)),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // WORK DATE
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.calendar_month_rounded, size: 16, color: Color(0xFF38BDF8)),
                                const SizedBox(width: 6),
                                Text(
                                  'WORK DATE',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: textSecondary, letterSpacing: 0.8),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withAlpha(isDark ? 35 : 20),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF10B981).withAlpha(80)),
                              ),
                              child: const Text(
                                'Automated',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF10B981)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        InkWell(
                          onTap: _pickDate,
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            height: 48,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: bgInput,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: borderCol),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  DateFormat('dd-MM-yyyy').format(_workDate),
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textPrimary),
                                ),
                                Icon(Icons.event_rounded, size: 18, color: textSecondary),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // PROJECT ID / NAME
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.inventory_2_outlined, size: 16, color: Color(0xFFF59E0B)),
                                const SizedBox(width: 6),
                                Text(
                                  'PROJECT ID / NAME',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: textSecondary, letterSpacing: 0.8),
                                ),
                              ],
                            ),
                            Text(
                              'Required',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: textSecondary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        _searchableProjectDropdown(
                          bgInput: bgInput,
                          bgCard: bgCard,
                          textPrimary: textPrimary,
                          textSecondary: textSecondary,
                          borderCol: borderCol,
                          amberPrimary: amberPrimary,
                          amberDark: amberDark,
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // ── Card 2: ASSIGNMENT SCOPE ─────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: bgCard,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: borderCol),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withAlpha(isDark ? 30 : 6), blurRadius: 12, offset: const Offset(0, 3)),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.account_tree_outlined, size: 16, color: Color(0xFFF59E0B)),
                            const SizedBox(width: 6),
                            Text(
                              'ASSIGNMENT SCOPE',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: textPrimary, letterSpacing: 0.8),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // DEPARTMENT
                        _fieldHeader(Icons.business_outlined, 'DEPARTMENT', textSecondary),
                        const SizedBox(height: 6),
                        _customDropdown(
                          value: _selectedDepartment,
                          items: _departments,
                          bgInput: bgInput,
                          bgCard: bgCard,
                          textPrimary: textPrimary,
                          textSecondary: textSecondary,
                          borderCol: borderCol,
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _selectedDepartment = val;
                                final newTasks = _tasksByDept[val] ?? ['General Task'];
                                _selectedTask = newTasks.first;
                                final newSubtasks = _subtasksByTask[_selectedTask] ?? ['General Subtask'];
                                _selectedSubtask = newSubtasks.first;
                              });
                            }
                          },
                        ),

                        const SizedBox(height: 14),

                        // TASK
                        _fieldHeader(Icons.folder_open_rounded, 'TASK', textSecondary),
                        const SizedBox(height: 6),
                        _customDropdown(
                          value: currentTasks.contains(_selectedTask) ? _selectedTask : currentTasks.first,
                          items: currentTasks,
                          bgInput: bgInput,
                          bgCard: bgCard,
                          textPrimary: textPrimary,
                          textSecondary: textSecondary,
                          borderCol: borderCol,
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _selectedTask = val;
                                final newSubtasks = _subtasksByTask[val] ?? ['General Subtask'];
                                _selectedSubtask = newSubtasks.first;
                              });
                            }
                          },
                        ),

                        const SizedBox(height: 14),

                        // SUBTASK
                        _fieldHeader(Icons.push_pin_outlined, 'SUBTASK', textSecondary),
                        const SizedBox(height: 6),
                        _customDropdown(
                          value: currentSubtasks.contains(_selectedSubtask) ? _selectedSubtask : currentSubtasks.first,
                          items: currentSubtasks,
                          bgInput: bgInput,
                          bgCard: bgCard,
                          textPrimary: textPrimary,
                          textSecondary: textSecondary,
                          borderCol: borderCol,
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _selectedSubtask = val);
                            }
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // ── Card 3: OUTPUT & EFFORT ──────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: bgCard,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: borderCol),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withAlpha(isDark ? 30 : 6), blurRadius: 12, offset: const Offset(0, 3)),
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
                                const Icon(Icons.timelapse_rounded, size: 16, color: Color(0xFF0D9488)),
                                const SizedBox(width: 6),
                                Text(
                                  'OUTPUT & EFFORT',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: textPrimary, letterSpacing: 0.8),
                                ),
                              ],
                            ),
                            Text(
                              'Total: ${_parsedHours}h ${_parsedMinutes}m',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textSecondary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // QUANTITY PRODUCED
                        _fieldHeader(Icons.speed_rounded, 'QUANTITY PRODUCED', textSecondary),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Container(
                                height: 48,
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                decoration: BoxDecoration(
                                  color: bgInput,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: borderCol),
                                ),
                                child: Center(
                                  child: TextField(
                                    controller: _qtyCtrl,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    scrollPadding: const EdgeInsets.only(bottom: 120),
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textPrimary),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      border: InputBorder.none,
                                      hintText: '',
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: Container(
                                height: 48,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  color: bgInput,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: borderCol),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _units.contains(_selectedUnit) ? _selectedUnit : _units.first,
                                    isExpanded: true,
                                    dropdownColor: bgCard,
                                    icon: Icon(Icons.keyboard_arrow_down_rounded, color: textSecondary, size: 20),
                                    items: _units.map((u) {
                                      return DropdownMenuItem<String>(
                                        value: u,
                                        child: Text(u, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textPrimary)),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      if (val != null) setState(() => _selectedUnit = val);
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 14),

                        // HOURS & MINUTES (Clean numeric inputs matching Image 1)
                        Row(
                          children: [
                            // Hours Field
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _fieldHeader(Icons.access_time_rounded, 'HOURS', textSecondary),
                                  const SizedBox(height: 6),
                                  Container(
                                    height: 48,
                                    padding: const EdgeInsets.symmetric(horizontal: 14),
                                    decoration: BoxDecoration(
                                      color: bgInput,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: borderCol),
                                    ),
                                    child: Center(
                                      child: TextField(
                                        controller: _hoursCtrl,
                                        keyboardType: TextInputType.number,
                                        scrollPadding: const EdgeInsets.only(bottom: 120),
                                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textPrimary),
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          border: InputBorder.none,
                                          hintText: '',
                                        ),
                                        onChanged: (_) => setState(() {}),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Minutes Field
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _fieldHeader(Icons.hourglass_top_rounded, 'MINUTES', textSecondary),
                                  const SizedBox(height: 6),
                                  Container(
                                    height: 48,
                                    padding: const EdgeInsets.symmetric(horizontal: 14),
                                    decoration: BoxDecoration(
                                      color: bgInput,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: borderCol),
                                    ),
                                    child: Center(
                                      child: TextField(
                                        controller: _minutesCtrl,
                                        keyboardType: TextInputType.number,
                                        scrollPadding: const EdgeInsets.only(bottom: 120),
                                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textPrimary),
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          border: InputBorder.none,
                                          hintText: '',
                                        ),
                                        onChanged: (_) => setState(() {}),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 14),

                        // REVISION VERSION
                        _fieldHeader(Icons.history_rounded, 'REVISION', textSecondary),
                        const SizedBox(height: 6),
                        _customDropdown(
                          value: _revisions.contains(_selectedRevision) ? _selectedRevision : _revisions.first,
                          items: _revisions,
                          bgInput: bgInput,
                          bgCard: bgCard,
                          textPrimary: textPrimary,
                          textSecondary: textSecondary,
                          borderCol: borderCol,
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedRevision = val);
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // ── Card 4: REMARKS & CONTEXT (MANDATORY) ────────────────────
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: bgCard,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: _remarksCtrl.text.trim().isEmpty ? const Color(0xFFEF4444).withAlpha(120) : borderCol,
                        width: _remarksCtrl.text.trim().isEmpty ? 1.4 : 1.0,
                      ),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withAlpha(isDark ? 30 : 6), blurRadius: 12, offset: const Offset(0, 3)),
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
                                const Icon(Icons.chat_bubble_outline_rounded, size: 16, color: Color(0xFFA855F7)),
                                const SizedBox(width: 6),
                                Text(
                                  'REMARKS',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: textPrimary, letterSpacing: 0.8),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF4444).withAlpha(isDark ? 35 : 20),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFEF4444).withAlpha(80)),
                              ),
                              child: const Text(
                                'Required',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFEF4444)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: bgInput,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _remarksCtrl.text.trim().isEmpty ? const Color(0xFFEF4444).withAlpha(80) : borderCol,
                            ),
                          ),
                          child: TextField(
                            controller: _remarksCtrl,
                            maxLines: 3,
                            scrollPadding: const EdgeInsets.only(bottom: 160),
                            style: TextStyle(fontSize: 12.5, color: textPrimary, height: 1.4),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              hintText: '',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),

                        const SizedBox(height: 10),

                        // Quick Chips
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: _quickChips.map((chip) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: InkWell(
                                  onTap: () => _addQuickChip(chip),
                                  borderRadius: BorderRadius.circular(20),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: bgInput,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: borderCol),
                                    ),
                                    child: Text(
                                      chip,
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textSecondary),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Footer Actions ───────────────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        flex: 1,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded, size: 16),
                          label: const Text('Cancel'),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: borderCol),
                            foregroundColor: textSecondary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _isSaving ? null : _saveWorkEntry,
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: amberDark),
                                )
                              : const Icon(Icons.check_circle_rounded, size: 18),
                          label: Text(_isSaving ? 'Saving Entry...' : 'Save Work Entry'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: amberPrimary,
                            foregroundColor: amberDark,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            elevation: 0,
                            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

  Widget _fieldHeader(IconData icon, String title, Color color) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.6),
        ),
      ],
    );
  }

  Widget _customDropdown({
    required String value,
    required List<String> items,
    required Color bgInput,
    required Color bgCard,
    required Color textPrimary,
    required Color textSecondary,
    required Color borderCol,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: bgInput,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderCol),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(value) ? value : (items.isNotEmpty ? items.first : null),
          isExpanded: true,
          dropdownColor: bgCard,
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: textSecondary, size: 20),
          items: items.map((item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Text(
                item,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _searchableProjectDropdown({
    required Color bgInput,
    required Color bgCard,
    required Color textPrimary,
    required Color textSecondary,
    required Color borderCol,
    required Color amberPrimary,
    required Color amberDark,
    required bool isDark,
  }) {
    String formatLabel(Map<String, String> p) {
      final id = (p['id'] ?? '').trim();
      final name = (p['name'] ?? '').trim();
      if (id.isEmpty) return name;
      if (name.isEmpty || id == name) return id;
      return '#$id — $name';
    }

    final projectStrings = _projects.map(formatLabel).toList();
    final initialVal = _selectedProjectId.isNotEmpty && _projects.any((p) => p['id'] == _selectedProjectId)
        ? formatLabel(_projects.firstWhere((p) => p['id'] == _selectedProjectId))
        : (_projects.isNotEmpty ? formatLabel(_projects.first) : '');

    return LayoutBuilder(
      builder: (context, constraints) {
        return RawAutocomplete<String>(
          initialValue: TextEditingValue(text: initialVal),
          optionsBuilder: (TextEditingValue textEditingValue) {
            final query = textEditingValue.text.trim().toLowerCase().replaceAll('#', '');
            if (query.isEmpty) {
              return projectStrings;
            }
            return projectStrings.where((opt) {
              return opt.toLowerCase().replaceAll('#', '').contains(query);
            });
          },
          onSelected: (String selection) {
            final match = _projects.firstWhere(
              (p) => formatLabel(p) == selection,
              orElse: () => {'id': selection, 'name': selection},
            );
            setState(() {
              _selectedProjectId = match['id']?.isNotEmpty == true ? match['id']! : selection;
              _selectedProjectName = match['name']?.isNotEmpty == true ? match['name']! : selection;
            });
          },
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            return Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: bgInput,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: focusNode.hasFocus ? amberPrimary : borderCol,
                  width: focusNode.hasFocus ? 1.4 : 1.0,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      scrollPadding: const EdgeInsets.only(bottom: 120),
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary),
                      onChanged: (val) {
                        final clean = val.trim();
                        final cleanId = clean.replaceAll('#', '').split(' — ').first.trim();
                        final match = _projects.firstWhere(
                          (p) => formatLabel(p).toLowerCase() == clean.toLowerCase() || (p['id'] ?? '').toLowerCase() == cleanId.toLowerCase(),
                          orElse: () => {'id': cleanId, 'name': clean},
                        );
                        _selectedProjectId = match['id']?.isNotEmpty == true ? match['id']! : cleanId;
                        _selectedProjectName = match['name']?.isNotEmpty == true ? match['name']! : clean;
                      },
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        hintText: '',
                        hintStyle: TextStyle(fontSize: 12, color: textSecondary, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                  if (controller.text.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        controller.clear();
                        setState(() {
                          _selectedProjectId = '';
                          _selectedProjectName = '';
                        });
                        focusNode.requestFocus();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(Icons.cancel_rounded, size: 16, color: textSecondary),
                      ),
                    ),
                  GestureDetector(
                    onTap: () {
                      if (focusNode.hasFocus) {
                        focusNode.unfocus();
                      } else {
                        focusNode.requestFocus();
                      }
                    },
                    child: Icon(Icons.keyboard_arrow_down_rounded, color: textSecondary, size: 20),
                  ),
                ],
              ),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(14),
                color: bgCard,
                shadowColor: Colors.black.withAlpha(80),
                child: Container(
                  width: constraints.maxWidth,
                  constraints: const BoxConstraints(maxHeight: 260),
                  decoration: BoxDecoration(
                    color: bgCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderCol),
                  ),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    shrinkWrap: true,
                    itemCount: options.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: borderCol.withAlpha(80)),
                    itemBuilder: (BuildContext context, int index) {
                      final String option = options.elementAt(index);
                      final isSelected = option.startsWith('#$_selectedProjectId ');

                      return InkWell(
                        onTap: () => onSelected(option),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                          color: isSelected ? amberPrimary.withAlpha(isDark ? 40 : 25) : Colors.transparent,
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  option,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                    color: textPrimary,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                Icon(Icons.check_circle_rounded, color: amberPrimary, size: 18),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
