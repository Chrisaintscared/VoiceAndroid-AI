import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import '../services/class_service.dart';
import 'class_detail_screen.dart';
import 'class_requests_screen.dart';

class TeacherDashboard extends StatefulWidget {
  const TeacherDashboard({super.key});

  @override
  State<TeacherDashboard> createState() => _TeacherDashboardState();
}

class _TeacherDashboardState extends State<TeacherDashboard> {
  List<Map<String, dynamic>> _classes = [];
  bool _isLoading = true;
  String _teacherName = '';
  String _teacherEmail = '';
  int _pendingCount = 0;
  int _totalStudents = 0;
  final _classNameCtrl = TextEditingController();

  static const _navy = Color(0xFF0D1B2A);
  static const _navyMid = Color(0xFF1A2E45);
  static const _navyLight = Color(0xFF243B55);
  static const _surface = Color(0xFF152032);
  static const _surfaceHigh = Color(0xFF1E3048);
  static const _cyan = Color(0xFF00D4FF);
  static const _cyanDim = Color(0xFF0099BB);
  static const _success = Color(0xFF00E5A0);
  static const _purple = Color(0xFFB16CEA);
  static const _danger = Color(0xFFFF5B7F);
  static const _textPrimary = Color(0xFFF0F6FF);
  static const _textSub = Color(0xFF7EA8C4);
  static const _textMuted = Color(0xFF4A7090);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _classNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final user = await AuthService.getStoredUser();
      _teacherName = user?['name'] ?? 'Teacher';
      _teacherEmail = user?['email'] ?? '';

      final results = await Future.wait([
        ClassService.getMyClasses(),
        ClassService.getAllPendingRequests(),
      ]);

      final classes = List<Map<String, dynamic>>.from(results[0]);

      // Fetch member counts for each class in parallel
      final memberCounts = await Future.wait(
        classes.map((cls) => ClassService.getMembers(cls['id']).then(
              (members) => members.length,
            ).catchError((_) => 0)),
      );

      for (int i = 0; i < classes.length; i++) {
        classes[i] = {...classes[i], 'member_count': memberCounts[i]};
      }

      if (mounted) {
        setState(() {
          _classes = classes;
          _pendingCount = (results[1] as List).length;
          _totalStudents = memberCounts.fold(0, (a, b) => a + b);
        });
      }
    } catch (e) {
      _showSnack('Failed to load: $e', error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
                  style: TextStyle(color: _textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text("You'll need to sign in again\nto access your classes.",
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
                            child: Text('Cancel', style: TextStyle(color: _textSub, fontSize: 14))),
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
                                  color: _danger, fontWeight: FontWeight.w600, fontSize: 14)),
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

  void _showCreateDialog() {
    _classNameCtrl.clear();
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _purple.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _purple.withOpacity(0.3)),
                    ),
                    child: const Icon(Icons.add_rounded, color: _purple, size: 18),
                  ),
                  const SizedBox(width: 12),
                  const Text('Create Class',
                      style: TextStyle(
                          color: _textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _classNameCtrl,
                style: const TextStyle(color: _textPrimary),
                decoration: InputDecoration(
                  hintText: 'e.g. Math 101',
                  hintStyle: const TextStyle(color: _textMuted),
                  filled: true,
                  fillColor: _navyMid,
                  prefixIcon: const Icon(Icons.class_outlined, color: _textMuted, size: 18),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _navyLight)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _navyLight)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _purple)),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _navyMid,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _navyLight),
                        ),
                        child: const Center(
                            child: Text('Cancel', style: TextStyle(color: _textSub, fontSize: 14))),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        final name = _classNameCtrl.text.trim();
                        if (name.isEmpty) return;
                        Navigator.pop(ctx);
                        await _createClass(name);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [_purple, Color(0xFF8A4FD0)]),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: Text('Create',
                              style: TextStyle(
                                  color: Colors.white,
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

  Future<void> _createClass(String name) async {
    try {
      final cls = await ClassService.createClass(name);
      _showCodeDialog(cls['name'], cls['code']);
      await _loadData();
    } catch (e) {
      _showSnack(e.toString(), error: true);
    }
  }

  void _showCodeDialog(String name, String code) {
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
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _success.withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: _success.withOpacity(0.3)),
                ),
                child: const Icon(Icons.check_rounded, color: _success, size: 24),
              ),
              const SizedBox(height: 16),
              const Text('Class Created!',
                  style: TextStyle(
                      color: _textPrimary, fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(name,
                  style: const TextStyle(color: _textSub, fontSize: 13),
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 20),
              const Text('Share this code with your students',
                  style: TextStyle(color: _textMuted, fontSize: 12)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
                decoration: BoxDecoration(
                  color: _cyan.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _cyan.withOpacity(0.3)),
                ),
                child: Text(code,
                    style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                        color: _cyan,
                        letterSpacing: 8)),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: code));
                  _showSnack('Code copied!');
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: _cyan.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _cyan.withOpacity(0.3)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.copy_rounded, color: _cyan, size: 15),
                      SizedBox(width: 6),
                      Text('Copy Code', style: TextStyle(color: _cyan, fontSize: 13)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: _navyMid,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _navyLight),
                  ),
                  child: const Center(
                      child: Text('Done', style: TextStyle(color: _textSub, fontSize: 14))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Row(
          children: [
            Icon(error ? Icons.error_outline : Icons.check_circle_outline,
                color: Colors.white, size: 16),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      body: _isLoading ? _buildLoader() : _buildBody(),
    );
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

  Widget _buildBody() {
    return SafeArea(
      child: Column(
        children: [
          _buildTopBar(),
          Expanded(
            child: RefreshIndicator(
              color: _cyan,
              backgroundColor: _surfaceHigh,
              onRefresh: _loadData,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _buildProfileCard()),
                  SliverToBoxAdapter(child: _buildStatsRow()),
                  SliverToBoxAdapter(child: _buildSectionHeader()),
                  if (_classes.isEmpty)
                    const SliverFillRemaining(
                        hasScrollBody: false, child: _EmptyState())
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) => _ClassCard(
                            cls: _classes[i],
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ClassDetailScreen(
                                  classId: _classes[i]['id'],
                                  className: _classes[i]['name'],
                                  isTeacher: true,
                                  classCode: _classes[i]['code'],
                                ),
                              ),
                            ).then((_) => _loadData()),
                            onShowCode: () => _showCodeDialog(
                                _classes[i]['name'], _classes[i]['code']),
                          ),
                          childCount: _classes.length,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [_navyMid, _navyLight],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 4))
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: _purple.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _purple.withOpacity(0.3)),
            ),
            child: const Icon(Icons.school_rounded, color: _purple, size: 17),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('My Classes',
                style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          GestureDetector(
            onTap: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => ClassRequestsScreen()));
              _loadData();
            },
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _pendingCount > 0 ? _danger.withOpacity(0.12) : _navyLight.withOpacity(0.6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: _pendingCount > 0 ? _danger.withOpacity(0.4) : _navyLight),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(Icons.people_alt_rounded,
                      color: _pendingCount > 0 ? _danger : _textSub, size: 16),
                  if (_pendingCount > 0)
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: const BoxDecoration(color: _danger, shape: BoxShape.circle),
                        child: Center(
                          child: Text(
                            _pendingCount > 9 ? '9+' : '$_pendingCount',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          _TopBarAction(
              icon: Icons.logout_rounded, color: _danger, tooltip: 'Logout', onTap: _confirmLogout),
        ],
      ),
    );
  }

  Widget _buildProfileCard() {
    final initial = _teacherName.isNotEmpty ? _teacherName[0].toUpperCase() : 'T';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _purple.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(color: _purple.withOpacity(0.06), blurRadius: 20, offset: const Offset(0, 4))
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: [_purple.withOpacity(0.4), _purple.withOpacity(0.15)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: _purple.withOpacity(0.4)),
            ),
            child: Center(
              child: Text(initial,
                  style: const TextStyle(
                      color: _purple, fontSize: 22, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_teacherName,
                    style: const TextStyle(
                        color: _textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(_teacherEmail,
                    style: const TextStyle(color: _textSub, fontSize: 12),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _purple.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _purple.withOpacity(0.3)),
                  ),
                  child: const Text('TEACHER',
                      style: TextStyle(
                          fontSize: 9,
                          color: _purple,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Stats row — responsive, no overflow ───────────────────────────────
  Widget _buildStatsRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = (constraints.maxWidth - 24) / 3;
          return Row(
            children: [
              SizedBox(
                width: w,
                child: _StatTile(
                  label: 'Classes',
                  value: '${_classes.length}',
                  icon: Icons.class_outlined,
                  color: _cyan,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: w,
                child: _StatTile(
                  label: 'Students',
                  value: '$_totalStudents',
                  icon: Icons.people_alt_rounded,
                  color: _success,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: w,
                child: GestureDetector(
                  onTap: () async {
                    await Navigator.push(context,
                        MaterialPageRoute(builder: (_) => ClassRequestsScreen()));
                    _loadData();
                  },
                  child: _StatTile(
                    label: 'Pending',
                    value: '$_pendingCount',
                    icon: Icons.pending_actions_rounded,
                    color: _pendingCount > 0 ? _danger : _textMuted,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      child: Row(
        children: [
          const Text('MY CLASSES',
              style: TextStyle(
                  color: _cyan, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 1, color: _navyLight)),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _showCreateDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_purple, Color(0xFF8A4FD0)]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, color: Colors.white, size: 14),
                  SizedBox(width: 4),
                  Text('New Class',
                      style: TextStyle(
                          color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Top Bar Action ────────────────────────────────────────────────────────────

class _TopBarAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _TopBarAction(
      {required this.icon, required this.color, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(left: 6),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
      ),
    );
  }
}

// ── Stat Tile ─────────────────────────────────────────────────────────────────

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  static const _surface = Color(0xFF152032);
  static const _textMuted = Color(0xFF4A7090);

  const _StatTile(
      {required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(0.25)),
            ),
            child: Icon(icon, color: color, size: 14),
          ),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w800)),
          Text(label,
              style: const TextStyle(color: _textMuted, fontSize: 10),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

// ── Class Card ────────────────────────────────────────────────────────────────

class _ClassCard extends StatelessWidget {
  final Map<String, dynamic> cls;
  final VoidCallback onTap;
  final VoidCallback? onShowCode;

  static const _surface = Color(0xFF152032);
  static const _navyLight = Color(0xFF243B55);
  static const _cyan = Color(0xFF00D4FF);
  static const _purple = Color(0xFFB16CEA);
  static const _textPrimary = Color(0xFFF0F6FF);
  static const _textSub = Color(0xFF7EA8C4);
  static const _textMuted = Color(0xFF4A7090);

  const _ClassCard({required this.cls, required this.onTap, this.onShowCode});

  @override
  Widget build(BuildContext context) {
    final name = cls['name'] as String? ?? '—';
    final code = cls['code'] as String? ?? '—';
    final count = cls['member_count'] as int? ?? 0;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _navyLight),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [_purple.withOpacity(0.3), _purple.withOpacity(0.1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: _purple.withOpacity(0.4)),
              ),
              child: Center(
                child: Text(initial,
                    style: const TextStyle(
                        color: _purple, fontSize: 19, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          color: _textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.vpn_key_rounded, size: 10, color: _textMuted),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(code,
                            style: const TextStyle(
                                color: _cyan,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1),
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 10),
                      const Icon(Icons.people_alt_rounded, size: 10, color: _textMuted),
                      const SizedBox(width: 3),
                      Text('$count',
                          style: const TextStyle(color: _textSub, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
            if (onShowCode != null)
              GestureDetector(
                onTap: onShowCode,
                child: Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: _cyan.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: _cyan.withOpacity(0.25)),
                  ),
                  child: const Icon(Icons.share_rounded, color: _cyan, size: 14),
                ),
              ),
            const Icon(Icons.chevron_right_rounded, color: _textMuted, size: 18),
          ],
        ),
      ),
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  static const _textMuted = Color(0xFF4A7090);
  static const _purple = Color(0xFFB16CEA);

  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _purple.withOpacity(0.08),
              shape: BoxShape.circle,
              border: Border.all(color: _purple.withOpacity(0.2)),
            ),
            child: const Icon(Icons.class_outlined, size: 40, color: _textMuted),
          ),
          const SizedBox(height: 16),
          const Text('No classes yet',
              style: TextStyle(color: _textMuted, fontSize: 15, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          const Text("Tap 'New Class' to get started",
              style: TextStyle(color: _textMuted, fontSize: 12)),
        ],
      ),
    );
  }
}