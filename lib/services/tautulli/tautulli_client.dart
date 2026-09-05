import 'package:http/http.dart' as http;

import '../../models/tautulli/tautulli_session.dart';
import '../../utils/abortable_http_request.dart';
import '../../utils/app_logger.dart';
import '../../utils/platform_http_client_stub.dart'
    if (dart.library.io) '../../utils/platform_http_client_io.dart'
    as platform;
import '../trackers/tracker_http_client.dart';

const _requestTimeout = Duration(seconds: 10);

class TautulliApiException implements Exception {
  final String message;
  const TautulliApiException(this.message);

  @override
  String toString() => 'TautulliApiException: $message';
}

/// Thin client for the small slice of Tautulli's `/api/v2` this app uses —
/// just `get_activity`, for the admin-only active-streams panel. The API key
/// is a query parameter (Tautulli's own convention, not a header), and lives
/// only in this device's local Settings — never sent anywhere but the user's
/// own Tautulli instance.
class TautulliClient {
  final String baseUrl;
  final String apiKey;
  final http.Client _http;

  TautulliClient({required this.baseUrl, required this.apiKey, http.Client? httpClient})
    : _http = httpClient ?? platform.createPlatformClient();

  void dispose() => _http.close();

  Future<List<TautulliSession>> getActivity() async {
    // String-concatenated rather than Uri.resolve: baseUrl may carry a path
    // prefix (a reverse-proxied Tautulli under a subpath), and an
    // absolute-path resolve would silently drop it.
    final uri = Uri.parse('$baseUrl/api/v2').replace(queryParameters: {'apikey': apiKey, 'cmd': 'get_activity'});
    final response = await sendAbortableHttpRequest(
      _http,
      'GET',
      uri,
      headers: const {'Accept': 'application/json'},
      timeout: _requestTimeout,
      operation: 'Tautulli get_activity',
    );
    appLogger.d('Tautulli get_activity -> ${response.statusCode}');

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TautulliApiException('HTTP ${response.statusCode}');
    }

    final decoded = TrackerHttpClient.decodeJson(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const TautulliApiException('Unexpected response shape');
    }
    final apiResponse = decoded['response'];
    if (apiResponse is! Map<String, dynamic>) {
      throw const TautulliApiException('Missing response object');
    }
    if (apiResponse['result'] != 'success') {
      throw TautulliApiException((apiResponse['message'] as String?) ?? 'Tautulli reported an error');
    }
    final data = apiResponse['data'];
    if (data is! Map<String, dynamic>) {
      throw const TautulliApiException('Missing response data');
    }
    final sessions = data['sessions'];
    if (sessions is! List) return const [];

    return sessions.whereType<Map<String, dynamic>>().map(TautulliSession.fromJson).toList();
  }
}
