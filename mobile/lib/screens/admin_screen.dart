import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _attendance = [];
  bool _loadingUsers = true;
  bool _loadingLogs = true;
  String _searchQuery = '';

  static const _navy = Color(0xFF0D1B2A);
  static const _navyMid = Color(0xFF1A2E45);
  static const _navyLight = Color(0xFF243B55);
  static const _cyan = Color(0xFF00D4FF);
  static const _cyanDim = Color(0xFF0099BB);
  static const _surface = Color(0xFF152032);
  static const _surfaceHigh = Color(0xFF1E3048);
  static const _textPrimary = Color(0xFFF0F6FF);
  static const _textSub = Color(0xFF7EA8C4);
  static const _textMuted = Color(0xFF4A7090);
  static const _success = Color(0xFF00E5A0);
  static const _danger = Color(0xFFFF5B7F);
  static const _purple = Color(0xFFB16CEA);
  static const _warning = Color(0xFFFFB347);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadUsers();
    _loadLogs();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() => _loadingUsers = true);
    try {
      final users = await AuthService.adminListUsers();
      setState(() => _users = users);
    } catch (e) {
      _showSnack('Could not load users: $e', error: true);
    } finally {
      setState(() => _loadingUsers = false);
    }
  }

  Future<void> _loadLogs() async {
    setState(() => _loadingLogs = true);
    try {
      final logs = await AuthService.adminGetAttendance();
      setState(() => _attendance = logs);
    } catch (e) {
      _showSnack('Could not load logs: $e', error: true);
    } finally {
      setState(() => _loadingLogs = false);
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> user) async {
    final userId = user['id'];
    final currentlyActive = user['is_active'] ?? true;
    final action = currentlyActive ? 'deactivate' : 'activate';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: (currentlyActive ? _danger : _success).withOpacity(0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: (currentlyActive ? _danger : _success).withOpacity(0.3)),
                ),
                child: Icon(
                  currentlyActive ? Icons.block_rounded : Icons.check_circle_rounded,
                  color: currentlyActive ? _danger : _success,
                  size: 22,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '${action[0].toUpperCase()}${action.substring(1)} user?',
                style: const TextStyle(
                    color: _textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                '${user['name']} will be ${currentlyActive ? 'deactivated and unable to log in' : 'reactivated and able to log in again'}.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _textSub, fontSize: 13),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(ctx, false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: _navyMid,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _navyLight),
                        ),
                        child: const Center(
                            child: Text('Cancel',
                                style: TextStyle(color: _textSub, fontSize: 14))),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(ctx, true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: (currentlyActive ? _danger : _success).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: (currentlyActive ? _danger : _success).withOpacity(0.4)),
                        ),
                        child: Center(
                          child: Text(
                            action[0].toUpperCase() + action.substring(1),
                            style: TextStyle(
                                color: currentlyActive ? _danger : _success,
                                fontWeight: FontWeight.w600,
                                fontSize: 14),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      await AuthService.adminToggleActive(userId);
      await _loadUsers();
      _showSnack(
          '${user['name']} ${currentlyActive ? 'deactivated' : 'activated'} successfully');
    } catch (e) {
      _showSnack('Failed to update: $e', error: true);
    }
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _danger.withOpacity(0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: _danger.withOpacity(0.3)),
                ),
                child: const Icon(Icons.logout_rounded, color: _danger, size: 22),
              ),
              const SizedBox(height: 16),
              const Text('Log out?',
                  style: TextStyle(
                      color: _textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text("You'll need to sign in again\nto access the admin panel.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _textSub, fontSize: 13)),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: _navyMid,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _navyLight),
                        ),
                        child: const Center(
                            child: Text('Cancel',
                                style: TextStyle(color: _textSub, fontSize: 14))),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        Navigator.pop(ctx);
                        await AuthService.logout();
                        if (!mounted) return;
                        Navigator.pushReplacementNamed(context, '/login');
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: _danger.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _danger.withOpacity(0.4)),
                        ),
                        child: const Center(
                          child: Text('Log out',
                              style: TextStyle(
                                  color: _danger,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          Icon(error ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Flexible(child: Text(msg, style: const TextStyle(fontSize: 13))),
        ],
      ),
      backgroundColor: error ? _danger : _cyanDim,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 3),
    ));
  }

  Color _roleColor(String? role) {
    switch (role) {
      case 'admin':
        return _purple;
      case 'teacher':
        return _cyan;
      default:
        return _success;
    }
  }

  IconData _roleIcon(String? role) {
    switch (role) {
      case 'admin':
        return Icons.shield_rounded;
      case 'teacher':
        return Icons.school_rounded;
      default:
        return Icons.person_rounded;
    }
  }

  List<Map<String, dynamic>> get _filteredUsers {
    if (_searchQuery.isEmpty) return _users;
    final q = _searchQuery.toLowerCase();
    return _users.where((u) {
      final name = (u['name'] ?? '').toString().toLowerCase();
      final email = (u['email'] ?? '').toString().toLowerCase();
      final role = (u['role'] ?? '').toString().toLowerCase();
      return name.contains(q) || email.contains(q) || role.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      appBar: _buildAppBar(),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildUsersTab(),
          _buildAttendanceTab(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(130),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_navyMid, _navyLight],
          ),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 16,
                offset: const Offset(0, 4)),
          ],
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _cyan.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _cyan.withOpacity(0.3)),
                      ),
                      child: const Icon(Icons.admin_panel_settings_rounded,
                          color: _cyan, size: 20),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Admin Panel',
                              style: TextStyle(
                                  color: _textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  letterSpacing: 0.3)),
                          Text('System Dashboard',
                              style: TextStyle(
                                  color: _textMuted,
                                  fontSize: 11,
                                  letterSpacing: 0.5)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: _danger.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _danger.withOpacity(0.3)),
                        ),
                        child: const Icon(Icons.logout_rounded,
                            color: _danger, size: 18),
                      ),
                      tooltip: 'Sign out',
                      onPressed: _confirmLogout,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TabBar(
                controller: _tabs,
                indicatorColor: _cyan,
                indicatorWeight: 2,
                indicatorSize: TabBarIndicatorSize.label,
                labelColor: _cyan,
                unselectedLabelColor: _textMuted,
                labelStyle:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.people_alt_rounded, size: 15),
                        const SizedBox(width: 6),
                        Text('Users (${_users.length})'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.event_available_rounded, size: 15),
                        const SizedBox(width: 6),
                        Text('Logs (${_attendance.length})'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUsersTab() {
    if (_loadingUsers) return _buildLoader();
    if (_users.isEmpty) {
      return _buildEmpty(Icons.people_alt_rounded, 'No users found',
          'Users will appear here once registered');
    }

    final admins = _users.where((u) => u['role'] == 'admin').length;
    final teachers = _users.where((u) => u['role'] == 'teacher').length;
    final students = _users.where((u) => u['role'] == 'student').length;
    final active = _users.where((u) => u['is_active'] == true).length;
    final inactive = _users.length - active;
    final filtered = _filteredUsers;

    return RefreshIndicator(
      color: _cyan,
      backgroundColor: _surfaceHigh,
      onRefresh: _loadUsers,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Role stats
                  Row(
                    children: [
                      _StatCard(
                          label: 'Admins',
                          value: admins,
                          icon: Icons.shield_rounded,
                          color: _purple),
                      const SizedBox(width: 8),
                      _StatCard(
                          label: 'Teachers',
                          value: teachers,
                          icon: Icons.school_rounded,
                          color: _cyan),
                      const SizedBox(width: 8),
                      _StatCard(
                          label: 'Students',
                          value: students,
                          icon: Icons.person_rounded,
                          color: _success),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Active/Inactive stats
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 12),
                          decoration: BoxDecoration(
                            color: _surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: _success.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                    color: _success,
                                    shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 8),
                              Text('$active Active',
                                  style: const TextStyle(
                                      color: _success,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 12),
                          decoration: BoxDecoration(
                            color: _surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: _danger.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                    color: _danger,
                                    shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 8),
                              Text('$inactive Inactive',
                                  style: const TextStyle(
                                      color: _danger,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Search
                  Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _navyLight),
                    ),
                    child: TextField(
                      onChanged: (v) => setState(() => _searchQuery = v),
                      style:
                          const TextStyle(color: _textPrimary, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search users…',
                        hintStyle:
                            const TextStyle(color: _textMuted, fontSize: 13),
                        prefixIcon: const Icon(Icons.search_rounded,
                            color: _textMuted, size: 18),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close_rounded,
                                    color: _textMuted, size: 16),
                                onPressed: () =>
                                    setState(() => _searchQuery = ''),
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) {
                  final u = filtered[i];
                  return _UserCard(
                    user: u,
                    roleColor: _roleColor(u['role']),
                    roleIcon: _roleIcon(u['role']),
                    onToggleActive: () => _toggleActive(u),
                  );
                },
                childCount: filtered.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceTab() {
    if (_loadingLogs) return _buildLoader();
    if (_attendance.isEmpty) {
      return _buildEmpty(Icons.event_available_rounded, 'No attendance records',
          'Records will appear after check-ins');
    }

    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final log in _attendance) {
      final ts = log['timestamp']?.toString() ?? '';
      final date = ts.length >= 10 ? ts.substring(0, 10) : 'Unknown';
      grouped.putIfAbsent(date, () => []).add(log);
    }
    final dates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return RefreshIndicator(
      color: _cyan,
      backgroundColor: _surfaceHigh,
      onRefresh: _loadLogs,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _success.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                      border:
                          Border.all(color: _success.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle_outline,
                            color: _success, size: 14),
                        const SizedBox(width: 6),
                        Text('${_attendance.length} total check-ins',
                            style: const TextStyle(
                                color: _success,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          for (final date in dates) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Row(
                  children: [
                    Text(_formatDate(date),
                        style: const TextStyle(
                            color: _cyan,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2)),
                    const SizedBox(width: 8),
                    Expanded(child: Container(height: 1, color: _navyLight)),
                    const SizedBox(width: 8),
                    Text('${grouped[date]!.length}',
                        style: const TextStyle(
                            color: _textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _AttendanceCard(log: grouped[date]![i]),
                  childCount: grouped[date]!.length,
                ),
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      const months = [
        '', 'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
        'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'
      ];
      return '${months[dt.month]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return iso.toUpperCase();
    }
  }

  Widget _buildLoader() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(color: _cyan, strokeWidth: 2.5)),
          SizedBox(height: 12),
          Text('Loading…', style: TextStyle(color: _textMuted, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildEmpty(IconData icon, String title, String sub) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: RadialGradient(
                    colors: [_cyan.withOpacity(0.12), _cyan.withOpacity(0.0)]),
                shape: BoxShape.circle,
              ),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: _cyan.withOpacity(0.3)),
                ),
                child: Icon(icon, size: 32, color: _cyan),
              ),
            ),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(sub,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: _textMuted, fontSize: 13, height: 1.5)),
          ],
        ),
      ),
    );
  }
}

// ── Stat Card ─────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;

  const _StatCard(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) {
    const surface = Color(0xFF152032);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.25)),
          boxShadow: [
            BoxShadow(
                color: color.withOpacity(0.08),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: 14),
            ),
            const SizedBox(height: 8),
            Text('$value',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: color,
                    height: 1)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: color.withOpacity(0.7),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }
}

// ── User Card ─────────────────────────────────────────────────────────────────

class _UserCard extends StatelessWidget {
  final Map<String, dynamic> user;
  final Color roleColor;
  final IconData roleIcon;
  final VoidCallback onToggleActive;

  static const _surface = Color(0xFF152032);
  static const _surfaceHigh = Color(0xFF1E3048);
  static const _navyLight = Color(0xFF243B55);
  static const _textPrimary = Color(0xFFF0F6FF);
  static const _textSub = Color(0xFF7EA8C4);
  static const _textMuted = Color(0xFF4A7090);
  static const _success = Color(0xFF00E5A0);
  static const _danger = Color(0xFFFF5B7F);

  const _UserCard({
    required this.user,
    required this.roleColor,
    required this.roleIcon,
    required this.onToggleActive,
  });

  @override
  Widget build(BuildContext context) {
    final name = user['name'] ?? '?';
    final email = user['email'] ?? '—';
    final role = user['role'] ?? 'student';
    final isActive = user['is_active'] ?? true;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final statusColor = isActive ? _success : _danger;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isActive ? _surface : _surface.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isActive ? _navyLight : _danger.withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Avatar with status dot
            Stack(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        roleColor.withOpacity(isActive ? 0.3 : 0.15),
                        roleColor.withOpacity(isActive ? 0.1 : 0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: roleColor.withOpacity(isActive ? 0.4 : 0.2)),
                  ),
                  child: Center(
                    child: Text(initial,
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: roleColor
                                .withOpacity(isActive ? 1.0 : 0.4))),
                  ),
                ),
                // Role badge
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: _surfaceHigh,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: roleColor.withOpacity(0.5)),
                    ),
                    child: Icon(roleIcon, size: 9, color: roleColor),
                  ),
                ),
                // Active status dot
                Positioned(
                  left: 0,
                  top: 0,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: _surface, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(name,
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: isActive
                                    ? _textPrimary
                                    : _textMuted),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1),
                      ),
                      // Active/Inactive badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: statusColor.withOpacity(0.3)),
                        ),
                        child: Text(
                          isActive ? 'ACTIVE' : 'INACTIVE',
                          style: TextStyle(
                              fontSize: 8,
                              color: statusColor,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(email,
                      style: const TextStyle(color: _textSub, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: roleColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: roleColor.withOpacity(0.3)),
                        ),
                        child: Text(role.toUpperCase(),
                            style: TextStyle(
                                fontSize: 9,
                                color: roleColor,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Toggle button
            GestureDetector(
              onTap: onToggleActive,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: statusColor.withOpacity(0.3)),
                ),
                child: Icon(
                  isActive ? Icons.block_rounded : Icons.check_circle_outline,
                  color: statusColor,
                  size: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Attendance Card ───────────────────────────────────────────────────────────

class _AttendanceCard extends StatelessWidget {
  final Map<String, dynamic> log;

  static const _surface = Color(0xFF152032);
  static const _navyLight = Color(0xFF243B55);
  static const _textPrimary = Color(0xFFF0F6FF);
  static const _textSub = Color(0xFF7EA8C4);
  static const _success = Color(0xFF00E5A0);
  static const _warning = Color(0xFFFFB347);

  const _AttendanceCard({required this.log});

  @override
  Widget build(BuildContext context) {
    final name = log['user_name'] ?? log['name'] ?? 'Unknown';
    final className = log['class_name'] ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final confidence = (log['confidence'] as num?)?.toDouble() ?? 0.0;
    final confPct = (confidence * 100).toStringAsFixed(0);
    final highConf = confidence > 0.85;
    final confColor = highConf ? _success : _warning;

    String timeStr = '—';
    final ts = log['timestamp']?.toString() ?? '';
    if (ts.length >= 19) timeStr = ts.substring(11, 19);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _navyLight),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _success.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _success.withOpacity(0.3)),
            ),
            child: Center(
              child: Text(initial,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _success,
                      fontSize: 16)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: _textPrimary),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.access_time_rounded,
                        size: 11, color: _textSub),
                    const SizedBox(width: 4),
                    Text(timeStr,
                        style: const TextStyle(color: _textSub, fontSize: 11)),
                    if (className.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.class_outlined,
                          size: 11, color: _textSub),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(className,
                            style: const TextStyle(
                                color: _textSub, fontSize: 11),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _success.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _success.withOpacity(0.3)),
                ),
                child: const Text('PRESENT',
                    style: TextStyle(
                        fontSize: 9,
                        color: _success,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6)),
              ),
              const SizedBox(height: 5),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    highConf
                        ? Icons.verified_rounded
                        : Icons.info_outline_rounded,
                    size: 11,
                    color: confColor,
                  ),
                  const SizedBox(width: 3),
                  Text('$confPct%',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: confColor)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}