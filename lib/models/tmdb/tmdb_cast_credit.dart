/// One cast entry from TMDb's `/movie/{id}/credits` or
/// `/tv/{id}/aggregate_credits` endpoint — used to match against Plex's own
/// cast list by name so a [TmdbPerson] lookup can be resolved for a tapped
/// cast member.
class TmdbCastCredit {
  final int personId;
  final String name;
  final String? character;
  final String? profilePath;
  final int order;

  const TmdbCastCredit({
    required this.personId,
    required this.name,
    this.character,
    this.profilePath,
    required this.order,
  });

  factory TmdbCastCredit.fromJson(Map<String, dynamic> json) {
    // Plain `/credits` (movies) has a flat `character` string. TV's
    // `/aggregate_credits` instead has a `roles` array — one entry per
    // distinct named role the actor played across the show's run — since
    // long-running shows sometimes recast or rename characters.
    final roles = json['roles'] as List<dynamic>?;
    final character = roles != null && roles.isNotEmpty
        ? roles.first['character'] as String?
        : json['character'] as String?;

    return TmdbCastCredit(
      personId: json['id'] as int,
      name: json['name'] as String? ?? '',
      character: character,
      profilePath: json['profile_path'] as String?,
      order: json['order'] as int? ?? 999,
    );
  }
}