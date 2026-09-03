import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:auto_updater/auto_updater.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:plezy/utils/app_logger.dart';
import 'package:plezy/utils/media_server_http_client.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'base_shared_preferences_service.dart';

/// Service to check for new versions of this fork, self-hosted rather than
/// upstream's GitHub-releases/Sparkle-appcast setup: a small static JSON
/// manifest at [_updateManifestUrl] (uploaded by hand alongside each new
/// build) names the current version and where to download it per platform.
/// Enabled by default — [isUpdateCheckEnabled] can still turn it off via
/// the ENABLE_UPDATE_CHECK build flag if ever needed.
///
/// No native Sparkle/WinSparkle path: that needs a signed appcast per
/// release, which this fork's simpler self-hosted setup doesn't produce.
/// Every platform gets the same in-app "update available" dialog with a
/// download link (see lib/utils/update_dialog.dart) — Android downloads the
/// APK and the user installs it as usual; Windows downloads the installer.
class UpdateService {
  static const String _updateManifestUrl = 'https://plezy.shayno.net/latest.json';
  // Unused while useNativeUpdater is hardcoded false below, but
  // initNativeUpdater/checkForUpdatesNative still reference it — dead call
  // sites in main_screen.dart/settings_screen.dart still have to compile.
  static const String _feedUrl = 'https://cdn.jsdelivr.net/gh/edde746/plezy@appcast/appcast.xml';

  static const String _keySkippedVersion = 'update_skipped_version';
  static const String _keyLastCheckTime = 'update_last_check_time';

  // Check cooldown: 6 hours
  static const Duration _checkCooldown = Duration(hours: 6);

  static bool _nativeUpdaterInitialized = false;

  /// Check if update checking is enabled via build flag
  static bool get isUpdateCheckEnabled {
    return const bool.fromEnvironment('ENABLE_UPDATE_CHECK', defaultValue: true);
  }

  /// Whether any in-app update path applies to this install.
  /// False inside a packaged (MSIX/Store) install: the Store owns updates and
  /// the package directory is read-only, so the download-link dialog has
  /// nothing it can do. Gates the settings entry too, so no dead affordance
  /// ships.
  static bool get isUpdateCheckAvailable => isUpdateCheckEnabled && !PlatformDetector.isPackagedInstall();

  /// No native updater on this fork — see the class doc. Kept as a getter
  /// (rather than deleting every call site) so re-adding a signed appcast
  /// later is a one-line change here instead of touching main_screen.dart
  /// and settings_screen.dart again.
  static bool get useNativeUpdater => false;

  /// Initialize the native auto_updater (Sparkle/WinSparkle).
  /// Call once at startup if [useNativeUpdater] is true.
  static Future<void> initNativeUpdater() async {
    if (_nativeUpdaterInitialized) return;

    try {
      await autoUpdater.setFeedURL(_feedUrl);
      _nativeUpdaterInitialized = true;
    } catch (error, stackTrace) {
      appLogger.e('Failed to initialize native auto updater', error: error, stackTrace: stackTrace);
    }
  }

  /// Trigger a background update check via Sparkle/WinSparkle.
  /// Only shows UI if an update is found.
  static Future<void> checkForUpdatesNative({bool inBackground = true}) async {
    if (!_nativeUpdaterInitialized) {
      await initNativeUpdater();
      if (!_nativeUpdaterInitialized) return;
    }
    try {
      await autoUpdater.checkForUpdates(inBackground: inBackground);
    } catch (error, stackTrace) {
      appLogger.e('Native update check failed', error: error, stackTrace: stackTrace);
    }
  }

  static Future<void> skipVersion(String version) async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setString(_keySkippedVersion, version);
  }

  static Future<String?> getSkippedVersion() async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    return prefs.getString(_keySkippedVersion);
  }

  /// Check if cooldown period has passed since last check
  static Future<bool> shouldCheckForUpdates() async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    final lastCheckString = prefs.getString(_keyLastCheckTime);
    if (lastCheckString == null) return true;

    final now = DateTime.now();
    final lastCheck = DateTime.tryParse(lastCheckString);
    if (lastCheck == null || lastCheck.isAfter(now)) {
      await prefs.remove(_keyLastCheckTime);
      return true;
    }

    return now.difference(lastCheck) >= _checkCooldown;
  }

  static Future<void> _updateLastCheckTime() async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setString(_keyLastCheckTime, DateTime.now().toIso8601String());
  }

  /// Internal method that performs the actual update check
  /// [respectCooldown] - if true, checks cooldown and records the attempt before the request
  static Future<Map<String, dynamic>?> _performUpdateCheck({
    required bool respectCooldown,
    MediaServerHttpClient? client,
    bool forceEnabled = false,
  }) async {
    if (!forceEnabled && !isUpdateCheckAvailable) {
      return null;
    }

    // Check cooldown if requested
    if (respectCooldown && !await shouldCheckForUpdates()) {
      return null;
    }

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      if (respectCooldown) {
        await _updateLastCheckTime();
      }

      final response = await (client ?? httpClient).get(_updateManifestUrl);

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final latestVersion = data['version'] as String;

        // Remove 'v' prefix if present
        final cleanVersion = latestVersion.startsWith('v') ? latestVersion.substring(1) : latestVersion;

        final hasUpdate = _isNewerVersion(cleanVersion, currentVersion);

        if (hasUpdate) {
          // Check if this version was skipped
          final skippedVersion = await getSkippedVersion();
          if (skippedVersion == cleanVersion) {
            return null;
          }

          // Only Android and Windows builds are actually produced right
          // now (see plezy-windows-installer.exe / app-release.apk); no
          // entry for this platform means nothing to offer.
          final downloadUrl = Platform.isAndroid
              ? data['apk_url'] as String?
              : Platform.isWindows
              ? data['windows_url'] as String?
              : null;
          if (downloadUrl == null) return null;

          return {
            'hasUpdate': true,
            'currentVersion': currentVersion,
            'latestVersion': cleanVersion,
            'releaseUrl': downloadUrl,
            'releaseName': data['name'] as String? ?? 'Plezy $cleanVersion',
            'releaseNotes': data['notes'] as String? ?? '',
            'publishedAt': data['published_at'] as String? ?? '',
          };
        }
      }
    } catch (error, stackTrace) {
      appLogger.e('Failed to check for updates', error: error, stackTrace: stackTrace);
    }

    return null;
  }

  @visibleForTesting
  static Future<Map<String, dynamic>?> debugPerformUpdateCheck({
    required bool respectCooldown,
    required MediaServerHttpClient client,
  }) {
    return _performUpdateCheck(respectCooldown: respectCooldown, client: client, forceEnabled: true);
  }

  /// Check for updates on GitHub (manual check, ignores cooldown)
  /// Returns a map with update info, or null if no update or error
  static Future<Map<String, dynamic>?> checkForUpdates() {
    return _performUpdateCheck(respectCooldown: false);
  }

  /// Check for updates on startup (respects cooldown and skipped versions)
  /// Returns update info if available, null otherwise
  static Future<Map<String, dynamic>?> checkForUpdatesOnStartup() {
    return _performUpdateCheck(respectCooldown: true);
  }

  /// Parse version string into list of integers
  /// Handles versions like "1.2.3+4" by taking only the numeric parts
  static List<int> _parseVersionParts(String version) {
    return version.split('.').map((p) {
      final numPart = p.split('+').first.split('-').first;
      return int.tryParse(numPart) ?? 0;
    }).toList();
  }

  /// Compare two version strings
  /// Returns true if newVersion is newer than currentVersion
  static bool _isNewerVersion(String newVersion, String currentVersion) {
    try {
      final newParts = _parseVersionParts(newVersion);
      final currentParts = _parseVersionParts(currentVersion);

      // Compare each part
      final maxLength = newParts.length > currentParts.length ? newParts.length : currentParts.length;

      for (int i = 0; i < maxLength; i++) {
        final newPart = i < newParts.length ? newParts[i] : 0;
        final currentPart = i < currentParts.length ? currentParts[i] : 0;

        if (newPart > currentPart) return true;
        if (newPart < currentPart) return false;
      }

      return false;
    } catch (error, stackTrace) {
      appLogger.e('Error comparing versions', error: error, stackTrace: stackTrace);
      return false;
    }
  }
}
