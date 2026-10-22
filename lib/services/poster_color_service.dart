import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../database/app_database.dart';
import '../database/poster_color_operations.dart';
import '../media/media_item.dart';
import '../media/media_server_client.dart';
import '../utils/app_logger.dart';
import '../utils/blurhash.dart';
import '../utils/media_image_helper.dart';
import 'settings_service.dart' show EpisodePosterMode;

/// Reduces a poster to one vivid colour for the OLED focus effects.
///
/// Colours are remembered in memory and in the app database, so a poster is
/// sampled once, whether that happens when it is first focused or earlier in
/// a [PosterColorScanner] pass.
class PosterColorService {
  PosterColorService._();

  static final PosterColorService instance = PosterColorService._();

  static const _maxEntries = 300;
  static const _sampleWidth = 16;
  static const _sampleHeight = 24;

  final LinkedHashMap<String, Color?> _cache = LinkedHashMap();
  final Map<String, Future<Color?>> _inFlight = {};
  AppDatabase? _database;

  void attach(AppDatabase database) => _database = database;

  /// The colour already known for [key] without any lookup. Distinguishes
  /// "not known yet" (null record) from "known to have no usable colour"
  /// (record holding null).
  ({Color? color})? cached(String key) {
    if (!_cache.containsKey(key)) return null;
    final color = _cache.remove(key);
    _cache[key] = color;
    return (color: color);
  }

  /// Whether a colour for [key] is already stored, so a scan can skip it.
  Future<bool> isKnown(String key) async {
    if (cached(key) != null) return true;
    final stored = await _stored(key);
    if (stored == null) return false;
    _remember(key, stored);
    return true;
  }

  /// Records a colour the server already told us about, so nothing has to be
  /// downloaded or sampled for [key].
  void seed(String key, Color color) {
    _remember(key, color);
    _persist(key, color);
  }

  Future<Color?> resolve(String key, ImageProvider Function() provider) {
    final hit = cached(key);
    if (hit != null) return Future.value(hit.color);
    return _inFlight[key] ??= _load(key, provider).whenComplete(() => _inFlight.remove(key));
  }

  Future<Color?> _load(String key, ImageProvider Function() provider) async {
    final stored = await _stored(key);
    if (stored != null) {
      _remember(key, stored);
      return stored;
    }
    final sampled = await _sample(provider());
    _remember(key, sampled);
    if (sampled != null) await _persist(key, sampled);
    return sampled;
  }

  Future<Color?> _stored(String key) async {
    try {
      return await _database?.getPosterColor(key);
    } catch (error, stackTrace) {
      appLogger.d('Poster colour lookup failed', error: error, stackTrace: stackTrace);
      return null;
    }
  }

  Future<void> _persist(String key, Color color) async {
    try {
      await _database?.setPosterColor(key, color);
    } catch (error, stackTrace) {
      appLogger.d('Poster colour could not be stored', error: error, stackTrace: stackTrace);
    }
  }

  void _remember(String key, Color? color) {
    _cache[key] = color;
    while (_cache.length > _maxEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  Future<Color?> _sample(ImageProvider provider) async {
    final loaded = Completer<ui.Image?>();
    final stream = provider.resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener(
      (info, _) {
        if (!loaded.isCompleted) loaded.complete(info.image.clone());
      },
      onError: (Object error, StackTrace? stackTrace) {
        if (!loaded.isCompleted) loaded.complete(null);
      },
    );
    stream.addListener(listener);
    ui.Image? image;
    try {
      image = await loaded.future.timeout(const Duration(seconds: 8), onTimeout: () => null);
    } finally {
      stream.removeListener(listener);
    }
    if (image == null) return null;

    try {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromLTWH(0, 0, _sampleWidth.toDouble(), _sampleHeight.toDouble()),
        Paint()..filterQuality = FilterQuality.medium,
      );
      final picture = recorder.endRecording();
      final small = await picture.toImage(_sampleWidth, _sampleHeight);
      picture.dispose();
      final data = await small.toByteData(format: ui.ImageByteFormat.rawRgba);
      small.dispose();
      return data == null ? null : vividColorFromRgba(data.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  }
}

/// The poster's dominant hue, pushed to a colour that glows on black.
///
/// Pixels are weighted by how saturated and how bright they are, so a dark
/// frame or a white title block does not drown out the artwork's real colour.
/// The result keeps that hue but is lifted to a lightness a glow can use.
/// Returns null when [rgba] holds no opaque pixels.
Color? vividColorFromRgba(Uint8List rgba) {
  var weightSum = 0.0;
  var r = 0.0;
  var g = 0.0;
  var b = 0.0;
  var opaque = 0;

  for (var i = 0; i + 3 < rgba.length; i += 4) {
    if (rgba[i + 3] < 128) continue;
    opaque++;
    final red = rgba[i] / 255;
    final green = rgba[i + 1] / 255;
    final blue = rgba[i + 2] / 255;
    final maxChannel = [red, green, blue].reduce((a, b) => a > b ? a : b);
    final minChannel = [red, green, blue].reduce((a, b) => a < b ? a : b);
    final saturation = maxChannel == 0 ? 0.0 : (maxChannel - minChannel) / maxChannel;
    final weight = 0.02 + saturation * saturation * maxChannel;
    weightSum += weight;
    r += red * weight;
    g += green * weight;
    b += blue * weight;
  }
  if (opaque == 0 || weightSum == 0) return null;

  final average = Color.from(alpha: 1, red: r / weightSum, green: g / weightSum, blue: b / weightSum);
  final hsl = HSLColor.fromColor(average);
  return hsl
      .withSaturation(hsl.saturation.clamp(0.0, 1.0) < 0.12 ? hsl.saturation : hsl.saturation.clamp(0.6, 0.95))
      .withLightness(hsl.lightness.clamp(0.52, 0.64))
      .toColor();
}

/// What the colour of [item]'s poster is looked up and sampled by: a key that
/// is stable across launches (the item plus its artwork path, so new artwork
/// gets a fresh colour) and a lazily built request for a small copy of the
/// poster. Null when the item has no artwork or the artwork cannot be
/// addressed (offline, no client).
({String key, ImageProvider Function() provider})? posterColorTarget({
  required MediaItem item,
  required MediaServerClient? client,
  required EpisodePosterMode mode,
  required bool mixedHubContext,
}) {
  final path =
      item.posterThumb(mode: mode, mixedHubContext: mixedHubContext) ??
      item.posterThumbFallback(mode: mode, mixedHubContext: mixedHubContext);
  if (path == null || path.isEmpty) return null;
  final url = MediaImageHelper.getOptimizedImageUrl(
    client: client,
    thumbPath: path,
    maxWidth: 120,
    maxHeight: 180,
    pixelRatio: 1,
  );
  if (url.isEmpty) return null;
  final key = '${item.globalKey}|$path';
  if (PosterColorService.instance.cached(key) == null) {
    final hash = posterBlurHash(item, path);
    final pixels = hash == null ? null : decodeBlurHash(hash);
    final color = pixels == null ? null : vividColorFromRgba(pixels);
    if (color != null) PosterColorService.instance.seed(key, color);
  }
  return (
    key: key,
    provider: () => MediaImageHelper.serverArtworkProvider(imageUrl: url, memWidth: 120, memHeight: 180),
  );
}

/// The BlurHash the server sent for [item]'s own poster at [path], if any.
/// Jellyfin and Emby include it with every item; Plex only when asked.
String? posterBlurHash(MediaItem item, String path) {
  if (path != item.thumbPath) return null;
  final raw = item.raw;
  if (raw == null) return null;
  final plex = raw['thumbBlurHash'];
  if (plex is String && plex.isNotEmpty) return plex;
  final tags = raw['ImageTags'];
  final hashes = raw['ImageBlurHashes'];
  if (tags is! Map || hashes is! Map) return null;
  final tag = tags['Primary'];
  final primary = hashes['Primary'];
  if (tag is! String || primary is! Map) return null;
  final hash = primary[tag];
  return hash is String && hash.isNotEmpty ? hash : null;
}
