import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'auth_service.dart';

class VoiceEnrollService {
  static const String _baseUrl = 'https://voiceandroid-ai.onrender.com';
  static const Duration _timeout = Duration(seconds: 180);
  static const int _maxAttempts = 2;
  static const Duration _retryDelay = Duration(seconds: 3);

  static Future<Map<String, String>> _authHeaders() async {
    final token = await AuthService.getToken();
    return {
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Map<String, dynamic> _parseBody(String body, int statusCode) {
    if (body.isEmpty) {
      return {'detail': 'Empty response from server (status $statusCode).'};
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      return {'detail': 'Unexpected response format.'};
    } catch (_) {
      return {'detail': 'Server returned non-JSON response.', 'raw': body};
    }
  }

  static String _messageForStatus(int statusCode, Map<String, dynamic> data) {
    final detail = data['detail']?.toString();
    switch (statusCode) {
      case 400:
        return detail ?? 'Bad request — audio may be invalid or too short.';
      case 401:
        return 'Unauthorized — please log in again.';
      case 409:
        return 'A voice profile already exists for this account.';
      case 413:
        return 'Audio file is too large. Please record a shorter clip.';
      case 422:
        return detail ?? 'Validation error — check audio format and length.';
      case 503:
        return 'Server is starting up. Please wait and try again.';
      default:
        return detail ?? 'Request failed (status $statusCode).';
    }
  }

  static void _log(String message) {
    // ignore: avoid_print
    print('[VoiceEnrollService] $message');
  }

  static Future<bool> isEnrolled() async {
    final url = '$_baseUrl/voice/enroll-status';
    _log('GET $url');

    for (int attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        final headers = await _authHeaders();
        final response = await http
            .get(Uri.parse(url), headers: headers)
            .timeout(_timeout);

        _log('← ${response.statusCode}  body: ${response.body}');

        if (response.body.isEmpty && attempt < _maxAttempts) {
          await Future.delayed(_retryDelay);
          continue;
        }

        if (response.statusCode == 200) {
          final data = _parseBody(response.body, response.statusCode);
          return data['enrolled'] == true;
        }

        return false;
      } on TimeoutException {
        if (attempt < _maxAttempts) {
          await Future.delayed(_retryDelay);
          continue;
        }
        return false;
      } on SocketException {
        if (attempt < _maxAttempts) {
          await Future.delayed(_retryDelay);
          continue;
        }
        return false;
      } catch (_) {
        return false;
      }
    }

    return false;
  }

  static Future<void> enrollVoice(File audioFile) async {
    if (!audioFile.existsSync()) {
      throw Exception('Audio file not found at path: ${audioFile.path}');
    }
    // Use async length check — avoids blocking the event loop
    if (await audioFile.length() == 0) {
      throw Exception('Audio file is empty (0 bytes). Please re-record.');
    }

    final url = '$_baseUrl/voice/enroll-voice';
    _log('POST $url  file: ${audioFile.path}  size: ${await audioFile.length()}B');

    for (int attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        final token = await AuthService.getToken();

        final request = http.MultipartRequest('POST', Uri.parse(url));

        request.headers['Accept'] = 'application/json';
        if (token != null) {
          request.headers['Authorization'] = 'Bearer $token';
        }

        // fromPath streams the file instead of loading it all into memory at once.
        // This is more efficient and avoids RAM spikes on large audio files.
        // filename is hardcoded to 'voice.webm' — matches Android Chrome's default format.
        request.files.add(
          await http.MultipartFile.fromPath(
            'voice',
            audioFile.path,
            filename: 'voice.wav',
            contentType: MediaType('audio', 'wav'),
          ),
        );

        final streamed = await request.send().timeout(_timeout);
        final body = await streamed.stream.bytesToString();

        _log('← ${streamed.statusCode}  body: $body');

        if (body.isEmpty && attempt < _maxAttempts) {
          _log('Empty body on attempt $attempt — retrying …');
          await Future.delayed(_retryDelay);
          continue;
        }

        final data = _parseBody(body, streamed.statusCode);

        if (streamed.statusCode >= 200 && streamed.statusCode < 300) {
          return; // Success
        }

        throw Exception(_messageForStatus(streamed.statusCode, data));
      } on TimeoutException {
        if (attempt < _maxAttempts) {
          _log('Timeout on attempt $attempt — retrying …');
          await Future.delayed(_retryDelay);
          continue;
        }
        throw Exception(
          'Request timed out after ${_timeout.inSeconds}s. '
          'The server may be starting up — please try again.',
        );
      } on SocketException catch (e) {
        if (attempt < _maxAttempts) {
          _log('Socket error ($e) on attempt $attempt — retrying …');
          await Future.delayed(_retryDelay);
          continue;
        }
        throw Exception('Network error: $e. Check your internet connection.');
      } on Exception {
        rethrow;
      } catch (e) {
        throw Exception('Unexpected error during enrollment: $e');
      }
    }

    throw Exception('Enrollment failed after $_maxAttempts attempts.');
  }
}