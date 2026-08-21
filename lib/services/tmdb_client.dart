import 'dart:convert';

import 'package:http/http.dart' as http;

import '../database/app_database.dart';
import '../database/tmdb_cache_operations.dart';
import '../models/tmdb/tmdb_cast_credit.dart';
import '../models/tmdb/tmdb_filmography_credit.dart';
import '../models/tmdb/tmdb_person.dart';
import '../models/tmdb/tmdb_tv_details.dart';
import '../utils/app_logger.dart';


class TmdbClient {
  static const String _apiKey = '081c05fd83dc7e4b14f3cc56b41fd390';
  static const String _baseUrl = 'https://api.themoviedb.org/3';

  final http.Client _http;
  final AppDatabase? _database;

  TmdbClient({http.Client? httpClient, AppDatabase? database}) : _http = httpClient ?? http.Client(), _database = database;

  void dispose() => _http.close();

  Future<List<TmdbCastCredit>> getMovieCredits(int tmdbMovieId) => _getCastCredits('/movie/$tmdbMovieId/credits');

  Future<List<TmdbCastCredit>> getTvCredits(int tmdbShowId) =>
      _getCastCredits('/tv/$tmdbShowId/aggregate_credits');

  Future<List<TmdbCastCredit>> _getCastCredits(String path) async {
    final json = await _get(path);
    if (json == null) return const [];
    final cast = json['cast'] as List<dynamic>?;
    if (cast == null) return const [];
    return cast.map((entry) => TmdbCastCredit.fromJson(entry as Map<String, dynamic>)).toList();
  }

  Future<TmdbPerson?> getPerson(int personId) async {
    final json = await _get('/person/$personId');
    if (json == null) return null;
    return TmdbPerson.fromJson(json);
  }

  Future<List<TmdbFilmographyCredit>> getPersonCombinedCredits(int personId) async {
    final json = await _get('/person/$personId/combined_credits');
    if (json == null) return const [];
    final cast = json['cast'] as List<dynamic>?;
    if (cast == null) return const [];
    return cast.map((entry) => TmdbFilmographyCredit.fromJson(entry as Map<String, dynamic>)).toList();
  }

  /// Show-level status (`status`, `in_production`) and `next_episode_to_air`
  /// — used to tell an airing show apart from a finished one and, when
  /// airing, when its next episode lands.
  Future<TmdbTvDetails?> getTvShowDetails(int tmdbShowId) async {
    final json = await _get('/tv/$tmdbShowId', cacheBust: true);
    if (json == null) return null;
    return TmdbTvDetails.fromJson(json);
  }

  /// Total episode count TMDb has listed for a season, aired or not — used
  /// for "episode 8 of 10". Returns null on a failed/missing lookup rather
  /// than 0, so callers can tell "unknown" apart from "no episodes".
  Future<int?> getSeasonEpisodeCount(int tmdbShowId, int seasonNumber) async {
    final json = await _get('/tv/$tmdbShowId/season/$seasonNumber', cacheBust: true);
    if (json == null) return null;
    final episodes = json['episodes'] as List<dynamic>?;
    return episodes?.length;
  }

  /// Today's date (UTC) as `YYYY-MM-DD`, appended to a cache key so
  /// schedule-sensitive lookups (next-air-date, episode counts) refresh once
  /// a day instead of caching forever like [_get]'s other callers — cheaper
  /// than adding real TTL support to the underlying cache table.
  String _cacheBustSuffix() {
    final now = DateTime.now().toUtc();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '?_d=${now.year}-$month-$day';
  }

  Future<Map<String, dynamic>?> _get(String path, {bool cacheBust = false}) async {
    final effectivePath = cacheBust ? '$path${_cacheBustSuffix()}' : path;
    return _getRaw(effectivePath);
  }

  Future<Map<String, dynamic>?> _getRaw(String path) async {
    final database = _database;
    if (database != null) {
      final cached = await database.getTmdbCache(path);
      if (cached != null) return cached;
    }

    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: {'api_key': _apiKey});
    try {
      final response = await _http.get(uri);
      if (response.statusCode != 200) {
        appLogger.w('TMDb request failed: ${response.statusCode} for $path');
        return null;
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (database != null) await database.setTmdbCache(path, json);
      return json;
    } catch (e) {
      appLogger.w('TMDb request error for $path', error: e);
      return null;
    }
  }
}