import '../media/library_query.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_library.dart';
import '../media/media_server_client.dart';
import '../utils/app_logger.dart';
import 'poster_color_service.dart';
import 'settings_service.dart' show EpisodePosterMode;

/// Walks the movie and show libraries in the background and records each
/// poster's colour in the app database, so the OLED focus effects have it the
/// first time a title is focused. Titles that already have a colour are skipped.
class PosterColorScanner {
  static const _throttle = Duration(milliseconds: 120);

  final MediaServerClient Function(MediaLibrary library) clientForLibrary;
  final PosterColorService service;
  final void Function(int scanned, int total)? onProgress;

  bool _cancelled = false;

  PosterColorScanner({required this.clientForLibrary, PosterColorService? service, this.onProgress})
    : service = service ?? PosterColorService.instance;

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
        (start, size) => client.fetchLibraryPagedContent(library.id, query: LibraryQuery(offset: start, limit: size)),
        pageSize: 200,
      );
    } catch (e) {
      appLogger.w('Poster colour scan: failed to list library ${library.title}', error: e);
      return;
    }

    for (var i = 0; i < items.length; i++) {
      if (_cancelled) return;
      final item = items[i];
      final target = posterColorTarget(
        item: item,
        client: client,
        mode: EpisodePosterMode.seriesPoster,
        mixedHubContext: false,
      );
      if (target != null && !await service.isKnown(target.key)) {
        try {
          await service.resolve(target.key, target.provider);
        } catch (e) {
          appLogger.w('Poster colour scan: failed for "${item.title}"', error: e);
        }
        await Future.delayed(_throttle);
      }
      onProgress?.call(i + 1, items.length);
    }
  }
}
