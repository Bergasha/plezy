import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/media_card.dart';
import 'package:plezy/widgets/tv_extras_strip.dart';
import 'package:provider/provider.dart';

import '../test_helpers/media_items.dart';
import '../test_helpers/multi_server_fixtures.dart';
import '../test_helpers/prefs.dart';

final _extras = [
  testMediaItem(id: 'extra_1', backend: MediaBackend.plex, kind: MediaKind.clip, title: 'Trailer'),
  testMediaItem(id: 'extra_2', backend: MediaBackend.plex, kind: MediaKind.clip, title: 'Behind the Scenes'),
];

Widget _wrap(Widget child) {
  final serverManager = MultiServerManager();
  return ChangeNotifierProvider<MultiServerProvider>(
    create: (_) => testMultiServerProvider(serverManager),
    child: MaterialApp(theme: monoTheme(dark: true), home: Scaffold(body: child)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  testWidgets('owns horizontal focus and delegates vertical section navigation', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final key = GlobalKey<TvExtrasStripState>();
    var navigatedUp = 0;
    var navigatedDown = 0;

    await tester.pumpWidget(
      _wrap(
        TvExtrasStrip(
          key: key,
          extras: _extras,
          onNavigateUp: () => navigatedUp++,
          onNavigateDown: () => navigatedDown++,
        ),
      ),
    );

    key.currentState!.requestFocus();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_extras_row');

    // LEFT/RIGHT move the highlighted card within the strip (handled, no
    // navigation callback fired) rather than falling through to the screen.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(navigatedUp, 0);
    expect(navigatedDown, 0);

    // UP/DOWN delegate to the parent screen's vertical navigation chain.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(navigatedUp, 1);
    expect(navigatedDown, 1);
  });

  testWidgets('renders one card per extra', (tester) async {
    await tester.pumpWidget(_wrap(TvExtrasStrip(extras: _extras)));

    final cards = tester.widgetList<MediaCard>(find.byType(MediaCard));
    expect(cards, hasLength(_extras.length));
  });

  testWidgets('clamps its focus index when the extras list changes', (tester) async {
    final key = GlobalKey<TvExtrasStripState>();
    var extras = _extras;
    late StateSetter setHostState;

    await tester.pumpWidget(
      _wrap(
        StatefulBuilder(
          builder: (context, setState) {
            setHostState = setState;
            return TvExtrasStrip(key: key, extras: extras);
          },
        ),
      ),
    );

    key.currentState!.requestFocus();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    setHostState(() => extras = const []);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('requestFocus is a no-op when there are no extras', (tester) async {
    final key = GlobalKey<TvExtrasStripState>();

    await tester.pumpWidget(_wrap(TvExtrasStrip(key: key, extras: const [])));

    key.currentState!.requestFocus();
    await tester.pump();

    expect(FocusManager.instance.primaryFocus?.debugLabel, isNot('tv_extras_row'));
  });
}
