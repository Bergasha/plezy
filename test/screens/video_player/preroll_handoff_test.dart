import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/screens/video_player/preroll_handoff.dart';

void main() {
  const preRoll = MediaItem.plex(id: 'preroll-1', kind: MediaKind.clip, title: 'Pre-roll', playQueueItemId: 40);
  const movie = MediaItem.plex(id: 'movie-1', kind: MediaKind.movie, title: 'Movie', playQueueItemId: 41);
  const otherClip = MediaItem.plex(id: 'clip-2', kind: MediaKind.clip, title: 'Clip 2', playQueueItemId: 42);

  test('a pre-roll clip ahead of the movie its queue was launched for is a hand-off', () {
    expect(isPrerollHandoff(current: preRoll, launchContextKey: 'movie-1', queue: [preRoll, movie]), isTrue);
  });

  test('a second pre-roll before the movie is still a hand-off', () {
    expect(isPrerollHandoff(current: preRoll, launchContextKey: 'movie-1', queue: [preRoll, otherClip, movie]), isTrue);
  });

  test('a clip in a playlist of clips keeps the normal Play Next behaviour', () {
    expect(isPrerollHandoff(current: preRoll, launchContextKey: 'playlist-9', queue: [preRoll, otherClip]), isFalse);
  });

  test('a movie finishing is never a hand-off', () {
    expect(isPrerollHandoff(current: movie, launchContextKey: 'movie-1', queue: [preRoll, movie]), isFalse);
  });

  test('a queue with no launch context is not a hand-off', () {
    expect(isPrerollHandoff(current: preRoll, launchContextKey: null, queue: [preRoll, movie]), isFalse);
  });
}
