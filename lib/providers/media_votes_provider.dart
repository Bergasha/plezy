import 'dart:async';

import 'package:flutter/foundation.dart';

import '../connection/connection_registry.dart';
import '../mixins/disposable_change_notifier_mixin.dart';
import '../models/ratings/media_vote.dart';
import '../profiles/active_plex_token.dart';
import '../profiles/active_profile_provider.dart';
import '../profiles/profile_connection_registry.dart';
import '../services/ratings/ratings_client.dart';
import '../services/ratings/ratings_exceptions.dart';
import '../services/ratings/ratings_service_endpoint.dart';
import '../services/settings_service.dart';
import '../utils/app_logger.dart';

/// Supplies the active profile's live Plex account token for a ratings
/// call. Same shape as `SeerrPlexTokenSupplier` — a plain closure so this
/// provider doesn't need to know how profiles/connections resolve one.
typedef RatingsPlexTokenSupplier = Future<String?> Function();

/// Resolve the active profile's Plex token for ratings calls — identical
/// policy to `buildSeerrPlexTokenSupplier`: the profile's per-user token
/// when a bind exists, else the account token.
RatingsPlexTokenSupplier buildRatingsPlexTokenSupplier({
  required ActiveProfileProvider activeProfile,
  required ConnectionRegistry connections,
  required ProfileConnectionRegistry profileConnections,
}) {
  return () async {
    final resolved = await resolveActivePlexToken(
      activeProfile: activeProfile,
      connections: connections,
      profileConnections: profileConnections,
      allowAccountTokenForHomeUser: true,
    );
    return resolved?.token;
  };
}

/// Shared "good"/"bad" votes on media items, synced through a self-hosted
/// plezy-ratings instance (see `lib/services/ratings/`). On by default
/// against the fork's own instance (`RatingsServiceEndpoint.defaultEndpoint`);
/// Settings > Advanced only needs touching to point at a different one.
/// [isEnabled] can still read false if that setting is somehow cleared to an
/// unparseable value — every method degrades to a harmless no-op / null in
/// that case rather than throwing.
///
/// Optimistic like `CatalogWatchlistMachinery`'s watchlist mutation: [vote]
/// flips the local cache and notifies listeners immediately, then reverts on
/// a failed network call. Reads are batch-fetched per grid page via
/// [ensureLoaded] and cached by `'$serverId:$ratingKey'`; there is no
/// realtime push (see plezy-ratings' README for why), so a friend's new vote
/// only appears after the next [ensureLoaded]/[refresh] for that item.
class MediaVotesProvider extends ChangeNotifier with DisposableChangeNotifierMixin {
  /// [testClient], when set, is used instead of the settings-derived client
  /// and never disposed by this provider — tests own its lifecycle. This is
  /// the only constructor-level test seam; everything else is driven
  /// through the public vote/ensureLoaded/aggregateFor surface.
  MediaVotesProvider({required this._plexTokenSupplier, @visibleForTesting RatingsClient? testClient})
    : _cachedClient = testClient,
      _usesTestClient = testClient != null;

  final RatingsPlexTokenSupplier _plexTokenSupplier;
  final bool _usesTestClient;

  final Map<String, VoteAggregate> _aggregates = {};
  final Set<String> _inFlightLoads = {};

  RatingsServiceEndpoint? _cachedEndpoint;
  RatingsClient? _cachedClient;

  static String _cacheKey(String serverId, String ratingKey) => '$serverId:$ratingKey';

  /// True once a valid ratings service URL is configured. UI should hide the
  /// vote buttons/borders entirely when this is false rather than showing a
  /// permanently-broken control.
  bool get isEnabled => _client != null;

  /// Synchronous read of the last-loaded aggregate; null means "not loaded
  /// yet" (never fetched, or the fetch failed) rather than "no votes".
  VoteAggregate? aggregateFor(String serverId, String ratingKey) => _aggregates[_cacheKey(serverId, ratingKey)];

  /// Batch-fetches aggregates for [ratingKeys] not already cached. Safe to
  /// call repeatedly (e.g. every time a grid page's visible range changes) —
  /// already-cached keys are skipped for free.
  Future<void> ensureLoaded(String serverId, Iterable<String> ratingKeys) async {
    final client = _client;
    if (client == null) return;

    final missing = <String>{};
    for (final key in ratingKeys) {
      final cacheKey = _cacheKey(serverId, key);
      if (!_aggregates.containsKey(cacheKey) && !_inFlightLoads.contains(cacheKey)) {
        missing.add(key);
      }
    }
    if (missing.isEmpty) return;

    for (final key in missing) {
      _inFlightLoads.add(_cacheKey(serverId, key));
    }
    try {
      await _fetchBatch(client, serverId, missing);
    } finally {
      for (final key in missing) {
        _inFlightLoads.remove(_cacheKey(serverId, key));
      }
    }
  }

  /// Drops cached aggregates for [ratingKeys] so the next [ensureLoaded]
  /// re-fetches them — the closest this provider gets to "refresh", used
  /// e.g. when a detail screen is reopened and might be stale.
  Future<void> refresh(String serverId, Iterable<String> ratingKeys) async {
    for (final key in ratingKeys) {
      _aggregates.remove(_cacheKey(serverId, key));
    }
    await ensureLoaded(serverId, ratingKeys);
  }

  Future<void> _fetchBatch(RatingsClient client, String serverId, Set<String> ratingKeys) async {
    final token = await _plexTokenSupplier();
    if (token == null) return;
    try {
      final result = await client.votesFor(plexToken: token, serverId: serverId, ratingKeys: ratingKeys);
      for (final entry in result.entries) {
        _aggregates[_cacheKey(serverId, entry.key)] = entry.value;
      }
      safeNotifyListeners();
    } catch (e) {
      appLogger.w('Ratings: batch load failed for $serverId (${ratingKeys.length} items)', error: e);
      // Leave the keys uncached (not "voteless") so a later ensureLoaded
      // call retries instead of assuming zero votes forever.
    }
  }

  /// Cast, change, or (direction == null) clear the caller's own vote.
  /// Optimistic: flips the local cache and notifies *synchronously*, before
  /// any await — including the token lookup — so a caller that reads
  /// [aggregateFor] right after calling this (without awaiting it) already
  /// sees the flipped value. Reverts on failure. Rethrows so the UI can show
  /// an error.
  Future<void> vote(String serverId, String ratingKey, VoteDirection? direction) async {
    final client = _client;
    if (client == null) return;

    final cacheKey = _cacheKey(serverId, ratingKey);
    final previous = _aggregates[cacheKey] ?? const VoteAggregate();
    final optimistic = _optimisticFlip(previous, direction);
    _aggregates[cacheKey] = optimistic;
    safeNotifyListeners();

    try {
      final token = await _plexTokenSupplier();
      if (token == null) throw const RatingsApiException('Not signed in to Plex', statusCode: 401);
      final updated = await client.vote(
        plexToken: token,
        serverId: serverId,
        ratingKey: ratingKey,
        direction: direction,
      );
      _aggregates[cacheKey] = updated;
      safeNotifyListeners();
    } catch (e) {
      // Revert only if nothing else (a concurrent vote, a refresh) replaced
      // the optimistic value while this call was in flight — mirrors
      // CatalogWatchlistMachinery's identical-check-before-revert.
      if (identical(_aggregates[cacheKey], optimistic)) {
        _aggregates[cacheKey] = previous;
        safeNotifyListeners();
      }
      rethrow;
    }
  }

  static VoteAggregate _optimisticFlip(VoteAggregate current, VoteDirection? next) {
    var good = current.good;
    var bad = current.bad;
    switch (current.mine) {
      case VoteDirection.good:
        good--;
      case VoteDirection.bad:
        bad--;
      case null:
        break;
    }
    switch (next) {
      case VoteDirection.good:
        good++;
      case VoteDirection.bad:
        bad++;
      case null:
        break;
    }
    return VoteAggregate(good: good, bad: bad, mine: next);
  }

  RatingsClient? get _client {
    if (_usesTestClient) return _cachedClient;

    final endpoint = RatingsServiceEndpoint.resolve(
      SettingsService.instanceOrNull?.read(SettingsService.ratingsServiceUrl),
    );
    if (endpoint == null) {
      _disposeClient();
      return null;
    }
    if (_cachedClient != null && _cachedEndpoint == endpoint) return _cachedClient;
    _disposeClient();
    _cachedEndpoint = endpoint;
    _cachedClient = RatingsClient(endpoint: endpoint);
    return _cachedClient;
  }

  void _disposeClient() {
    _cachedClient?.dispose();
    _cachedClient = null;
    _cachedEndpoint = null;
  }

  @override
  void dispose() {
    if (!_usesTestClient) _disposeClient();
    super.dispose();
  }
}
