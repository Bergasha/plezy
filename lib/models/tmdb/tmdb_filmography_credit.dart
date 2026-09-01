/// One entry from TMDb's `/person/{id}/combined_credits` — a movie or TV
/// show the person has appeared in, movie and TV entries mixed together.
class TmdbFilmographyCredit {
  final int id;
  final String? title;

  /// `'movie'` or `'tv'` as TMDb reports it.
  final String mediaType;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;

  /// `release_date` for movies, `first_air_date` for TV — TMDb's format,
  /// `YYYY-MM-DD`.
  final String? releaseDate;
  final double? voteAverage;
  final int? voteCount;

  const TmdbFilmographyCredit({
    required this.id,
    this.title,
    required this.mediaType,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.releaseDate,
    this.voteAverage,
    this.voteCount,
  });

  factory TmdbFilmographyCredit.fromJson(Map<String, dynamic> json) {
    final mediaType = json['media_type'] as String? ?? 'movie';
    final isTv = mediaType == 'tv';
    return TmdbFilmographyCredit(
      id: json['id'] as int,
      title: (isTv ? json['name'] : json['title']) as String?,
      mediaType: mediaType,
      overview: json['overview'] as String?,
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      releaseDate: (isTv ? json['first_air_date'] : json['release_date']) as String?,
      voteAverage: (json['vote_average'] as num?)?.toDouble(),
      voteCount: json['vote_count'] as int?,
    );
  }
}