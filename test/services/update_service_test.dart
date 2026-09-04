import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plezy/exceptions/media_server_exceptions.dart';
import 'package:plezy/utils/media_server_http_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/base_shared_preferences_service.dart';
import 'package:plezy/services/update_service.dart';

import '../test_helpers/io_fakes.dart';
import '../test_helpers/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const lastCheckKey = 'update_last_check_time';
  const installerChannel = MethodChannel('com.plezy/app_installer');

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

  group('downloadAndInstallAndroidUpdate', () {
    late Directory tmpRoot;
    late PathProviderPlatform previousPathProvider;

    setUp(() async {
      tmpRoot = await Directory.systemTemp.createTemp('update_service_test_');
      previousPathProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = FakePathProvider(tmpRoot);
    });

    tearDown(() async {
      PathProviderPlatform.instance = previousPathProvider;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        installerChannel,
        null,
      );
      if (await tmpRoot.exists()) {
        await tmpRoot.delete(recursive: true);
      }
    });

    test(
      'streams the download to app-private cache, reports progress, and hands the path to the installer channel',
      () async {
        final bytes = List<int>.generate(1000, (i) => i % 256);
        final client = MockClient((_) async => http.Response.bytes(bytes, 200));

        final progressValues = <double?>[];
        String? installedPath;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(installerChannel, (
          call,
        ) async {
          expect(call.method, 'install');
          installedPath = (call.arguments as Map)['filePath'] as String;
          return true;
        });

        await UpdateService.downloadAndInstallAndroidUpdate(
          url: 'https://plezy.shayno.net/app-release.apk',
          onProgress: progressValues.add,
          client: client,
        );

        expect(progressValues, isNotEmpty);
        expect(progressValues.last, 1.0);
        expect(installedPath, isNotNull);
        expect(installedPath, contains('plezy-update.apk'));
        // The app's own copy is deleted once the platform call returns — the
        // installer session already holds its own copy of the bytes by then.
        expect(await File(installedPath!).exists(), isFalse);
      },
    );

    test('sweeps a stale file left over from an earlier interrupted download before starting a new one', () async {
      final updateDir = Directory('${tmpRoot.path}/temp/plezy-update');
      await updateDir.create(recursive: true);
      final staleFile = File('${updateDir.path}/plezy-update.apk');
      await staleFile.writeAsBytes(List<int>.filled(10, 1));
      expect(await staleFile.exists(), isTrue);

      final client = MockClient((_) async => http.Response.bytes([1, 2, 3], 200));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        installerChannel,
        (call) async => true,
      );

      await UpdateService.downloadAndInstallAndroidUpdate(
        url: 'https://plezy.shayno.net/app-release.apk',
        onProgress: (_) {},
        client: client,
      );

      // Swept before the new download started, and the new download's own
      // file is gone too once the install call returns.
      expect(await staleFile.exists(), isFalse);
    });

    test('propagates a download failure and never reaches the installer channel', () async {
      final client = MockClient((_) async => http.Response('server error', 500));
      var installCalled = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(installerChannel, (
        call,
      ) async {
        installCalled = true;
        return true;
      });

      await expectLater(
        UpdateService.downloadAndInstallAndroidUpdate(
          url: 'https://plezy.shayno.net/app-release.apk',
          onProgress: (_) {},
          client: client,
        ),
        throwsA(isA<MediaServerHttpException>()),
      );

      expect(installCalled, isFalse);
    });

    test('propagates an installer-channel failure to the caller', () async {
      final client = MockClient((_) async => http.Response.bytes([1, 2, 3], 200));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(installerChannel, (
        call,
      ) async {
        throw PlatformException(code: 'INSTALL_FAILED', message: 'boom');
      });

      await expectLater(
        UpdateService.downloadAndInstallAndroidUpdate(
          url: 'https://plezy.shayno.net/app-release.apk',
          onProgress: (_) {},
          client: client,
        ),
        throwsA(isA<PlatformException>()),
      );
    });
  });
}
