import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/services/poster_color_service.dart';
import 'package:plezy/utils/blurhash.dart';

const _alphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#\$%*+,-.:;=?@[]^_{|}~';

String _encode83(int value, int length) {
  final digits = <String>[];
  for (var i = 0; i < length; i++) {
    digits.insert(0, _alphabet[value % 83]);
    value ~/= 83;
  }
  return digits.join();
}

String _solid(int rgb) =>
    '0'
    '0${_encode83(rgb, 4)}';

void main() {
  test('a one-component hash decodes to its flat colour', () {
    final pixels = decodeBlurHash(_solid(0xE5484D), width: 4, height: 4)!;
    expect(pixels.length, 4 * 4 * 4);
    expect(pixels[0], closeTo(0xE5, 1));
    expect(pixels[1], closeTo(0x48, 1));
    expect(pixels[2], closeTo(0x4D, 1));
    expect(pixels[3], 255);
  });

  test('a malformed hash decodes to nothing', () {
    expect(decodeBlurHash(''), isNull);
    expect(decodeBlurHash('short'), isNull);
    expect(decodeBlurHash('L${_solid(0).substring(1)}'), isNull);
    expect(decodeBlurHash('0 é invalid'), isNull);
  });

  test('a real hash decodes and gives a poster colour', () {
    final pixels = decodeBlurHash('LEHV6nWB2yk8pyo0adR*.7kCMdnj')!;
    expect(vividColorFromRgba(pixels), isNotNull);
  });

  MediaItem jellyfin({Map<String, Object?>? raw, String? thumbPath = '/Items/1/Images/Primary?tag=abc'}) =>
      MediaItem(id: '1', backend: MediaBackend.jellyfin, kind: MediaKind.movie, thumbPath: thumbPath, raw: raw);

  test('the Jellyfin hash for the poster tag is found', () {
    final item = jellyfin(
      raw: {
        'ImageTags': {'Primary': 'abc'},
        'ImageBlurHashes': {
          'Primary': {'abc': 'HASH', 'other': 'NOPE'},
        },
      },
    );
    expect(posterBlurHash(item, item.thumbPath!), 'HASH');
  });

  test('a hash is not used for a different poster than the item own', () {
    final item = jellyfin(
      raw: {
        'ImageTags': {'Primary': 'abc'},
        'ImageBlurHashes': {
          'Primary': {'abc': 'HASH'},
        },
      },
    );
    expect(posterBlurHash(item, '/Items/9/Images/Primary'), isNull);
  });

  test('items without hashes report none', () {
    expect(posterBlurHash(jellyfin(), '/Items/1/Images/Primary?tag=abc'), isNull);
    expect(posterBlurHash(jellyfin(raw: {'ImageTags': {}}), '/Items/1/Images/Primary?tag=abc'), isNull);
  });

  test('the Plex hash is read from the item', () {
    final item = MediaItem(
      id: '1',
      backend: MediaBackend.plex,
      kind: MediaKind.movie,
      thumbPath: '/library/metadata/1/thumb/5',
      raw: {'thumbBlurHash': 'HASH'},
    );
    expect(posterBlurHash(item, '/library/metadata/1/thumb/5'), 'HASH');
  });
}
