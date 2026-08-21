import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/media/server_capabilities.dart';
import 'package:plezy/providers/libraries_provider.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/services/data_aggregation_service.dart';
import 'package:plezy/services/gamepad_service.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/utils/media_server_http_client.dart';
import 'package:plezy/widgets/cycling_media_backdrop.dart';
import 'package:plezy/widgets/idle_screensaver_overlay.dart';

import '../test_helpers/media_items.dart';
import '../test_helpers/prefs.dart';

class _FakeAggregationService extends DataAggregationService {
  _FakeAggregationService(super.serverManager);

  List<MediaLibrary> libraryResult = const [];

  @override
  Future<LibraryAggregationResult> getMediaLibrariesFromAllServers({Set<String>? serverIds}) async {
    return (
      libraries: libraryResult,
      succeededServerIds: const {'server_1'},
      cancelledServerIds: const <String>{},
      failedServerIds: const <String>{},
    );
  }
}

class _FakeClient implements MediaServerClient {
  List<MediaItem> libraryContent = const [];

  @override
  ServerId get serverId => ServerId('server_1');

  @override
  String? get serverName => 'Server';

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  String thumbnailUrl(String? path, {int? width, int? height, bool cover = true}) => 'https://test/$path';

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async {
    return LibraryPage(items: libraryContent, totalCount: libraryContent.length);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeClient client;
  late MultiServerManager manager;
  late _FakeAggregationService aggregation;
  late MultiServerProvider multiServer;
  late LibrariesProvider libraries;

  final movieLibrary = MediaLibrary(
    id: 'lib1',
    backend: MediaBackend.plex,
    title: 'Movies',
    kind: MediaKind.movie,
    serverId: 'server_1',
  );

  final kidsMovieLibrary = MediaLibrary(
    id: 'lib2',
    backend: MediaBackend.plex,
    title: 'Kids Movies',
    kind: MediaKind.movie,
    serverId: 'server_1',
  );

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    LocaleSettings.setLocaleSync(AppLocale.en);
    await initializeDateFormatting('en');

    client = _FakeClient();
    manager = MultiServerManager()..debugRegisterClientForTesting(client);
    aggregation = _FakeAggregationService(manager);
    multiServer = MultiServerProvider(manager, aggregation);
    libraries = LibrariesProvider();
    libraries.initialize(aggregation);
  });

  Future<void> pumpOverlay(WidgetTester tester) {
    return tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
          ChangeNotifierProvider<LibrariesProvider>.value(value: libraries),
        ],
        child: const MaterialApp(home: IdleScreensaverOverlay()),
      ),
    );
  }

  testWidgets('stays hidden past the idle timeout while disabled', (tester) async {
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.screensaverIdleMinutes, 1);
    aggregation.libraryResult = [movieLibrary];
    client.libraryContent = [testMediaItem(id: 'a', title: 'Movie A', artPath: '/art/a.jpg', serverId: 'server_1')];
    await tester.runAsync(() => libraries.loadLibraries());

    await pumpOverlay(tester);
    await tester.pump(const Duration(minutes: 2));

    expect(find.byType(CyclingMediaBackdrop), findsNothing);
  });

  testWidgets('shows a random backdrop after the idle timeout once enabled', (tester) async {
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.screensaverIdleMinutes, 1);
    await settings.write(SettingsService.screensaverEnabled, true);
    aggregation.libraryResult = [movieLibrary];
    client.libraryContent = [testMediaItem(id: 'a', title: 'Movie A', artPath: '/art/a.jpg', serverId: 'server_1')];
    await tester.runAsync(() => libraries.loadLibraries());

    await pumpOverlay(tester);
    await tester.pump(const Duration(minutes: 2));
    await tester.pump();

    expect(find.byType(CyclingMediaBackdrop), findsOneWidget);
  });

  testWidgets('does not show when no library art is available', (tester) async {
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.screensaverIdleMinutes, 1);
    await settings.write(SettingsService.screensaverEnabled, true);
    aggregation.libraryResult = const [];
    await tester.runAsync(() => libraries.loadLibraries());

    await pumpOverlay(tester);
    await tester.pump(const Duration(minutes: 2));
    await tester.pump();

    expect(find.byType(CyclingMediaBackdrop), findsNothing);
  });

  testWidgets('skips kids libraries even though they share the movie/show kind', (tester) async {
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.screensaverIdleMinutes, 1);
    await settings.write(SettingsService.screensaverEnabled, true);
    // Only a kids library is available — the primary-name filter should
    // reject it, leaving nothing to sample from.
    aggregation.libraryResult = [kidsMovieLibrary];
    client.libraryContent = [
      testMediaItem(id: 'k', title: 'Kids Movie', artPath: '/art/k.jpg', serverId: 'server_1'),
    ];
    await tester.runAsync(() => libraries.loadLibraries());

    await pumpOverlay(tester);
    await tester.pump(const Duration(minutes: 2));
    await tester.pump();

    expect(find.byType(CyclingMediaBackdrop), findsNothing);
  });

  testWidgets('reveals the title a few seconds after the backdrop appears', (tester) async {
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.screensaverIdleMinutes, 1);
    await settings.write(SettingsService.screensaverEnabled, true);
    aggregation.libraryResult = [movieLibrary];
    client.libraryContent = [testMediaItem(id: 'a', title: 'Movie A', artPath: '/art/a.jpg', serverId: 'server_1')];
    await tester.runAsync(() => libraries.loadLibraries());

    await pumpOverlay(tester);
    await tester.pump(const Duration(minutes: 2));
    await tester.pump();
    expect(find.byType(CyclingMediaBackdrop), findsOneWidget);

    // Not yet — the title only appears a few seconds after the backdrop.
    expect(find.text('Movie A'), findsNothing);

    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Movie A'), findsOneWidget);
  });

  testWidgets('dismisses on a key press and re-arms the idle timer', (tester) async {
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.screensaverIdleMinutes, 1);
    await settings.write(SettingsService.screensaverEnabled, true);
    aggregation.libraryResult = [movieLibrary];
    client.libraryContent = [testMediaItem(id: 'a', title: 'Movie A', artPath: '/art/a.jpg', serverId: 'server_1')];
    await tester.runAsync(() => libraries.loadLibraries());

    await pumpOverlay(tester);
    await tester.pump(const Duration(minutes: 2));
    await tester.pump();
    expect(find.byType(CyclingMediaBackdrop), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(find.byType(CyclingMediaBackdrop), findsNothing);

    // Re-armed: waiting out a fresh idle window brings it back.
    await tester.pump(const Duration(minutes: 2));
    await tester.pump();
    expect(find.byType(CyclingMediaBackdrop), findsOneWidget);
  });

  testWidgets('dismisses on tap', (tester) async {
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.screensaverIdleMinutes, 1);
    await settings.write(SettingsService.screensaverEnabled, true);
    aggregation.libraryResult = [movieLibrary];
    client.libraryContent = [testMediaItem(id: 'a', title: 'Movie A', artPath: '/art/a.jpg', serverId: 'server_1')];
    await tester.runAsync(() => libraries.loadLibraries());

    await pumpOverlay(tester);
    await tester.pump(const Duration(minutes: 2));
    await tester.pump();
    expect(find.byType(CyclingMediaBackdrop), findsOneWidget);

    // The dismiss gesture belongs to the enclosing GestureDetector; the
    // gradient scrim painted above the backdrop is the literal hit target.
    await tester.tap(find.byType(CyclingMediaBackdrop), warnIfMissed: false);
    await tester.pump();
    expect(find.byType(CyclingMediaBackdrop), findsNothing);
  });

  testWidgets('dismisses on gamepad/remote input, not just mouse movement', (tester) async {
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.screensaverIdleMinutes, 1);
    await settings.write(SettingsService.screensaverEnabled, true);
    aggregation.libraryResult = [movieLibrary];
    client.libraryContent = [testMediaItem(id: 'a', title: 'Movie A', artPath: '/art/a.jpg', serverId: 'server_1')];
    await tester.runAsync(() => libraries.loadLibraries());

    await pumpOverlay(tester);
    await tester.pump(const Duration(minutes: 2));
    await tester.pump();
    expect(find.byType(CyclingMediaBackdrop), findsOneWidget);

    // A Shield remote / gamepad button press arrives as a GamepadEvent, not
    // a standard KeyEvent — this is the path that used to be missed.
    GamepadService.debugNotifyGamepadInput();
    await tester.pump();
    expect(find.byType(CyclingMediaBackdrop), findsNothing);
  });
}
