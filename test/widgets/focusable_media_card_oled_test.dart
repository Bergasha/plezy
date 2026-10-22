import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/focus/focus_glow_overlay.dart';
import 'package:plezy/focus/oled_spotlight.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/focusable_media_card.dart';
import 'package:plezy/widgets/media_card.dart';

import '../test_helpers/media_items.dart';
import '../test_helpers/prefs.dart';

MediaItem _movie(String id) => testMediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: 'Movie $id',
  year: 2022,
  durationMs: const Duration(hours: 2).inMilliseconds,
);

Future<List<FocusNode>> _pumpCards(WidgetTester tester, {required bool withHost}) async {
  final nodes = [FocusNode(debugLabel: 'a'), FocusNode(debugLabel: 'b'), FocusNode(debugLabel: 'c')];
  addTearDown(() {
    for (final node in nodes) {
      node.dispose();
    }
  });
  Widget grid = Scaffold(
    body: Row(
      children: [
        for (final (index, node) in nodes.indexed)
          SizedBox(
            width: 220,
            height: 330,
            child: FocusableMediaCard(
              item: _movie('m$index'),
              focusNode: node,
              width: 220,
              height: 280,
              viewModeOverride: ViewMode.grid,
              isOffline: true,
            ),
          ),
      ],
    ),
  );
  if (withHost) grid = OledSpotlightHost(child: grid);
  grid = InputModeTracker(child: grid);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1000, 600);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(MaterialApp(theme: monoTheme(dark: true), home: grid));
  await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
  await tester.pump();
  FocusManager.instance.primaryFocus?.unfocus();
  await _settle(tester);
  return nodes;
}

List<double> _dims(WidgetTester tester) => [
  for (final card in tester.widgetList<MediaCard>(find.byType(MediaCard))) card.artworkDim?.value ?? -1,
];

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    await initializeDateFormatting('en');
  });

  testWidgets('focusing a card dims the others and leaves it bright', (tester) async {
    final nodes = await _pumpCards(tester, withHost: true);
    expect(_dims(tester), everyElement(0), reason: 'nothing is spotlit before anything is focused');

    nodes[1].requestFocus();
    await _settle(tester);

    final dims = _dims(tester);
    expect(dims[1], 0);
    expect(dims[0], greaterThan(0.3));
    expect(dims[2], greaterThan(0.3));
  });

  testWidgets('moving focus fades the old card down and the new one up', (tester) async {
    final nodes = await _pumpCards(tester, withHost: true);
    nodes[0].requestFocus();
    await _settle(tester);

    nodes[2].requestFocus();
    await _settle(tester);

    final dims = _dims(tester);
    expect(dims[2], 0);
    expect(dims[0], greaterThan(0.3));
    expect(dims[1], greaterThan(0.3));
  });

  testWidgets('leaving the grid releases the spotlight', (tester) async {
    final nodes = await _pumpCards(tester, withHost: true);
    nodes[1].requestFocus();
    await _settle(tester);

    nodes[1].unfocus();
    await _settle(tester);

    expect(_dims(tester), everyElement(0));
  });

  testWidgets('without a spotlight host the cards never dim', (tester) async {
    final nodes = await _pumpCards(tester, withHost: false);
    nodes[1].requestFocus();
    await _settle(tester);

    expect(tester.widgetList<MediaCard>(find.byType(MediaCard)).map((card) => card.artworkDim), everyElement(isNull));
  });

  testWidgets('the dim setting turns the spotlight off', (tester) async {
    await SettingsService.instance.write(SettingsService.oledSpotlight, false);
    final nodes = await _pumpCards(tester, withHost: true);
    nodes[1].requestFocus();
    await _settle(tester);

    expect(tester.widgetList<MediaCard>(find.byType(MediaCard)).map((card) => card.artworkDim), everyElement(isNull));
  });

  testWidgets('only the focused poster glows', (tester) async {
    final nodes = await _pumpCards(tester, withHost: true);
    nodes[1].requestFocus();
    await _settle(tester);

    final glowing = tester.widgetList<FocusGlowOverlay>(find.byType(FocusGlowOverlay)).where((g) => g.isFocused);
    expect(glowing, hasLength(1));
  });

  testWidgets('the glow settings turn the poster glow off', (tester) async {
    await SettingsService.instance.write(SettingsService.oledPosterGlow, false);
    await SettingsService.instance.write(SettingsService.oledColorBleed, false);
    final nodes = await _pumpCards(tester, withHost: true);
    nodes[1].requestFocus();
    await _settle(tester);

    expect(find.byType(FocusGlowOverlay), findsNothing);
  });
}
