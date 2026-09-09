import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'settings_service.dart';

/// Bundled "what's new" bullet points, shown once right after an update to
/// whichever version key they're listed under — not fetched from the
/// network, so it's available instantly at launch and never depends on the
/// update manifest being reachable.
///
/// Keyed by the semantic version only (matches `pubspec.yaml`'s version
/// before the `+buildNumber`). Deliberately sparse: most releases (fixes,
/// dependency bumps, internal refactors) have no entry here at all, and
/// [WhatsNewService.checkAndConsume] treats a missing entry as "nothing
/// worth announcing" rather than a fallback to generic notes. Add an entry
/// only when a release ships something a non-technical user would actually
/// notice — plain language, a handful of bullets at most.
const Map<String, List<String>> _whatsNewByVersion = {
  '2.17.18': [
    'Long-press a movie or show to report a problem straight to Shayno',
    'Vote "This was Good" or "This was Shit" on anything you watch',
    'Plezy now updates itself — no more downloading a new version by hand',
  ],
  '2.17.19': ['Bug fixes and improvements'],
  '2.17.20': ['Theme music now plays while browsing TV shows', 'A few bug fixes'],
  '2.17.24': ['Report issues straight from Plezy', 'Bug fixes and improvements'],
};

abstract final class WhatsNewService {
  /// Replaces [_whatsNewByVersion] in tests. Reset to null in `tearDown`.
  @visibleForTesting
  static Map<String, List<String>>? debugEntriesOverride;

  /// Call once per app startup. Returns the bullet list to show if the
  /// current version has one and it hasn't been shown before on this
  /// device, otherwise null. Always records the current version as seen, so
  /// a version is never announced twice.
  ///
  /// Deliberately does not special-case a fresh install (no prior recorded
  /// version): that would also silently swallow the very first rollout of
  /// this feature for every existing user, since none of them have a
  /// recorded version yet either. Entries are only ever added for changes
  /// worth a one-time mention regardless of whether this is someone's
  /// first launch or their fiftieth, so showing on a fresh install too is
  /// harmless.
  static Future<List<String>?> checkAndConsume() async {
    final settings = await SettingsService.getInstance();
    final previousVersion = settings.read(SettingsService.lastSeenAppVersion);
    final currentVersion = (await PackageInfo.fromPlatform()).version;

    if (previousVersion == currentVersion) return null;
    await settings.write(SettingsService.lastSeenAppVersion, currentVersion);

    return (debugEntriesOverride ?? _whatsNewByVersion)[currentVersion];
  }
}
