/// Full person detail from TMDb's `/person/{id}` endpoint — biography,
/// birth/death dates, and place of birth for a cast/crew member.
class TmdbPerson {
  final int id;
  final String name;
  final String? biography;
  final String? birthday;
  final String? deathday;
  final String? placeOfBirth;
  final String? profilePath;
  final String? knownForDepartment;

  const TmdbPerson({
    required this.id,
    required this.name,
    this.biography,
    this.birthday,
    this.deathday,
    this.placeOfBirth,
    this.profilePath,
    this.knownForDepartment,
  });

  factory TmdbPerson.fromJson(Map<String, dynamic> json) => TmdbPerson(
    id: json['id'] as int,
    name: json['name'] as String? ?? '',
    biography: (json['biography'] as String?)?.trim().isEmpty ?? true ? null : json['biography'] as String?,
    birthday: json['birthday'] as String?,
    deathday: json['deathday'] as String?,
    placeOfBirth: json['place_of_birth'] as String?,
    profilePath: json['profile_path'] as String?,
    knownForDepartment: json['known_for_department'] as String?,
  );
}