import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/poster_color_service.dart';

Uint8List _pixels(List<List<int>> rgba) => Uint8List.fromList([for (final p in rgba) ...p]);

double _hue(Color color) => HSLColor.fromColor(color).hue;

void main() {
  test('a red poster glows red', () {
    final color = vividColorFromRgba(_pixels(List.generate(40, (_) => [200, 30, 40, 255])))!;

    final hue = _hue(color);
    expect(hue < 15 || hue > 345, isTrue, reason: 'hue was $hue');
  });

  test('a blue poster glows blue', () {
    final color = vividColorFromRgba(_pixels(List.generate(40, (_) => [40, 70, 210, 255])))!;

    expect(_hue(color), inInclusiveRange(215, 235));
  });

  test('a dark frame with a little orange keeps the orange, not a muddy grey', () {
    final pixels = [
      ...List.generate(36, (_) => [12, 12, 14, 255]),
      ...List.generate(4, (_) => [240, 140, 20, 255]),
    ];

    final color = vividColorFromRgba(_pixels(pixels))!;

    expect(_hue(color), inInclusiveRange(25, 45));
    expect(HSLColor.fromColor(color).saturation, greaterThan(0.5));
  });

  test('the result is always bright enough to glow on black', () {
    final dark = vividColorFromRgba(_pixels(List.generate(40, (_) => [30, 5, 5, 255])))!;

    expect(HSLColor.fromColor(dark).lightness, greaterThan(0.5));
  });

  test('a greyscale poster stays neutral instead of inventing a hue', () {
    final color = vividColorFromRgba(_pixels(List.generate(40, (_) => [128, 128, 128, 255])))!;

    expect(HSLColor.fromColor(color).saturation, lessThan(0.12));
  });

  test('transparent pixels are ignored and an empty sample has no colour', () {
    expect(vividColorFromRgba(_pixels(List.generate(40, (_) => [200, 30, 40, 0]))), isNull);
    expect(vividColorFromRgba(Uint8List(0)), isNull);
  });
}
