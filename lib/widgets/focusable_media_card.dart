import 'dart:async';

import 'package:flutter/material.dart';

import '../focus/focus_theme.dart';
import '../focus/focusable_wrapper.dart';
import '../focus/input_mode_tracker.dart';
import '../focus/oled_spotlight.dart';
import '../media/ids.dart';
import '../media/media_item.dart';
import '../services/poster_color_service.dart';
import '../services/settings_service.dart';
import '../utils/oled_effects.dart';
import '../utils/provider_extensions.dart';
import '../utils/platform_detector.dart';
import 'media_card.dart';

/// A focusable wrapper for MediaCard that handles D-pad navigation.
///
/// Wraps MediaCard with focus handling for TV/desktop navigation:
/// - Shows scale + border decoration when focused
/// - Handles SELECT key for activation with long-press detection
/// - Accepts optional external focusNode for programmatic focus control
class FocusableMediaCard extends StatefulWidget {
  /// Either a [MediaItem] or a [MediaPlaylist]. Typed as [Object] because
  /// Dart has no nominal union type. Forwarded as-is to the inner [MediaCard].
  final Object item;

  /// Optional row/column position announced with this card.
  final String? semanticValue;
  final double? width;
  final double? height;
  final void Function(MediaItem source)? onRefresh;
  final VoidCallback? onRemoveFromContinueWatching;
  final VoidCallback? onListRefresh;

  /// Replaces the card's default media navigation, for both pointer taps and
  /// D-pad SELECT. Null keeps [MediaCard]'s standard navigation.
  final VoidCallback? onTap;

  /// Pins the inner [MediaCard] to grid or list layout; null follows the
  /// user's view-mode setting.
  final ViewMode? viewModeOverride;
  final bool isInContinueWatching;
  final bool usesContinueWatchingAction;
  final String? collectionId;

  /// True for downloaded content without server access
  final bool isOffline;

  /// True when in a hub with mixed content (movies + episodes)
  final bool mixedHubContext;

  /// Render grid cards as image-only full-bleed cards.
  final bool fullBleedImage;

  /// Overrides the silhouette inferred from [item]. Used for container types
  /// such as music collections and playlists.
  final CardShape? cardShapeOverride;

  /// Show server name in list view (multi-server)
  final bool showServerName;

  /// Library name to attribute the item with in list view, resolved by the
  /// caller (see `LibrariesProvider.libraryLabelFor`). Null renders nothing.
  final String? libraryName;

  /// Whether to disable the scale animation on focus (e.g. in list view).
  final bool disableScale;

  /// Optional external focus node for programmatic focus control.
  /// If not provided, an internal focus node is created.
  final FocusNode? focusNode;

  /// Called when the user presses UP and there's no focusable item above.
  /// Used to navigate from the top row to filter chips.
  final VoidCallback? onNavigateUp;

  /// Called when the user presses DOWN and there's no focusable item below.
  /// When the grid wires explicit row navigation, this points at the item in
  /// the next row (or null on the last row).
  final VoidCallback? onNavigateDown;

  /// Called when the user presses LEFT and there's no focusable item to the left.
  /// Used to navigate from the first column to the sidebar.
  final VoidCallback? onNavigateLeft;

  /// Called when the user presses RIGHT and there's no focusable item to the right.
  /// Used to navigate from the last column to the alpha jump bar.
  final VoidCallback? onNavigateRight;

  /// Called when the user presses BACK.
  /// Used to navigate from tab content to tab bar.
  final VoidCallback? onBack;

  /// Called when focus changes.
  /// Used to track which grid item was last focused.
  final ValueChanged<bool>? onFocusChange;

  const FocusableMediaCard({
    super.key,
    required this.item,
    this.semanticValue,
    this.width,
    this.height,
    this.onRefresh,
    this.onRemoveFromContinueWatching,
    this.onListRefresh,
    this.onTap,
    this.viewModeOverride,
    this.isInContinueWatching = false,
    bool? usesContinueWatchingAction,
    this.collectionId,
    this.isOffline = false,
    this.mixedHubContext = false,
    this.fullBleedImage = false,
    this.cardShapeOverride,
    this.showServerName = false,
    this.libraryName,
    this.disableScale = false,
    this.focusNode,
    this.onNavigateUp,
    this.onNavigateDown,
    this.onNavigateLeft,
    this.onNavigateRight,
    this.onBack,
    this.onFocusChange,
  }) : usesContinueWatchingAction = usesContinueWatchingAction ?? isInContinueWatching;

  @override
  State<FocusableMediaCard> createState() => _FocusableMediaCardState();
}

class _FocusableMediaCardState extends State<FocusableMediaCard> {
  final GlobalKey<MediaCardState> _mediaCardKey = GlobalKey();

  Color? _posterColor;
  Timer? _posterColorTimer;
  OledSpotlightModel? _spotlight;

  void _handleFocusChange(bool hasFocus) {
    widget.onFocusChange?.call(hasFocus);
    if (!mounted) return;
    if (!hasFocus) {
      _posterColorTimer?.cancel();
      _spotlight?.blur(this);
      return;
    }
    if (InputModeTracker.currentMode != InputMode.keyboard) return;
    if (OledEffects.spotlight) {
      _spotlight = OledSpotlightHost.maybeOf(context);
      _spotlight?.focus(this);
    }
    _resolvePosterColor();
  }

  void _resolvePosterColor() {
    if (!OledEffects.needsPosterColor || widget.isOffline) return;
    final item = widget.item;
    if (item is! MediaItem) return;
    final target = posterColorTarget(
      item: item,
      client: context.tryGetMediaClientWithFallback(serverIdOrNull(item.serverId)),
      mode: SettingsService.instance.read(SettingsService.episodePosterMode) ?? EpisodePosterMode.seriesPoster,
      mixedHubContext: widget.mixedHubContext,
    );
    if (target == null) return;

    final cached = PosterColorService.instance.cached(target.key);
    if (cached != null) {
      if (cached.color != _posterColor) setState(() => _posterColor = cached.color);
      return;
    }
    _posterColorTimer?.cancel();
    _posterColorTimer = Timer(const Duration(milliseconds: 140), () async {
      final color = await PosterColorService.instance.resolve(target.key, target.provider);
      if (mounted && color != _posterColor) setState(() => _posterColor = color);
    });
  }

  @override
  void dispose() {
    _posterColorTimer?.cancel();
    _spotlight?.blur(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final oledGlow = OledEffects.posterGlow;
    final oledBleed = OledEffects.colorBleed;
    final glowActive = oledGlow || oledBleed;
    final spotlight = OledEffects.spotlight ? OledSpotlightHost.maybeOf(context) : null;
    return FocusableWrapper(
      focusNode: widget.focusNode,
      // The MediaCard already exposes the complete static button semantics.
      // Avoid invalidating a dense TV grid's semantics tree on every D-pad
      // focus change unless an accessibility service needs focused state.
      includeFocusSemantics: !PlatformDetector.isTV() || MediaQuery.accessibleNavigationOf(context),
      onSelect: () => _mediaCardKey.currentState?.handleTap(),
      onLongPress: () => _mediaCardKey.currentState?.showContextMenu(),
      onNavigateUp: widget.onNavigateUp,
      onNavigateDown: widget.onNavigateDown,
      onNavigateLeft: widget.onNavigateLeft,
      onNavigateRight: widget.onNavigateRight,
      onBack: widget.onBack,
      onFocusChange: _handleFocusChange,
      enableLongPress: true,
      disableScale: widget.disableScale,
      focusScale: widget.fullBleedImage ? FocusTheme.fullCardFocusScale : FocusTheme.focusScale,
      useFocusGlow: widget.fullBleedImage,
      posterGlow: glowActive && !widget.fullBleedImage,
      glowBleed: oledBleed,
      focusColor: glowActive ? _posterColor : null,
      // MediaCard draws the focus border itself, on the rect its layout
      // highlights (poster for standard grid cards, whole card otherwise).
      delegateFocusBorder: true,
      useComfortableZone: !PlatformDetector.isTV(), // Always center on TV
      scrollAlignment: 0.5,
      child: MediaCard(
        key: _mediaCardKey,
        item: widget.item,
        semanticValue: widget.semanticValue,
        width: widget.width,
        height: widget.height,
        onRefresh: widget.onRefresh,
        onRemoveFromContinueWatching: widget.onRemoveFromContinueWatching,
        onListRefresh: widget.onListRefresh,
        onTap: widget.onTap,
        viewModeOverride: widget.viewModeOverride,
        isInContinueWatching: widget.isInContinueWatching,
        usesContinueWatchingAction: widget.usesContinueWatchingAction,
        collectionId: widget.collectionId,
        isOffline: widget.isOffline,
        mixedHubContext: widget.mixedHubContext,
        fullBleedImage: widget.fullBleedImage,
        cardShapeOverride: widget.cardShapeOverride,
        showServerName: widget.showServerName,
        libraryName: widget.libraryName,
        artworkDim: spotlight == null ? null : SpotlightDim(spotlight, this),
      ),
    );
  }
}
