import 'package:drift/native.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/database/poster_color_operations.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/services/poster_color_service.dart';
import 'package:plezy/services/settings_service.dart' show EpisodePosterMode;

MediaItem _movie(String id, {Map<String, Object?>? raw}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  thumbPath: '/thumb/$id',
  serverId: 'srv',
  raw: raw,
);

String _key(MediaItem item) => '${item.globalKey}|${item.thumbPath}';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PosterColorService.instance.attach(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('stored colours for many keys come back in one call, in chunks', () async {
    for (var i = 0; i < 450; i++) {
      await db.setPosterColor('k$i', Color(0xFF000000 + i));
    }

    final found = await db.getPosterColors([for (var i = 0; i < 460; i++) 'k$i']);

    expect(found.length, 450);
    expect(found['k449'], const Color(0xFF0001C1));
  });

  test('a page of titles gets its stored colours before any is focused', () async {
    final stored = _movie('preload-stored');
    await db.setPosterColor(_key(stored), const Color(0xFFE5484D));

    await PosterColorService.instance.preload([stored], mode: EpisodePosterMode.seriesPoster);

    expect(PosterColorService.instance.cached(_key(stored))?.color, const Color(0xFFE5484D));
  });

  test('a title with a server hash is ready without touching the database', () async {
    final hashed = _movie('preload-hash', raw: {'thumbBlurHash': 'LEHV6nWB2yk8pyo0adR*.7kCMdnj'});

    await PosterColorService.instance.preload([hashed], mode: EpisodePosterMode.seriesPoster);

    expect(PosterColorService.instance.cached(_key(hashed))?.color, isNotNull);
    expect(await db.getPosterColor(_key(hashed)), isNull);
  });

  test('a title with no stored colour is left for the focus lookup', () async {
    final unknown = _movie('preload-unknown');

    await PosterColorService.instance.preload([unknown], mode: EpisodePosterMode.seriesPoster);

    expect(PosterColorService.instance.cached(_key(unknown)), isNull);
  });
}
