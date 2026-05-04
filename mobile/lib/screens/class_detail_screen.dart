import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:VoiceAndroid/services/attendance_service.dart';
import '../services/class_service.dart';
import '../services/ml_service.dart';
import '../services/server_warmup_service.dart'; // ← new
import 'attendance_report_screen.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';

class ClassDetailScreen extends StatefulWidget {
  final int classId;
  final String className;
  final bool isTeacher;
  final String? classCode;

  const ClassDetailScreen({
    super.key,
    required this.classId,
    required this.className,
    required this.isTeacher,
    this.classCode,
  });

  @override
  State<ClassDetailScreen> createState() => _ClassDetailScreenState();
}

class _ClassDetailScreenState extends State<ClassDetailScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;

  List<Map<String, dynamic>> _attendance = [];
  List<Map<String, dynamic>> _members = [];

  bool _isLoading = true;
  bool _isCheckingIn = false;
  bool _isProcessing = false;
  double _confidence = 0.0;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;
  late AnimationController _rippleController;
  late Animation<double> _rippleAnim;

  final AudioRecorder _audioRecorder = AudioRecorder();
  String? _recordedPath;

  // ── Design tokens ──────────────────────────────────────────────────────
  static const _navy = Color(0xFF0D1B2A);
  static const _navyMid = Color(0xFF1A2E45);
  static const _navyLight = Color(0xFF243B55);
  static const _cyan = Color(0xFF00D4FF);
  static const _cyanDim = Color(0xFF0099BB);
  static const _danger = Color(0xFFFF5B7F);
  static const _purple = Color(0xFFB16CEA);
  static const _textPrimary = Color(0xFFF0F6FF);
  static const _textSub = Color(0xFF7EA8C4);
  static const _textMuted = Color(0xFF4A7090);

  // ── Lifecycle ──────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tabController =
        TabController(length: widget.isTeacher ? 2 : 1, vsync: this);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _rippleAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _rippleController, curve: Curves.easeOut),
    );

    _loadData();
    // Wake the Render server in the background so it is ready
    // before the student finishes their 3-second recording.
    if (!widget.isTeacher) ServerWarmupService.ping();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pulseController.dispose();
    _rippleController.dispose();
    super.dispose();
  }

  // ── Data ───────────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final attendance = await ClassService.getClassAttendance(widget.classId);
      List<Map<String, dynamic>> members = [];
      if (widget.isTeacher) {
        members = await ClassService.getMembers(widget.classId);
      }
      if (mounted) {
        setState(() {
          _attendance = attendance;
          _members = members;
        });
      }
    } catch (e) {
      _showSnack('Failed to load: $e', error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Check-in ───────────────────────────────────────────────────────────

  bool _alreadyCheckedInToday() {
    final now = DateTime.now();
    return _attendance.any((a) {
      try {
        final dt = DateTime.parse(a['timestamp'].toString()).toLocal();
        return dt.year == now.year &&
            dt.month == now.month &&
            dt.day == now.day;
      } catch (_) {
        return false;
      }
    });
  }

  Future<void> _startCheckIn() async {
    if (_alreadyCheckedInToday()) {
      _showSnack('Already checked in today', error: true);
      return;
    }

    if (!mounted) return;

    final permission = await Permission.microphone.request();
    if (!permission.isGranted) {
      _showSnack('Microphone permission required', error: true);
      return;
    }

    try {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/checkin_${DateTime.now().millisecondsSinceEpoch}.wav';

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
        ),
        path: path,
      );

      setState(() {
        _isCheckingIn = true;
        _isProcessing = false;
        _confidence = 0.0;
      });

      _showSnack('Recording… tap again to stop');
    } catch (e) {
      _showSnack('Failed to start recording', error: true);
    }
  }

  Future<void> _stopCheckIn() async {
    if (!mounted) return;

    setState(() {
      _isCheckingIn = false;
      _isProcessing = true;
    });

    try {
      final path = await _audioRecorder.stop();
      if (path == null) throw Exception('Recording failed');

      final file = File(path);

      // ── Silence / minimum-duration guard ────────────────────────────────
      // A valid 3-second 16 kHz mono 16-bit WAV is ~96 KB.
      // Anything under 40 KB is silence or a mic failure – reject early so
      // we don't waste a network round-trip.
      if (!file.existsSync() || file.lengthSync() < 40000) {
        setState(() => _isProcessing = false);
        _showSnack('No voice detected. Please speak louder!', error: true);
        return;
      }

      // ── Phase-A: attempt on-device embedding ────────────────────────────
      // Returns null when the TFLite model asset is not loaded (Phase 1).
      // Swap to Phase 2 by placing voice_model.tflite in assets/ and
      // uncommenting tflite_flutter in pubspec.yaml + ml_service.dart.
      final embedding = await MLService.instance.generateEmbedding(file);

      // ── Phase-B: send to backend (with one cold-start retry) ────────────
      Map<String, dynamic> result;

      try {
        result = await _callBackend(file, embedding);
      } on TimeoutException {
        // Render free-tier cold-start can take 30–50 s on first request.
        // Show a friendly message, wait 4 s, then retry once.
        _showSnack('Server waking up… retrying');
        await Future.delayed(const Duration(seconds: 4));
        result = await _callBackend(file, embedding);
      }

      final score =
          ((result['confidence'] as num?)?.toDouble() ?? 0.0) / 100.0;

      await _loadData();

      if (!mounted) return;

      setState(() {
        _confidence = score;
        _isProcessing = false;
      });

      _showSnack('Verified! Confidence: ${(score * 100).toInt()}%');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _confidence = 0.0;
      });
      _showSnack(e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  // ── Backend routing ────────────────────────────────────────────────────

  /// Phase 1: embedding == null  →  upload WAV (existing behaviour, unchanged)
  /// Phase 2: embedding != null  →  POST float vector only (lightweight)
  Future<Map<String, dynamic>> _callBackend(
    File wavFile,
    List<double>? embedding,
  ) async {
    if (embedding != null) {
      // ── PHASE 2 ─────────────────────────────────────────────────────────
      // Implement AttendanceService.embeddingCheckIn() on the Dart side, and
      // add a POST /attendance/checkin_embedding route on the FastAPI side
      // that accepts { class_id, embedding } and does cosine similarity
      // against the stored enrollment vectors.
      //
      // return await AttendanceService.embeddingCheckIn(
      //   embedding,
      //   widget.classId,
      // );
    }

    // ── PHASE 1 (current): upload WAV file ──────────────────────────────
    return await AttendanceService.voiceCheckIn(wavFile, widget.classId);
  }

  // ── Button tap handler ────────────────────────────────────────────────

  void _handleCheckInTap() {
    if (_isProcessing) return;
    if (_isCheckingIn) {
      _stopCheckIn();
    } else {
      _startCheckIn();
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  String _formatTimestamp(String raw) {
    try {
      final dt = DateTime.parse(raw).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')}  '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw;
    }
  }

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

  void _openReport() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AttendanceReportScreen(
          classId: widget.classId,
          className: widget.className,
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      appBar: _buildAppBar(),
      body: _isLoading
          ? _buildLoader()
          : widget.isTeacher
              ? TabBarView(
                  controller: _tabController,
                  children: [
                    _AttendanceTab(
                      attendance: _attendance,
                      formatTimestamp: _formatTimestamp,
                      onRefresh: _loadData,
                    ),
                    _StudentsTab(
                      members: _members,
                      onRefresh: _loadData,
                    ),
                  ],
                )
              : _StudentView(
                  attendance: _attendance,
                  formatTimestamp: _formatTimestamp,
                  isCheckingIn: _isCheckingIn,
                  isProcessing: _isProcessing,
                  alreadyCheckedIn: _alreadyCheckedInToday(),
                  onCheckInTap: _handleCheckInTap,
                  onRefresh: _loadData,
                  pulseAnim: _pulseAnim,
                  rippleAnim: _rippleAnim,
                  confidence: _confidence,
                ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final accentColor = widget.isTeacher ? _purple : _cyan;
    return PreferredSize(
      preferredSize: Size.fromHeight(widget.isTeacher ? 120 : 72),
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
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          size: 18, color: _textSub),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: accentColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: accentColor.withOpacity(0.3), width: 1),
                      ),
                      child: Icon(
                        widget.isTeacher
                            ? Icons.school_rounded
                            : Icons.person_rounded,
                        color: accentColor,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.className,
                            style: const TextStyle(
                                color: _textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                letterSpacing: 0.2),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            widget.isTeacher ? 'Teacher View' : 'Student View',
                            style: const TextStyle(
                                color: _textMuted,
                                fontSize: 11,
                                letterSpacing: 0.5),
                          ),
                        ],
                      ),
                    ),
                    if (widget.isTeacher)
                      _AppBarAction(
                        icon: Icons.bar_chart_rounded,
                        color: accentColor,
                        tooltip: 'Attendance Report',
                        onTap: _openReport,
                      ),
                    if (widget.classCode != null)
                      _AppBarAction(
                        icon: Icons.copy_rounded,
                        color: _cyan,
                        tooltip: 'Copy Code',
                        onTap: () {
                          Clipboard.setData(
                              ClipboardData(text: widget.classCode!));
                          _showSnack('Code copied!');
                        },
                      ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
              if (widget.isTeacher) ...[
                const SizedBox(height: 6),
                TabBar(
                  controller: _tabController,
                  indicatorColor: accentColor,
                  indicatorWeight: 2,
                  indicatorSize: TabBarIndicatorSize.label,
                  labelColor: accentColor,
                  unselectedLabelColor: _textMuted,
                  labelStyle: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 12),
                  tabs: const [
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.event_available_rounded, size: 14),
                          SizedBox(width: 6),
                          Text('Attendance'),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.people_alt_rounded, size: 14),
                          SizedBox(width: 6),
                          Text('Students'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
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
//  The sub-widgets below (_StudentView, _AttendanceTab, _StudentsTab,
//  _AttendanceCard) are unchanged from your original file.  Paste them back
//  here from class_detail_screen.dart lines ~335–1405.
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
//  AppBar Action
// ─────────────────────────────────────────────────────────────────────────────

class _AppBarAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _AppBarAction({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.3), width: 1),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Student View
// ─────────────────────────────────────────────────────────────────────────────

class _StudentView extends StatelessWidget {
  final List<Map<String, dynamic>> attendance;
  final String Function(String) formatTimestamp;
  final bool isCheckingIn;
  final bool isProcessing;
  final bool alreadyCheckedIn;
  final VoidCallback onCheckInTap;
  final Future<void> Function() onRefresh;
  final Animation<double> pulseAnim;
  final Animation<double> rippleAnim;
  final double confidence;

  static const _navyLight = Color(0xFF243B55);
  static const _surface = Color(0xFF152032);
  static const _surfaceHigh = Color(0xFF1E3048);
  static const _cyan = Color(0xFF00D4FF);
  static const _success = Color(0xFF00E5A0);
  static const _danger = Color(0xFFFF5B7F);
  static const _textPrimary = Color(0xFFF0F6FF);
  static const _textSub = Color(0xFF7EA8C4);
  static const _textMuted = Color(0xFF4A7090);

  const _StudentView({
    required this.attendance,
    required this.formatTimestamp,
    required this.isCheckingIn,
    required this.isProcessing,
    required this.alreadyCheckedIn,
    required this.onCheckInTap,
    required this.onRefresh,
    required this.pulseAnim,
    required this.rippleAnim,
    required this.confidence,
  });

  _BtnState get _btnState {
    if (alreadyCheckedIn) return _BtnState.done;
    if (isProcessing) return _BtnState.processing;
    if (isCheckingIn) return _BtnState.recording;
    return _BtnState.idle;
  }

  Color get _btnColor {
    switch (_btnState) {
      case _BtnState.done:
        return _success;
      case _BtnState.processing:
        return const Color(0xFFFFB347);
      case _BtnState.recording:
        return _danger;
      case _BtnState.idle:
        return _cyan;
    }
  }

  Color _confidenceColor(double c) {
    if (c >= 0.75) return _success;
    if (c >= 0.45) return const Color(0xFFFFB347);
    return _danger;
  }

  String _confidenceHint(double c) {
    if (c >= 0.75) return 'Strong match — voice verified successfully.';
    if (c >= 0.45) return 'Moderate match — consider re-enrolling your voice.';
    return 'Low match — environmental noise may have affected accuracy.';
  }

  @override
  Widget build(BuildContext context) {
    final btnColor = _btnColor;
    final state = _btnState;

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: _cyan,
      backgroundColor: _surfaceHigh,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: btnColor.withOpacity(0.25), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: btnColor.withOpacity(0.08),
                    blurRadius: 20,
                    spreadRadius: 2,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      _statusLabel(state),
                      key: ValueKey(state),
                      style: TextStyle(
                        color: btnColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 24),
                  GestureDetector(
                    onTap: (state == _BtnState.done ||
                            state == _BtnState.processing)
                        ? null
                        : onCheckInTap,
                    child: SizedBox(
                      width: 160,
                      height: 160,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (state == _BtnState.recording) ...[
                            _RippleRing(
                              animation: rippleAnim,
                              color: _danger,
                              maxRadius: 78,
                              delay: 0.0,
                            ),
                            _RippleRing(
                              animation: rippleAnim,
                              color: _danger,
                              maxRadius: 72,
                              delay: 0.35,
                            ),
                          ],
                          AnimatedBuilder(
                            animation: pulseAnim,
                            builder: (_, __) => Transform.scale(
                              scale: state == _BtnState.recording
                                  ? pulseAnim.value
                                  : 1.0,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                width: 140,
                                height: 140,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: btnColor.withOpacity(0.3),
                                    width: 2,
                                  ),
                                  gradient: RadialGradient(
                                    colors: [
                                      btnColor.withOpacity(0.0),
                                      btnColor.withOpacity(0.08),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          AnimatedBuilder(
                            animation: pulseAnim,
                            builder: (_, __) => Transform.scale(
                              scale: state == _BtnState.recording
                                  ? pulseAnim.value * 0.97
                                  : 1.0,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                width: 108,
                                height: 108,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: [
                                      btnColor.withOpacity(0.4),
                                      btnColor.withOpacity(0.15),
                                    ],
                                  ),
                                  border: Border.all(
                                    color: btnColor.withOpacity(0.6),
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: btnColor.withOpacity(
                                          state == _BtnState.recording
                                              ? 0.45
                                              : 0.25),
                                      blurRadius: state == _BtnState.recording
                                          ? 28
                                          : 16,
                                      spreadRadius:
                                          state == _BtnState.recording ? 4 : 0,
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: state == _BtnState.processing
                                      ? SizedBox(
                                          width: 32,
                                          height: 32,
                                          child: CircularProgressIndicator(
                                            color: btnColor,
                                            strokeWidth: 2.5,
                                          ),
                                        )
                                      : AnimatedSwitcher(
                                          duration:
                                              const Duration(milliseconds: 300),
                                          child: Icon(
                                            _btnIcon(state),
                                            key: ValueKey(state),
                                            color: btnColor,
                                            size: 42,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Text(
                      _subLabel(state),
                      key: ValueKey('sub-$state'),
                      style: const TextStyle(color: _textMuted, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (confidence > 0) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _surfaceHigh,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color:
                                _confidenceColor(confidence).withOpacity(0.25),
                            width: 1),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.graphic_eq_rounded,
                                      size: 12,
                                      color: _confidenceColor(confidence)),
                                  const SizedBox(width: 5),
                                  const Text('Voice Confidence',
                                      style: TextStyle(
                                          color: _textSub,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500)),
                                ],
                              ),
                              Text(
                                '${(confidence * 100).toStringAsFixed(1)}%',
                                style: TextStyle(
                                    color: _confidenceColor(confidence),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: confidence,
                              minHeight: 5,
                              backgroundColor: _navyLight,
                              valueColor: AlwaysStoppedAnimation(
                                  _confidenceColor(confidence)),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _confidenceHint(confidence),
                            style: TextStyle(
                                color: _textMuted.withOpacity(0.8),
                                fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const Text(
                    'MY ATTENDANCE',
                    style: TextStyle(
                        color: _cyan,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Container(height: 1, color: _navyLight)),
                  const SizedBox(width: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _success.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: _success.withOpacity(0.3), width: 1),
                    ),
                    child: Text(
                      '${attendance.length} sessions',
                      style: const TextStyle(
                          color: _success,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (attendance.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.history_rounded, color: _textMuted, size: 36),
                    SizedBox(height: 10),
                    Text('No check-ins yet',
                        style: TextStyle(color: _textMuted, fontSize: 13)),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _AttendanceCard(
                    log: attendance[i],
                    formatTimestamp: formatTimestamp,
                    showName: false,
                    index: i,
                  ),
                  childCount: attendance.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _statusLabel(_BtnState s) {
    switch (s) {
      case _BtnState.done:      return '✓  Checked in today';
      case _BtnState.processing: return 'Processing your voice…';
      case _BtnState.recording:  return 'Recording… tap to stop';
      case _BtnState.idle:       return 'Tap to check in';
    }
  }

  String _subLabel(_BtnState s) {
    switch (s) {
      case _BtnState.done:       return 'Attendance recorded for today';
      case _BtnState.processing: return 'Please wait a moment';
      case _BtnState.recording:  return 'Speak your name clearly';
      case _BtnState.idle:       return 'Voice recognition check-in';
    }
  }

  IconData _btnIcon(_BtnState s) {
    switch (s) {
      case _BtnState.done:      return Icons.check_circle_rounded;
      case _BtnState.recording: return Icons.stop_rounded;
      default:                  return Icons.mic_rounded;
    }
  }
}

enum _BtnState { idle, recording, processing, done }

// ─────────────────────────────────────────────────────────────────────────────
//  Ripple Ring
// ─────────────────────────────────────────────────────────────────────────────

class _RippleRing extends StatelessWidget {
  final Animation<double> animation;
  final Color color;
  final double maxRadius;
  final double delay;

  const _RippleRing({
    required this.animation,
    required this.color,
    required this.maxRadius,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) {
        double t = (animation.value - delay) % 1.0;
        if (t < 0) t += 1.0;
        final radius = maxRadius * t;
        final opacity = (1.0 - t).clamp(0.0, 0.5);
        return SizedBox(
          width: maxRadius * 2,
          height: maxRadius * 2,
          child: CustomPaint(
            painter: _RipplePainter(
              radius: radius,
              color: color.withOpacity(opacity),
            ),
          ),
        );
      },
    );
  }
}

class _RipplePainter extends CustomPainter {
  final double radius;
  final Color color;
  _RipplePainter({required this.radius, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      radius,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_RipplePainter old) =>
      old.radius != radius || old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Teacher — Attendance Tab
// ─────────────────────────────────────────────────────────────────────────────

class _AttendanceTab extends StatelessWidget {
  final List<Map<String, dynamic>> attendance;
  final String Function(String) formatTimestamp;
  final Future<void> Function() onRefresh;

  static const _navyLight = Color(0xFF243B55);
  static const _surfaceHigh = Color(0xFF1E3048);
  static const _cyan = Color(0xFF00D4FF);
  static const _success = Color(0xFF00E5A0);
  static const _textMuted = Color(0xFF4A7090);

  const _AttendanceTab({
    required this.attendance,
    required this.formatTimestamp,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: _cyan,
      backgroundColor: _surfaceHigh,
      child: attendance.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.event_available_rounded,
                      color: _textMuted, size: 36),
                  SizedBox(height: 10),
                  Text('No attendance yet',
                      style: TextStyle(color: _textMuted, fontSize: 13)),
                ],
              ),
            )
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      children: [
                        const Text('ALL RECORDS',
                            style: TextStyle(
                                color: _cyan,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.4)),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Container(height: 1, color: _navyLight)),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _success.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: _success.withOpacity(0.3), width: 1),
                          ),
                          child: Text(
                            '${attendance.length} entries',
                            style: const TextStyle(
                                color: _success,
                                fontSize: 11,
                                fontWeight: FontWeight.w600),
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
                      (_, i) => _AttendanceCard(
                        log: attendance[i],
                        formatTimestamp: formatTimestamp,
                        showName: true,
                        index: i,
                      ),
                      childCount: attendance.length,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Teacher — Students Tab
// ─────────────────────────────────────────────────────────────────────────────

class _StudentsTab extends StatelessWidget {
  final List<Map<String, dynamic>> members;
  final Future<void> Function() onRefresh;

  static const _navyLight = Color(0xFF243B55);
  static const _surface = Color(0xFF152032);
  static const _surfaceHigh = Color(0xFF1E3048);
  static const _cyan = Color(0xFF00D4FF);
  static const _purple = Color(0xFFB16CEA);
  static const _textPrimary = Color(0xFFF0F6FF);
  static const _textSub = Color(0xFF7EA8C4);
  static const _textMuted = Color(0xFF4A7090);

  const _StudentsTab({required this.members, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: _cyan,
      backgroundColor: _surfaceHigh,
      child: members.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people_alt_rounded, color: _textMuted, size: 36),
                  SizedBox(height: 10),
                  Text('No students yet',
                      style: TextStyle(color: _textMuted, fontSize: 13)),
                ],
              ),
            )
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      children: [
                        const Text('ENROLLED',
                            style: TextStyle(
                                color: _cyan,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.4)),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Container(height: 1, color: _navyLight)),
                        const SizedBox(width: 10),
                        Text(
                          '${members.length} students',
                          style: const TextStyle(
                              color: _textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
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
                        final m = members[i];
                        final name = (m['name'] as String?) ?? '?';
                        final email = (m['email'] as String?) ?? '';
                        final initial =
                            name.isNotEmpty ? name[0].toUpperCase() : '?';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _navyLight, width: 1),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      _purple.withOpacity(0.3),
                                      _purple.withOpacity(0.1),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(13),
                                  border: Border.all(
                                      color: _purple.withOpacity(0.4),
                                      width: 1),
                                ),
                                child: Center(
                                  child: Text(initial,
                                      style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: _purple)),
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
                                            fontSize: 14,
                                            color: _textPrimary),
                                        overflow: TextOverflow.ellipsis),
                                    if (email.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(email,
                                          style: const TextStyle(
                                              color: _textSub, fontSize: 11),
                                          overflow: TextOverflow.ellipsis),
                                    ],
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: _purple.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: _purple.withOpacity(0.3),
                                      width: 1),
                                ),
                                child: const Text('STUDENT',
                                    style: TextStyle(
                                        fontSize: 9,
                                        color: _purple,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.8)),
                              ),
                            ],
                          ),
                        );
                      },
                      childCount: members.length,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Attendance Card
// ─────────────────────────────────────────────────────────────────────────────

class _AttendanceCard extends StatelessWidget {
  final Map<String, dynamic> log;
  final String Function(String) formatTimestamp;
  final bool showName;
  final int index;

  static const _navyLight = Color(0xFF243B55);
  static const _surface = Color(0xFF152032);
  static const _success = Color(0xFF00E5A0);
  static const _textPrimary = Color(0xFFF0F6FF);
  static const _textSub = Color(0xFF7EA8C4);

  const _AttendanceCard({
    required this.log,
    required this.formatTimestamp,
    required this.showName,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final name =
        (log['user_name'] as String?) ?? (log['name'] as String?) ?? 'Unknown';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final ts = formatTimestamp(log['timestamp']?.toString() ?? '');
    final parts = ts.split('  ');
    final datePart = parts.isNotEmpty ? parts[0] : ts;
    final timePart = parts.length > 1 ? parts[1] : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _navyLight, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _success.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _success.withOpacity(0.3), width: 1),
            ),
            child: Center(
              child: showName
                  ? Text(initial,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _success,
                          fontSize: 16))
                  : const Icon(Icons.how_to_reg_rounded,
                      color: _success, size: 18),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showName)
                  Text(name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: _textPrimary),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1),
                Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded,
                        size: 10, color: _textSub),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(datePart,
                          style:
                              const TextStyle(color: _textSub, fontSize: 11)),
                    ),
                    if (timePart.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.access_time_rounded,
                          size: 10, color: _textSub),
                      const SizedBox(width: 4),
                      Text(timePart,
                          style:
                              const TextStyle(color: _textSub, fontSize: 11)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _success.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _success.withOpacity(0.3), width: 1),
            ),
            child: const Text('PRESENT',
                style: TextStyle(
                    fontSize: 9,
                    color: _success,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6)),
          ),
        ],
      ),
    );
  }
}