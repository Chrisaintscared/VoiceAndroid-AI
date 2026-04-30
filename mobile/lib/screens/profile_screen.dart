import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _user;
  bool _isLoading = true;

  // ── Design tokens (Synced with TeacherDashboard styles) ────────────────────
  static const _navy = Color(0xFF0D1B2A);
  static const _navyMid = Color(0xFF1A2E45);
  static const _navyLight = Color(0xFF243B55);
  static const _surface = Color(0xFF152032);
  static const _cyan = Color(0xFF00D4FF);
  static const _danger = Color(0xFFFF5B7F);
  static const _textPrimary = Color(0xFFF0F6FF);
  static const _textSub = Color(0xFF7EA8C4);

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    try {
      final user = await AuthService.getStoredUser();
      if (mounted) setState(() => _user = user);
    } catch (e) {
      debugPrint("Profile load error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Logout Confirmation (Copied from Teacher Dashboard) ────────────────────
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
                child:
                    const Icon(Icons.logout_rounded, color: _danger, size: 22),
              ),
              const SizedBox(height: 16),
              const Text('Log out?',
                  style: TextStyle(
                      color: _textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text(
                  "You'll need to sign in again\nto access your account.",
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
                              style: TextStyle(color: _textSub, fontSize: 14)),
                        ),
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

  @override
  Widget build(BuildContext context) {
    final name = _user?['name'] ?? 'User';
    final email = _user?['email'] ?? '';
    final role = _user?['role'] ?? 'Student';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';

    return Scaffold(
      backgroundColor: _navy,
      body: SafeArea(
        child: _isLoading
            ? _buildLoader()
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildTopHeader(),
                    const SizedBox(height: 24),

                    // ── Avatar & Info ────────────────────────────────────────
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _cyan.withOpacity(0.4),
                            _cyan.withOpacity(0.1)
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: _cyan.withOpacity(0.4)),
                      ),
                      child: Center(
                        child: Text(initial,
                            style: const TextStyle(
                                color: _cyan,
                                fontSize: 40,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(name,
                        style: const TextStyle(
                            color: _textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.bold)),
                    Text(email,
                        style: const TextStyle(color: _textSub, fontSize: 14)),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: _cyan.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _cyan.withOpacity(0.3)),
                      ),
                      child: Text(role.toUpperCase(),
                          style: const TextStyle(
                              color: _cyan,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1)),
                    ),
                    const SizedBox(height: 32),

                    // ── Menu Options ─────────────────────────────────────────
                    _MenuOption(
                      icon: Icons.mic_external_on_rounded,
                      title: 'Voice Enrollment',
                      onTap: () => Navigator.pushNamed(context, '/enroll'),
                    ),
                    _MenuOption(
                      icon: Icons.lock_outline_rounded,
                      title: 'Change Password',
                      onTap: () {},
                    ),
                    _MenuOption(
                      icon: Icons.logout_rounded,
                      title: 'Logout',
                      isDanger: true,
                      onTap:
                          _confirmLogout, // Updated to use confirmation dialog
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildTopHeader() {
    return Row(
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _navyLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.arrow_back_rounded,
                color: _textPrimary, size: 20),
          ),
        ),
        const SizedBox(width: 16),
        const Text("Profile",
            style: TextStyle(
                color: _textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildLoader() {
    return const Center(
        child: CircularProgressIndicator(color: _cyan, strokeWidth: 2));
  }
}

// ── Custom Menu Item ─────────────────────────────────────────────────────────
class _MenuOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool isDanger;

  const _MenuOption({
    required this.icon,
    required this.title,
    required this.onTap,
    this.isDanger = false,
  });

  @override
  Widget build(BuildContext context) {
    const _surface = Color(0xFF152032);
    const _navyLight = Color(0xFF243B55);
    const _textPrimary = Color(0xFFF0F6FF);
    const _danger = Color(0xFFFF5B7F);
    const _cyan = Color(0xFF00D4FF);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _navyLight),
        ),
        child: Row(
          children: [
            Icon(icon, color: isDanger ? _danger : _cyan, size: 20),
            const SizedBox(width: 16),
            Text(title,
                style: TextStyle(
                    color: isDanger ? _danger : _textPrimary,
                    fontWeight: FontWeight.w500)),
            const Spacer(),
            Icon(Icons.chevron_right_rounded,
                color: isDanger
                    ? _danger.withOpacity(0.5)
                    : const Color(0xFF4A7090),
                size: 20),
          ],
        ),
      ),
    );
  }
}
