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

/// TMDb's `/tv/{id}` show-level status fields relevant to "is this still airing".
class TmdbTvDetails {
  final String status;
  final bool inProduction;
  final TmdbNextEpisode? nextEpisodeToAir;

  const TmdbTvDetails({required this.status, required this.inProduction, this.nextEpisodeToAir});

  /// TMDb keeps `in_production` true for a renewed-but-unscheduled next
  /// season, so a terminal [status] is checked too — a show is only "airing"
  /// while both agree it's still making episodes.
  bool get isAiring => inProduction && status != 'Ended' && status != 'Canceled';

  factory TmdbTvDetails.fromJson(Map<String, dynamic> json) {
    final nextRaw = json['next_episode_to_air'];
    return TmdbTvDetails(
      status: json['status'] as String? ?? '',
      inProduction: json['in_production'] as bool? ?? false,
      nextEpisodeToAir: nextRaw is Map<String, dynamic> ? TmdbNextEpisode.fromJson(nextRaw) : null,
    );
  }
}
