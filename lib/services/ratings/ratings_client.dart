import '../../models/ratings/media_vote.dart';
import 'ratings_http_client.dart';
import 'ratings_service_endpoint.dart';

/// Talks to one self-hosted plezy-ratings instance. Every call needs the
/// caller's own live Plex account token, supplied fresh per call (never
/// cached here), the same pattern `SeerrClient`'s token supplier uses.
class RatingsClient {
  final RatingsServiceEndpoint endpoint;
  final RatingsHttpClient _http;

  RatingsClient({required this.endpoint, RatingsHttpClient? httpClient})
    : _http = httpClient ?? RatingsHttpClient(endpoint: endpoint);

  void dispose() => _http.dispose();

  /// Cast, change, or (direction == null) clear the caller's own vote on one
  /// item. Returns the item's updated aggregate.
  Future<VoteAggregate> vote({
    required String plexToken,
    required String serverId,
    required String ratingKey,
    required VoteDirection? direction,
  }) async {
    final res = await _http.send(
      'POST',
      endpoint.voteUri,
      plexToken: plexToken,
      body: {'server_id': serverId, 'rating_key': ratingKey, 'direction': direction?.wireValue},
    );
    RatingsHttpClient.throwForStatus(res);
    return VoteAggregate.fromJson(res.data as Map<String, dynamic>);
  }

  /// Batch aggregate lookup for a page of visible cards. [ratingKeys] should
  /// stay well under the service's own cap (200 per call as of writing);
  /// callers page larger sets themselves.
  Future<Map<String, VoteAggregate>> votesFor({
    required String plexToken,
    required String serverId,
    required Iterable<String> ratingKeys,
  }) async {
    final keys = ratingKeys.toList();
    if (keys.isEmpty) return const {};

    final uri = endpoint.votesUri.replace(queryParameters: {'server_id': serverId, 'rating_keys': keys.join(',')});
    final res = await _http.send('GET', uri, plexToken: plexToken);
    RatingsHttpClient.throwForStatus(res);
    final data = res.data as Map<String, dynamic>? ?? const {};
    return data.map((key, value) => MapEntry(key, VoteAggregate.fromJson(value as Map<String, dynamic>)));
  }
}
