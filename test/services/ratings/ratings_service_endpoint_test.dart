import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/ratings/ratings_service_endpoint.dart';

void main() {
  group('RatingsServiceEndpoint.resolve', () {
    test('unset/blank falls back to the fork-wide default endpoint', () {
      expect(RatingsServiceEndpoint.resolve(null), RatingsServiceEndpoint.defaultEndpoint);
      expect(RatingsServiceEndpoint.resolve(''), RatingsServiceEndpoint.defaultEndpoint);
      expect(RatingsServiceEndpoint.resolve('   '), RatingsServiceEndpoint.defaultEndpoint);
    });

    test('a valid URL resolves to an endpoint', () {
      final endpoint = RatingsServiceEndpoint.resolve('https://ratings.example.com');
      expect(endpoint, isNotNull);
      expect(endpoint!.canonicalBaseUrl, 'https://ratings.example.com');
    });

    test('an invalid URL resolves to null rather than throwing', () {
      expect(RatingsServiceEndpoint.resolve('not a url'), isNull);
    });
  });

  group('RatingsServiceEndpoint.tryParseCustom', () {
    test('strips a trailing slash and default port', () {
      final endpoint = RatingsServiceEndpoint.tryParseCustom('https://ratings.example.com:443/');
      expect(endpoint!.canonicalBaseUrl, 'https://ratings.example.com');
    });

    test('keeps a non-default port', () {
      final endpoint = RatingsServiceEndpoint.tryParseCustom('http://192.168.1.5:8090');
      expect(endpoint!.canonicalBaseUrl, 'http://192.168.1.5:8090');
    });

    test('rejects a non-http(s) scheme', () {
      expect(RatingsServiceEndpoint.tryParseCustom('ftp://example.com'), isNull);
    });

    test('rejects a URL with userinfo, query, or fragment', () {
      expect(RatingsServiceEndpoint.tryParseCustom('https://user:pass@example.com'), isNull);
      expect(RatingsServiceEndpoint.tryParseCustom('https://example.com?x=1'), isNull);
      expect(RatingsServiceEndpoint.tryParseCustom('https://example.com#frag'), isNull);
    });

    test('rejects an out-of-range port', () {
      expect(RatingsServiceEndpoint.tryParseCustom('https://example.com:99999'), isNull);
    });
  });

  group('RatingsServiceEndpoint route URIs', () {
    test('appends the health/vote/votes paths under the configured base', () {
      final endpoint = RatingsServiceEndpoint.resolve('https://ratings.example.com/proxy')!;
      expect(endpoint.healthUri.toString(), 'https://ratings.example.com/proxy/health');
      expect(endpoint.voteUri.toString(), 'https://ratings.example.com/proxy/api/vote');
      expect(endpoint.votesUri.toString(), 'https://ratings.example.com/proxy/api/votes');
    });
  });

  group('RatingsServiceEndpoint equality', () {
    test('two endpoints with the same canonical URL are equal', () {
      final a = RatingsServiceEndpoint.resolve('https://ratings.example.com/')!;
      final b = RatingsServiceEndpoint.resolve('https://ratings.example.com')!;
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
