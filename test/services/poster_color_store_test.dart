import 'package:drift/native.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/database/poster_color_operations.dart';
import 'package:plezy/services/poster_color_service.dart';

class _MustNotLoad extends ImageProvider<_MustNotLoad> {
  @override
  Future<_MustNotLoad> obtainKey(ImageConfiguration configuration) => throw StateError('the artwork was fetched');
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PosterColorService.instance.attach(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('a stored colour comes back exactly, and an unknown key has none', () async {
    await db.setPosterColor('server:1|/thumb/1', const Color(0xFFE5484D));

    expect(await db.getPosterColor('server:1|/thumb/1'), const Color(0xFFE5484D));
    expect(await db.getPosterColor('server:2|/thumb/2'), isNull);
  });

  test('storing a colour again replaces the old one', () async {
    await db.setPosterColor('k', const Color(0xFF111111));
    await db.setPosterColor('k', const Color(0xFF222222));

    expect(await db.getPosterColor('k'), const Color(0xFF222222));
  });

  test('a colour already in the database is used without fetching the artwork', () async {
    const key = 'server:9|/thumb/9';
    await db.setPosterColor(key, const Color(0xFF3E63DD));

    expect(await PosterColorService.instance.isKnown(key), isTrue);
    expect(await PosterColorService.instance.resolve(key, _MustNotLoad.new), const Color(0xFF3E63DD));
  });

  test('a poster with no stored colour is not known', () async {
    expect(await PosterColorService.instance.isKnown('server:10|/thumb/never'), isFalse);
  });
}
