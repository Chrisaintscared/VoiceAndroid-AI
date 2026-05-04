import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class ApiService {
  // ── CONFIG ─────────────────────────────────────────────

  static const String baseUrl = "https://voiceandroid-ai.onrender.com";

  static const Duration _timeout = Duration(seconds: 60);
  static const int _maxAttempts = 2;
  static const Duration _retryDelay = Duration(seconds: 3);

  // ── ERROR HANDLER ──────────────────────────────────────

  static Map<String, dynamic> _errorMap({
    required int statusCode,
    required String message,
    String rawResponse = '',
  }) {
    return {
      'success': false,
      'statusCode': statusCode,
      'message': message,
      'rawResponse': rawResponse,
    };
  }

  // ── RESPONSE PARSER ────────────────────────────────────

  static Map<String, dynamic> _parseResponse(http.Response response) {
    _log('← ${response.statusCode}  ${response.body}');

    if (response.body.isEmpty) {
      return _errorMap(
        statusCode: response.statusCode,
        message: 'Empty response from server.',
      );
    }

    try {
      final decoded = jsonDecode(response.body);
      return {
        'success': response.statusCode >= 200 && response.statusCode < 300,
        'statusCode': response.statusCode,
        ...decoded,
      };
    } catch (_) {
      return _errorMap(
        statusCode: response.statusCode,
        message: 'Invalid JSON response',
        rawResponse: response.body,
      );
    }
  }

  // ── RETRY WRAPPER ──────────────────────────────────────

  static Future<Map<String, dynamic>> _withRetry(
    Future<http.Response> Function() call,
  ) async {
    for (int attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        _log('→ attempt $attempt');

        final response = await call().timeout(_timeout);

        if (response.body.isEmpty && attempt < _maxAttempts) {
          await Future.delayed(_retryDelay);
          continue;
        }

        return _parseResponse(response);
      } on TimeoutException {
        if (attempt < _maxAttempts) {
          await Future.delayed(_retryDelay);
          continue;
        }
        return _errorMap(
          statusCode: 408,
          message: 'Request timeout',
        );
      } on SocketException catch (e) {
        if (attempt < _maxAttempts) {
          await Future.delayed(_retryDelay);
          continue;
        }
        return _errorMap(
          statusCode: 0,
          message: 'Network error: $e',
        );
      } catch (e) {
        return _errorMap(
          statusCode: 0,
          message: 'Unexpected error: $e',
        );
      }
    }

    return _errorMap(statusCode: 0, message: 'Retry failed');
  }

  // ── MULTIPART RETRY ────────────────────────────────────

  static Future<Map<String, dynamic>> _withRetryMultipart(
    http.MultipartRequest Function() build,
  ) async {
    for (int attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        final streamed = await build().send().timeout(_timeout);
        final body = await streamed.stream.bytesToString();

        final response =
            http.Response(body, streamed.statusCode, headers: streamed.headers);

        if (body.isEmpty && attempt < _maxAttempts) {
          await Future.delayed(_retryDelay);
          continue;
        }

        return _parseResponse(response);
      } catch (e) {
        if (attempt < _maxAttempts) {
          await Future.delayed(_retryDelay);
          continue;
        }
        return _errorMap(statusCode: 0, message: 'Upload failed: $e');
      }
    }

    return _errorMap(statusCode: 0, message: 'Upload retry failed');
  }

  static void _log(String msg) {
    print('[ApiService] $msg');
  }

  // ── AUTH ───────────────────────────────────────────────

  static Future<Map<String, dynamic>> login(
      String email, String password) async {
    final url = '$baseUrl/auth/login';

    return _withRetry(() => http.post(
          Uri.parse(url),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {
            'username': email,
            'password': password,
          },
        ));
  }

  // ── ENROLL VOICE ───────────────────────────────────────

  static Future<Map<String, dynamic>> enrollVoice(
      String filePath, String token) async {
    final file = File(filePath);

    final url = '$baseUrl/voice/enroll-voice';

    return _withRetryMultipart(() {
      final request = http.MultipartRequest('POST', Uri.parse(url));

      request.headers['Authorization'] = 'Bearer $token';

      request.files.add(http.MultipartFile.fromBytes(
        'voice',
        file.readAsBytesSync(),
        filename: file.uri.pathSegments.last,
      ));

      return request;
    });
  }

  // ── MARK ATTENDANCE ────────────────────────────────────

  static Future<Map<String, dynamic>> markAttendance(
    String filePath,
    String token,
  ) async {
    final file = File(filePath);

    final url = '$baseUrl/attendance/mark';

    return _withRetryMultipart(() {
      final request = http.MultipartRequest('POST', Uri.parse(url));

      request.headers['Authorization'] = 'Bearer $token';

      request.files.add(http.MultipartFile.fromBytes(
        'audio',
        file.readAsBytesSync(),
        filename: file.uri.pathSegments.last,
      ));

      return request;
    });
  }

  // ── HEALTH CHECK (IMPORTANT) ───────────────────────────

  static Future<Map<String, dynamic>> healthCheck() async {
    final url = '$baseUrl/health';

    _log('→ GET $url (warm-up)');

    return _withRetry(() => http.get(Uri.parse(url)));
  }
}
