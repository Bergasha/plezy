import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/models/plex/plex_community_review.dart';
import 'package:plezy/services/plex_community_service.dart';
import 'package:plezy/utils/media_server_http_client.dart';

void main() {
  group('plexCommunityMetadataId', () {
    test('extracts the id from a movie GUID', () {
      expect(plexCommunityMetadataId('plex://movie/5d9f3ce906d220001febdd28'), '5d9f3ce906d220001febdd28');
    });

    test('extracts the id from a show GUID', () {
      expect(plexCommunityMetadataId('plex://show/5d9c081e6ffe7e001eb08a86'), '5d9c081e6ffe7e001eb08a86');
    });

    test('returns null for null, blank, episode, or agent GUIDs it does not recognize', () {
      expect(plexCommunityMetadataId(null), isNull);
      expect(plexCommunityMetadataId(''), isNull);
      expect(plexCommunityMetadataId('plex://episode/5d9c081e6ffe7e001eb08a86'), isNull);
      expect(plexCommunityMetadataId('com.plexapp.agents.imdb://tt0111161'), isNull);
      expect(plexCommunityMetadataId('plex://movie/'), isNull);
    });
  });

  group('PlexCommunityService.fetchRatingsAndReviews', () {
    test('POSTs the GraphQL operation to community.plex.tv with the account token header', () async {
      http.BaseRequest? capturedRequest;
      String? capturedBody;

      final http_ = MediaServerHttpClient(
        client: MockClient((request) async {
          capturedRequest = request;
          capturedBody = request.body;
          return http.Response(
            jsonEncode(_ratingsAndReviewsPayload()),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(http_.close);

      final service = PlexCommunityService.forTesting(http: http_);
      addTearDown(service.dispose);

      final result = await service.fetchRatingsAndReviews(accountToken: 'acct-token', metadataId: 'meta-1');

      expect(capturedRequest!.method, 'POST');
      expect(capturedRequest!.url.toString(), 'https://community.plex.tv/api');
      expect(capturedRequest!.headers['x-plex-token'], 'acct-token');

      final decodedBody = jsonDecode(capturedBody!) as Map<String, dynamic>;
      expect(decodedBody['operationName'], 'getRatingsAndReviewsHubData');
      expect(decodedBody['variables'], {'metadataID': 'meta-1'});
      expect(decodedBody['query'], contains('getRatingsAndReviewsHubData'));

      expect(result.reviews, hasLength(2));
      expect(result.reviews.map((r) => r.id), containsAll(['top-1', 'friend-1']));
    });

    test('excludes entries with no message (rating-only activity)', () async {
      final http_ = MediaServerHttpClient(
        client: MockClient(
          (request) async =>
              http.Response(jsonEncode(_ratingsAndReviewsPayload()), 200, headers: {'content-type': 'application/json'}),
        ),
      );
      addTearDown(http_.close);

      final service = PlexCommunityService.forTesting(http: http_);
      addTearDown(service.dispose);

      final result = await service.fetchRatingsAndReviews(accountToken: 'acct-token', metadataId: 'meta-1');

      // The fixture includes a rating-only ActivityRating (id rating-only-1)
      // with no `message` — it must not appear in the returned list.
      expect(result.reviews.any((r) => r.id == 'rating-only-1'), isFalse);
    });

    test('dedupes an activity that appears in more than one result set', () async {
      final http_ = MediaServerHttpClient(
        client: MockClient(
          (request) async =>
              http.Response(jsonEncode(_ratingsAndReviewsPayload()), 200, headers: {'content-type': 'application/json'}),
        ),
      );
      addTearDown(http_.close);

      final service = PlexCommunityService.forTesting(http: http_);
      addTearDown(service.dispose);

      final result = await service.fetchRatingsAndReviews(accountToken: 'acct-token', metadataId: 'meta-1');

      // top-1 appears in both userReview and topReviews.nodes in the fixture.
      expect(result.reviews.where((r) => r.id == 'top-1'), hasLength(1));
    });
  });

  group('PlexRatingsAndReviews.fromGraphQLResponse', () {
    test('parses star rating, message, reactions, and reviewer identity', () {
      final result = PlexRatingsAndReviews.fromGraphQLResponse(_ratingsAndReviewsPayload());
      final review = result.reviews.firstWhere((r) => r.id == 'top-1');

      expect(review.displayName, 'Alice');
      expect(review.starRating, 4.0); // reviewRating 8 / 2
      expect(review.message, 'Loved every minute of it.');
      expect(review.reactionsCount, 23);
      expect(review.reactionsTypes, ['LIKE', 'LOVE']);
      expect(review.avatarUrl, 'https://plex.tv/avatar/alice.png');
    });

    test('falls back to username when displayName is blank', () {
      final result = PlexRatingsAndReviews.fromGraphQLResponse(_ratingsAndReviewsPayload());
      final review = result.reviews.firstWhere((r) => r.id == 'friend-1');

      expect(review.displayName, 'bobby_username');
    });

    test('returns empty for a malformed/missing data envelope', () {
      expect(PlexRatingsAndReviews.fromGraphQLResponse({}).isEmpty, isTrue);
      expect(PlexRatingsAndReviews.fromGraphQLResponse({'data': null}).isEmpty, isTrue);
    });
  });
}

/// Realistic fixture mirroring the shape captured from a live
/// community.plex.tv response for `getRatingsAndReviewsHubData`.
Map<String, dynamic> _ratingsAndReviewsPayload() => {
  'data': {
    'userReview': {
      '__typename': 'ActivityReview',
      'id': 'top-1',
      'date': '2025-04-20T12:00:00.000Z',
      'reactionsCount': '23',
      'reactionsTypes': ['LIKE', 'LOVE'],
      'reviewRating': 8,
      'message': 'Loved every minute of it.',
      'hasSpoilers': false,
      'userV2': {'id': 'u1', 'username': 'alice_username', 'displayName': 'Alice', 'avatar': 'https://plex.tv/avatar/alice.png'},
    },
    'friendReviews': {
      'nodes': [
        {
          '__typename': 'ActivityWatchReview',
          'id': 'friend-1',
          'date': '2025-06-01T08:30:00.000Z',
          'reactionsCount': '0',
          'reactionsTypes': <String>[],
          'reviewRating': 5,
          'message': 'Pretty good, a bit slow in the middle.',
          'hasSpoilers': true,
          'userV2': {'id': 'u2', 'username': 'bobby_username', 'displayName': '', 'avatar': null},
        },
      ],
    },
    'topReviews': {
      'nodes': [
        {
          '__typename': 'ActivityReview',
          'id': 'top-1',
          'date': '2025-04-20T12:00:00.000Z',
          'reactionsCount': '23',
          'reactionsTypes': ['LIKE', 'LOVE'],
          'reviewRating': 8,
          'message': 'Loved every minute of it.',
          'hasSpoilers': false,
          'userV2': {'id': 'u1', 'username': 'alice_username', 'displayName': 'Alice', 'avatar': 'https://plex.tv/avatar/alice.png'},
        },
        {
          '__typename': 'ActivityRating',
          'id': 'rating-only-1',
          'date': '2025-05-01T00:00:00.000Z',
          'reactionsCount': '0',
          'reactionsTypes': <String>[],
          'rating': 10,
          'userV2': {'id': 'u3', 'username': 'carol_username', 'displayName': 'Carol', 'avatar': null},
        },
      ],
    },
  },
};
