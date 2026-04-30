import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  static const String baseUrl = "https://VoiceAndroid-backend.onrender.com";
  static const Duration _timeout = Duration(seconds: 15);
  static const int _maxRetries = 3;

  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'jwt_token';
  static const _userKey = 'current_user';

  // ────────────────────────────────────────────────
  // RETRY HELPERS
  // ────────────────────────────────────────────────

  static Future<http.Response> _getWithRetry(Uri uri,
      {Map<String, String>? headers}) async {
    Exception? lastError;
    for (int i = 0; i < _maxRetries; i++) {
      try {
        return await http.get(uri, headers: headers).timeout(_timeout);
      } catch (e) {
        lastError = Exception(e.toString());
        if (i < _maxRetries - 1) {
          await Future.delayed(Duration(seconds: 2 * (i + 1)));
        }
      }
    }
    throw lastError ?? Exception('Request failed after $_maxRetries retries');
  }

  static Future<http.Response> _postWithRetry(Uri uri,
      {Map<String, String>? headers, Object? body}) async {
    Exception? lastError;
    for (int i = 0; i < _maxRetries; i++) {
      try {
        return await http
            .post(uri, headers: headers, body: body)
            .timeout(_timeout);
      } catch (e) {
        lastError = Exception(e.toString());
        if (i < _maxRetries - 1) {
          await Future.delayed(Duration(seconds: 2 * (i + 1)));
        }
      }
    }
    throw lastError ?? Exception('Request failed after $_maxRetries retries');
  }

  // ────────────────────────────────────────────────
  // STORAGE
  // ────────────────────────────────────────────────

  static Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  static Future<String?> getToken() async {
    return _storage.read(key: _tokenKey);
  }

  static Future<void> saveUser(Map<String, dynamic> user) async {
    await _storage.write(key: _userKey, value: jsonEncode(user));
  }

  static Future<Map<String, dynamic>?> getStoredUser() async {
    final raw = await _storage.read(key: _userKey);
    if (raw == null) return null;
    return jsonDecode(raw);
  }

  static Future<void> logout() async {
    await _storage.deleteAll();
  }

  static Future<Map<String, String>> _authHeaders() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ────────────────────────────────────────────────
  // SAFE JSON PARSER
  // ────────────────────────────────────────────────

  static dynamic _safeDecode(http.Response res) {
    if (res.body.isEmpty) {
      throw Exception("Empty response from server");
    }
    try {
      return jsonDecode(res.body);
    } catch (_) {
      throw Exception("Invalid JSON response:\n${res.body}");
    }
  }

  // ────────────────────────────────────────────────
  // JWT DECODER
  // ────────────────────────────────────────────────

  static Map<String, dynamic> _decodeJwt(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return {};
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      return Map<String, dynamic>.from(payload);
    } catch (_) {
      return {};
    }
  }

  static Map<String, dynamic> _userFromToken(String token, String email) {
    final payload = _decodeJwt(token);
    return {
      'role': payload['role'] ?? 'student',
      'email': payload['sub'] ?? email,
      'name': payload['name'] ?? '',
      'id': payload['id'] ?? payload['user_id'] ?? '',
    };
  }

  // ────────────────────────────────────────────────
  // AUTH
  // ────────────────────────────────────────────────

  static Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
    String? role,
  }) async {
    final res = await _postWithRetry(
      Uri.parse('$baseUrl/auth/register'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'name': name,
        'email': email,
        'password': password,
        'role': role ?? 'student',
      }),
    );

    print("REGISTER STATUS: ${res.statusCode}");
    print("REGISTER BODY: ${res.body}");

    if (res.statusCode == 201 || res.statusCode == 200) {
      final data = _safeDecode(res);

      // Plain string token
      if (data is String) {
        await saveToken(data);
        final user = _userFromToken(data, email);
        await saveUser(user);
        return {'access_token': data, 'user': user};
      }

      // Object response
      if (data is Map<String, dynamic>) {
        final token = data['access_token'] as String?;
        final user = data['user'] as Map<String, dynamic>? ??
            (token != null
                ? _userFromToken(token, email)
                : {'role': 'student', 'email': email});
        if (token != null) await saveToken(token);
        await saveUser(user);
        return {'access_token': token ?? '', 'user': user};
      }

      throw Exception('Unexpected response format');
    }

    final data = _safeDecode(res);
    throw Exception(data['detail'] ?? 'Registration failed');
  }

  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final res = await _postWithRetry(
      Uri.parse('$baseUrl/auth/login'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    );

    print("LOGIN STATUS: ${res.statusCode}");
    print("LOGIN BODY: ${res.body}");

    if (res.statusCode == 200) {
      final data = _safeDecode(res);

      // Plain string token
      if (data is String) {
        await saveToken(data);
        final user = _userFromToken(data, email);
        await saveUser(user);
        return {'access_token': data, 'user': user};
      }

      // Object response
      if (data is Map<String, dynamic>) {
        final token = data['access_token'] as String?;
        final user = data['user'] as Map<String, dynamic>? ??
            (token != null
                ? _userFromToken(token, email)
                : {'role': 'student', 'email': email});
        if (token != null) await saveToken(token);
        await saveUser(user);
        return {'access_token': token ?? '', 'user': user};
      }

      throw Exception('Unexpected response format');
    }

    final data = _safeDecode(res);
    throw Exception(data['detail'] ?? 'Login failed');
  }

  static Future<Map<String, dynamic>> voiceLogin(File voiceFile) async {
    Exception? lastError;
    for (int i = 0; i < _maxRetries; i++) {
      try {
        final req = http.MultipartRequest(
          'POST',
          Uri.parse('$baseUrl/auth/voice-login'),
        )..files
            .add(await http.MultipartFile.fromPath('voice', voiceFile.path));

        final streamed = await req.send().timeout(_timeout);
        final body = await streamed.stream.bytesToString();

        print("VOICE LOGIN STATUS: ${streamed.statusCode}");
        print("VOICE LOGIN BODY: $body");

        if (streamed.statusCode == 200) {
          final data = jsonDecode(body);

          // Plain string token
          if (data is String) {
            await saveToken(data);
            final user = _userFromToken(data, '');
            await saveUser(user);
            return {'access_token': data, 'user': user};
          }

          // Object response
          if (data is Map<String, dynamic>) {
            final token = data['access_token'] as String?;
            final user = data['user'] as Map<String, dynamic>? ??
                (token != null
                    ? _userFromToken(token, '')
                    : {'role': 'student'});
            if (token != null) await saveToken(token);
            await saveUser(user);
            return {'access_token': token ?? '', 'user': user};
          }

          throw Exception('Unexpected response format');
        }

        final errData = jsonDecode(body);
        throw Exception(errData['detail'] ?? 'Voice login failed');
      } catch (e) {
        lastError = Exception(e.toString());
        if (i < _maxRetries - 1) {
          await Future.delayed(Duration(seconds: 2 * (i + 1)));
        }
      }
    }
    throw lastError ??
        Exception('Voice login failed after $_maxRetries retries');
  }

  static Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final res = await _postWithRetry(
      Uri.parse('$baseUrl/auth/change-password'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'current_password': currentPassword,
        'new_password': newPassword,
      }),
    );

    final data = _safeDecode(res);

    if (res.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Password change failed');
    }
  }

  // ────────────────────────────────────────────────
  // ADMIN
  // ────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> adminListUsers() async {
    final res = await _getWithRetry(
      Uri.parse('$baseUrl/admin/users'),
      headers: await _authHeaders(),
    );

    final data = _safeDecode(res);

    if (res.statusCode == 200) {
      return List<Map<String, dynamic>>.from(data);
    }

    throw Exception('Could not load users');
  }

  static Future<void> adminDeleteUser(String userId) async {
    Exception? lastError;
    for (int i = 0; i < _maxRetries; i++) {
      try {
        final res = await http
            .delete(
              Uri.parse('$baseUrl/admin/users/$userId'),
              headers: await _authHeaders(),
            )
            .timeout(_timeout);

        if (res.statusCode == 204) return;

        final data = _safeDecode(res);
        throw Exception(data['detail'] ?? 'Delete failed');
      } catch (e) {
        lastError = Exception(e.toString());
        if (i < _maxRetries - 1) {
          await Future.delayed(Duration(seconds: 2 * (i + 1)));
        }
      }
    }
    throw lastError ?? Exception('Delete failed after $_maxRetries retries');
  }

  static Future<List<Map<String, dynamic>>> adminGetAttendance({
    int limit = 100,
  }) async {
    final res = await _getWithRetry(
      Uri.parse('$baseUrl/admin/attendance?limit=$limit'),
      headers: await _authHeaders(),
    );

    final data = _safeDecode(res);

    if (res.statusCode == 200) {
      return List<Map<String, dynamic>>.from(data);
    }

    throw Exception('Could not load attendance logs');
  }

  static Future<void> adminUpdateRole(
    String userId,
    String role,
  ) async {
    Exception? lastError;
    for (int i = 0; i < _maxRetries; i++) {
      try {
        final res = await http
            .put(
              Uri.parse('$baseUrl/admin/users/$userId/role'),
              headers: await _authHeaders(),
              body: jsonEncode({'role': role}),
            )
            .timeout(_timeout);

        final data = _safeDecode(res);

        if (res.statusCode != 200) {
          throw Exception(data['detail'] ?? 'Role update failed');
        }
        return;
      } catch (e) {
        lastError = Exception(e.toString());
        if (i < _maxRetries - 1) {
          await Future.delayed(Duration(seconds: 2 * (i + 1)));
        }
      }
    }
    throw lastError ??
        Exception('Role update failed after $_maxRetries retries');
  }
}
