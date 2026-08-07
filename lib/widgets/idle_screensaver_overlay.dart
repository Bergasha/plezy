import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../media/ids.dart';
import '../media/library_query.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_library.dart';
import '../media/media_server_client.dart';
import '../providers/libraries_provider.dart';
import '../providers/multi_server_provider.dart';
import '../screens/video_player_screen.dart';
import '../services/companion_remote/companion_remote_receiver.dart';
import '../services/gamepad_service.dart';
import '../services/settings_service.dart';
import '../utils/app_logger.dart';
import 'cycling_media_backdrop.dart';
import 'home_clock.dart';
import 'settings_builder.dart';

/// One rotation entry — just enough to paint a backdrop and its title.
typedef _ScreensaverEntry = ({String title, String artPath});

/// Shows a full-screen slideshow of random backdrop art from the user's
/// libraries after a period of app-wide inactivity — each backdrop's title
/// fades in a few seconds after it appears, Plex HTPC-style. Dismisses on
/// the next key press, tap, or pointer movement. Opt-in via
/// [SettingsService.screensaverEnabled].
///
/// Self-contained, like [MusicMiniPlayerOverlay] — mount as a `Positioned.fill`
/// sibling of the profile-scoped nested [Navigator] (see
/// `navigation/profile_session_screen.dart`), not above it. Placing it any
/// higher (e.g. `main.dart`'s root `MaterialApp.builder`) puts it outside the
/// profile-scoped provider tree ([LibrariesProvider], [MultiServerProvider])
/// it needs to load art.
class IdleScreensaverOverlay extends StatefulWidget {
  const IdleScreensaverOverlay({super.key});

  @override
  State<IdleScreensaverOverlay> createState() => _IdleScreensaverOverlayState();
}

class _IdleScreensaverOverlayState extends State<IdleScreensaverOverlay> {
  /// Kinds whose library items carry meaningful backdrop art.
  static const _backdropKinds = {MediaKind.movie, MediaKind.show};

  /// Library name allowlist. Kids/anime/other specialty libraries share the
  /// same [MediaKind] as the main Movies/TV Shows libraries, so kind alone
  /// can't tell them apart — a single unlucky random sample could otherwise
  /// end up screensaving nothing but kids content for the whole session.
  static const _primaryLibraryTitles = {'movies', 'tv shows', 'tv'};

  /// Libraries sampled per idle session — enough variety without a big fan-out.
  static const _librariesToSample = 3;
  static const _itemsPerLibrary = 12;

  static bool _isPrimaryLibrary(MediaLibrary library) =>
      _primaryLibraryTitles.contains(library.title.trim().toLowerCase());

  Timer? _idleTimer;
  bool _showing = false;
  bool _artLoadAttempted = false;
  List<_ScreensaverEntry> _entries = const [];
  MediaServerClient? _artClient;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_handleGlobalPointerEvent);
    // TV remotes and gamepads (the Shield remote included) frequently arrive
    // as GamepadEvents rather than standard KeyEvents — HardwareKeyboard
    // alone misses them entirely, which is why only mouse movement used to
    // wake the screensaver.
    GamepadService.addGamepadInputListener(_handleActivity);
    CompanionRemoteReceiver.addRemoteInputListener(_handleActivity);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_handleGlobalPointerEvent);
    GamepadService.removeGamepadInputListener(_handleActivity);
    CompanionRemoteReceiver.removeRemoteInputListener(_handleActivity);
    _idleTimer?.cancel();
    super.dispose();
  }

  // Passive observation only — never consumes the event, so normal input
  // handling elsewhere in the app is completely unaffected.
  bool _handleGlobalKeyEvent(KeyEvent event) {
    _handleActivity();
    return false;
  }

  void _handleGlobalPointerEvent(PointerEvent event) {
    if (event is PointerDownEvent || event is PointerMoveEvent || event is PointerHoverEvent) {
      _handleActivity();
    }
  }

  /// Single funnel for "the user did something": arms the idle countdown
  /// while browsing, or dismisses the screensaver while it's showing. Driven
  /// globally (not through the shown content's own Focus/Gesture handlers)
  /// so dismissal works regardless of which widget actually holds focus —
  /// [_ScreensaverContent] still absorbs the same tap/key locally too, but
  /// this is the path that can't be defeated by a focus fight underneath.
  void _handleActivity() {
    if (_showing) {
      _dismiss();
    } else {
      _armIdleTimer();
    }
  }

  void _armIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = null;
    final settings = SettingsService.instanceOrNull;
    if (settings == null || !settings.read(SettingsService.screensaverEnabled)) return;
    final minutes = settings.read(SettingsService.screensaverIdleMinutes);
    _idleTimer = Timer(Duration(minutes: minutes), _tryShowScreensaver);
  }

  Future<void> _tryShowScreensaver() async {
    if (!mounted || _showing) return;
    // Never interrupt active playback — VideoPlayerScreenState clears this
    // the moment its route is gone, so this check needs no route plumbing.
    if (VideoPlayerScreenState.activeGlobalKey != null) return;

    if (!_artLoadAttempted) {
      await _loadRandomArt();
      if (!mounted) return;
    }
    if (_entries.isEmpty) return;
    setState(() => _showing = true);
  }

  /// Loads a random sample of movie/show backdrop art once per app session
  /// (reused across idle windows) instead of just Continue Watching, so
  /// repeat idle windows don't keep showing the same handful of titles.
  /// [CyclingMediaBackdrop] resolves every path through one
  /// [MediaServerClient], so — correct for the common single/primary-server
  /// setup — this sticks to whichever connected server contributes the most
  /// eligible libraries rather than mixing paths across servers.
  Future<void> _loadRandomArt() async {
    _artLoadAttempted = true;
    try {
      final libraries = context
          .read<LibrariesProvider>()
          .libraries
          .where((l) => _backdropKinds.contains(l.kind) && l.serverId != null && _isPrimaryLibrary(l))
          .toList();
      if (libraries.isEmpty) return;

      final byServer = <String, List<MediaLibrary>>{};
      for (final library in libraries) {
        (byServer[library.serverId!] ??= []).add(library);
      }
      final bestServerId = byServer.entries.reduce((a, b) => a.value.length >= b.value.length ? a : b).key;
      final multiServer = context.read<MultiServerProvider>();
      final client = multiServer.getClientForServer(ServerId(bestServerId));
      if (client == null) return;

      final candidateLibraries = byServer[bestServerId]!..shuffle();
      final sampled = candidateLibraries.take(_librariesToSample);

      const randomSort = LibrarySort(field: 'random');
      final fetches = sampled.map(
        (library) => client
            .fetchLibraryContent(library.id, const LibraryQuery(sort: randomSort, limit: _itemsPerLibrary))
            .then((page) => page.items)
            .catchError((Object e, StackTrace st) {
              appLogger.w('Screensaver: failed to sample library ${library.id}', error: e, stackTrace: st);
              return const <MediaItem>[];
            }),
      );
      final pages = await Future.wait(fetches);
      if (!mounted) return;

      final seenArt = <String>{};
      final entries = <_ScreensaverEntry>[];
      for (final items in pages) {
        for (final item in items) {
          final path = item.artPath;
          final title = item.title;
          if (path == null || path.isEmpty || title == null || title.isEmpty) continue;
          if (!seenArt.add(path)) continue;
          entries.add((title: title, artPath: path));
        }
      }
      if (entries.isEmpty) return;
      entries.shuffle();

      setState(() {
        _entries = entries;
        _artClient = client;
      });
    } catch (e, st) {
      appLogger.w('Screensaver: failed to load backdrop art', error: e, stackTrace: st);
    }
  }

  void _dismiss() {
    if (!_showing) return;
    setState(() => _showing = false);
    _armIdleTimer();
  }

  @override
  Widget build(BuildContext context) {
    return SettingsBuilder(
      prefs: const [SettingsService.screensaverEnabled],
      builder: (context) {
        final enabled = SettingsService.instance.read(SettingsService.screensaverEnabled);
        if (!enabled) {
          _idleTimer?.cancel();
          _idleTimer = null;
        } else if (_idleTimer == null && !_showing) {
          // Covers both first build and the setting having just been turned
          // on — arm from now rather than waiting for the next activity.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _armIdleTimer();
          });
        }

        if (!_showing) return const SizedBox.shrink();
        return _ScreensaverContent(entries: _entries, client: _artClient, onDismiss: _dismiss);
      },
    );
  }
}

class _ScreensaverContent extends StatefulWidget {
  const _ScreensaverContent({required this.entries, required this.client, required this.onDismiss});

  final List<_ScreensaverEntry> entries;
  final MediaServerClient? client;
  final VoidCallback onDismiss;

  @override
  State<_ScreensaverContent> createState() => _ScreensaverContentState();
}

class _ScreensaverContentState extends State<_ScreensaverContent> {
  static const _backdropInterval = Duration(seconds: 15);
  static const _titleRevealDelay = Duration(seconds: 4);

  final _random = Random();
  late int _currentIndex = _random.nextInt(widget.entries.length);
  Timer? _rotationTimer;
  Timer? _titleRevealTimer;
  bool _showTitle = false;

  _ScreensaverEntry get _current => widget.entries[_currentIndex];

  @override
  void initState() {
    super.initState();
    _scheduleTitleReveal();
    _scheduleNextBackdrop();
  }

  @override
  void dispose() {
    _rotationTimer?.cancel();
    _titleRevealTimer?.cancel();
    super.dispose();
  }

  void _scheduleNextBackdrop() {
    _rotationTimer?.cancel();
    if (widget.entries.length < 2) return;
    _rotationTimer = Timer(_backdropInterval, _advance);
  }

  void _scheduleTitleReveal() {
    _titleRevealTimer?.cancel();
    setState(() => _showTitle = false);
    _titleRevealTimer = Timer(_titleRevealDelay, () {
      if (mounted) setState(() => _showTitle = true);
    });
  }

  void _advance() {
    if (!mounted) return;
    // Pick a different random entry rather than a fixed sequence, so a
    // dismissed-and-reopened screensaver doesn't always restart the same way.
    final next = widget.entries.length < 2
        ? _currentIndex
        : (_currentIndex + 1 + _random.nextInt(widget.entries.length - 1)) % widget.entries.length;
    setState(() => _currentIndex = next);
    _scheduleTitleReveal();
    _scheduleNextBackdrop();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        widget.onDismiss();
        return KeyEventResult.handled;
      },
      child: MouseRegion(
        onHover: (_) => widget.onDismiss(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onDismiss,
          child: ExcludeSemantics(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: Colors.black),
                    CyclingMediaBackdrop(
                      mediaKey: _currentIndex,
                      imagePaths: [_current.artPath],
                      client: widget.client,
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      fallbackColor: Colors.black,
                    ),
                    // Keeps the clock and title readable regardless of how
                    // bright the current backdrop is.
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black54, Colors.transparent, Colors.black87],
                          stops: [0.0, 0.35, 1.0],
                        ),
                      ),
                    ),
                    const Positioned(top: 32, right: 32, child: HomeClock(color: Colors.white)),
                    Positioned(
                      left: 56,
                      bottom: 56,
                      right: 56,
                      // AnimatedSwitcher (not AnimatedOpacity) so the outgoing
                      // title fades out as itself, keyed to the index it
                      // belongs to — an opacity tween alone would fade in the
                      // *next* title's text while the previous backdrop was
                      // still on screen, since the Text's content swaps
                      // instantly but opacity only catches up gradually.
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 900),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          transitionBuilder: (child, animation) => FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
                                  .animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
                              child: child,
                            ),
                          ),
                          child: _showTitle
                              ? _ScreensaverTitle(key: ValueKey(_currentIndex), title: _current.title)
                              : const SizedBox.shrink(key: ValueKey('hidden')),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom-left title card: a thin accent bar beside the title, matching the
/// vertical-rule treatment common in premium media UIs.
class _ScreensaverTitle extends StatelessWidget {
  const _ScreensaverTitle({super.key, required this.title});

  final String title;

  /// Warm champagne tone — reads as "premium cinema" rather than flat white,
  /// and holds up against backdrop art of any brightness.
  static const _titleColor = Color(0xFFF4E3C1);

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(height: 40, width: 4, color: _titleColor.withValues(alpha: 0.9)),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _titleColor,
                fontSize: 38,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                height: 1.1,
                // Layered shadows fake an embossed/engraved look: a tight
                // dark shadow for edge definition, a soft wide one for
                // depth, and a faint highlight above for the "raised" edge —
                // rather than a single flat drop shadow.
                shadows: [
                  Shadow(color: Colors.black87, blurRadius: 3, offset: Offset(0, 1)),
                  Shadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, 6)),
                  Shadow(color: Colors.white24, blurRadius: 1, offset: Offset(0, -1)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
