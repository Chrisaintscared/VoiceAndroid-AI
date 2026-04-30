// TODO Implement this library.
import 'package:flutter/material.dart';
import '../services/class_service.dart';

class ClassRequestsScreen extends StatefulWidget {
  const ClassRequestsScreen({super.key});

  @override
  State<ClassRequestsScreen> createState() => _ClassRequestsScreenState();
}

class _ClassRequestsScreenState extends State<ClassRequestsScreen> {
  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = true;
  String? _error;

  static const _navy = Color(0xFF0D1B2A);
  static const _navyMid = Color(0xFF1A2E45);
  static const _navyLight = Color(0xFF243B55);
  static const _surface = Color(0xFF152032);
  static const _cyan = Color(0xFF00D4FF);
  static const _green = Color(0xFF00E5A0);
  static const _danger = Color(0xFFFF5B7F);
  static const _textPrimary = Color(0xFFF0F6FF);
  static const _textSub = Color(0xFF7EA8C4);

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final requests = await ClassService.getAllPendingRequests();
      if (mounted) setState(() => _requests = requests);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _approve(int classId, int studentId) async {
    try {
      await ClassService.approveRequest(classId, studentId);
      _showSnack('Student approved ✓', _green);
      await _loadRequests();
    } catch (e) {
      _showSnack(e.toString(), _danger);
    }
  }

  Future<void> _decline(int classId, int studentId) async {
    try {
      await ClassService.declineRequest(classId, studentId);
      _showSnack('Request declined', _textSub);
      await _loadRequests();
    } catch (e) {
      _showSnack(e.toString(), _danger);
    }
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
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
          const Text(
            'Join Requests',
            style: TextStyle(
                color: _textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _loadRequests,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _navyLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.refresh_rounded, color: _cyan, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: _cyan, strokeWidth: 2));
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: _danger, size: 40),
            const SizedBox(height: 12),
            Text(_error!,
                style: const TextStyle(color: _textSub),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            _ActionButton(label: 'Retry', color: _cyan, onTap: _loadRequests),
          ],
        ),
      );
    }

    if (_requests.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _navyMid,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.inbox_rounded, color: _textSub, size: 36),
            ),
            const SizedBox(height: 16),
            const Text('No pending requests',
                style: TextStyle(
                    color: _textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text('Students who request to join\nwill appear here.',
                style: TextStyle(color: _textSub, fontSize: 13),
                textAlign: TextAlign.center),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRequests,
      color: _cyan,
      backgroundColor: _navyMid,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _requests.length,
        itemBuilder: (context, i) => _buildRequestCard(_requests[i]),
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> req) {
    final classId = req['class_id'] as int;
    final studentId = req['student_id'] as int;
    final studentName = req['student_name'] ?? 'Unknown';
    final studentEmail = req['student_email'] ?? '';
    final className = req['class_name'] ?? 'Unknown Class';
    final initial = studentName.isNotEmpty ? studentName[0].toUpperCase() : '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _navyLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Class label
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: _cyan.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _cyan.withOpacity(0.3)),
            ),
            child: Text(className,
                style: const TextStyle(
                    color: _cyan, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 12),

          // Student info
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _navyMid,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _navyLight),
                ),
                child: Center(
                  child: Text(initial,
                      style: const TextStyle(
                          color: _cyan,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(studentName,
                        style: const TextStyle(
                            color: _textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 15)),
                    Text(studentEmail,
                        style: const TextStyle(color: _textSub, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  label: 'Decline',
                  color: _danger,
                  outlined: true,
                  onTap: () => _decline(classId, studentId),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionButton(
                  label: 'Approve',
                  color: _green,
                  onTap: () => _approve(classId, studentId),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool outlined;

  const _ActionButton({
    required this.label,
    required this.color,
    required this.onTap,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: outlined ? Colors.transparent : color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color:
                  outlined ? color.withOpacity(0.5) : color.withOpacity(0.4)),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ),
      ),
    );
  }
}