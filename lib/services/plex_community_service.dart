import 'package:flutter/foundation.dart';

import '../models/plex/plex_community_review.dart';
import '../utils/media_server_http_client.dart';
import '../utils/media_server_timeouts.dart';

/// Client for Plex's community GraphQL API (`community.plex.tv`) — fan
/// ratings & reviews, distinct from both the per-server Plex Media Server API
/// ([PlexClient]) and the plex.tv account API ([PlexAuthService]).
///
/// Auth is the plex.tv **account-level** token (`x-plex-token` header), never
/// a per-server access token — community.plex.tv doesn't know about
/// individual servers. Standalone [MediaServerHttpClient] instance, mirroring
/// [PlexAuthService]'s pattern for plex.tv-hosted (as opposed to
/// server-hosted) calls.
class PlexCommunityService {
  static const String _apiBase = 'https://community.plex.tv/api';

  final MediaServerHttpClient _http;

  PlexCommunityService._(this._http);

  @visibleForTesting
  PlexCommunityService.forTesting({required MediaServerHttpClient http}) : _http = http;

  static Future<PlexCommunityService> create() async {
    return PlexCommunityService._(
      MediaServerHttpClient(
        connectTimeout: MediaServerTimeouts.plexTvConnect,
        receiveTimeout: MediaServerTimeouts.plexTvReceive,
      ),
    );
  }

  /// Close the underlying HTTP client. Call when the service is short-lived
  /// (created for a single screen visit) to avoid leaking sockets.
  void dispose() => _http.close();

  /// Fetch the "Ratings & Reviews" hub data for a movie/show identified by
  /// its Plex community [metadataId] — the id portion of the item's
  /// `plex://movie/<id>` or `plex://show/<id>` GUID (see
  /// [plexCommunityMetadataId]).
  ///
  /// [accountToken] must be a plex.tv account token, not a per-server access
  /// token — see the class doc.
  Future<PlexRatingsAndReviews> fetchRatingsAndReviews({
    required String accountToken,
    required String metadataId,
  }) async {
    final response = await _http.post(
      _apiBase,
      headers: {'Accept': 'application/json', 'Content-Type': 'application/json', 'x-plex-token': accountToken},
      body: {
        'operationName': 'getRatingsAndReviewsHubData',
        'query': _ratingsAndReviewsQuery,
        'variables': {'metadataID': metadataId},
      },
      timeout: MediaServerTimeouts.plexTvReceive,
    );

    throwIfHttpError(response);

    final data = response.data;
    if (data is! Map) return PlexRatingsAndReviews.empty;
    return PlexRatingsAndReviews.fromGraphQLResponse(Map<String, Object?>.from(data));
  }
}

/// Extracts the community-API metadata id from a Plex GUID of the form
/// `plex://movie/<id>` or `plex://show/<id>` (i.e. [MediaItem.guid]). Returns
/// null when [guid] is null/blank or doesn't match either prefix — e.g.
/// episodes, or items whose GUID uses a different agent.
String? plexCommunityMetadataId(String? guid) {
  if (guid == null || guid.isEmpty) return null;
  const prefixes = ['plex://movie/', 'plex://show/'];
  for (final prefix in prefixes) {
    if (guid.startsWith(prefix)) {
      final id = guid.substring(prefix.length);
      return id.isEmpty ? null : id;
    }
  }
  return null;
}

/// GraphQL document for the `getRatingsAndReviewsHubData` operation, captured
/// verbatim from a live Network-tab session against community.plex.tv — do
/// not modify the field selections, only reuse as-is.
const String _ratingsAndReviewsQuery = r'''
query getRatingsAndReviewsHubData($metadataID: ID!, $skipUserState: Boolean = false) {
  userReview: metadataReviewV2(
    metadata: {id: $metadataID}
    ignoreFutureMetadata: true
  ) {
    ... on ActivityRating {
      ...ActivityRatingFragment
    }
    ... on ActivityWatchRating {
      ...ActivityWatchRatingFragment
    }
    ... on ActivityReview {
      ...ActivityReviewFragment
    }
    ... on ActivityWatchReview {
      ...ActivityWatchReviewFragment
    }
  }
  friendReviews: metadataReviewsV2(
    metadata: {id: $metadataID}
    type: FRIENDS
    first: 25
    after: null
    last: null
    before: null
  ) {
    nodes {
      ... on ActivityRating {
        ...ActivityRatingFragment
      }
      ... on ActivityReview {
        ...ActivityReviewFragment
      }
      ... on ActivityWatchRating {
        ...ActivityWatchRatingFragment
      }
      ... on ActivityWatchReview {
        ...ActivityWatchReviewFragment
      }
    }
  }
  topReviews: metadataReviewsV2(
    metadata: {id: $metadataID}
    type: TOP
    first: 25
    after: null
    last: null
    before: null
  ) {
    nodes {
      ... on ActivityRating {
        ...ActivityRatingFragment
      }
      ... on ActivityReview {
        ...ActivityReviewFragment
      }
      ... on ActivityWatchRating {
        ...ActivityWatchRatingFragment
      }
      ... on ActivityWatchReview {
        ...ActivityWatchReviewFragment
      }
    }
  }
}

fragment ActivityRatingFragment on ActivityRating {
  ...activityFragment
  rating
}

fragment activityFragment on Activity {
  __typename
  commentCount
  date
  id
  isMuted
  isPrimary
  privacy
  reaction
  reactionsCount
  reactionsTypes
  metadataItem {
    ...itemFields
  }
  userV2 {
    id
    username
    displayName
    avatar
    friendStatus
    isMuted
    isHidden
    isBlocked
    mutualFriends {
      count
      friends {
        avatar
        displayName
        id
        username
      }
    }
  }
}

fragment itemFields on MetadataItem {
  id
  images {
    coverArt
    coverPoster
    thumbnail
    art
  }
  userState @skip(if: $skipUserState) {
    viewCount
    viewedLeafCount
    watchlistedAt
  }
  title
  key
  type
  index
  publicPagesURL
  parent {
    ...parentFields
  }
  grandparent {
    ...parentFields
  }
  publishedAt
  leafCount
  year
  originallyAvailableAt
  childCount
}

fragment parentFields on MetadataItem {
  index
  title
  publishedAt
  key
  type
  images {
    coverArt
    coverPoster
    thumbnail
    art
  }
  userState @skip(if: $skipUserState) {
    viewCount
    viewedLeafCount
    watchlistedAt
  }
}

fragment ActivityWatchRatingFragment on ActivityWatchRating {
  ...activityFragment
  rating
}

fragment ActivityReviewFragment on ActivityReview {
  ...activityFragment
  reviewRating: rating
  hasSpoilers
  message
  updatedAt
  status
  updatedAt
}

fragment ActivityWatchReviewFragment on ActivityWatchReview {
  ...activityFragment
  reviewRating: rating
  hasSpoilers
  message
  updatedAt
  status
  updatedAt
}
''';
