import 'dart:convert';

import 'package:drift/drift.dart';

import 'app_database.dart';


extension TmdbCacheOperations on AppDatabase {
  Future<Map<String, dynamic>?> getTmdbCache(String key) async {
    final result = await (select(apiCache)..where((t) => t.cacheKey.equals('tmdb:$key'))).getSingleOrNull();
    if (result == null) return null;
    return jsonDecode(result.data) as Map<String, dynamic>;
  }

  Future<void> setTmdbCache(String key, Map<String, dynamic> data) async {
    await into(
      apiCache,
    ).insertOnConflictUpdate(ApiCacheCompanion(cacheKey: Value('tmdb:$key'), data: Value(jsonEncode(data))));
  }
}