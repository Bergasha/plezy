/// Non-2xx response from the ratings service, with the server's own message
/// when it sent one (e.g. "no access to that Plex server").
class RatingsApiException implements Exception {
  final String message;
  final int statusCode;
  const RatingsApiException(this.message, {required this.statusCode});

  @override
  String toString() => 'RatingsApiException($statusCode): $message';
}
