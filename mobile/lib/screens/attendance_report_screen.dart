import 'package:flutter/material.dart';
import '../services/class_service.dart';

class AttendanceReportScreen extends StatefulWidget {
  final int classId;
  final String className;

  const AttendanceReportScreen({
    super.key,
    required this.classId,
    required this.className,
  });

  @override
  State<AttendanceReportScreen> createState() => _AttendanceReportScreenState();
}

class _AttendanceReportScreenState extends State<AttendanceReportScreen>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _logs = [];
  List<Map<String, dynamic>> _members = [];
  bool _isLoading = true;
  String _filter = 'all';
  DateTime? _selectedDate;         // ← new
  late AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _loadData();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        ClassService.getClassAttendance(widget.classId),
        ClassService.getClassMembers(widget.classId),
      ]);
      if (mounted) {
        setState(() {
          _logs    = List<Map<String, dynamic>>.from(results[0]);
          _members = List<Map<String, dynamic>>.from(results[1]);
        });
        _animCtrl.forward(from: 0);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("Failed to load: $e"),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Date picker ───────────────────────────────

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary:   Color(0xFF6C63FF),
            onPrimary: Colors.white,
            surface:   Color(0xFF0E1120),
            onSurface: Colors.white,
          ),
          dialogBackgroundColor: const Color(0xFF0E1120),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  void _clearDate() => setState(() => _selectedDate = null);

  // ── Logs filtered by selected date ────────────

  List<Map<String, dynamic>> get _dateLogs {
    if (_selectedDate == null) return _logs;
    return _logs.where((l) {
      try {
        final dt = DateTime.parse(l['timestamp'].toString()).toLocal();
        return dt.year  == _selectedDate!.year &&
               dt.month == _selectedDate!.month &&
               dt.day   == _selectedDate!.day;
      } catch (_) {
        return false;
      }
    }).toList();
  }

  // ── Derived data (all use _dateLogs) ──────────

  Set<String> get _presentNames =>
      _dateLogs.map((l) => (l['user_name'] as String? ?? '').toLowerCase()).toSet();

  int get _presentCount => _members
      .where((m) =>
          _presentNames.contains((m['name'] as String? ?? '').toLowerCase()))
      .length;

  int get _absentCount => _members.length - _presentCount;

  double get _attendanceRate =>
      _members.isEmpty ? 0 : _presentCount / _members.length;

  Map<String, int> get _sessionCountByStudent {
    final map = <String, int>{};
    for (final log in _dateLogs) {
      final name = (log['user_name'] as String? ?? '');
      map[name] = (map[name] ?? 0) + 1;
    }
    return map;
  }

  List<Map<String, dynamic>> get _filteredMembers {
    return _members.where((m) {
      final name = (m['name'] as String? ?? '').toLowerCase();
      final isPresent = _presentNames.contains(name);
      if (_filter == 'present') return isPresent;
      if (_filter == 'absent')  return !isPresent;
      return true;
    }).toList();
  }

  // ── Helpers ───────────────────────────────────

  String _timeAgo(String? raw) {
    if (raw == null) return '—';
    try {
      final dt   = DateTime.parse(raw).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1)  return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24)   return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return '—';
    }
  }

  String _formatDate(String? raw) {
    if (raw == null) return '—';
    try {
      final dt = DateTime.parse(raw).toLocal();
      const months = [
        'Jan','Feb','Mar','Apr','May','Jun',
        'Jul','Aug','Sep','Oct','Nov','Dec'
      ];
      final h   = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year} · $h:$min';
    } catch (_) {
      return '—';
    }
  }

  String _formatSelectedDate(DateTime d) {
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  String _lastSeen(String memberName) {
    final matching = _dateLogs
        .where((l) =>
            (l['user_name'] as String? ?? '').toLowerCase() ==
            memberName.toLowerCase())
        .toList();
    if (matching.isEmpty) return 'Never';
    matching.sort((a, b) =>
        (b['timestamp'] as String? ?? '')
            .compareTo(a['timestamp'] as String? ?? ''));
    return _timeAgo(matching.first['timestamp'] as String?);
  }

  // ── Build ─────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080B14),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF6C63FF)))
          : CustomScrollView(
              slivers: [
                _buildAppBar(),
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      _buildDateFilter(),       // ← new
                      _buildSummaryCards(),
                      _buildRateGauge(),
                      _buildRecentActivity(),
                      _buildStudentList(),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // ── App Bar ───────────────────────────────────

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 130,
      pinned: true,
      backgroundColor: const Color(0xFF080B14),
      foregroundColor: Colors.white,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ATTENDANCE REPORT',
              style: TextStyle(
                color: const Color(0xFF6C63FF).withOpacity(0.8),
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.5,
              ),
            ),
            Text(
              widget.className,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF13102A), Color(0xFF080B14)],
            ),
          ),
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loadData,
          tooltip: 'Refresh',
        ),
      ],
    );
  }

  // ── Date Filter Bar ───────────────────────────

  Widget _buildDateFilter() {
    final hasDate = _selectedDate != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _pickDate,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: hasDate
                      ? const Color(0xFF6C63FF).withOpacity(0.15)
                      : const Color(0xFF0E1120),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: hasDate
                        ? const Color(0xFF6C63FF).withOpacity(0.5)
                        : Colors.white.withOpacity(0.08),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_month_rounded,
                      size: 16,
                      color: hasDate
                          ? const Color(0xFF6C63FF)
                          : Colors.white38,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      hasDate
                          ? _formatSelectedDate(_selectedDate!)
                          : 'Filter by date',
                      style: TextStyle(
                        color: hasDate ? Colors.white : Colors.white38,
                        fontSize: 13,
                        fontWeight: hasDate
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (hasDate) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _clearDate,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: Colors.white54,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Summary Cards ─────────────────────────────

  Widget _buildSummaryCards() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: _GlowCard(
              accent: const Color(0xFF6C63FF),
              icon: Icons.people_alt_rounded,
              label: 'Total',
              value: '${_members.length}',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _GlowCard(
              accent: const Color(0xFF00E5A0),
              icon: Icons.check_circle_rounded,
              label: 'Present',
              value: '$_presentCount',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _GlowCard(
              accent: const Color(0xFFFF5C5C),
              icon: Icons.cancel_rounded,
              label: 'Absent',
              value: '$_absentCount',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _GlowCard(
              accent: const Color(0xFFFFB347),
              icon: Icons.receipt_long_rounded,
              label: 'Check-ins',
              value: '${_dateLogs.length}',
            ),
          ),
        ],
      ),
    );
  }

  // ── Attendance Rate Gauge ─────────────────────

  Widget _buildRateGauge() {
    final pct   = (_attendanceRate * 100).toStringAsFixed(1);
    final color = _attendanceRate >= 0.75
        ? const Color(0xFF00E5A0)
        : _attendanceRate >= 0.5
            ? const Color(0xFFFFB347)
            : const Color(0xFFFF5C5C);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1120),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
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
                  const Text(
                    'Attendance Rate',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_selectedDate != null)
                    Text(
                      _formatSelectedDate(_selectedDate!),
                      style: const TextStyle(
                          color: Color(0xFF6C63FF), fontSize: 11),
                    ),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withOpacity(0.3)),
                ),
                child: Text(
                  '$pct%',
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: _attendanceRate),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (_, val, __) => LinearProgressIndicator(
                value: val,
                minHeight: 12,
                backgroundColor: Colors.white.withOpacity(0.07),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _attendanceRate >= 0.75
                ? '✓ Good attendance across the class'
                : _attendanceRate >= 0.5
                    ? '⚠ Attendance needs improvement'
                    : '✗ Critical — many students missing',
            style: TextStyle(color: color.withOpacity(0.8), fontSize: 11),
          ),
        ],
      ),
    );
  }

  // ── Recent Activity ───────────────────────────

  Widget _buildRecentActivity() {
    if (_dateLogs.isEmpty) return const SizedBox.shrink();

    final recent = [..._dateLogs]
      ..sort((a, b) => (b['timestamp'] as String? ?? '')
          .compareTo(a['timestamp'] as String? ?? ''));
    final top = recent.take(5).toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1120),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'RECENT CHECK-INS',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
              ),
              if (_selectedDate != null)
                Text(
                  _formatSelectedDate(_selectedDate!),
                  style: const TextStyle(
                      color: Color(0xFF6C63FF), fontSize: 10),
                ),
            ],
          ),
          const SizedBox(height: 14),
          ...top.map((log) {
            final name = log['user_name'] as String? ?? '—';
            final ts   = log['timestamp'] as String?;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor:
                        const Color(0xFF6C63FF).withOpacity(0.15),
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: Color(0xFF6C63FF),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    _formatDate(ts),
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Student List ──────────────────────────────

  Widget _buildStudentList() {
    final filtered      = _filteredMembers;
    final sessionCounts = _sessionCountByStudent;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1120),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 12, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'STUDENTS',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                _FilterChip(
                  label: 'All',
                  active: _filter == 'all',
                  onTap: () => setState(() => _filter = 'all'),
                ),
                const SizedBox(width: 6),
                _FilterChip(
                  label: 'Present',
                  active: _filter == 'present',
                  color: const Color(0xFF00E5A0),
                  onTap: () => setState(() => _filter = 'present'),
                ),
                const SizedBox(width: 6),
                _FilterChip(
                  label: 'Absent',
                  active: _filter == 'absent',
                  color: const Color(0xFFFF5C5C),
                  onTap: () => setState(() => _filter = 'absent'),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 1),

          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  _filter == 'present'
                      ? 'No students present'
                      : _filter == 'absent'
                          ? 'No students absent 🎉'
                          : 'No students enrolled',
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 13),
                ),
              ),
            )
          else
            ...filtered.asMap().entries.map((entry) {
              final i         = entry.key;
              final m         = entry.value;
              final name      = m['name'] as String? ?? '—';
              final isPresent = _presentNames.contains(name.toLowerCase());
              final sessions  = sessionCounts[name] ?? 0;
              final isLast    = i == filtered.length - 1;

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 13),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: isPresent
                                ? const Color(0xFF00E5A0).withOpacity(0.12)
                                : const Color(0xFFFF5C5C).withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: TextStyle(
                                color: isPresent
                                    ? const Color(0xFF00E5A0)
                                    : const Color(0xFFFF5C5C),
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isPresent
                                    ? 'Last seen: ${_lastSeen(name)}'
                                    : 'Not checked in',
                                style: TextStyle(
                                  color: isPresent
                                      ? Colors.white38
                                      : const Color(0xFFFF5C5C)
                                          .withOpacity(0.6),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isPresent
                                ? const Color(0xFF00E5A0).withOpacity(0.15)
                                : Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            isPresent
                                ? '$sessions session${sessions == 1 ? '' : 's'}'
                                : 'Absent',
                            style: TextStyle(
                              color: isPresent
                                  ? const Color(0xFF00E5A0)
                                  : const Color(0xFFFF5C5C),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isLast)
                    const Divider(
                        color: Colors.white10, height: 1, indent: 66),
                ],
              );
            }),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Sub-widgets
// ─────────────────────────────────────────────

class _GlowCard extends StatelessWidget {
  final Color accent;
  final IconData icon;
  final String label;
  final String value;

  const _GlowCard({
    required this.accent,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withOpacity(0.18)),
      ),
      child: Column(
        children: [
          Icon(icon, color: accent, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: accent,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.active,
    this.color = const Color(0xFF6C63FF),
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? color.withOpacity(0.5) : Colors.white12,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? color : Colors.white38,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}