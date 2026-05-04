import 'api_service.dart';

class ServerWarmupService {
  /// Fire-and-forget warmup
  static Future<void> ping() async {
    try {
      await ApiService.healthCheck();
    } catch (_) {
      // Ignore completely — warmup must never break UI
    }
  }
}
