import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/widgets/home_clock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    LocaleSettings.setLocaleSync(AppLocale.en);
    await initializeDateFormatting('en');
  });

  Future<void> pumpClock(WidgetTester tester, {bool alwaysUse24HourFormat = true}) {
    return tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(alwaysUse24HourFormat: alwaysUse24HourFormat),
        child: const MaterialApp(home: Scaffold(body: Center(child: HomeClock()))),
      ),
    );
  }

  testWidgets('renders the current time in 24-hour format', (tester) async {
    await tester.runAsync(() async {
      await pumpClock(tester);

      final now = DateTime.now();
      final expected = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      expect(find.text(expected), findsOneWidget);
    });
  });

  testWidgets('re-renders in 12-hour format when the platform prefers it', (tester) async {
    await tester.runAsync(() async {
      await pumpClock(tester, alwaysUse24HourFormat: false);

      expect(find.textContaining(RegExp(r'(AM|PM)')), findsOneWidget);
    });
  });
}
