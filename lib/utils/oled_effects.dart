import '../services/device_performance.dart';
import '../services/settings_service.dart' as settings;

/// Which of the OLED focus effects are on.
///
/// They belong to the OLED theme only, and sit out the reduced-performance
/// tier where blurred shadows are too costly. Read at build time, like the
/// existing Focus Glow setting.
abstract final class OledEffects {
  static bool get _active {
    final service = settings.SettingsService.instanceOrNull;
    if (service == null || DevicePerformance.isReduced) return false;
    return service.read(settings.SettingsService.themeMode) == settings.ThemeMode.oled;
  }

  static bool _on(settings.BoolPref pref) => _active && settings.SettingsService.instance.read(pref);

  static bool get posterGlow => _on(settings.SettingsService.oledPosterGlow);

  static bool get spotlight => _on(settings.SettingsService.oledSpotlight);

  static bool get colorBleed => _on(settings.SettingsService.oledColorBleed);

  /// Whether anything needs the focused poster's colour.
  static bool get needsPosterColor => posterGlow || colorBleed;
}
