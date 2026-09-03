/// Canonical HTTP(S) base endpoint for a self-hosted plezy-ratings service.
///
/// [defaultEndpoint] points at this fork's own instance — same pattern as
/// the Watch Together relay's default, except this one isn't upstream's
/// shared infrastructure, it's the fork owner's. Every plezy install shares
/// votes through it unless overridden in Settings, so friends get working
/// vote buttons with no setup.
final class RatingsServiceEndpoint {
  RatingsServiceEndpoint._(this._baseUri);

  static const String defaultBaseUrl = 'https://plezy-ratings.shayno.net';

  static final RatingsServiceEndpoint defaultEndpoint = RatingsServiceEndpoint._(Uri.parse(defaultBaseUrl));

  final Uri _baseUri;

  String get canonicalBaseUrl => _baseUri.toString();

  Uri get healthUri => _appendPathSegment('health');
  Uri get voteUri => _appendPathSegment('api/vote');
  Uri get votesUri => _appendPathSegment('api/votes');

  /// [defaultEndpoint] when [value] is unset/blank; a parsed override
  /// otherwise, or null if [value] doesn't parse as a valid base URL.
  static RatingsServiceEndpoint? resolve(String? value) {
    if (value == null || value.trim().isEmpty) return defaultEndpoint;
    return tryParseCustom(value);
  }

  static RatingsServiceEndpoint? tryParseCustom(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    final Uri uri;
    try {
      uri = Uri.parse(trimmed);
      if (uri.hasPort && (uri.port < 1 || uri.port > 65535)) {
        return null;
      }
    } on FormatException {
      return null;
    }

    if ((uri.scheme != 'http' && uri.scheme != 'https') ||
        !uri.isAbsolute ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }

    final normalized = uri.normalizePath();
    var path = normalized.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    final hasDefaultPort =
        normalized.hasPort &&
        ((normalized.scheme == 'http' && normalized.port == 80) ||
            (normalized.scheme == 'https' && normalized.port == 443));
    final canonical = Uri(
      scheme: normalized.scheme,
      host: normalized.host,
      port: normalized.hasPort && !hasDefaultPort ? normalized.port : null,
      path: path,
    );
    return RatingsServiceEndpoint._(canonical);
  }

  Uri _appendPathSegment(String segment) {
    final prefix = _baseUri.path;
    return _baseUri.replace(path: '$prefix/$segment');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is RatingsServiceEndpoint && other.canonicalBaseUrl == canonicalBaseUrl;

  @override
  int get hashCode => canonicalBaseUrl.hashCode;

  @override
  String toString() => canonicalBaseUrl;
}
