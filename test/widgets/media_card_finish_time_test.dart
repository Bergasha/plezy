import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/media_card.dart';

import '../test_helpers/media_items.dart';
import '../test_helpers/prefs.dart';

MediaItem _item(MediaKind kind, {int? year = 2022, int? durationMs, int? viewOffsetMs}) => testMediaItem(
  id: '${kind.id}_1',
  backend: MediaBackend.plex,
  kind: kind,
  title: 'Test ${kind.id}',
  year: year,
  durationMs: durationMs,
  viewOffsetMs: viewOffsetMs,
);

Future<void> _pumpCard(WidgetTester tester, MediaItem item) => tester.pumpWidget(
  MaterialApp(
    theme: monoTheme(dark: true),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 220,
          height: 330,
          child: MediaCard(item: item, width: 220, height: 280, viewModeOverride: ViewMode.grid, isOffline: true),
        ),
      ),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    await initializeDateFormatting('en');
  });

  test('a fresh item finishes its whole runtime from now', () {
    final now = DateTime(2026, 10, 20, 19, 30);
    final item = _item(MediaKind.movie, durationMs: const Duration(hours: 2, minutes: 10).inMilliseconds);

    expect(mediaFinishTime(item, now), DateTime(2026, 10, 20, 21, 40));
  });

  test('a partly watched item finishes what is left of it', () {
    final now = DateTime(2026, 10, 20, 19, 30);
    final item = _item(
      MediaKind.movie,
      durationMs: const Duration(hours: 2).inMilliseconds,
      viewOffsetMs: const Duration(minutes: 90).inMilliseconds,
    );

    expect(mediaFinishTime(item, now), DateTime(2026, 10, 20, 20, 0));
  });

  test('a resume point at or past the end counts as a fresh start', () {
    final now = DateTime(2026, 10, 20, 19, 30);
    final item = _item(
      MediaKind.movie,
      durationMs: const Duration(hours: 1).inMilliseconds,
      viewOffsetMs: const Duration(hours: 1).inMilliseconds,
    );

    expect(mediaFinishTime(item, now), DateTime(2026, 10, 20, 20, 30));
  });

  test('an item with no runtime has no finish time', () {
    expect(mediaFinishTime(_item(MediaKind.movie), DateTime(2026, 10, 20, 19, 30)), isNull);
  });

  testWidgets('a movie card shows the finish time next to the year', (tester) async {
    await _pumpCard(tester, _item(MediaKind.movie, durationMs: const Duration(hours: 2).inMilliseconds));

    expect(find.textContaining('2022 · Finishes at '), findsOneWidget);
  });

  testWidgets('a show card shows the finish time next to the year', (tester) async {
    await _pumpCard(tester, _item(MediaKind.show, durationMs: const Duration(minutes: 45).inMilliseconds));

    expect(find.textContaining('2022 · Finishes at '), findsOneWidget);
  });

  testWidgets('the year stands alone when the setting is off', (tester) async {
    await SettingsService.instance.write(SettingsService.showFinishTimeOnCards, false);
    await _pumpCard(tester, _item(MediaKind.movie, durationMs: const Duration(hours: 2).inMilliseconds));

    expect(find.text('2022'), findsOneWidget);
    expect(find.textContaining('Finishes at'), findsNothing);
  });

  testWidgets('the year stands alone when the runtime is unknown', (tester) async {
    await _pumpCard(tester, _item(MediaKind.movie));

    expect(find.text('2022'), findsOneWidget);
    expect(find.textContaining('Finishes at'), findsNothing);
  });
}
