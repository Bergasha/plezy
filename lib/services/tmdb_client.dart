import 'dart:convert';

import 'package:http/http.dart' as http;

import '../database/app_database.dart';
import '../database/tmdb_cache_operations.dart';
import '../models/tmdb/tmdb_cast_credit.dart';
import '../models/tmdb/tmdb_filmography_credit.dart';
import '../models/tmdb/tmdb_person.dart';
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

  Future<Map<String, dynamic>?> _get(String path) async {
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