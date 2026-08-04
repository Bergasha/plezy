import '../media/library_query.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_library.dart';
import '../media/media_server_client.dart';
import '../utils/app_logger.dart';
import '../utils/serial_future_queue.dart';
import 'tmdb_cast_matcher.dart';


class TmdbCacheWarmer {
  static const _throttle = Duration(milliseconds: 250);

  final MediaServerClient Function(MediaLibrary library) clientForLibrary;
  final TmdbCastMatcher matcher;
  final void Function(int scanned, int total)? onProgress;

  final _queue = SerialFutureQueue();
  bool _cancelled = false;

  TmdbCacheWarmer({required this.clientForLibrary, required this.matcher, this.onProgress});

  void cancel() => _cancelled = true;

  bool _isScannable(MediaLibrary library) => library.kind == MediaKind.movie || library.kind == MediaKind.show;

  Future<void> scanLibraries(List<MediaLibrary> libraries) async {
    for (final library in libraries.where(_isScannable)) {
      if (_cancelled) return;
      await _scanLibrary(library);
    }
  }

  Future<void> _scanLibrary(MediaLibrary library) async {
    final client = clientForLibrary(library);
    List<MediaItem> items;
    try {
      items = await drainPages<MediaItem>(
        (start, size) => client.fetchLibraryContent(library.id, LibraryQuery(offset: start, limit: size)),
        pageSize: 200,
      );
    } catch (e) {
      appLogger.w('TMDb cache warmer: failed to list library ${library.title}', error: e);
      return;
    }

    for (var i = 0; i < items.length; i++) {
      if (_cancelled) return;
      final item = items[i];
      final roles = item.roles;
      if (roles != null && roles.isNotEmpty) {
        await _queue.run(() async {
          try {
            await matcher.resolveCastMembersForTitle(
              metadata: item,
              actorNames: roles.map((r) => r.tag).toList(),
              client: client,
            );
          } catch (e) {
            appLogger.w('TMDb cache warmer: failed for "${item.title}"', error: e);
          }
          await Future.delayed(_throttle);
        });
      }
      onProgress?.call(i + 1, items.length);
    }
  }
}