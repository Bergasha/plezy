import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/playback_coordinator.dart';

void main() {
  final coordinator = PlaybackCoordinator.instance;

  test('music claim releases the theme session', () async {
    var themeStops = 0;
    Future<void> stopTheme() async => themeStops++;

    coordinator.registerThemeSession(stopAndDispose: stopTheme);
    addTearDown(() => coordinator.unregisterThemeSession(stopTheme));

    await coordinator.claimMusic();

    expect(themeStops, 1);
  });

  test('theme claim releases the music session', () async {
    var musicStops = 0;
    Future<void> stopMusic() async => musicStops++;

    coordinator.registerMusicSession(stopAndDispose: stopMusic);
    addTearDown(() => coordinator.unregisterMusicSession(stopMusic));

    await coordinator.claimTheme();

    expect(musicStops, 1);
  });

  test('video claim releases music before theme', () async {
    final stops = <String>[];
    Future<void> stopMusic() async => stops.add('music');
    Future<void> stopTheme() async => stops.add('theme');

    coordinator.registerMusicSession(stopAndDispose: stopMusic);
    coordinator.registerThemeSession(stopAndDispose: stopTheme);
    addTearDown(() {
      coordinator.unregisterMusicSession(stopMusic);
      coordinator.unregisterThemeSession(stopTheme);
    });

    await coordinator.claimVideo();

    expect(stops, ['music', 'theme']);
  });

  test('stale video release preserves the active owner and waits for its stop', () async {
    final stopped = Completer<void>();
    var oldStops = 0;
    var musicStops = 0;
    Future<void> oldOwner() async => oldStops++;
    Future<void> activeOwner() => stopped.future;
    Future<void> musicOwner() async => musicStops++;
    coordinator.registerMusicSession(stopAndDispose: musicOwner);
    coordinator.registerVideoSession(shutdown: oldOwner);
    coordinator.registerVideoSession(shutdown: activeOwner);
    addTearDown(() {
      coordinator.unregisterVideoSession(oldOwner);
      coordinator.unregisterVideoSession(activeOwner);
      coordinator.unregisterMusicSession(musicOwner);
    });

    coordinator.unregisterVideoSession(oldOwner);
    var done = false;
    final shutdown = coordinator.shutdownVideo().whenComplete(() => done = true);
    await Future<void>.delayed(Duration.zero);
    expect(done, isFalse);
    expect(oldStops, 0);
    expect(musicStops, 0);
    stopped.complete();
    await shutdown;
    expect(done, isTrue);

    coordinator.unregisterVideoSession(activeOwner);
    await coordinator.shutdownVideo();
    expect(oldStops, 0);
    expect(musicStops, 0);
  });
}
