/// TMDb's `/tv/{id}` "next episode to air" entry.
class TmdbNextEpisode {
  /// ISO `YYYY-MM-DD`, as TMDb returns it — pass straight to [formatAbbreviatedDate].
  final String? airDate;
  final int? episodeNumber;
  final int? seasonNumber;

  const TmdbNextEpisode({this.airDate, this.episodeNumber, this.seasonNumber});

  factory TmdbNextEpisode.fromJson(Map<String, dynamic> json) => TmdbNextEpisode(
    airDate: json['air_date'] as String?,
    episodeNumber: json['episode_number'] as int?,
    seasonNumber: json['season_number'] as int?,
  );
}

/// One entry from TMDb's `/tv/{id}` `seasons` list — present for every season
/// TMDb has created a page for, including one announced but not yet detailed
/// episode-by-episode.
class TmdbSeasonSummary {
  final int seasonNumber;

  /// ISO `YYYY-MM-DD`, once TMDb has a premiere date for the season. TMDb
  /// stubs a season entry (and its date, once known) as soon as a renewal is
  /// announced — well before per-episode data exists, which is what
  /// [TmdbNextEpisode] needs. Checking here catches most renewals
  /// [TmdbTvDetails.nextEpisodeToAir] misses entirely.
  final String? airDate;

  const TmdbSeasonSummary({required this.seasonNumber, this.airDate});

  factory TmdbSeasonSummary.fromJson(Map<String, dynamic> json) =>
      TmdbSeasonSummary(seasonNumber: json['season_number'] as int? ?? 0, airDate: json['air_date'] as String?);
}

/// TMDb's `/tv/{id}` show-level status fields relevant to "is this still airing".
class TmdbTvDetails {
  final String status;
  final bool inProduction;
  final TmdbNextEpisode? nextEpisodeToAir;
  final List<TmdbSeasonSummary> seasons;

  const TmdbTvDetails({
    required this.status,
    required this.inProduction,
    this.nextEpisodeToAir,
    this.seasons = const [],
  });

  /// TMDb keeps `in_production` true for a renewed-but-unscheduled next
  /// season, so a terminal [status] is checked too — a show is only "airing"
  /// while both agree it's still making episodes.
  bool get isAiring => inProduction && status != 'Ended' && status != 'Canceled';

  /// The earliest known premiere date for a season after [afterSeasonNumber],
  /// if TMDb has one — see [TmdbSeasonSummary.airDate] for why this often
  /// finds a date [nextEpisodeToAir] cannot yet.
  String? upcomingSeasonAirDate(int afterSeasonNumber) {
    final candidates =
        seasons.where((season) => season.seasonNumber > afterSeasonNumber && season.airDate != null).toList()
          ..sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
    return candidates.firstOrNull?.airDate;
  }

  factory TmdbTvDetails.fromJson(Map<String, dynamic> json) {
    final nextRaw = json['next_episode_to_air'];
    final seasonsRaw = json['seasons'];
    return TmdbTvDetails(
      status: json['status'] as String? ?? '',
      inProduction: json['in_production'] as bool? ?? false,
      nextEpisodeToAir: nextRaw is Map<String, dynamic> ? TmdbNextEpisode.fromJson(nextRaw) : null,
      seasons: seasonsRaw is List
          ? seasonsRaw.whereType<Map<String, dynamic>>().map(TmdbSeasonSummary.fromJson).toList()
          : const [],
    );
  }
}
