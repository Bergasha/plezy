import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../utils/abortable_http_request.dart';
import '../../utils/app_logger.dart';
import '../../utils/platform_http_client_stub.dart'
    if (dart.library.io) '../../utils/platform_http_client_io.dart'
    as platform;
import '../trackers/tracker_http_client.dart';
import 'ratings_exceptions.dart';
import 'ratings_service_endpoint.dart';

const _requestTimeout = Duration(seconds: 15);

/// HTTP response paired with its decoded JSON body.
class RatingsResponse {
  final http.Response response;
  final dynamic data;
  const RatingsResponse(this.response, this.data);

  int get statusCode => response.statusCode;
}

/// Thin wrapper over `package:http` for the self-hosted plezy-ratings
/// service, modeled on `SeerrHttpClient` but with no session/cookie state —
/// every request is authenticated by sending the caller's own live Plex
/// token as `X-Plex-Token`, which the service verifies against plex.tv on
/// its side per call (see plezy-ratings' `auth.go`).
class RatingsHttpClient {
  final RatingsServiceEndpoint endpoint;
  final http.Client _http;

  RatingsHttpClient({required this.endpoint, http.Client? httpClient})
    : _http = httpClient ?? platform.createPlatformClient();

  void dispose() => _http.close();

  Future<RatingsResponse> send(
    String method,
    Uri uri, {
    required String plexToken,
    Map<String, Object?>? body,
    Duration timeout = _requestTimeout,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'X-Plex-Token': plexToken,
      if (body != null) 'Content-Type': 'application/json',
    };
    final response = await sendAbortableHttpRequest(
      _http,
      method,
      uri,
      headers: headers,
      body: body == null ? null : jsonEncode(body),
      timeout: timeout,
      operation: 'Ratings $method ${uri.path}',
    );
    appLogger.d('Ratings $method ${uri.path} -> ${response.statusCode}');
    return RatingsResponse(response, TrackerHttpClient.decodeJson(response.body));
  }

  /// Throw the mapped exception for a 4xx/5xx response; no-op on success.
  static void throwForStatus(RatingsResponse res) {
    final code = res.statusCode;
    if (code >= 200 && code < 300) return;
    final data = res.data;
    final message = data is Map<String, dynamic> ? data['error'] as String? : null;
    throw RatingsApiException((message?.isNotEmpty ?? false) ? message! : 'HTTP $code', statusCode: code);
  }
}
