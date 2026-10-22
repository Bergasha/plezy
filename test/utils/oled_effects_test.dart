import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/utils/oled_effects.dart';

import '../test_helpers/prefs.dart';

void main() {
  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  test('every effect is on by default under the OLED theme', () {
    expect(SettingsService.instance.read(SettingsService.themeMode), ThemeMode.oled);
    expect(OledEffects.posterGlow, isTrue);
    expect(OledEffects.spotlight, isTrue);
    expect(OledEffects.colorBleed, isTrue);
    expect(OledEffects.needsPosterColor, isTrue);
  });

  test('each effect follows its own setting', () async {
    await SettingsService.instance.write(SettingsService.oledPosterGlow, false);

    expect(OledEffects.posterGlow, isFalse);
    expect(OledEffects.colorBleed, isTrue);
    expect(OledEffects.needsPosterColor, isTrue, reason: 'the bleed still needs the colour');

    await SettingsService.instance.write(SettingsService.oledColorBleed, false);

    expect(OledEffects.needsPosterColor, isFalse);
    expect(OledEffects.spotlight, isTrue, reason: 'dimming needs no colour');
  });

  test('none of them apply outside the OLED theme', () async {
    await SettingsService.instance.write(SettingsService.themeMode, ThemeMode.dark);

    expect(OledEffects.posterGlow, isFalse);
    expect(OledEffects.spotlight, isFalse);
    expect(OledEffects.colorBleed, isFalse);
  });
}
