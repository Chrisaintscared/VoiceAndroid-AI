import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/audio_recorder_service.dart';
import '../services/voice_enroll_service.dart';

class VoiceEnrollScreen extends StatefulWidget {
  final bool isFirstTime;

  const VoiceEnrollScreen({super.key, this.isFirstTime = false});

  @override
  State<VoiceEnrollScreen> createState() => _VoiceEnrollScreenState();
}

class _VoiceEnrollScreenState extends State<VoiceEnrollScreen> {
  final _recorder = AudioRecorderService();

  int _step = 0;
  bool _isRecording = false;
  bool _isSubmitting = false;
  File? _recordedFile;

  DateTime? _recordStartTime;

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // PERMISSION
  // ─────────────────────────────────────────────

  Future<bool> _requestMicPermission() async {
    final status = await Permission.microphone.request();

    if (status.isGranted) return true;

    if (!mounted) return false;

    if (status.isPermanentlyDenied) {
      _showSnack(
        'Microphone permanently denied. Enable it in Settings.',
        error: true,
        action: SnackBarAction(
          label: 'Settings',
          onPressed: openAppSettings,
        ),
      );
    } else {
      _showSnack('Microphone permission is required.', error: true);
    }

    return false;
  }

  // ─────────────────────────────────────────────
  // RECORDING
  // ─────────────────────────────────────────────

  Future<void> _startRecording() async {
    if (_isRecording) return;

    final allowed = await _requestMicPermission();
    if (!allowed) return;

    final started = await _recorder.startRecording();

    if (!started) {
      _showSnack('Failed to start recording.', error: true);
      return;
    }

    setState(() {
      _isRecording = true;
      _recordedFile = null;
      _step = 1;
      _recordStartTime = DateTime.now();
    });
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;

    final file = await _recorder.stopRecording();

    final duration = DateTime.now().difference(_recordStartTime!);

    setState(() => _isRecording = false);

    // ❗ enforce minimum duration (VERY IMPORTANT for ML)
    if (duration.inSeconds < 3) {
      _showSnack('Please record at least 3 seconds.', error: true);
      _reset();
      return;
    }

    if (file == null || !file.existsSync() || file.lengthSync() == 0) {
      _showSnack('Recording failed. Try again.', error: true);
      _reset();
      return;
    }

    setState(() {
      _recordedFile = file;
      _step = 2;
    });
  }

  // ─────────────────────────────────────────────
  // SUBMIT
  // ─────────────────────────────────────────────

  Future<void> _submitEnrollment() async {
    if (_isSubmitting) return;

    final file = _recordedFile;

    if (file == null || !file.existsSync()) {
      _showSnack('Invalid recording. Re-record.', error: true);
      _reset();
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await VoiceEnrollService.enrollVoice(file);

      if (!mounted) return;

      setState(() => _step = 3);
    } on TimeoutException {
      _showSnack(
        'Server timeout… try again (Render cold start).',
        error: true,
      );
    } catch (e) {
      _showSnack(
        e.toString().replaceFirst('Exception: ', ''),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ─────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────

  void _reset() {
    setState(() {
      _recordedFile = null;
      _isRecording = false;
      _isSubmitting = false;
      _step = 0;
    });
  }

  void _finish() {
    if (widget.isFirstTime) {
      Navigator.pushReplacementNamed(context, '/sboard');
    } else {
      Navigator.pop(context);
    }
  }

  void _showSnack(String msg, {bool error = false, SnackBarAction? action}) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : Colors.teal,
        action: action,
      ),
    );
  }

  // ─────────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Enrollment'),
        backgroundColor: Colors.teal,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _buildStep(),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _stepIntro();
      case 1:
        return _stepRecording();
      case 2:
        return _stepReview();
      case 3:
        return _stepDone();
      default:
        return _stepIntro();
    }
  }

  Widget _stepIntro() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.mic, size: 80, color: Colors.teal),
        const SizedBox(height: 20),
        const Text(
          'Enroll Your Voice',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        const Text(
          'Speak your name clearly for voice verification.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 30),
        ElevatedButton(
          onPressed: _startRecording,
          child: const Text('Start Recording'),
        ),
      ],
    );
  }

  Widget _stepRecording() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.mic, size: 80, color: Colors.red),
        const SizedBox(height: 20),
        const Text('Recording...'),
        const SizedBox(height: 30),
        ElevatedButton(
          onPressed: _stopRecording,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          child: const Text('Stop'),
        ),
      ],
    );
  }

  Widget _stepReview() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.check, size: 80, color: Colors.teal),
        const SizedBox(height: 20),
        const Text('Ready to submit'),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submitEnrollment,
          child: _isSubmitting
              ? const CircularProgressIndicator(color: Colors.white)
              : const Text('Submit'),
        ),
        TextButton(onPressed: _reset, child: const Text('Retry')),
      ],
    );
  }

  Widget _stepDone() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.verified, size: 80, color: Colors.teal),
        const SizedBox(height: 20),
        const Text('Voice Enrolled!'),
        const SizedBox(height: 30),
        ElevatedButton(
          onPressed: _finish,
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
