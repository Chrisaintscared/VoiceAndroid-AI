library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();

  String? _outputPath;
  DateTime? _recordingStartTime;

  static const int _sampleRate = 16000;
  static const int _numChannels = 1;
  static const int _minDurationSeconds = 2;
  static const int _minFileSizeBytes = 1024;

  Future<bool> startRecording() async {
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) return false;

      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }

      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _outputPath = '${tempDir.path}/VoiceAndroid_$timestamp.wav';
      _recordingStartTime = DateTime.now();

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: _sampleRate,
          numChannels: _numChannels,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
        ),
        path: _outputPath!,
      );

      return true;
    } catch (_) {
      _outputPath = null;
      _recordingStartTime = null;
      return false;
    }
  }

  Future<File?> stopRecording() async {
    try {
      final isActive = await _recorder.isRecording();
      if (!isActive) return null;

      final duration = _recordingStartTime != null
          ? DateTime.now().difference(_recordingStartTime!)
          : Duration.zero;

      if (duration.inSeconds < _minDurationSeconds) {
        await _recorder.stop();
        _outputPath = null;
        _recordingStartTime = null;
        return null;
      }

      final path = await _recorder.stop();
      _recordingStartTime = null;

      final resolvedPath = path ?? _outputPath;
      if (resolvedPath == null) return null;

      final file = File(resolvedPath);
      if (!await file.exists()) return null;

      final fileSize = await file.length();
      if (fileSize < _minFileSizeBytes) {
        await file.delete().catchError((_) => file);
        return null;
      }

      _outputPath = null;
      return file;
    } catch (_) {
      _outputPath = null;
      _recordingStartTime = null;
      return null;
    }
  }

  Future<void> cancelRecording() async {
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
      if (_outputPath != null) {
        final file = File(_outputPath!);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (_) {
    } finally {
      _outputPath = null;
      _recordingStartTime = null;
    }
  }

  Future<bool> get isRecording => _recorder.isRecording();

  Future<void> dispose() async {
    await cancelRecording();
    await _recorder.dispose();
  }
}