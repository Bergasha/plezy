import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter/painting.dart' show ImageProvider;

import '../media/library_query.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_library.dart';
import '../media/media_server_client.dart';
import '../utils/app_logger.dart';
import 'poster_color_service.dart';
import 'settings_service.dart' show EpisodePosterMode;

/// What a [PosterColorScanner] pass did.
class PosterColorScanResult {
  const PosterColorScanResult({
    required this.total,
    required this.sampled,
    required this.skipped,
    required this.failed,
  });

  /// Titles the pass looked at.
  final int total;

  /// Titles whose poster colour was worked out and stored.
  final int sampled;

  /// Titles that already had a colour, or have no poster to read.
  final int skipped;

  /// Titles whose poster could not be read.
  final int failed;
}

/// Walks the movie and show libraries in the background and records each
/// poster's colour in the app database, so the OLED focus effects have it the
/// first time a title is focused. Titles that already have a colour are skipped.
///
/// Every title is listed before any poster is fetched, so the total is known
/// from the start, and posters are read a few at a time. A library whose
/// posters keep failing (an unreachable server, a broken image route) is given
/// up on rather than spending a timeout on each of its titles.
class PosterColorScanner {
  static const _throttle = Duration(milliseconds: 60);
  static const _concurrency = 4;
  static const _itemTimeout = Duration(seconds: 20);
  static const _maxConsecutiveFailures = 8;

  final MediaServerClient Function(MediaLibrary library) clientForLibrary;
  final Future<bool> Function(String key) isKnown;
  final Future<Color?> Function(String key, ImageProvider Function() provider) resolve;

  /// Called as titles finish: how many are done out of the total.
  final void Function(int scanned, int total)? onProgress;

  bool _cancelled = false;

  PosterColorScanner({
    required this.clientForLibrary,
    Future<bool> Function(String key)? isKnown,
    Future<Color?> Function(String key, ImageProvider Function() provider)? resolve,
    this.onProgress,
  }) : isKnown = isKnown ?? PosterColorService.instance.isKnown,
       resolve = resolve ?? PosterColorService.instance.resolve;

  void cancel() => _cancelled = true;

  bool _isScannable(MediaLibrary library) => library.kind == MediaKind.movie || library.kind == MediaKind.show;

  Future<PosterColorScanResult> scanLibraries(List<MediaLibrary> libraries) async {
    final jobs = <_ScanJob>[];
    for (final library in libraries.where(_isScannable)) {
      if (_cancelled) break;
      jobs.addAll(await _listLibrary(library));
    }
    appLogger.i('Poster colour scan: ${jobs.length} titles to look at');

    final total = jobs.length;
    var scanned = 0;
    var sampled = 0;
    var skipped = 0;
    var failed = 0;
    var next = 0;
    final consecutiveFailures = <String, int>{};
    final abandoned = <String>{};

    Future<void> worker() async {
      while (!_cancelled) {
        final index = next++;
        if (index >= total) return;
        final job = jobs[index];

        final outcome = abandoned.contains(job.library.globalKey) ? _Outcome.failed : await _scanOne(job);
        switch (outcome) {
          case _Outcome.sampled:
            sampled++;
            consecutiveFailures[job.library.globalKey] = 0;
          case _Outcome.skipped:
            skipped++;
          case _Outcome.failed:
            failed++;
            final run = (consecutiveFailures[job.library.globalKey] ?? 0) + 1;
            consecutiveFailures[job.library.globalKey] = run;
            if (run >= _maxConsecutiveFailures && abandoned.add(job.library.globalKey)) {
              appLogger.w('Poster colour scan: giving up on ${job.library.title}, its posters keep failing');
            }
        }
        scanned++;
        onProgress?.call(scanned, total);
        if (scanned % 100 == 0) appLogger.i('Poster colour scan: $scanned of $total');
      }
    }

    if (total > 0) onProgress?.call(0, total);
    await Future.wait([for (var i = 0; i < _concurrency; i++) worker()]);
    appLogger.i('Poster colour scan done: $sampled stored, $skipped skipped, $failed failed');
    return PosterColorScanResult(total: total, sampled: sampled, skipped: skipped, failed: failed);
  }

  Future<List<_ScanJob>> _listLibrary(MediaLibrary library) async {
    final client = clientForLibrary(library);
    try {
      final items = await drainPages<MediaItem>(
        (start, size) => client.fetchLibraryPagedContent(
          library.id,
          query: LibraryQuery(offset: start, limit: size),
        ),
        pageSize: 200,
      );
      return [for (final item in items) _ScanJob(library: library, client: client, item: item)];
    } catch (e) {
      appLogger.w('Poster colour scan: failed to list library ${library.title}', error: e);
      return const [];
    }
  }

  Future<_Outcome> _scanOne(_ScanJob job) async {
    try {
      final target = posterColorTarget(
        item: job.item,
        client: job.client,
        mode: EpisodePosterMode.seriesPoster,
        mixedHubContext: false,
      );
      if (target == null || await isKnown(target.key)) return _Outcome.skipped;
      final color = await resolve(target.key, target.provider).timeout(_itemTimeout);
      await Future<void>.delayed(_throttle);
      return color == null ? _Outcome.failed : _Outcome.sampled;
    } catch (e) {
      appLogger.w('Poster colour scan: failed for "${job.item.title}"', error: e);
      return _Outcome.failed;
    }
  }
}

enum _Outcome { sampled, skipped, failed }

class _ScanJob {
  const _ScanJob({required this.library, required this.client, required this.item});

  final MediaLibrary library;
  final MediaServerClient client;
  final MediaItem item;
}
