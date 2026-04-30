import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'auth_service.dart';

class AttendanceService {
  static const String baseUrl = "https://VoiceAndroid-backend.onrender.com";

  /// Increased to 45 s — the AI model on Render takes time to boot/process.
  static const Duration timeout = Duration(seconds: 45);

  // ── Voice check-in ──────────────────────────────────────────────────────────

  /// Submits [audioFile] to the backend for voice verification.
  /// Returns `{"status": "success", "confidence": 92.5}` on success.
  /// Throws a descriptive [Exception] on any failure.
  static Future<Map<String, dynamic>> voiceCheckIn(
    File audioFile,
    int classId,
  ) async {
    final token = await AuthService.getToken();
    if (token == null) throw Exception("User not logged in");
    if (!audioFile.existsSync()) throw Exception("Audio file not found");

    final uri = Uri.parse('$baseUrl/attendance/mark?class_id=$classId');
    final request = http.MultipartRequest('POST', uri);

    request.headers.addAll({
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
    });

    // Field name 'audio' must match the Python UploadFile parameter name.
    request.files.add(
      await http.MultipartFile.fromPath(
        'audio',
        audioFile.path,
        contentType: MediaType('audio', 'wav'),
      ),
    );

    try {
      final streamedResponse = await request.send().timeout(timeout);
      final response = await http.Response.fromStream(streamedResponse);
      final data = json.decode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        return data; // {"status": "success", "confidence": 92.5}
      }

      // Surface the backend's human-readable error message.
      throw Exception(data['detail'] ?? "Verification failed");
    } on http.ClientException {
      throw Exception("Server connection failed. Please try again.");
    } on Exception {
      rethrow;
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  // ── Attendance logs ─────────────────────────────────────────────────────────

  /// Fetches the current user's attendance logs.
  /// Optionally filter by [classId].
  static Future<List<dynamic>> getLogs({int? classId}) async {
    final token = await AuthService.getToken();
    if (token == null) throw Exception("User not logged in");

    final queryParams = classId != null ? '?class_id=$classId' : '';
    final uri = Uri.parse('$baseUrl/attendance/logs$queryParams');

    try {
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return data['logs'] ?? [];
      }

      final error = json.decode(response.body) as Map<String, dynamic>;
      throw Exception(error['detail'] ?? "Failed to load attendance logs");
    } on http.ClientException {
      throw Exception("Server connection failed. Please try again.");
    } on Exception {
      rethrow;
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  // ── Health check ────────────────────────────────────────────────────────────

  /// Returns `true` if the backend is reachable and healthy.
  static Future<bool> testConnection() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/attendance/test'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
