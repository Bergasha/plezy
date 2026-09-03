import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/models/ratings/media_vote.dart';
import 'package:plezy/providers/media_votes_provider.dart';
import 'package:plezy/services/ratings/ratings_client.dart';
import 'package:plezy/services/ratings/ratings_exceptions.dart';
import 'package:plezy/services/ratings/ratings_http_client.dart';
import 'package:plezy/services/ratings/ratings_service_endpoint.dart';

http.Response _json(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

MediaVotesProvider _providerWith(Future<http.Response> Function(http.Request) handler, {String token = 'plex-token'}) {
  final endpoint = RatingsServiceEndpoint.resolve('https://ratings.example.com')!;
  final ratingsHttp = RatingsHttpClient(endpoint: endpoint, httpClient: MockClient(handler));
  final client = RatingsClient(endpoint: endpoint, httpClient: ratingsHttp);
  return MediaVotesProvider(plexTokenSupplier: () async => token, testClient: client);
}

void main() {
  group('MediaVotesProvider.isEnabled', () {
    test('is true once a client is supplied for testing', () {
      final provider = _providerWith((r) async => _json({}));
      expect(provider.isEnabled, isTrue);
    });
  });

  group('MediaVotesProvider.ensureLoaded', () {
    test('populates aggregateFor from the batch response', () async {
      final provider = _providerWith((request) async {
        expect(request.url.path, '/api/votes');
        expect(request.url.queryParameters['server_id'], 'srv');
        expect(request.url.queryParameters['rating_keys'], '1,2');
        return _json({
          '1': {'good': 3, 'bad': 1, 'mine': 'good'},
          '2': {'good': 0, 'bad': 0, 'mine': null},
        });
      });

      expect(provider.aggregateFor('srv', '1'), isNull);
      await provider.ensureLoaded('srv', ['1', '2']);

      expect(provider.aggregateFor('srv', '1'), const VoteAggregate(good: 3, bad: 1, mine: VoteDirection.good));
      expect(provider.aggregateFor('srv', '2'), const VoteAggregate());
    });

    test('does not re-fetch keys that are already cached', () async {
      var calls = 0;
      final provider = _providerWith((request) async {
        calls++;
        return _json({
          for (final key in request.url.queryParameters['rating_keys']!.split(','))
            key: {'good': 1, 'bad': 0, 'mine': null},
        });
      });

      await provider.ensureLoaded('srv', ['1']);
      await provider.ensureLoaded('srv', ['1']);
      expect(calls, 1);

      await provider.ensureLoaded('srv', ['1', '2']);
      expect(calls, 2);
    });

    test('a failed batch leaves the keys uncached rather than assuming zero votes', () async {
      final provider = _providerWith((request) async => http.Response('', 500));
      await provider.ensureLoaded('srv', ['1']);
      expect(provider.aggregateFor('srv', '1'), isNull);
    });
  });

  group('MediaVotesProvider.vote', () {
    test('optimistically flips the cache before the network call resolves', () async {
      final calls = <void>[];
      final provider = _providerWith((request) async {
        calls.add(null);
        // A slow server: aggregateFor must already read the optimistic
        // value before this response arrives.
        await Future<void>.delayed(Duration.zero);
        return _json({'good': 5, 'bad': 2, 'mine': 'good'});
      });

      final future = provider.vote('srv', '1', VoteDirection.good);
      expect(provider.aggregateFor('srv', '1'), const VoteAggregate(good: 1, bad: 0, mine: VoteDirection.good));
      await future;
      expect(provider.aggregateFor('srv', '1'), const VoteAggregate(good: 5, bad: 2, mine: VoteDirection.good));
    });

    test('switching from good to bad moves both counts in one call', () async {
      var calls = 0;
      final provider = _providerWith((request) async {
        calls++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (calls == 1) {
          expect(body['direction'], 'good');
          return _json({'good': 1, 'bad': 0, 'mine': 'good'});
        }
        expect(body['direction'], 'bad');
        return _json({'good': 0, 'bad': 1, 'mine': 'bad'});
      });

      await provider.vote('srv', '1', VoteDirection.good);
      expect(provider.aggregateFor('srv', '1'), const VoteAggregate(good: 1, bad: 0, mine: VoteDirection.good));

      await provider.vote('srv', '1', VoteDirection.bad);
      expect(provider.aggregateFor('srv', '1'), const VoteAggregate(good: 0, bad: 1, mine: VoteDirection.bad));
    });

    test('direction null sends a clearing request', () async {
      final provider = _providerWith((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['direction'], isNull);
        return _json({'good': 0, 'bad': 0, 'mine': null});
      });
      await provider.vote('srv', '1', null);
    });

    test('reverts the optimistic flip and rethrows on failure', () async {
      final provider = _providerWith((request) async => http.Response('{"error":"nope"}', 500));

      await expectLater(provider.vote('srv', '1', VoteDirection.good), throwsA(isA<RatingsApiException>()));
      // Reverted to "no vote" (there was nothing cached beforehand).
      expect(provider.aggregateFor('srv', '1'), const VoteAggregate());
    });

    test('a later successful refresh is not clobbered by a stale revert', () async {
      final provider = _providerWith((request) async {
        if (request.method == 'POST') return http.Response('', 500);
        return _json({
          '1': {'good': 9, 'bad': 0, 'mine': 'good'},
        });
      });

      final voteFuture = provider.vote('srv', '1', VoteDirection.good);
      // Attach the expectation before yielding control (the `await` below)
      // so voteFuture's eventual rejection is always observed — otherwise
      // it can reject unobserved while `refresh` runs, which the test
      // framework reports as an unhandled exception rather than the
      // expected failure.
      final expectation = expectLater(voteFuture, throwsA(isA<RatingsApiException>()));
      // A concurrent refresh (drops the cache entry, then re-fetches) lands
      // a fresh value while the failing vote is still in flight.
      await provider.refresh('srv', ['1']);
      await expectation;

      // The revert must not have stomped the fresher, unrelated value.
      expect(provider.aggregateFor('srv', '1'), const VoteAggregate(good: 9, bad: 0, mine: VoteDirection.good));
    });
  });
}
