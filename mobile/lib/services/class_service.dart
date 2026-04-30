import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class ClassService {
  static const String baseUrl = "https://VoiceAndroid-backend.onrender.com";

  static Future<Map<String, String>> _headers() async {
    final token = await AuthService.getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Safely decodes a response body, throwing a readable error if the
  /// server returned HTML (e.g. a 500 crash page) instead of JSON.
  static dynamic _decode(http.Response res) {
    final contentType = res.headers['content-type'] ?? '';
    if (!contentType.contains('application/json')) {
      throw Exception(
          'Server error (${res.statusCode}) — backend returned non-JSON. Check Render logs.');
    }
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> createClass(String name) async {
    final res = await http.post(
      Uri.parse('$baseUrl/classes/create'),
      headers: await _headers(),
      body: jsonEncode({'name': name}),
    );
    final data = _decode(res);
    if (res.statusCode == 201) return Map<String, dynamic>.from(data);
    throw Exception(data['detail'] ?? 'Failed to create class');
  }

  /// Sends a join request — teacher must approve before student is enrolled.
  static Future<String> joinClass(String code) async {
    final res = await http.post(
      Uri.parse('$baseUrl/classes/join'),
      headers: await _headers(),
      body: jsonEncode({'code': code.toUpperCase()}),
    );
    final data = _decode(res);
    if (res.statusCode == 200) {
      return data['message'] ?? 'Join request sent';
    }
    throw Exception(data['detail'] ?? 'Failed to send join request');
  }

  static Future<List<Map<String, dynamic>>> getMyClasses() async {
    final res = await http.get(
      Uri.parse('$baseUrl/classes/my-classes'),
      headers: await _headers(),
    );
    final data = _decode(res);
    if (res.statusCode == 200) {
      return List<Map<String, dynamic>>.from(data);
    }
    throw Exception(data['detail'] ?? 'Failed to load classes');
  }

  /// Teacher: get all pending requests across all their classes.
  static Future<List<Map<String, dynamic>>> getAllPendingRequests() async {
    final res = await http.get(
      Uri.parse('$baseUrl/classes/requests'),
      headers: await _headers(),
    );
    final data = _decode(res);
    if (res.statusCode == 200) {
      return List<Map<String, dynamic>>.from(data);
    }
    throw Exception(data['detail'] ?? 'Failed to load requests');
  }

  /// Teacher: get pending requests for a specific class.
  static Future<List<Map<String, dynamic>>> getClassRequests(
      int classId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/classes/$classId/requests'),
      headers: await _headers(),
    );
    final data = _decode(res);
    if (res.statusCode == 200) {
      return List<Map<String, dynamic>>.from(data);
    }
    throw Exception(data['detail'] ?? 'Failed to load requests');
  }

  static Future<void> approveRequest(int classId, int studentId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/classes/$classId/requests/$studentId/approve'),
      headers: await _headers(),
    );
    if (res.statusCode != 200) {
      final data = _decode(res);
      throw Exception(data['detail'] ?? 'Failed to approve');
    }
  }

  static Future<void> declineRequest(int classId, int studentId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/classes/$classId/requests/$studentId/decline'),
      headers: await _headers(),
    );
    if (res.statusCode != 200) {
      final data = _decode(res);
      throw Exception(data['detail'] ?? 'Failed to decline');
    }
  }

  static Future<List<Map<String, dynamic>>> getMembers(int classId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/classes/$classId/members'),
      headers: await _headers(),
    );
    final data = _decode(res);
    if (res.statusCode == 200) {
      return List<Map<String, dynamic>>.from(data);
    }
    throw Exception(data['detail'] ?? 'Failed to load members');
  }

  static Future<List<Map<String, dynamic>>> getClassMembers(int classId) =>
      getMembers(classId);

  static Future<List<Map<String, dynamic>>> getClassAttendance(
      int classId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/classes/$classId/attendance'),
      headers: await _headers(),
    );
    // ✅ Check content-type FIRST — crashes here before if server sent HTML
    final data = _decode(res);
    if (res.statusCode == 200) {
      // ✅ Null-safe: fall back to empty list if 'logs' key is missing
      return List<Map<String, dynamic>>.from(data['logs'] ?? []);
    }
    throw Exception(data['detail'] ?? 'Failed to load attendance');
  }

  static Future<void> checkIn(int classId, String voiceFilePath) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/classes/$classId/checkin'),
    )
      ..headers.addAll(await _headers()
        ..remove('Content-Type'))
      ..files.add(await http.MultipartFile.fromPath('voice', voiceFilePath));

    final streamed = await req.send();
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) {
      // ✅ Guard multipart response too
      final ct = streamed.headers['content-type'] ?? '';
      if (!ct.contains('application/json')) {
        throw Exception(
            'Server error (${streamed.statusCode}) — check Render logs.');
      }
      final data = jsonDecode(body);
      throw Exception(data['detail'] ?? 'Check-in failed');
    }
  }
}
