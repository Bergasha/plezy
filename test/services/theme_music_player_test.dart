import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/services/theme_music_player.dart';

import '../test_helpers/prefs.dart';
import 'music/music_playback_service_test.dart' show FakePlayer;

// Real timers rather than fakeAsync: ThemeMusicService's repeat/fade timers
// chain onto PlaybackCoordinator.instance, a process-wide singleton shared
// across every test in this file, and a Future completed inside one
// fakeAsync zone silently never resolves its `.then()` continuations
// registered from a later, separate fakeAsync zone — the previous version of
// this file hung on the second test for exactly that reason.
void main() {
  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  test('stops after the initial play plus one repeat instead of looping', () async {
    final player = FakePlayer();
    final service = ThemeMusicService(playerFactory: () => player);
    const owner = 'owner';

    await service.play(owner, 'fake://theme');
    expect(player.openedUris, ['fake://theme']);

    // First natural completion repeats once, after the repeat delay.
    player.completedCtrl.add(true);
    await Future<void>.delayed(const Duration(seconds: 6));
    expect(player.openedUris, ['fake://theme', 'fake://theme']);

    // Second completion: already played twice — stops instead of a second repeat.
    final stopsBefore = player.stopCalls;
    player.completedCtrl.add(true);
    await Future<void>.delayed(const Duration(seconds: 6));
    expect(player.openedUris, ['fake://theme', 'fake://theme'], reason: 'no third play');
    expect(player.stopCalls, greaterThan(stopsBefore));
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('a later theme for the same owner gets its own fresh two plays', () async {
    final player = FakePlayer();
    final service = ThemeMusicService(playerFactory: () => player);
    const owner = 'owner';

    await service.play(owner, 'fake://one');
    player.completedCtrl.add(true);
    await Future<void>.delayed(const Duration(seconds: 6));
    expect(player.openedUris, ['fake://one', 'fake://one'], reason: 'first theme already used its repeat');

    // A different item for the same owner (e.g. browsing to another show)
    // starts its own count rather than inheriting the exhausted one.
    await service.play(owner, 'fake://two');
    player.completedCtrl.add(true);
    await Future<void>.delayed(const Duration(seconds: 6));
    expect(player.openedUris.where((u) => u == 'fake://two').length, 2);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('fades to the configured theme music volume', () async {
    await SettingsService.instance.write(SettingsService.themeMusicVolume, 60);

    final player = FakePlayer();
    final service = ThemeMusicService(playerFactory: () => player);
    await service.play('owner', 'fake://theme');
    // play() resolves once the open commits; the volume fade-in runs
    // unawaited alongside it, so give it time to reach its target.
    await Future<void>.delayed(const Duration(milliseconds: 1400));

    expect(player.volumes.last, 60.0);
  });

  test('defaults to 35% when nothing is configured', () async {
    final player = FakePlayer();
    final service = ThemeMusicService(playerFactory: () => player);
    await service.play('owner', 'fake://theme');
    await Future<void>.delayed(const Duration(milliseconds: 1400));

    expect(player.volumes.last, 35.0);
  });
}
