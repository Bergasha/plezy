import '../database/app_database.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_server_client.dart';
import '../models/tmdb/tmdb_filmography_credit.dart';
import '../models/tmdb/tmdb_person.dart';
import '../utils/app_logger.dart';
import 'tmdb_client.dart';


class TmdbCastMatcher {
  final TmdbClient _tmdb;

  TmdbCastMatcher({TmdbClient? tmdbClient, AppDatabase? database}) : _tmdb = tmdbClient ?? TmdbClient(database: database);

  void dispose() => _tmdb.dispose();

  /// Returns null when the title has no TMDb match, or the actor can't be
  /// matched by name in TMDb's credits for it.
  Future<TmdbPerson?> resolveCastMember({
    required MediaItem metadata,
    required String actorName,
    required MediaServerClient client,
  }) async {
    final externalIds = await client.fetchExternalIds(metadata.id);
    final tmdbId = externalIds.tmdb;
    appLogger.d('TMDb cast match: resolved tmdbId=$tmdbId for ${metadata.kind} "${metadata.title}"');
    if (tmdbId == null) return null;

    final isShow = metadata.kind == MediaKind.show || metadata.kind == MediaKind.episode;
    final credits = isShow ? await _tmdb.getTvCredits(tmdbId) : await _tmdb.getMovieCredits(tmdbId);
    appLogger.d('TMDb cast match: got ${credits.length} credits, looking for "$actorName"');

    final normalizedTarget = _normalize(actorName);
    for (final credit in credits) {
      if (_normalize(credit.name) == normalizedTarget) {
        appLogger.d('TMDb cast match: matched "$actorName" -> personId=${credit.personId}');
        return _tmdb.getPerson(credit.personId);
      }
    }
    appLogger.d(
      'TMDb cast match: no match for "$actorName" among [${credits.take(5).map((c) => c.name).join(", ")}${credits.length > 5 ? ", ..." : ""}]',
    );
    return null;
  }

  Future<List<TmdbFilmographyCredit>> getFilmography(int personId) => _tmdb.getPersonCombinedCredits(personId);

  String _normalize(String name) => name.trim().toLowerCase();

 
  Future<Map<String, TmdbPerson>> resolveCastMembersForTitle({
    required MediaItem metadata,
    required List<String> actorNames,
    required MediaServerClient client,
  }) async {
    final externalIds = await client.fetchExternalIds(metadata.id);
    final tmdbId = externalIds.tmdb;
    if (tmdbId == null) return const {};

    final isShow = metadata.kind == MediaKind.show || metadata.kind == MediaKind.episode;
    final credits = isShow ? await _tmdb.getTvCredits(tmdbId) : await _tmdb.getMovieCredits(tmdbId);
    if (credits.isEmpty) return const {};

    final byNormalizedName = {for (final c in credits) _normalize(c.name): c};
    final result = <String, TmdbPerson>{};
    for (final name in actorNames) {
      final credit = byNormalizedName[_normalize(name)];
      if (credit == null) continue;
      final person = await _tmdb.getPerson(credit.personId);
      if (person != null) result[name] = person;
    }
    return result;
  }
}