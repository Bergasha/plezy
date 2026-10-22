import 'dart:math' as math;
import 'dart:typed_data';

const _alphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#\$%*+,-.:;=?@[]^_{|}~';

int? _decode83(String hash, int from, int to) {
  var value = 0;
  for (var i = from; i < to; i++) {
    final digit = _alphabet.indexOf(hash[i]);
    if (digit < 0) return null;
    value = value * 83 + digit;
  }
  return value;
}

double _srgbToLinear(int value) {
  final v = value / 255;
  return v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
}

int _linearToSrgb(double value) {
  final v = value.clamp(0.0, 1.0);
  final s = v <= 0.0031308 ? v * 12.92 : 1.055 * math.pow(v, 1 / 2.4) - 0.055;
  return (s * 255 + 0.5).toInt().clamp(0, 255);
}

double _signedSquare(double value) => value.sign * value * value;

/// Expands a BlurHash string into [width] x [height] opaque RGBA pixels, or
/// null when [hash] is not a well-formed BlurHash.
Uint8List? decodeBlurHash(String hash, {int width = 16, int height = 24}) {
  if (hash.length < 6) return null;
  final sizeFlag = _decode83(hash, 0, 1);
  if (sizeFlag == null) return null;
  final componentsY = sizeFlag ~/ 9 + 1;
  final componentsX = sizeFlag % 9 + 1;
  if (hash.length != 4 + 2 * componentsX * componentsY) return null;

  final quantisedMax = _decode83(hash, 1, 2);
  if (quantisedMax == null) return null;
  final maxValue = (quantisedMax + 1) / 166;

  final colors = <List<double>>[];
  for (var i = 0; i < componentsX * componentsY; i++) {
    if (i == 0) {
      final dc = _decode83(hash, 2, 6);
      if (dc == null) return null;
      colors.add([_srgbToLinear(dc >> 16), _srgbToLinear((dc >> 8) & 255), _srgbToLinear(dc & 255)]);
    } else {
      final ac = _decode83(hash, 4 + i * 2, 6 + i * 2);
      if (ac == null) return null;
      colors.add([
        _signedSquare(((ac ~/ (19 * 19)) - 9) / 9) * maxValue,
        _signedSquare((((ac ~/ 19) % 19) - 9) / 9) * maxValue,
        _signedSquare(((ac % 19) - 9) / 9) * maxValue,
      ]);
    }
  }

  final pixels = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var r = 0.0;
      var g = 0.0;
      var b = 0.0;
      for (var j = 0; j < componentsY; j++) {
        for (var i = 0; i < componentsX; i++) {
          final basis = math.cos(math.pi * x * i / width) * math.cos(math.pi * y * j / height);
          final color = colors[i + j * componentsX];
          r += color[0] * basis;
          g += color[1] * basis;
          b += color[2] * basis;
        }
      }
      final offset = (y * width + x) * 4;
      pixels[offset] = _linearToSrgb(r);
      pixels[offset + 1] = _linearToSrgb(g);
      pixels[offset + 2] = _linearToSrgb(b);
      pixels[offset + 3] = 255;
    }
  }
  return pixels;
}
