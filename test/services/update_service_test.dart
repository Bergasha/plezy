import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:plezy/utils/media_server_http_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/base_shared_preferences_service.dart';
import 'package:plezy/services/update_service.dart';

import '../test_helpers/prefs.dart';

void main() {
  const lastCheckKey = 'update_last_check_time';

  setUp(resetSharedPreferencesForTest);
  PackageInfo.setMockInitialValues(
    appName: 'Plezy',
    packageName: 'com.plezy.test',
    version: '1.0.0',
    buildNumber: '1',
    buildSignature: '',
  );

  test('malformed cooldown state fails open and removes the invalid value', () async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setString(lastCheckKey, 'not-an-instant');

    expect(await UpdateService.shouldCheckForUpdates(), isTrue);
    expect(prefs.getString(lastCheckKey), isNull);
  });

  test('future cooldown state fails open and removes the invalid value', () async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setString(lastCheckKey, DateTime.now().add(const Duration(days: 30)).toIso8601String());

    expect(await UpdateService.shouldCheckForUpdates(), isTrue);
    expect(prefs.getString(lastCheckKey), isNull);
  });

  test('recent valid cooldown state suppresses a duplicate check and remains stored', () async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    final recent = DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String();
    await prefs.setString(lastCheckKey, recent);

    expect(await UpdateService.shouldCheckForUpdates(), isFalse);
    expect(prefs.getString(lastCheckKey), recent);
  });

  test('old valid cooldown state permits a new check', () async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    final old = DateTime.now().subtract(const Duration(days: 2)).toIso8601String();
    await prefs.setString(lastCheckKey, old);

    expect(await UpdateService.shouldCheckForUpdates(), isTrue);
    expect(prefs.getString(lastCheckKey), old);
  });

  final failedResponses = <String, Future<http.Response> Function()>{
    'timeout': () async => throw TimeoutException('request timed out'),
    'non-200 response': () async => http.Response('unavailable', 503),
    'parse failure': () async => http.Response('not-json', 200, headers: {'content-type': 'application/json'}),
  };

  for (final failure in failedResponses.entries) {
    test('startup ${failure.key} records cooldown before request and manual check bypasses it', () async {
      final prefs = await BaseSharedPreferencesService.sharedCache();
      final cooldownAtRequest = <String?>[];
      var requestCount = 0;
      final client = MediaServerHttpClient(
        client: MockClient((_) async {
          requestCount++;
          cooldownAtRequest.add(prefs.getString(lastCheckKey));
          return failure.value();
        }),
      );
      addTearDown(client.close);

      expect(await UpdateService.debugPerformUpdateCheck(respectCooldown: true, client: client), isNull);
      expect(requestCount, 1);
      expect(cooldownAtRequest.single, isNotNull);
      final recordedCooldown = prefs.getString(lastCheckKey);
      expect(recordedCooldown, cooldownAtRequest.single);
      expect(DateTime.now().difference(DateTime.parse(recordedCooldown!)), lessThan(const Duration(minutes: 1)));

      expect(await UpdateService.debugPerformUpdateCheck(respectCooldown: true, client: client), isNull);
      expect(requestCount, 1, reason: 'a simulated next launch must honor the failed attempt cooldown');

      expect(await UpdateService.debugPerformUpdateCheck(respectCooldown: false, client: client), isNull);
      expect(requestCount, 2, reason: 'an explicit manual check must bypass a recent startup cooldown');
      expect(
        prefs.getString(lastCheckKey),
        recordedCooldown,
        reason: 'manual checks must not rewrite startup cooldown',
      );
    });
  }

  http.Response manifestResponse(Map<String, dynamic> body, {int status = 200}) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

  test('a newer manifest version surfaces the platform-appropriate download URL', () async {
    final client = MediaServerHttpClient(
      client: MockClient(
        (_) async => manifestResponse({
          'version': '9.9.9',
          'name': 'Plezy 9.9.9',
          'notes': 'Big release',
          'published_at': '2026-01-01T00:00:00Z',
          'apk_url': 'https://plezy.shayno.net/plezy-latest.apk',
          'windows_url': 'https://plezy.shayno.net/plezy-windows-installer.exe',
        }),
      ),
    );
    addTearDown(client.close);

    final result = await UpdateService.debugPerformUpdateCheck(respectCooldown: false, client: client);

    expect(result, isNotNull);
    expect(result!['hasUpdate'], isTrue);
    expect(result['latestVersion'], '9.9.9');
    expect(result['currentVersion'], '1.0.0');
    expect(result['releaseName'], 'Plezy 9.9.9');
    expect(result['releaseNotes'], 'Big release');
    final expectedUrl = Platform.isAndroid
        ? 'https://plezy.shayno.net/plezy-latest.apk'
        : 'https://plezy.shayno.net/plezy-windows-installer.exe';
    expect(result['releaseUrl'], expectedUrl);
  });

  test('a manifest version no newer than the current one reports no update', () async {
    final client = MediaServerHttpClient(
      client: MockClient((_) async => manifestResponse({'version': '1.0.0', 'apk_url': 'x', 'windows_url': 'x'})),
    );
    addTearDown(client.close);

    expect(await UpdateService.debugPerformUpdateCheck(respectCooldown: false, client: client), isNull);
  });

  test('a skipped version is not offered again even though it is newer', () async {
    await UpdateService.skipVersion('9.9.9');
    final client = MediaServerHttpClient(
      client: MockClient((_) async => manifestResponse({'version': '9.9.9', 'apk_url': 'x', 'windows_url': 'x'})),
    );
    addTearDown(client.close);

    expect(await UpdateService.debugPerformUpdateCheck(respectCooldown: false, client: client), isNull);
  });

  test('a manifest with no download URL for this platform reports no update rather than a broken link', () async {
    final client = MediaServerHttpClient(
      client: MockClient((_) async => manifestResponse({'version': '9.9.9', 'notes': 'no builds for you'})),
    );
    addTearDown(client.close);

    expect(await UpdateService.debugPerformUpdateCheck(respectCooldown: false, client: client), isNull);
  });
}
