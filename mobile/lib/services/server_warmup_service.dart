import 'package:http/http.dart' as http;
import '/config/api_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  ServerWarmupService
//  Location: mobile/lib/services/server_warmup_service.dart
//
//  Fires a silent GET /health to your FastAPI backend the moment a screen
//  loads.  By the time the student finishes their 3-second recording the
//  Render free-tier dyno is already awake, eliminating cold-start timeouts.
//
//  Call it in any screen's initState where voice check-in happens:
//
//    @override
//    void initState() {
//      super.initState();
//      ServerWarmupService.ping(); // fire-and-forget
//    }
// ─────────────────────────────────────────────────────────────────────────────

class ServerWarmupService {
  // ── Change this to your real Render URL ─────────────────────────────────
  // URL comes from ApiConfig — update api_config.dart if the backend changes.

  /// Fire-and-forget.  Never throws, never blocks the UI.
  static Future<void> ping() async {
    try {
      await http
          .get(Uri.parse('${ApiConfig.baseUrl}/health'))
          .timeout(const Duration(seconds: 60));
      // Response body is ignored — we only care that the dyno woke up.
    } catch (_) {
      // Swallowed intentionally.  If the ping fails the real request
      // will still work (or show the retry snackbar as a fallback).
    }
  }
}