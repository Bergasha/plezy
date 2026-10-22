import 'dart:convert';
import 'dart:ui' show Color;

import 'package:drift/drift.dart';

import 'app_database.dart';

extension PosterColorOperations on AppDatabase {
  /// The stored poster colour for [key], or null when it was never sampled.
  /// A stored row always holds a colour.
  Future<Color?> getPosterColor(String key) async {
    final row = await (select(apiCache)..where((t) => t.cacheKey.equals('poster_color:$key'))).getSingleOrNull();
    if (row == null) return null;
    final argb = (jsonDecode(row.data) as Map<String, dynamic>)['argb'];
    return argb is int ? Color(argb) : null;
  }

  Future<void> setPosterColor(String key, Color color) async {
    await into(apiCache).insertOnConflictUpdate(
      ApiCacheCompanion(cacheKey: Value('poster_color:$key'), data: Value(jsonEncode({'argb': color.toARGB32()}))),
    );
  }
}
