import 'dart:io';
import 'dart:typed_data';

// ─────────────────────────────────────────────────────────────────────────────
//  MLService  –  On-device voice embedding via TFLite
//
//  STATUS: Phase-2 stub.  The class is wired into AttendanceService already,
//  but _modelLoaded stays false until you drop voice_model.tflite into assets/
//  and uncomment the tflite_flutter import + dependency in pubspec.yaml.
//
//  When the model IS available the flow becomes:
//    WAV bytes → pre-process → TFLite → Float32 embedding (512-d)
//    → POST /attendance/checkin  { embedding: [...] }   (no audio file upload)
//
//  When the model is NOT available the service falls back to uploading the
//  raw WAV file, which is the existing behaviour – so nothing breaks today.
// ─────────────────────────────────────────────────────────────────────────────

// ── Uncomment this import once you add tflite_flutter: ^0.11.0 ──────────────
// import 'package:tflite_flutter/tflite_flutter.dart';

class MLService {
  // Singleton so the interpreter is only allocated once.
  MLService._();
  static final MLService instance = MLService._();

  // ignore: unused_field
  bool _modelLoaded = false;

  // Uncomment when tflite_flutter is available:
  // Interpreter? _interpreter;

  // ── Constants ─────────────────────────────────────────────────────────────

  /// Sample rate your TFLite model was trained on (must match backend).
  static const int kSampleRate = 16000;

  /// Expected input length in samples fed to the model in one shot.
  /// Adjust to match your model's input shape.
  static const int kWindowSamples = 48000; // 3 s @ 16 kHz

  /// Output embedding dimension – must match your X-Vector / d-vector model.
  static const int kEmbeddingDim = 512;

  // ── Model lifecycle ───────────────────────────────────────────────────────

  /// Call once, e.g. in main() after WidgetsFlutterBinding.ensureInitialized().
  /// Safe to call even when the asset doesn't exist yet – it will simply log
  /// and leave _modelLoaded = false so the WAV fallback is used.
  Future<void> loadModel() async {
    // ── PHASE-2: uncomment when ready ────────────────────────────────────
    // try {
    //   _interpreter = await Interpreter.fromAsset('voice_model.tflite');
    //   _modelLoaded = true;
    //   debugPrint('[MLService] TFLite model loaded ✓');
    // } catch (e) {
    //   debugPrint('[MLService] Model not found – using server fallback: $e');
    // }
  }

  // ── Inference ─────────────────────────────────────────────────────────────

  /// Returns a 512-d embedding, or null if the model isn't loaded.
  ///
  /// [wavFile] must be a 16 kHz, mono, 16-bit PCM WAV file.
  Future<List<double>?> generateEmbedding(File wavFile) async {
    if (!_modelLoaded) return null;

    // ── PHASE-2: uncomment when ready ────────────────────────────────────
    // final interpreter = _interpreter;
    // if (interpreter == null) return null;
    //
    // try {
    //   final pcm = _extractPcmFromWav(await wavFile.readAsBytes());
    //   final input  = _padOrTrim(pcm, kWindowSamples);
    //   final inputTensor  = [input];          // shape [1, kWindowSamples]
    //   final outputTensor = [Float32List(kEmbeddingDim)]; // shape [1, 512]
    //
    //   interpreter.run(inputTensor, outputTensor);
    //   return outputTensor[0].map((v) => v.toDouble()).toList();
    // } catch (e) {
    //   debugPrint('[MLService] Inference error: $e');
    //   return null;
    // }

    return null; // Phase-1: always use server-side inference
  }

  // ── Audio pre-processing helpers ──────────────────────────────────────────

  /// Strips the 44-byte WAV header and returns raw 16-bit PCM samples
  /// normalised to the range [-1.0, 1.0].
  List<double> _extractPcmFromWav(Uint8List bytes) {
    const wavHeaderBytes = 44;
    final pcmBytes = bytes.sublist(wavHeaderBytes);
    final samples = <double>[];

    for (int i = 0; i < pcmBytes.length - 1; i += 2) {
      // Little-endian int16 → float
      final int16 = pcmBytes[i] | (pcmBytes[i + 1] << 8);
      final signed = int16 >= 0x8000 ? int16 - 0x10000 : int16;
      samples.add(signed / 32768.0);
    }

    return samples;
  }

  /// Pads with zeros or centre-crops to exactly [targetLen] samples.
  List<double> _padOrTrim(List<double> samples, int targetLen) {
    if (samples.length >= targetLen) {
      // Centre-crop
      final start = (samples.length - targetLen) ~/ 2;
      return samples.sublist(start, start + targetLen);
    }
    // Zero-pad at the end
    return [...samples, ...List.filled(targetLen - samples.length, 0.0)];
  }

  // ── Cosine similarity (utility, unused in Phase 1) ────────────────────────

  /// Cosine similarity between two equal-length vectors.
  /// Returns a value in [-1.0, 1.0].  Used for local verification if needed.
  static double cosineSimilarity(List<double> a, List<double> b) {
    assert(a.length == b.length, 'Vectors must have equal length');
    double dot = 0, normA = 0, normB = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    final denom = (normA * normB);
    return denom == 0 ? 0.0 : dot / (denom == 0 ? 1 : denom);
  }
}