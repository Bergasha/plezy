import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/models/plex/plex_community_review.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/plex_review_card.dart';

final List<PlexCommunityReview> _reviews = [
  const PlexCommunityReview(id: '1', typename: 'ActivityReview', displayName: 'Alice', message: 'Great movie!'),
  const PlexCommunityReview(id: '2', typename: 'ActivityReview', displayName: 'Bob', message: 'Pretty good.'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('owns horizontal focus and delegates vertical section navigation', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final key = GlobalKey<PlexReviewStripState>();
    var navigatedUp = 0;
    var navigatedDown = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(
          body: PlexReviewStrip(
            key: key,
            reviews: _reviews,
            onNavigateUp: () => navigatedUp++,
            onNavigateDown: () => navigatedDown++,
          ),
        ),
      ),
    );

    key.currentState!.requestFocus();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'reviews_row');

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

  testWidgets('renders one card per review with the reviewer name', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(body: PlexReviewStrip(reviews: _reviews)),
      ),
    );

    final cards = tester.widgetList<PlexReviewCard>(find.byType(PlexReviewCard));
    expect(cards, hasLength(_reviews.length));
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
  });

  testWidgets('clamps its focus index when the review list changes', (tester) async {
    final key = GlobalKey<PlexReviewStripState>();
    var reviews = _reviews;
    late StateSetter setHostState;

    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setHostState = setState;
              return PlexReviewStrip(key: key, reviews: reviews);
            },
          ),
        ),
      ),
    );

    key.currentState!.requestFocus();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    setHostState(() => reviews = const []);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('requestFocus is a no-op when there are no reviews', (tester) async {
    final key = GlobalKey<PlexReviewStripState>();

    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(body: PlexReviewStrip(key: key, reviews: const [])),
      ),
    );

    key.currentState!.requestFocus();
    await tester.pump();

    expect(FocusManager.instance.primaryFocus?.debugLabel, isNot('reviews_row'));
  });
}
