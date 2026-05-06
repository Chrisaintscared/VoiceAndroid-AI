import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/class_service.dart';
import 'class_detail_screen.dart';
import 'profile_screen.dart';

class StudentDashboard extends StatefulWidget {
  const StudentDashboard({super.key});

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _pendingRequests = [];
  bool _isLoading = true;
  String _userName = '';
  String _userEmail = '';
  final _codeCtrl = TextEditingController();
  int _selectedIndex = 0;

  // ── Design tokens ──────────────────────────────────────────────────────
  static const _navy = Color(0xFF0D1B2A);
  static const _navyMid = Color(0xFF1A2E45);
  static const _navyLight = Color(0xFF243B55);
  static const _surface = Color(0xFF152032);
  static const _surfaceHigh = Color(0xFF1E3048);
  static const _cyan = Color(0xFF00D4FF);
  static const _cyanDim = Color(0xFF0099BB);
  static const _success = Color(0xFF00E5A0);
  static const _danger = Color(0xFFFF5B7F);
  static const _warning = Color(0xFFFFB347);
  static const _textPrimary = Color(0xFFF0F6FF);
  static const _textSub = Color(0xFF7EA8C4);
  static const _textMuted = Color(0xFF4A7090);

  // ── Lifecycle ──────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  // ── Data ───────────────────────────────────────────────────────────────
  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final user = await AuthService.getStoredUser();
      _userName = user?['name'] ?? 'Student';
      _userEmail = user?['email'] ?? '';
      final classes = await ClassService.getMyClasses();
      final pending = await ClassService.getMyPendingRequests();
      if (mounted) {
        setState(() {
          _classes = (classes as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _pendingRequests = (pending as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        });
      }
    } catch (e) {
      _showSnack('Failed to load: $e', error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Join class ─────────────────────────────────────────────────────────
  void _showJoinDialog() {
    _codeCtrl.clear();
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
                      color: _cyan.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _cyan.withOpacity(0.3)),
                    ),
                    child: const Icon(Icons.vpn_key_rounded,
                        color: _cyan, size: 18),
                  ),
                  const SizedBox(width: 12),
                  const Text('Join a Class',
                      style: TextStyle(
                          color: _textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _codeCtrl,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(
                  color: _textPrimary,
                  letterSpacing: 4,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
                decoration: InputDecoration(
                  hintText: 'AB12CD',
                  hintStyle: const TextStyle(
                      color: _textMuted, letterSpacing: 2, fontSize: 16),
                  filled: true,
                  fillColor: _navyMid,
                  prefixIcon: const Icon(Icons.tag_rounded,
                      color: _textMuted, size: 18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _navyLight),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _navyLight),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _cyan),
                  ),
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
                          child: Text('Cancel',
                              style: TextStyle(color: _textSub, fontSize: 14)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        final code = _codeCtrl.text.trim();
                        if (code.isEmpty) return;
                        Navigator.pop(ctx);
                        await _joinClass(code);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_cyan, _cyanDim],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: Text('Join',
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

  Future<void> _joinClass(String code) async {
    try {
      final result = await ClassService.joinClass(code);
      _showSnack(result);
      await _loadData();
    } catch (e) {
      _showSnack(e.toString(), error: true);
    }
  }

  // ── Pending requests bottom sheet ──────────────────────────────────────
  void _showPendingSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (_, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            // drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: _navyLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: _warning.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _warning.withOpacity(0.3)),
                  ),
                  child: const Icon(Icons.hourglass_top_rounded,
                      color: _warning, size: 16),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Pending Requests',
                  style: TextStyle(
                      color: _textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _warning.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _warning.withOpacity(0.3)),
                  ),
                  child: Text(
                    '${_pendingRequests.length}',
                    style: const TextStyle(
                        color: _warning,
                        fontSize: 12,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Waiting for teacher approval',
              style: TextStyle(color: _textMuted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            ..._pendingRequests.map((req) {
              final className = req['class_name'] ?? 'Unknown Class';
              final teacherName = req['teacher_name'] ?? '';
              final initial =
                  className.isNotEmpty ? className[0].toUpperCase() : '?';
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _navyMid,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _warning.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _warning.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _warning.withOpacity(0.3)),
                      ),
                      child: Center(
                        child: Text(initial,
                            style: const TextStyle(
                                color: _warning,
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(className,
                              style: const TextStyle(
                                  color: _textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14)),
                          if (teacherName.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                const Icon(Icons.person_rounded,
                                    size: 11, color: _textMuted),
                                const SizedBox(width: 4),
                                Text(teacherName,
                                    style: const TextStyle(
                                        color: _textSub, fontSize: 12)),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _warning.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _warning.withOpacity(0.3)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.hourglass_top_rounded,
                              size: 10, color: _warning),
                          SizedBox(width: 4),
                          Text('Pending',
                              style: TextStyle(
                                  color: _warning,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  // ── Snack ──────────────────────────────────────────────────────────────
  void _showSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Row(
          children: [
            Icon(
              error ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
              size: 16,
            ),
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

  // ── Build ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildClassesTab(),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
      floatingActionButton: _selectedIndex == 0 ? _buildJoinFab() : null,
    );
  }

  // ── Bottom nav ─────────────────────────────────────────────────────────
  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: _navyMid,
        border: Border(top: BorderSide(color: _navyLight, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              _NavItem(
                icon: Icons.class_outlined,
                activeIcon: Icons.class_rounded,
                label: 'Classes',
                isActive: _selectedIndex == 0,
                onTap: () => setState(() => _selectedIndex = 0),
              ),
              _NavItem(
                icon: Icons.person_outline_rounded,
                activeIcon: Icons.person_rounded,
                label: 'Profile',
                isActive: _selectedIndex == 1,
                onTap: () => setState(() => _selectedIndex = 1),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── FAB ────────────────────────────────────────────────────────────────
  Widget _buildJoinFab() {
    return GestureDetector(
      onTap: _showJoinDialog,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_cyan, _cyanDim],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: _cyan.withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Join Class',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14)),
          ],
        ),
      ),
    );
  }

  // ── Classes tab ────────────────────────────────────────────────────────
  Widget _buildClassesTab() {
    return SafeArea(
      child: Column(
        children: [
          _buildTopBar(),
          Expanded(
            child: _isLoading
                ? _buildLoader()
                : RefreshIndicator(
                    color: _cyan,
                    backgroundColor: _surfaceHigh,
                    onRefresh: _loadData,
                    child: CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(child: _buildProfileCard()),
                        if (_pendingRequests.isNotEmpty)
                          SliverToBoxAdapter(child: _buildPendingBanner()),
                        SliverToBoxAdapter(child: _buildSectionHeader()),
                        if (_classes.isEmpty)
                          const SliverFillRemaining(
                            hasScrollBody: false,
                            child: _EmptyState(),
                          )
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
                                        isTeacher: false,
                                      ),
                                    ),
                                  ).then((_) => _loadData()),
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

  // ── Pending banner ─────────────────────────────────────────────────────
  Widget _buildPendingBanner() {
    return GestureDetector(
      onTap: _showPendingSheet,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _warning.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _warning.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _warning.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.hourglass_top_rounded,
                  color: _warning, size: 15),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_pendingRequests.length} pending join ${_pendingRequests.length == 1 ? 'request' : 'requests'}',
                    style: const TextStyle(
                        color: _warning,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 1),
                  const Text(
                    'Waiting for teacher approval',
                    style: TextStyle(color: _textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: _warning, size: 18),
          ],
        ),
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_navyMid, _navyLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: _cyan.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _cyan.withOpacity(0.3)),
            ),
            child: const Icon(Icons.person_rounded, color: _cyan, size: 17),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('My Classes',
                style: TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
          ),
        ],
      ),
    );
  }

  // ── Profile card ───────────────────────────────────────────────────────
  Widget _buildProfileCard() {
    final initial = _userName.isNotEmpty ? _userName[0].toUpperCase() : 'S';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _cyan.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: _cyan.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_cyan.withOpacity(0.4), _cyan.withOpacity(0.15)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: _cyan.withOpacity(0.4)),
            ),
            child: Center(
              child: Text(initial,
                  style: const TextStyle(
                      color: _cyan, fontSize: 22, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_userName,
                    style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(_userEmail,
                    style: const TextStyle(color: _textSub, fontSize: 12),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _cyan.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _cyan.withOpacity(0.3)),
                  ),
                  child: const Text('STUDENT',
                      style: TextStyle(
                          fontSize: 9,
                          color: _cyan,
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

  // ── Section header ─────────────────────────────────────────────────────
  Widget _buildSectionHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      child: Row(
        children: [
          const Text('MY CLASSES',
              style: TextStyle(
                  color: _cyan,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4)),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 1, color: _navyLight)),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _success.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _success.withOpacity(0.3)),
            ),
            child: Text(
              '${_classes.length} enrolled',
              style: const TextStyle(
                  color: _success, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ── Loader ─────────────────────────────────────────────────────────────
  Widget _buildLoader() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(color: _cyan, strokeWidth: 2.5),
          ),
          SizedBox(height: 12),
          Text('Loading…', style: TextStyle(color: _textMuted, fontSize: 13)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Nav Item
// ─────────────────────────────────────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  static const _cyan = Color(0xFF00D4FF);
  static const _textMuted = Color(0xFF4A7090);

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? _cyan.withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive ? _cyan.withOpacity(0.25) : Colors.transparent,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isActive ? activeIcon : icon,
                color: isActive ? _cyan : _textMuted,
                size: 22,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? _cyan : _textMuted,
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Class Card
// ─────────────────────────────────────────────────────────────────────────────

class _ClassCard extends StatelessWidget {
  final Map<String, dynamic> cls;
  final VoidCallback onTap;

  static const _surface = Color(0xFF152032);
  static const _navyLight = Color(0xFF243B55);
  static const _cyan = Color(0xFF00D4FF);
  static const _textPrimary = Color(0xFFF0F6FF);
  static const _textSub = Color(0xFF7EA8C4);
  static const _textMuted = Color(0xFF4A7090);

  const _ClassCard({required this.cls, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = cls['name'] as String? ?? '—';
    final teacherName = cls['teacher_name'] as String? ?? '';
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
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _cyan.withOpacity(0.3),
                    _cyan.withOpacity(0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _cyan.withOpacity(0.4)),
              ),
              child: Center(
                child: Text(initial,
                    style: const TextStyle(
                        color: _cyan,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          color: _textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14),
                      overflow: TextOverflow.ellipsis),
                  if (teacherName.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.person_rounded,
                            size: 11, color: _textMuted),
                        const SizedBox(width: 4),
                        Text(teacherName,
                            style:
                                const TextStyle(color: _textSub, fontSize: 12),
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: _textMuted, size: 20),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Empty State
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  static const _textMuted = Color(0xFF4A7090);
  static const _cyan = Color(0xFF00D4FF);

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
              color: _cyan.withOpacity(0.08),
              shape: BoxShape.circle,
              border: Border.all(color: _cyan.withOpacity(0.2)),
            ),
            child:
                const Icon(Icons.school_outlined, size: 40, color: _textMuted),
          ),
          const SizedBox(height: 16),
          const Text('No classes yet',
              style: TextStyle(
                  color: _textMuted,
                  fontSize: 15,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          const Text("Tap 'Join Class' to get started",
              style: TextStyle(color: _textMuted, fontSize: 12)),
        ],
      ),
    );
  }
}
