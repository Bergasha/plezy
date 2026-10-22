import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/utils/media_server_http_client.dart' show AbortController;
import 'package:plezy/services/poster_color_scanner.dart';

import '../test_helpers/media_items.dart';

class _FakeClient implements MediaServerClient {
  _FakeClient(this.items);

  final List<MediaItem> items;
  final pageRequests = <int>[];

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async {
    final offset = query.offset;
    final limit = query.limit;
    pageRequests.add(offset);
    final start = offset.clamp(0, items.length);
    final end = (offset + limit).clamp(0, items.length);
    return LibraryPage(items: items.sublist(start, end), totalCount: items.length, offset: offset);
  }

  @override
  String thumbnailUrl(String? path, {int? width, int? height, bool cover = true}) => 'http://server$path';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ThrowingClient implements MediaServerClient {
  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async => throw StateError('server unreachable');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaLibrary _library(String id, {MediaKind kind = MediaKind.movie, String server = 'server-a'}) => MediaLibrary(
  id: id,
  backend: MediaBackend.plex,
  title: 'Library $id',
  kind: kind,
  serverId: ServerId(server),
  serverName: server,
);

List<MediaItem> _items(int count, {String server = 'server-a', String prefix = 'm'}) => [
  for (var i = 0; i < count; i++)
    testMediaItem(
      id: '$prefix$i',
      kind: MediaKind.movie,
      title: 'Movie $i',
      thumbPath: '/thumb/$prefix$i',
      serverId: server,
    ),
];

void main() {
  test('every title is counted, with the total known before the first poster is read', () async {
    final client = _FakeClient(_items(10));
    final progress = <(int, int)>[];
    final resolved = <String>[];

    final scanner = PosterColorScanner(
      clientForLibrary: (_) => client,
      isKnown: (_) async => false,
      resolve: (key, provider) async {
        resolved.add(key);
        return const Color(0xFFE5484D);
      },
      onProgress: (scanned, total) => progress.add((scanned, total)),
    );

    final result = await scanner.scanLibraries([_library('1')]);

    expect(progress.first, (0, 10), reason: 'the dialog can show a real total straight away');
    expect(progress.last, (10, 10));
    expect(result.total, 10);
    expect(result.sampled, 10);
    expect(result.failed, 0);
    expect(resolved, hasLength(10));
  });

  test('a long library is listed page by page', () async {
    final client = _FakeClient(_items(450));
    final scanner = PosterColorScanner(
      clientForLibrary: (_) => client,
      isKnown: (_) async => true,
      resolve: (key, provider) async => null,
    );

    final result = await scanner.scanLibraries([_library('1')]);

    expect(client.pageRequests, [0, 200, 400]);
    expect(result.total, 450);
    expect(result.skipped, 450);
  });

  test('titles that already have a colour are skipped without reading their poster', () async {
    final client = _FakeClient(_items(5));
    var resolved = 0;
    final scanner = PosterColorScanner(
      clientForLibrary: (_) => client,
      isKnown: (key) async => key.contains('m1') || key.contains('m3'),
      resolve: (key, provider) async {
        resolved++;
        return const Color(0xFF3E63DD);
      },
    );

    final result = await scanner.scanLibraries([_library('1')]);

    expect(resolved, 3);
    expect(result.skipped, 2);
    expect(result.sampled, 3);
  });

  test('only movie and show libraries are scanned', () async {
    final movies = _FakeClient(_items(3));
    final music = _FakeClient(_items(3, prefix: 'x'));
    final scanner = PosterColorScanner(
      clientForLibrary: (library) => library.kind == MediaKind.artist ? music : movies,
      isKnown: (_) async => false,
      resolve: (key, provider) async => const Color(0xFF000000),
    );

    final result = await scanner.scanLibraries([_library('1'), _library('2', kind: MediaKind.artist)]);

    expect(music.pageRequests, isEmpty);
    expect(result.total, 3);
  });

  test('a library whose posters keep failing is given up on instead of spending a wait on every title', () async {
    final client = _FakeClient(_items(60));
    var attempts = 0;
    final scanner = PosterColorScanner(
      clientForLibrary: (_) => client,
      isKnown: (_) async => false,
      resolve: (key, provider) async {
        attempts++;
        return null;
      },
    );

    final result = await scanner.scanLibraries([_library('1')]);

    expect(result.total, 60);
    expect(result.failed, 60, reason: 'all of them are accounted for');
    expect(attempts, lessThan(60), reason: 'but most were never attempted');
  });

  test('one failing library does not stop a healthy one', () async {
    final bad = _FakeClient(_items(30, prefix: 'bad'));
    final good = _FakeClient(_items(5, prefix: 'good', server: 'server-b'));
    final scanner = PosterColorScanner(
      clientForLibrary: (library) => library.id == 'bad' ? bad : good,
      isKnown: (_) async => false,
      resolve: (key, provider) async => key.contains('good') ? const Color(0xFF30A46C) : null,
    );

    final result = await scanner.scanLibraries([_library('bad'), _library('good', server: 'server-b')]);

    expect(result.sampled, 5);
    expect(result.failed, 30);
  });

  test('a listing error skips that library and carries on', () async {
    final broken = _ThrowingClient();
    final good = _FakeClient(_items(4, server: 'server-b'));
    final scanner = PosterColorScanner(
      clientForLibrary: (library) => library.id == 'broken' ? broken : good,
      isKnown: (_) async => false,
      resolve: (key, provider) async => const Color(0xFF8E4EC6),
    );

    final result = await scanner.scanLibraries([_library('broken'), _library('good', server: 'server-b')]);

    expect(result.total, 4);
    expect(result.sampled, 4);
  });

  test('cancelling stops the scan part way', () async {
    final client = _FakeClient(_items(100));
    late PosterColorScanner scanner;
    var resolved = 0;
    scanner = PosterColorScanner(
      clientForLibrary: (_) => client,
      isKnown: (_) async => false,
      resolve: (key, provider) async {
        resolved++;
        if (resolved == 10) scanner.cancel();
        return const Color(0xFFF5A524);
      },
    );

    final result = await scanner.scanLibraries([_library('1')]);

    expect(resolved, lessThan(100));
    expect(result.sampled + result.skipped + result.failed, lessThan(100));
  });

  test('a title whose poster never loads times out instead of hanging the scan', () async {
    final client = _FakeClient(_items(2));
    final scanner = PosterColorScanner(
      clientForLibrary: (_) => client,
      isKnown: (_) async => false,
      resolve: (key, provider) => Completer<Color?>().future,
    );

    final result = await scanner.scanLibraries([_library('1')]).timeout(const Duration(seconds: 60));

    expect(result.failed, 2);
  });
}
