import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// VoiceAttend AI — API Service
///
/// Design rules:
///   • Every public method returns a [Map<String, dynamic>] that always
///     contains at least {"statusCode": int, "success": bool}.
///   • Network calls are wrapped in a retry helper (max 2 attempts) to
///     survive Render free-tier cold starts (~30 s spin-up).
///   • Timeouts are generous (60 s connect, 60 s receive) for the same reason.
///   • No method ever throws — all exceptions are caught and returned as a
///     structured error map so callers can handle them uniformly.
class ApiService {
  // ── Configuration ──────────────────────────────────────────────────────────

  static const String baseUrl = "https://voiceandroid-ai.onrender.com";

  /// Total time to wait for a single attempt before giving up.
  /// 60 s covers Render free-tier cold starts (~15–30 s) plus inference time.
  static const Duration _timeout = Duration(seconds: 60);

  /// Maximum number of attempts (1 initial + 1 retry).
  static const int _maxAttempts = 2;

  /// Delay between retry attempts — gives the server a moment to recover.
  static const Duration _retryDelay = Duration(seconds: 3);

  // ── Internal helpers ────────────────────────────────────────────────────────

  /// Structured error map returned whenever a request cannot be completed.
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

  /// Parse [response.body] as JSON and merge standard fields.
  /// Falls back to an error map on decode failure.
  static Map<String, dynamic> _parseResponse(http.Response response) {
    _log('← ${response.statusCode}  body: ${response.body}');

    // Surface well-known HTTP errors as readable messages before JSON parsing.
    switch (response.statusCode) {
      case 401:
        return _errorMap(
          statusCode: 401,
          message: 'Unauthorized — token missing or expired. Please log in again.',
          rawResponse: response.body,
        );
      case 409:
        return _errorMap(
          statusCode: 409,
          message: 'Conflict — a voice profile already exists for this account.',
          rawResponse: response.body,
        );
      case 413:
        return _errorMap(
          statusCode: 413,
          message: 'Audio file is too large. Please record a shorter clip.',
          rawResponse: response.body,
        );
      case 422:
        // FastAPI validation error — body contains detail field.
        break;
      case 500:
      case 502:
      case 503:
        return _errorMap(
          statusCode: response.statusCode,
          message: 'Server error (${response.statusCode}). '
              'The backend may be starting up — please wait and retry.',
          rawResponse: response.body,
        );
    }

    if (response.body.isEmpty) {
      return _errorMap(
        statusCode: response.statusCode,
        message: 'Empty response from server.',
      );
    }

    try {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'success': response.statusCode >= 200 && response.statusCode < 300,
        'statusCode': response.statusCode,
        ...decoded,
      };
    } catch (_) {
      return _errorMap(
        statusCode: response.statusCode,
        message: 'Server returned non-JSON response.',
        rawResponse: response.body,
      );
    }
  }

  /// Generic retry wrapper for [http.Response]-returning lambdas.
  ///
  /// Retries on:
  ///   • [SocketException]   (no network / DNS failure)
  ///   • [HttpException]     (connection reset)
  ///   • [TimeoutException]  (server took too long)
  ///   • Empty body          (Render cold-start sometimes returns nothing)
  static Future<Map<String, dynamic>> _withRetry(
    Future<http.Response> Function() call,
  ) async {
    for (int attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        _log('→ attempt $attempt / $_maxAttempts');
        final sw       = Stopwatch()..start();
        final response = await call().timeout(_timeout);
        sw.stop();
        _log('   completed in ${sw.elapsedMilliseconds} ms');

        // Retry on empty body (Render cold-start race condition).
        if (response.body.isEmpty && attempt < _maxAttempts) {
          _log('   empty body — retrying after $_retryDelay …');
          await Future.delayed(_retryDelay);
          continue;
        }

        return _parseResponse(response);
      } on TimeoutException {
        if (attempt < _maxAttempts) {
          _log('   timeout — retrying after $_retryDelay …');
          await Future.delayed(_retryDelay);
          continue;
        }
        return _errorMap(
          statusCode: 408,
          message: 'Request timed out after ${_timeout.inSeconds} s. '
              'The server may be experiencing a cold start — please try again.',
        );
      } on SocketException catch (e) {
        if (attempt < _maxAttempts) {
          _log('   socket error ($e) — retrying …');
          await Future.delayed(_retryDelay);
          continue;
        }
        return _errorMap(
          statusCode: 0,
          message: 'Network error: $e. Check your internet connection.',
        );
      } on HttpException catch (e) {
        if (attempt < _maxAttempts) {
          _log('   HTTP error ($e) — retrying …');
          await Future.delayed(_retryDelay);
          continue;
        }
        return _errorMap(
          statusCode: 0,
          message: 'HTTP error: $e.',
        );
      } catch (e) {
        return _errorMap(
          statusCode: 0,
          message: 'Unexpected error: $e.',
        );
      }
    }

    // Should be unreachable, but Dart requires a return.
    return _errorMap(statusCode: 0, message: 'All retry attempts failed.');
  }

  /// Multipart-specific retry wrapper (http.StreamedResponse → String path).
  static Future<Map<String, dynamic>> _withRetryMultipart(
    http.MultipartRequest Function() buildRequest,
  ) async {
    for (int attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        _log('→ multipart attempt $attempt / $_maxAttempts');
        final sw       = Stopwatch()..start();
        final streamed = await buildRequest().send().timeout(_timeout);
        final body     = await streamed.stream.bytesToString();
        sw.stop();
        _log('   completed in ${sw.elapsedMilliseconds} ms');
        _log('← ${streamed.statusCode}  body: $body');

        // Fake an http.Response so _parseResponse can handle it uniformly.
        final fakeResp = http.Response(body, streamed.statusCode,
            headers: streamed.headers);

        if (body.isEmpty && attempt < _maxAttempts) {
          _log('   empty body — retrying after $_retryDelay …');
          await Future.delayed(_retryDelay);
          continue;
        }

        return _parseResponse(fakeResp);
      } on TimeoutException {
        if (attempt < _maxAttempts) {
          _log('   timeout — retrying after $_retryDelay …');
          await Future.delayed(_retryDelay);
          continue;
        }
        return _errorMap(
          statusCode: 408,
          message: 'Upload timed out. Audio file may be too large or the '
              'server is cold-starting — please try again.',
        );
      } on SocketException catch (e) {
        if (attempt < _maxAttempts) {
          await Future.delayed(_retryDelay);
          continue;
        }
        return _errorMap(statusCode: 0, message: 'Network error: $e.');
      } catch (e) {
        return _errorMap(statusCode: 0, message: 'Unexpected error: $e.');
      }
    }
    return _errorMap(statusCode: 0, message: 'All upload attempts failed.');
  }

  /// Minimal structured logger — replace with your logger package if needed.
  static void _log(String message) {
    // ignore: avoid_print
    print('[ApiService] $message');
  }

  // ── Auth endpoints ──────────────────────────────────────────────────────────

  /// Register a new user account.
  static Future<Map<String, dynamic>> createUser(
    String name,
    String email,
    String passwordHash,
  ) async {
    final url = '$baseUrl/auth/register';
    _log('→ POST $url');

    return _withRetry(() => http.post(
          Uri.parse(url),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'name': name,
            'email': email,
            'password_hash': passwordHash,
          }),
        ));
  }

  /// Authenticate and receive a JWT token.
  ///
  /// Returns map with 'token' key on success.
  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    final url = '$baseUrl/auth/login';
    _log('→ POST $url');

    // FastAPI OAuth2PasswordRequestForm expects form-encoded body, not JSON.
    return _withRetry(() => http.post(
          Uri.parse(url),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {
            'username': email,  // OAuth2 form field is "username"
            'password': password,
          },
        ));
  }

  // ── Voice enrollment ────────────────────────────────────────────────────────

  /// Upload a WAV audio file to enroll the user's voice profile.
  ///
  /// [filePath] must point to a local WAV file (16 kHz, mono).
  /// [token]    is the JWT returned by [login].
  static Future<Map<String, dynamic>> enrollVoice(
    String filePath,
    String token,
  ) async {
    // ── Pre-flight validation ────────────────────────────────────────────────
    if (filePath.isEmpty) {
      return _errorMap(statusCode: 400, message: 'filePath must not be empty.');
    }

    final file = File(filePath);
    if (!file.existsSync()) {
      return _errorMap(
        statusCode: 400,
        message: 'Audio file not found at path: $filePath',
      );
    }

    final fileSize = file.lengthSync();
    if (fileSize == 0) {
      return _errorMap(statusCode: 400, message: 'Audio file is empty (0 bytes).');
    }

    if (token.isEmpty) {
      return _errorMap(statusCode: 401, message: 'Auth token is missing.');
    }

    // Warn if the file extension is not .wav — backend requires WAV / 16 kHz.
    if (!filePath.toLowerCase().endsWith('.wav')) {
      _log('⚠️  WARNING: filePath does not end in .wav. '
          'The backend requires WAV format (16 kHz, mono). '
          'Convert before uploading.');
    }

    final url = '$baseUrl/voice/enroll-voice';
    _log('→ POST $url  file: $filePath  size: ${fileSize}B');

    return _withRetryMultipart(() {
      final request = http.MultipartRequest('POST', Uri.parse(url));

      request.headers['Authorization'] = 'Bearer $token';

      // Field name MUST match backend: File(...) parameter named "voice"
      request.files.add(http.MultipartFile.fromBytes(
        'voice',                         // ← matches FastAPI parameter name
        file.readAsBytesSync(),
        filename: file.uri.pathSegments.last,
      ));

      return request;
    });
  }

  // ── Attendance endpoints ────────────────────────────────────────────────────

  /// Voice-verified check-in.
  ///
  /// Sends audio to [/attendance/mark] for speaker verification.
  /// [filePath] must point to a local WAV file.
  /// [token]    is the JWT returned by [login].
  static Future<Map<String, dynamic>> markAttendance(
    String filePath,
    String token, {
    int? classId,
  }) async {
    // ── Pre-flight validation ────────────────────────────────────────────────
    if (filePath.isEmpty) {
      return _errorMap(statusCode: 400, message: 'filePath must not be empty.');
    }

    final file = File(filePath);
    if (!file.existsSync()) {
      return _errorMap(
        statusCode: 400,
        message: 'Audio file not found at path: $filePath',
      );
    }

    if (file.lengthSync() == 0) {
      return _errorMap(statusCode: 400, message: 'Audio file is empty (0 bytes).');
    }

    if (token.isEmpty) {
      return _errorMap(statusCode: 401, message: 'Auth token is missing.');
    }

    if (!filePath.toLowerCase().endsWith('.wav')) {
      _log('⚠️  WARNING: filePath does not end in .wav.');
    }

    final url = '$baseUrl/attendance/mark';
    _log('→ POST $url  file: $filePath  classId: $classId');

    return _withRetryMultipart(() {
      final request = http.MultipartRequest('POST', Uri.parse(url));

      request.headers['Authorization'] = 'Bearer $token';

      // Field name MUST match backend: File(...) parameter named "audio"
      request.files.add(http.MultipartFile.fromBytes(
        'audio',                          // ← matches FastAPI parameter name
        file.readAsBytesSync(),
        filename: file.uri.pathSegments.last,
      ));

      if (classId != null) {
        request.fields['class_id'] = classId.toString();
      }

      return request;
    });
  }

  // ── Attendance log endpoints ────────────────────────────────────────────────

  /// Fetch all attendance logs (admin use).
  static Future<Map<String, dynamic>> getAllLogs(String token) async {
    final url = '$baseUrl/attendance/logs';
    _log('→ GET $url');

    return _withRetry(() => http.get(
          Uri.parse(url),
          headers: {'Authorization': 'Bearer $token'},
        ));
  }

  /// Fetch attendance logs for a specific user.
  static Future<Map<String, dynamic>> getUserLogs(
    String userName,
    String token,
  ) async {
    final url = '$baseUrl/attendance/logs/$userName';
    _log('→ GET $url');

    return _withRetry(() => http.get(
          Uri.parse(url),
          headers: {'Authorization': 'Bearer $token'},
        ));
  }

  // ── Enrollment status ───────────────────────────────────────────────────────

  /// Check whether the current user has an enrolled voice profile.
  static Future<Map<String, dynamic>> getEnrollStatus(String token) async {
    final url = '$baseUrl/voice/enroll-status';
    _log('→ GET $url');

    return _withRetry(() => http.get(
          Uri.parse(url),
          headers: {'Authorization': 'Bearer $token'},
        ));
  }

  // ── Health check ────────────────────────────────────────────────────────────

  /// Ping the backend to confirm it is awake and the ML model is loaded.
  ///
  /// Useful to call once at app launch so the Render free-tier instance
  /// warms up before the user tries to enroll or check in.
  ///
  /// Returns {"status": "ok", "model_loaded": true/false}.
  static Future<Map<String, dynamic>> healthCheck() async {
    final url = '$baseUrl/';
    _log('→ GET $url  (health check / warm-up)');

    return _withRetry(() => http.get(Uri.parse(url)));
  }
}