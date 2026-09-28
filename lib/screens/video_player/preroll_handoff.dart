import '../../media/media_item.dart';
import '../../media/media_kind.dart';

/// Whether a finished [current] item is a server pre-roll handing over to the
/// movie its queue was launched for, rather than an ordinary queue item.
///
/// The pre-roll launch records the movie's id as the queue's launch context,
/// so a clip is a hand-off exactly when the queue holds that movie. A clip in
/// a playlist or folder of clips has a different launch context and keeps the
/// normal Play Next behaviour.
bool isPrerollHandoff({
  required MediaItem current,
  required String? launchContextKey,
  required Iterable<MediaItem> queue,
}) {
  if (current.kind != MediaKind.clip || launchContextKey == null) return false;
  return queue.any((item) => item.kind == MediaKind.movie && item.id == launchContextKey);
}
