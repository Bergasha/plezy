import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/services/whats_new_service.dart';

import '../test_helpers/prefs.dart';

void main() {
  setUp(() {
    resetSharedPreferencesForTest();
    WhatsNewService.debugEntriesOverride = {
      '2.0.0': ['A new thing'],
    };
    PackageInfo.setMockInitialValues(
      appName: 'Plezy',
      packageName: 'com.plezy.test',
      version: '2.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  tearDown(() => WhatsNewService.debugEntriesOverride = null);

  test('a fresh install (no recorded version) shows the entry for the version it launches on', () async {
    expect(await WhatsNewService.checkAndConsume(), ['A new thing']);

    final settings = await SettingsService.getInstance();
    expect(settings.read(SettingsService.lastSeenAppVersion), '2.0.0');
  });

  test('a fresh install on a version with no entry shows nothing but still records it', () async {
    WhatsNewService.debugEntriesOverride = {};

    expect(await WhatsNewService.checkAndConsume(), isNull);

    final settings = await SettingsService.getInstance();
    expect(settings.read(SettingsService.lastSeenAppVersion), '2.0.0');
  });

  test('launching again on the same recorded version shows nothing', () async {
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.lastSeenAppVersion, '2.0.0');

    expect(await WhatsNewService.checkAndConsume(), isNull);
  });

  test('an update to a version with an entry returns its bullet points once', () async {
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.lastSeenAppVersion, '1.0.0');

    expect(await WhatsNewService.checkAndConsume(), ['A new thing']);
    expect(settings.read(SettingsService.lastSeenAppVersion), '2.0.0');

    // A later launch on the same (now-recorded) version must not repeat it.
    expect(await WhatsNewService.checkAndConsume(), isNull);
  });

  test('an update to a version with no entry shows nothing but still records it', () async {
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.lastSeenAppVersion, '1.0.0');
    WhatsNewService.debugEntriesOverride = {};

    expect(await WhatsNewService.checkAndConsume(), isNull);
    expect(settings.read(SettingsService.lastSeenAppVersion), '2.0.0');
  });
}
