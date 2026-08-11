/// A single fan rating/review returned by Plex's community GraphQL API
/// (`community.plex.tv`), as opposed to third-party critic reviews (Rotten
/// Tomatoes etc.) surfaced elsewhere in the app.
///
/// Maps the `ActivityReview`/`ActivityWatchReview`/`ActivityRating`/
/// `ActivityWatchRating` union returned by the `getRatingsAndReviewsHubData`
/// operation. Only entries that carry [message] are useful for the
/// snippet-card UI; star-only entries are still parsed (callers may want the
/// rating alone) but [PlexRatingsAndReviews.fromGraphQLResponse] filters them
/// out of the list it returns.
class PlexCommunityReview {
  /// Activity id, unique within a response. Used as a dedupe key when the
  /// same review appears in more than one of the query's three result sets
  /// (the current user's own review, friends', and top reviews).
  final String id;

  /// GraphQL `__typename` of the underlying activity
  /// (`ActivityReview`/`ActivityWatchReview`/`ActivityRating`/`ActivityWatchRating`).
  final String typename;

  /// Reviewer's display name, falling back to their username. Empty when the
  /// API supplied neither — callers should substitute a generic label.
  final String displayName;

  /// Reviewer's avatar image URL, or null when absent/blank.
  final String? avatarUrl;

  /// When the review/rating was posted.
  final DateTime? date;

  /// Star rating on a 0-5 scale (halved from the API's 0-10 `rating`), or
  /// null when the entry carries no rating.
  final double? starRating;

  /// Review body text, or null for rating-only entries (or when blank).
  final String? message;

  /// Whether the reviewer flagged their own text as containing spoilers.
  final bool hasSpoilers;

  /// Total reaction count across all reaction types.
  final int reactionsCount;

  /// Reaction type keys present on this entry (e.g. `LIKE`, `LOVE`).
  final List<String> reactionsTypes;

  const PlexCommunityReview({
    required this.id,
    required this.typename,
    required this.displayName,
    this.avatarUrl,
    this.date,
    this.starRating,
    this.message,
    this.hasSpoilers = false,
    this.reactionsCount = 0,
    this.reactionsTypes = const [],
  });

  /// Whether this entry has review text suitable for the snippet-card UI.
  bool get hasText => message != null && message!.isNotEmpty;

  factory PlexCommunityReview.fromJson(Map<String, Object?> json) {
    final userV2 = json['userV2'];
    final user = userV2 is Map ? Map<String, Object?>.from(userV2) : const <String, Object?>{};

    final rawDisplayName = (user['displayName'] as String?)?.trim();
    final rawUsername = (user['username'] as String?)?.trim();
    final displayName = (rawDisplayName != null && rawDisplayName.isNotEmpty)
        ? rawDisplayName
        : (rawUsername ?? '');

    final rawAvatar = (user['avatar'] as String?)?.trim();
    final avatarUrl = (rawAvatar != null && rawAvatar.isNotEmpty) ? rawAvatar : null;

    final date = DateTime.tryParse(json['date'] as String? ?? '');

    // `reviewRating` is the aliased field name on the review fragments;
    // `rating` is used on the rating-only fragments. Both carry a 0-10 int.
    final rawRating = json['reviewRating'] ?? json['rating'];
    final ratingValue = switch (rawRating) {
      final num n => n.toDouble(),
      final String s => double.tryParse(s),
      _ => null,
    };
    final starRating = ratingValue == null ? null : ratingValue / 2.0;

    final rawMessage = (json['message'] as String?)?.trim();
    final message = (rawMessage != null && rawMessage.isNotEmpty) ? rawMessage : null;

    final rawReactionsCount = json['reactionsCount'];
    final reactionsCount = switch (rawReactionsCount) {
      final num n => n.toInt(),
      final String s => int.tryParse(s) ?? 0,
      _ => 0,
    };

    final rawReactionsTypes = json['reactionsTypes'];
    final reactionsTypes = rawReactionsTypes is List
        ? rawReactionsTypes.whereType<String>().toList(growable: false)
        : const <String>[];

    return PlexCommunityReview(
      id: json['id']?.toString() ?? '',
      typename: json['__typename'] as String? ?? '',
      displayName: displayName,
      avatarUrl: avatarUrl,
      date: date,
      starRating: starRating,
      message: message,
      hasSpoilers: json['hasSpoilers'] == true,
      reactionsCount: reactionsCount,
      reactionsTypes: reactionsTypes,
    );
  }
}

/// Parsed result of the `getRatingsAndReviewsHubData` GraphQL operation:
/// the current user's own review (if any), friends' reviews, and top
/// (community-wide) reviews, merged into one deduplicated, text-only list
/// suitable for the "Ratings & Reviews" snippet-card row.
class PlexRatingsAndReviews {
  /// Reviews with non-empty [PlexCommunityReview.message], deduplicated by
  /// id, in display order: the current user's own review first (if it has
  /// text), then top reviews, then friends' reviews.
  final List<PlexCommunityReview> reviews;

  const PlexRatingsAndReviews({required this.reviews});

  static const empty = PlexRatingsAndReviews(reviews: []);

  bool get isEmpty => reviews.isEmpty;

  bool get isNotEmpty => reviews.isNotEmpty;

  factory PlexRatingsAndReviews.fromGraphQLResponse(Map<String, Object?> json) {
    final data = json['data'];
    if (data is! Map) return empty;
    final dataMap = Map<String, Object?>.from(data);

    final seen = <String>{};
    final result = <PlexCommunityReview>[];

    void addNode(Object? node) {
      if (node is! Map) return;
      final review = PlexCommunityReview.fromJson(Map<String, Object?>.from(node));
      if (!review.hasText) return;
      if (review.id.isNotEmpty && !seen.add(review.id)) return;
      result.add(review);
    }

    addNode(dataMap['userReview']);

    final topReviews = dataMap['topReviews'];
    if (topReviews is Map) {
      final nodes = topReviews['nodes'];
      if (nodes is List) {
        for (final node in nodes) {
          addNode(node);
        }
      }
    }

    final friendReviews = dataMap['friendReviews'];
    if (friendReviews is Map) {
      final nodes = friendReviews['nodes'];
      if (nodes is List) {
        for (final node in nodes) {
          addNode(node);
        }
      }
    }

    return PlexRatingsAndReviews(reviews: result);
  }
}
