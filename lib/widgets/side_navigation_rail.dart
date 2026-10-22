import 'dart:async';
import 'dart:ui' show lerpDouble;
import '../media/ids.dart';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:plezy/widgets/app_icon.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../focus/dpad_navigator.dart';
import '../focus/focus_memory_tracker.dart';
import '../focus/input_mode_tracker.dart';
import '../media/media_item.dart';
import '../media/media_library.dart';
import '../mixins/mounted_set_state_mixin.dart';
import '../navigation/navigation_tabs.dart';
import '../providers/catalog_sources_provider.dart';
import '../providers/hidden_libraries_provider.dart';
import '../providers/libraries_provider.dart';
import '../services/device_performance.dart';
import '../services/music/music_playback_service.dart';
import '../services/settings_service.dart';
import '../utils/music_navigation.dart';
import '../utils/content_utils.dart';
import '../utils/platform_detector.dart';
import '../utils/scroll_utils.dart';
import '../utils/library_grouping.dart';
import 'music/equalizer_icon.dart';
import '../providers/multi_server_provider.dart';
import '../services/fullscreen_state_manager.dart';
import '../theme/mono_tokens.dart';
import '../widgets/backend_badge.dart';
import '../i18n/strings.g.dart';

sealed class _LibraryNavRow {
  const _LibraryNavRow();
}

final class _LibraryServerHeaderRow extends _LibraryNavRow {
  final String serverId;
  final String serverName;

  const _LibraryServerHeaderRow({required this.serverId, required this.serverName});
}

final class _LibraryItemRow extends _LibraryNavRow {
  final MediaLibrary library;
  final bool showServerName;

  const _LibraryItemRow({required this.library, this.showServerName = false});
}

/// SELECT activates the rail row, RIGHT hands off to the content area.
KeyEventResult _handleRailItemKey(KeyEvent event, {required VoidCallback onSelect, VoidCallback? onNavigateRight}) {
  if (event is! KeyDownEvent) return KeyEventResult.ignored;
  if (event.logicalKey.isSelectKey) {
    onSelect();
    return KeyEventResult.handled;
  }
  if (event.logicalKey == LogicalKeyboardKey.arrowRight && onNavigateRight != null) {
    onNavigateRight();
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}

/// Reusable navigation rail item widget that handles focus, selection, and interaction.
///
/// Renders the two M3 Expressive destination layouts and morphs between them:
/// collapsed is an icon-only 56x32 pill indicator centered in the strip
/// (announced via [collapsedLabel]); expanded is a full-width stadium row
/// with leading icon and [label]. Items that never render collapsed
/// (library rows) leave [collapsedLabel] null and always use the expanded
/// layout.
class NavigationRailItem extends StatelessWidget {
  /// M3E collapsed-rail active indicator geometry.
  static const double collapsedIndicatorWidth = 56;
  static const double collapsedIndicatorHeight = 32;

  /// Fixed collapsed item height so the collapse morph interpolates between
  /// known extents (32px pill + breathing room).
  static const double collapsedItemHeight = 40;

  final IconData icon;
  final IconData? selectedIcon;

  /// Custom leading widget rendered instead of the [icon] (e.g. the Now
  /// Playing item's equalizer). Should be at most [iconSize] tall/wide.
  final Widget? iconWidget;
  final Widget label;

  /// Base color inherited by single-style text labels. During the morph its
  /// alpha is changed at the leaf, avoiding an opacity layer for the row.
  final Color? labelColor;

  /// Builds labels with more than one text color at [opacity]. Non-text
  /// labels without a builder use one opacity layer only while morphing.
  final Widget Function(double opacity)? labelBuilder;

  /// Semantic label for the icon-only collapsed pill. Null means the item
  /// has no collapsed representation and always lays out expanded.
  final String? collapsedLabel;

  /// Widget rendered after the [label] (e.g. a section header's chevron).
  /// Expanded layout only.
  final Widget? trailing;

  /// Builds a trailing leaf at [opacity] when it should fade with the label.
  final Widget Function(double opacity)? trailingBuilder;
  final bool isSelected;
  final bool isCollapsed;
  final VoidCallback onTap;
  final FocusNode focusNode;
  final bool autofocus;
  final double iconSize;

  /// Horizontal content padding of the expanded row.
  final double horizontalPadding;

  /// Fixed content width of the expanded layout, so the collapse morph and
  /// the rail width animation stay in lockstep.
  final double expandedContentWidth;

  /// Expanded row height: fixed for collapsible items, a minimum for
  /// expanded-only items (whose labels may add a second line).
  final double expandedHeight;
  final bool suppressSelectedBackground;

  /// Background tint while keyboard-focused, and its stronger variant used
  /// when the item also shows its selected background.
  final double focusAlpha;
  final double selectedFocusAlpha;

  /// Called when RIGHT arrow is pressed to navigate to content area.
  final VoidCallback? onNavigateRight;

  const NavigationRailItem({
    super.key,
    required this.icon,
    this.selectedIcon,
    this.iconWidget,
    required this.label,
    this.collapsedLabel,
    this.labelColor,
    this.labelBuilder,
    this.trailing,
    this.trailingBuilder,
    required this.isSelected,
    this.isCollapsed = false,
    required this.onTap,
    required this.focusNode,
    this.autofocus = false,
    this.iconSize = 22,
    this.horizontalPadding = 17,
    this.expandedContentWidth = SideNavigationRailState.expandedWidth - 24,
    this.expandedHeight = 48,
    this.suppressSelectedBackground = false,
    this.focusAlpha = 0.22,
    this.selectedFocusAlpha = 0.32,
    this.onNavigateRight,
  });

  Color? _indicatorColorForLayout(MonoTokens t, {required bool focused, required bool collapsedLayout}) {
    // The collapsed TV rail is a transparent overlay strip; a persistent
    // active pill over artwork is noise there, so it shows focus only.
    final showSelected = isSelected && !suppressSelectedBackground && !(collapsedLayout && PlatformDetector.isTV());
    // `accent` picks up OLED's red so the currently-focused destination is
    // unmistakable while navigating; every other palette keeps accent == text
    // and this renders exactly as it always has.
    if (focused) return t.accent.withValues(alpha: showSelected ? selectedFocusAlpha : focusAlpha);
    if (showSelected) return t.text.withValues(alpha: 0.1);
    return null;
  }

  Color? _indicatorColor(MonoTokens t, {required bool focused, required double expansion}) {
    return Color.lerp(
      _indicatorColorForLayout(t, focused: focused, collapsedLayout: true),
      _indicatorColorForLayout(t, focused: focused, collapsedLayout: false),
      expansion,
    );
  }

  Widget _leadingIcon(MonoTokens t) =>
      iconWidget ??
      AppIcon(
        isSelected && selectedIcon != null ? selectedIcon! : icon,
        fill: 1,
        size: iconSize,
        color: isSelected ? t.text : t.textMuted,
      );

  static double _collapsedItemWidth(BuildContext context) =>
      SideNavigationRailState.collapsedWidthForContext(context) -
      2 * SideNavigationRailState.horizontalPaddingForContext(context, isCollapsed: true);

  /// M3E collapsed destination: an icon-only pill indicator.
  Widget _buildCollapsedLayout(BuildContext context, MonoTokens t, {required bool focused}) {
    final width = _collapsedItemWidth(context);
    return SizedBox(
      width: width,
      height: collapsedItemHeight,
      child: Center(
        child: Semantics(
          label: collapsedLabel,
          child: Container(
            width: width < collapsedIndicatorWidth ? width : collapsedIndicatorWidth,
            height: collapsedIndicatorHeight,
            alignment: .center,
            decoration: BoxDecoration(
              color: _indicatorColor(t, focused: focused, expansion: 0),
              borderRadius: BorderRadius.circular(MonoTokens.radiusFull),
            ),
            child: _leadingIcon(t),
          ),
        ),
      ),
    );
  }

  /// M3E expanded destination: full-width stadium indicator behind the row.
  Widget _labelAtOpacity(BuildContext context, double opacity) {
    final builder = labelBuilder;
    if (builder != null) return builder(opacity);

    final textStyle = label is Text ? (label as Text).style : null;
    final inheritsTextColor =
        label is Text &&
        (textStyle == null || (textStyle.inherit && textStyle.color == null && textStyle.foreground == null));
    final color = inheritsTextColor ? labelColor ?? DefaultTextStyle.of(context).style.color : null;
    if (color != null) {
      return DefaultTextStyle.merge(
        style: TextStyle(color: color.withValues(alpha: color.a * opacity)),
        child: label,
      );
    }
    if (opacity >= 1) return label;

    // The reconnect progress indicator is the only production caller of this
    // path. It cannot inherit text color, so retain one small opacity layer
    // rather than a layer for every destination row.
    return Opacity(opacity: opacity, child: label);
  }

  Widget? _trailingAtOpacity(double opacity) {
    final builder = trailingBuilder;
    return builder == null ? trailing : builder(opacity);
  }

  Widget _buildExpandedContent(
    BuildContext context,
    MonoTokens t, {
    required double labelOpacity,
    required bool showLeading,
  }) {
    return Row(
      children: [
        if (showLeading) _leadingIcon(t) else SizedBox(width: iconSize, height: iconSize),
        const SizedBox(width: 11),
        Expanded(child: _labelAtOpacity(context, labelOpacity)),
        ?_trailingAtOpacity(labelOpacity),
      ],
    );
  }

  Widget _buildExpandedLayout(BuildContext context, MonoTokens t, {required bool focused, required bool fixedHeight}) {
    return Container(
      constraints: fixedHeight ? null : BoxConstraints(minHeight: expandedHeight),
      alignment: .centerLeft,
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: fixedHeight ? 0 : 8),
      decoration: BoxDecoration(
        color: _indicatorColor(t, focused: focused, expansion: 1),
        borderRadius: BorderRadius.circular(MonoTokens.radiusFull),
      ),
      child: _buildExpandedContent(context, t, labelOpacity: 1, showLeading: true),
    );
  }

  /// At the endpoints only the active layout exists in the tree. Mid-morph a
  /// single icon moves with the pill geometry while label and indicator color
  /// alpha provide the crossfade without subtree opacity layers.
  Widget _buildMorphingLayouts(BuildContext context, MonoTokens t, {required bool focused, required double expansion}) {
    if (expansion <= 0) return _buildCollapsedLayout(context, t, focused: focused);
    if (expansion >= 1) {
      return SizedBox(
        width: expandedContentWidth,
        height: expandedHeight,
        child: _buildExpandedLayout(context, t, focused: focused, fixedHeight: true),
      );
    }

    final collapsedWidth = _collapsedItemWidth(context);
    const collapsedHeight = collapsedItemHeight;
    final collapsedPillWidth = collapsedWidth < collapsedIndicatorWidth ? collapsedWidth : collapsedIndicatorWidth;
    final indicatorLeft = lerpDouble((collapsedWidth - collapsedPillWidth) / 2, 0, expansion);
    final indicatorTop = lerpDouble((collapsedHeight - collapsedIndicatorHeight) / 2, 0, expansion);
    final iconLeft = lerpDouble((collapsedWidth - iconSize) / 2, horizontalPadding, expansion);
    final iconTop = lerpDouble((collapsedHeight - iconSize) / 2, (expandedHeight - iconSize) / 2, expansion);

    return SizedBox(
      width: lerpDouble(collapsedWidth, expandedContentWidth, expansion),
      height: lerpDouble(collapsedHeight, expandedHeight, expansion),
      child: Stack(
        children: [
          Positioned(
            left: indicatorLeft,
            top: indicatorTop,
            child: Container(
              width: lerpDouble(collapsedPillWidth, expandedContentWidth, expansion),
              height: lerpDouble(collapsedIndicatorHeight, expandedHeight, expansion),
              decoration: BoxDecoration(
                color: _indicatorColor(t, focused: focused, expansion: expansion),
                borderRadius: BorderRadius.circular(MonoTokens.radiusFull),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            child: SizedBox(
              width: expandedContentWidth,
              height: expandedHeight,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: _buildExpandedContent(context, t, labelOpacity: expansion, showLeading: false),
              ),
            ),
          ),
          Positioned(
            left: iconLeft,
            top: iconTop,
            child: SizedBox(
              width: iconSize,
              height: iconSize,
              child: Center(child: _leadingIcon(t)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);

    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, _) {
        final focused = focusNode.hasFocus && InputModeTracker.isKeyboardMode(context);
        final content = collapsedLabel == null
            ? SizedBox(
                width: expandedContentWidth,
                child: _buildExpandedLayout(context, t, focused: focused, fixedHeight: false),
              )
            : TweenAnimationBuilder<double>(
                tween: Tween(end: isCollapsed ? 0.0 : 1.0),
                duration: SideNavigationRailState.expandDuration,
                curve: SideNavigationRailState.expandCurve,
                builder: (context, expansion, _) =>
                    _buildMorphingLayouts(context, t, focused: focused, expansion: expansion),
              );
        return Focus(
          focusNode: focusNode,
          autofocus: autofocus,
          onKeyEvent: (node, event) => _handleRailItemKey(event, onSelect: onTap, onNavigateRight: onNavigateRight),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              canRequestFocus: false,
              onTap: onTap,
              borderRadius: BorderRadius.circular(MonoTokens.radiusFull),
              child: UnconstrainedBox(
                alignment: .centerLeft,
                constrainedAxis: Axis.vertical,
                clipBehavior: Clip.hardEdge,
                child: content,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Side navigation rail for Desktop and Android TV platforms
class SideNavigationRail extends StatefulWidget {
  final NavigationTabId selectedTab;
  final String? selectedLibraryKey;
  final bool isOfflineMode;
  final bool isSidebarFocused;
  final bool alwaysExpanded;
  final bool isReconnecting;
  final ValueChanged<NavigationTabId> onDestinationSelected;
  final ValueChanged<String> onLibrarySelected;

  /// Called when RIGHT arrow is pressed to navigate to content without selecting.
  final VoidCallback? onNavigateToContent;

  /// Called when the user taps the reconnect button in offline mode.
  final VoidCallback? onReconnect;

  /// Called when the rail starts or stops floating over the content as an
  /// M3E modal panel, so the shell can scrim the content it covers. Docked
  /// expansion (always-open, D-pad focus) displaces content and never scrims.
  final ValueChanged<bool>? onFloatingPanelChanged;

  const SideNavigationRail({
    super.key,
    required this.selectedTab,
    this.selectedLibraryKey,
    this.isOfflineMode = false,
    this.isSidebarFocused = false,
    this.alwaysExpanded = false,
    this.isReconnecting = false,
    required this.onDestinationSelected,
    required this.onLibrarySelected,
    this.onNavigateToContent,
    this.onFloatingPanelChanged,
    this.onReconnect,
  });

  @override
  State<SideNavigationRail> createState() => SideNavigationRailState();
}

class SideNavigationRailState extends State<SideNavigationRail> with MountedSetStateMixin {
  bool _isHovered = false;

  /// Set when a selection collapses the rail while the cursor is still over it.
  /// The cursor sits on the rail without ever re-entering it, so the hover is
  /// ignored until the cursor has left once; otherwise the open panel would
  /// keep covering the page that was just chosen.
  bool _hoverLocked = false;
  Offset? _lastPointer;
  Offset? _lockOrigin;
  bool _wasKeyboardMode = false;

  /// How far the cursor must travel from where the rail was shut before it
  /// counts as a deliberate move and reopens the rail.
  static const double _hoverUnlockDistance = 24.0;
  bool _isTouchExpanded = false;
  bool _lastReportedFloatingPanel = false;
  Timer? _collapseTimer;
  static const double collapsedWidth = 80.0;
  static const double tvCollapsedWidth = 48.0;
  static const double expandedWidth = 220.0;
  static const double _horizontalPadding = 12.0;
  static const double _collapsedHorizontalPadding = 4.0;
  static const double _itemGap = 4.0;
  static const Duration _collapseDelay = Duration(milliseconds: 150);

  /// Trailing corner radius of the floating (hover/touch) overlay panel; the
  /// docked open rail keeps the regular radiusLg card rounding.
  static const double overlayCornerRadius = 32.0;

  /// Collapse/expand morph timing, shared by the rail width, every item's
  /// layout morph, and the shell's content translate + bleed counter
  /// animations (MainScreen and SideNavigationBleedBuilder) so they all
  /// track tick for tick.
  /// Reduced-tier devices resolve this to zero; keep every consumer on this
  /// getter so the shell and rail continue to move in lockstep.
  static Duration get expandDuration => DevicePerformance.reducedDuration(const Duration(milliseconds: 250));
  static const Curve expandCurve = Curves.easeInOutCubicEmphasized;

  static double collapsedWidthForContext(BuildContext _) => PlatformDetector.isTV() ? tvCollapsedWidth : collapsedWidth;

  /// Edge padding around the item column; collapsed rails center their items
  /// (72px in the 80px desktop strip, 40px in the 48px TV strip).
  static double horizontalPaddingForContext(BuildContext _, {required bool isCollapsed}) {
    return isCollapsed ? _collapsedHorizontalPadding : _horizontalPadding;
  }

  static const _kHome = 'home';
  static const _kWatchlist = 'watchlist';
  static const _kExplore = 'explore';
  static const _kNowPlaying = 'nowPlaying';
  static const _kSearch = 'search';
  static const _kDownloads = 'downloads';
  static const _kSettings = 'settings';
  static const _kReconnect = 'reconnect';
  static const _kFullscreen = 'fullscreen';
  static const _kServerHeaderPrefix = 'serverHeader';
  static const _kLibraryItemPrefix = 'library';

  final Set<String> _collapsedServerGroupKeys = {};

  // Unified focus state tracker for all nav items (main + libraries)
  late final FocusMemoryTracker _focusTracker;

  /// Whether the sidebar should be expanded (always, hover, or focus)
  bool get _shouldExpand => widget.alwaysExpanded || _isHovered || _isTouchExpanded || widget.isSidebarFocused;

  bool get _interactionExpanded => _isHovered || _isTouchExpanded;

  /// True while the rail floats over the content as an M3E modal panel.
  ///
  /// Hover/touch expansion leaves the shell at its collapsed content offset,
  /// so a floating panel covers content and owns its own opaque surface and
  /// edge shadow. Every docked shape — collapsed, always-open, or D-pad
  /// focus-expanded — displaces content instead and stays transparent on TV.
  bool get _isFloatingPanel => _interactionExpanded && !widget.alwaysExpanded;

  bool get _showDownloads => !PlatformDetector.isAppleTV();

  /// macOS has the system green button; mobile/TV have no OS fullscreen toggle.
  bool get _showFullscreenToggle => Platform.isWindows || Platform.isLinux;

  @override
  void initState() {
    super.initState();
    _focusTracker = FocusMemoryTracker(debugLabelPrefix: 'nav');
  }

  @override
  void dispose() {
    _collapseTimer?.cancel();
    _focusTracker.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SideNavigationRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-collapse after navigation (selection changed)
    if (oldWidget.selectedTab != widget.selectedTab || oldWidget.selectedLibraryKey != widget.selectedLibraryKey) {
      final wasInteractionExpanded = _interactionExpanded;
      _isTouchExpanded = false;
      if (_isHovered) _lockHover();
      if (wasInteractionExpanded != _interactionExpanded) {
        _scheduleFloatingPanelNotification();
      }
    }
    // Toggling always-open while hovered/touched converts a floating panel
    // into a docked rail (or back) without any interaction-state change.
    if (oldWidget.alwaysExpanded != widget.alwaysExpanded) {
      _scheduleFloatingPanelNotification();
    }
  }

  /// didUpdateWidget runs during build, where notifying the parent would
  /// setState mid-build; defer that report to the next frame.
  void _scheduleFloatingPanelNotification() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _notifyFloatingPanelIfNeeded();
    });
  }

  void _notifyFloatingPanelIfNeeded() {
    final floating = _isFloatingPanel;
    if (_lastReportedFloatingPanel == floating) return;
    _lastReportedFloatingPanel = floating;
    widget.onFloatingPanelChanged?.call(floating);
  }

  /// Shuts a hover-opened rail and ignores the cursor until it leaves, or moves
  /// well away from where it rests now. A cursor parked on the rail never
  /// re-enters it, so without this the rail would stay open under it.
  void _lockHover() {
    _isHovered = false;
    _hoverLocked = true;
    _lockOrigin = _lastPointer;
  }

  /// Opens the rail on real cursor movement. A stationary cursor that the
  /// layout merely moved under (the rail growing, content shifting) does not
  /// reach here, unlike an enter event, which the framework also sends then.
  void _onPointerHover(PointerHoverEvent event) {
    _lastPointer = event.position;
    if (_hoverLocked) {
      final origin = _lockOrigin;
      if (origin != null && (event.position - origin).distance < _hoverUnlockDistance) return;
      _hoverLocked = false;
      _lockOrigin = null;
    }
    _onHoverEnter();
  }

  void _onHoverEnter() {
    _collapseTimer?.cancel();
    if (_hoverLocked || (_isHovered && !_isTouchExpanded)) return;
    setState(() {
      _isTouchExpanded = false; // Mouse takes over
      _isHovered = true;
    });
    _notifyFloatingPanelIfNeeded();
  }

  void _onHoverExit() {
    _hoverLocked = false;
    _lockOrigin = null;
    _collapseTimer?.cancel();
    _collapseTimer = Timer(_collapseDelay, () {
      if (mounted && _isHovered) {
        setState(() => _isHovered = false);
        _notifyFloatingPanelIfNeeded();
      }
    });
  }

  void _expandForTouch() {
    if (_isTouchExpanded) return;
    setState(() => _isTouchExpanded = true);
    _notifyFloatingPanelIfNeeded();
  }

  /// The key of the last focused sidebar item (for pre-capture before focus shifts).
  String? get lastFocusedKey => _focusTracker.lastFocusedKey;

  /// Focus the last focused nav item, or Home as fallback.
  /// If [targetKey] is provided, try it first (used when the caller captured
  /// the intended target before a focus-scope switch overwrote it).
  void focusActiveItem({String? targetKey}) {
    final node = _resolveFocusNode(targetKey) ?? _mountedFocusNodeFor(_kHome);
    if (node == null) return;
    _requestFocusAndReveal(node);
  }

  /// Focus the Home nav item (Back returning to the home tab).
  void focusHomeItem() {
    final node = _mountedFocusNodeFor(_kHome);
    if (node == null) return;
    _requestFocusAndReveal(node);
  }

  /// Resolve the best mounted focus node in priority order:
  /// 1. Explicit [targetKey] (captured before scope switch)
  /// 2. Last focused key still in the tracker
  /// 3. Currently selected navigation item (tab / library)
  /// 4. Home fallback
  FocusNode? _resolveFocusNode(String? targetKey) {
    return _mountedFocusNodeFor(targetKey) ??
        _mountedFocusNodeFor(_focusTracker.lastFocusedKey) ??
        _mountedFocusNodeFor(_resolveSelectedFocusKey());
  }

  FocusNode? _mountedFocusNodeFor(String? key) {
    if (key == null) return null;
    final node = _focusTracker.nodeFor(key);
    return node != null && _isMounted(node) ? node : null;
  }

  /// Whether [node] is attached to a mounted row. A detached node keeps its
  /// last context after the row unmounts (a collapsed library section or
  /// server group), so a null check alone lets focus land on a row that is
  /// gone and the request goes nowhere.
  static bool _isMounted(FocusNode node) => node.context?.mounted ?? false;

  /// Derive a focus key from the current selection state (tab + library).
  /// Returns null if no meaningful selected item exists.
  String? _resolveSelectedFocusKey() {
    switch (widget.selectedTab) {
      case NavigationTabId.discover:
        return _kHome;
      case NavigationTabId.watchlist:
        return _kWatchlist;
      case NavigationTabId.explore:
        return _kExplore;
      case NavigationTabId.libraries:
        final libKey = widget.selectedLibraryKey;
        if (libKey == null) return null;
        final key = _libraryItemFocusKey(libKey);
        return _mountedFocusNodeFor(key) != null ? key : null;
      case NavigationTabId.search:
        return _kSearch;
      case NavigationTabId.downloads:
        return _showDownloads ? _kDownloads : null;
      case NavigationTabId.settings:
        return _kSettings;
      case NavigationTabId.liveTv:
        return 'liveTv';
    }
  }

  /// Request focus on [node] and scroll it into view after the next frame.
  void _requestFocusAndReveal(FocusNode node) {
    node.requestFocus();
    scrollContextToCenter(node.context);
  }

  String _serverHeaderFocusKey(ServerId serverId) => '$_kServerHeaderPrefix:$serverId';

  String _libraryItemFocusKey(String libraryGlobalKey) => '$_kLibraryItemPrefix:$libraryGlobalKey';

  String _serverGroupStateKey(ServerId serverId) => '$serverId';

  String _focusKeyForLibraryRow(_LibraryNavRow row) => switch (row) {
    _LibraryServerHeaderRow(:final serverId) => _serverHeaderFocusKey(ServerId(serverId)),
    _LibraryItemRow(:final library) => _libraryItemFocusKey(library.globalKey),
  };

  Iterable<String> _focusKeysForLibraryRows(List<_LibraryNavRow> rows) => rows.map(_focusKeyForLibraryRow);

  /// Build the set of valid focus keys (main nav + currently rendered library rows).
  Set<String> _buildValidFocusKeys({
    required List<_LibraryNavRow> libraryRows,
    required bool hasLiveTv,
    required bool hasNowPlaying,
    required bool hasExplore,
    required bool hasWatchlist,
  }) {
    return {
      _kHome,
      if (hasWatchlist) _kWatchlist,
      if (hasNowPlaying) _kNowPlaying,
      if (hasExplore) _kExplore,
      _kSearch,
      if (_showDownloads) _kDownloads,
      _kSettings,
      _kReconnect,
      if (_showFullscreenToggle) _kFullscreen,
      if (hasLiveTv) 'liveTv',
      ..._focusKeysForLibraryRows(libraryRows),
    };
  }

  /// Build the rows the rail shows for the libraries the user keeps visible:
  /// one nav item per library, with a collapsible server header above each
  /// server's group when several servers are grouped. This is the single
  /// source of truth for both widget rendering and D-pad focus ordering.
  List<_LibraryNavRow> _buildLibraryRows(List<MediaLibrary> libs, {required bool showServerHeaders}) {
    if (!showServerHeaders) {
      final nonUniqueNames = _getNonUniqueLibraryNames(libs);
      return libs.map((lib) {
        return _LibraryItemRow(
          library: lib,
          showServerName: nonUniqueNames.contains(lib.title) && lib.serverName != null,
        );
      }).toList();
    }
    final grouped = groupLibrariesByFirstAppearance(libs);
    final result = <_LibraryNavRow>[];
    for (final serverKey in grouped.serverOrder) {
      final bucket = grouped.byServer[serverKey]!;
      if (serverKey.isNotEmpty) {
        result.add(_LibraryServerHeaderRow(serverId: serverKey, serverName: bucket.first.serverName ?? serverKey));
      }
      if (serverKey.isEmpty || !_collapsedServerGroupKeys.contains(_serverGroupStateKey(ServerId(serverKey)))) {
        for (final lib in bucket) {
          result.add(_LibraryItemRow(library: lib));
        }
      }
    }
    return result;
  }

  Set<String> _buildServerGroupStateKeys(List<MediaLibrary> libraries, {required bool showServerHeaders}) {
    if (!showServerHeaders) return {};

    return {
      for (final lib in libraries)
        if (lib.serverId != null) _serverGroupStateKey(ServerId(lib.serverId!)),
    };
  }

  /// Ordered list of focusable keys matching visual top-to-bottom order.
  List<String> _buildFocusOrder(
    List<_LibraryNavRow> libraryRows, {
    required bool hasLiveTv,
    required bool hasNowPlaying,
    required bool hasExplore,
    required bool hasWatchlist,
    required bool isCollapsed,
  }) {
    return [
      if (widget.isOfflineMode && widget.onReconnect != null) _kReconnect,
      if (!widget.isOfflineMode) ...[
        _kHome,
        if (hasWatchlist) _kWatchlist,
        if (hasNowPlaying) _kNowPlaying,
        // A collapsed rail has no server headers, so keep them out of the
        // D-pad order in lockstep with what is rendered.
        for (final row in libraryRows)
          if (!isCollapsed || row is _LibraryItemRow) _focusKeyForLibraryRow(row),
        if (hasLiveTv) 'liveTv',
        if (hasExplore) _kExplore,
        _kSearch,
      ],
      if (_showDownloads) _kDownloads,
      _kSettings,
      if (_showFullscreenToggle) _kFullscreen,
    ];
  }

  void _debugAssertUniqueFocusOrder(List<String> focusOrder) {
    assert(() {
      final seen = <String>{};
      for (final key in focusOrder) {
        if (!seen.add(key)) {
          throw FlutterError('SideNavigationRail focus order contains duplicate key: $key');
        }
      }
      return true;
    }());
  }

  /// Handle D-pad UP/DOWN by explicitly moving focus to the next/previous item.
  KeyEventResult _handleVerticalNavigation(FocusNode _, KeyEvent event, List<String> focusOrder) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final isDown = event.logicalKey == LogicalKeyboardKey.arrowDown;
    final isUp = event.logicalKey == LogicalKeyboardKey.arrowUp;
    if (!isDown && !isUp) return KeyEventResult.ignored;

    final currentKey = _focusTracker.lastFocusedKey;
    if (currentKey == null) return KeyEventResult.ignored;

    final currentIndex = focusOrder.indexOf(currentKey);
    if (currentIndex == -1) return KeyEventResult.ignored;

    // Scan onward past keys whose node is unmounted or focus-excluded (a row
    // can outlive its focusability, e.g. under an ExcludeFocus ancestor).
    // Returning handled without moving focus would swallow the key and also
    // suppress the framework's own directional traversal, so yield ignored
    // when no viable candidate remains in the requested direction.
    final step = isDown ? 1 : -1;
    for (var index = currentIndex + step; index >= 0 && index < focusOrder.length; index += step) {
      final node = _focusTracker.nodeFor(focusOrder[index]);
      if (node == null || !_isMounted(node) || !node.canRequestFocus) continue;
      _requestFocusAndReveal(node);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Collapse the sidebar (resets touch-expand state).
  void collapse() {
    if (_isTouchExpanded) {
      setState(() => _isTouchExpanded = false);
      _notifyFloatingPanelIfNeeded();
    }
  }

  /// Reload libraries (called when servers change or profile switches)
  void reloadLibraries() {
    final librariesProvider = context.read<LibrariesProvider>();
    librariesProvider.refresh();
  }

  /// Calculate top padding for macOS traffic lights
  double _getTopPadding(BuildContext context) {
    double basePadding = MediaQuery.paddingOf(context).top + 16;

    // On macOS, add extra padding for traffic lights (when not fullscreen)
    if (Platform.isMacOS) {
      final isFullscreen = FullscreenStateManager().isFullscreen;
      if (!isFullscreen) {
        // Traffic lights area is approximately 52 pixels high
        basePadding = basePadding < 52 ? 52 : basePadding;
      }
    }

    return basePadding;
  }

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    final librariesProvider = context.watch<LibrariesProvider>();
    final hiddenLibrariesProvider = context.watch<HiddenLibrariesProvider>();
    final hiddenKeys = hiddenLibrariesProvider.hiddenLibraryKeys;

    final allLibraries = librariesProvider.libraries;
    final visibleLibraries = <MediaLibrary>[];
    final serverIds = <String>{};
    for (final lib in allLibraries) {
      if (lib.serverId != null) serverIds.add(lib.serverId!);
      if (!hiddenKeys.contains(lib.globalKey)) visibleLibraries.add(lib);
    }

    // Keyboard or D-pad input takes over from a cursor resting on the rail:
    // the rail then follows focus, not the pointer, until the cursor moves.
    final keyboardMode = InputModeTracker.isKeyboardMode(context);
    if (keyboardMode && !_wasKeyboardMode && _isHovered) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(_lockHover);
        _notifyFloatingPanelIfNeeded();
      });
    }
    _wasKeyboardMode = keyboardMode;

    final isCollapsed = !_shouldExpand;
    final effectiveCollapsedWidth = collapsedWidthForContext(context);
    final horizontalPadding = horizontalPaddingForContext(context, isCollapsed: isCollapsed);
    final hasLiveTv = context.watch<MultiServerProvider>().hasLiveTv;
    // Nullable watch: rail tests (and any host without the profile session
    // scope) simply never show the Explore item.
    final hasExploreSource = context.watch<CatalogSourcesProvider?>()?.hasAnySource ?? false;
    // Nullable watch: rail tests (and any host without the profile session
    // scope) simply never show the Watchlist item.
    final hasWatchlist = context.watch<CatalogSourcesProvider?>()?.watchlistCapableSource != null;
    // Nullable watch: rail tests (and any host without the profile session
    // scope) simply never show the Now Playing item. TV-only — it is the
    // way back into the now-playing screen there; desktop already has the
    // mini-player for that.
    final musicService = context.watch<MusicPlaybackService?>();
    final nowPlayingTrack = widget.isOfflineMode || !PlatformDetector.isTV() ? null : musicService?.currentTrack;

    // Listen to fullscreen + the groupLibrariesByServer / showExploreTab
    // settings so the rail rebuilds when they are toggled in Appearance.
    return ListenableBuilder(
      listenable: Listenable.merge([
        FullscreenStateManager(),
        SettingsService.instance.listenable(SettingsService.groupLibrariesByServer),
        SettingsService.instance.listenable(SettingsService.showExploreTab),
      ]),
      builder: (context, _) {
        final hasExplore = hasExploreSource && SettingsService.instance.read(SettingsService.showExploreTab);
        // Server grouping: only when multi-server AND the user-facing toggle is on.
        final groupByServerSetting = SettingsService.instance.read(SettingsService.groupLibrariesByServer);
        final showServerHeaders = serverIds.length > 1 && groupByServerSetting;
        _collapsedServerGroupKeys.retainAll(
          _buildServerGroupStateKeys(visibleLibraries, showServerHeaders: showServerHeaders),
        );
        final libraryRows = _buildLibraryRows(visibleLibraries, showServerHeaders: showServerHeaders);
        _focusTracker.pruneExcept(
          _buildValidFocusKeys(
            libraryRows: libraryRows,
            hasLiveTv: hasLiveTv,
            hasNowPlaying: nowPlayingTrack != null,
            hasExplore: hasExplore,
            hasWatchlist: hasWatchlist,
          ),
        );
        final focusOrder = _buildFocusOrder(
          libraryRows,
          hasLiveTv: hasLiveTv,
          hasNowPlaying: nowPlayingTrack != null,
          hasExplore: hasExplore,
          hasWatchlist: hasWatchlist,
          isCollapsed: isCollapsed,
        );
        _debugAssertUniqueFocusOrder(focusOrder);
        return TapRegion(
          onTapOutside: (_) {
            if (_isTouchExpanded) {
              setState(() => _isTouchExpanded = false);
              _notifyFloatingPanelIfNeeded();
            }
          },
          child: MouseRegion(
            cursor: isCollapsed ? SystemMouseCursors.click : MouseCursor.defer,
            onHover: _onPointerHover,
            onExit: (_) => _onHoverExit(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: isCollapsed ? _expandForTouch : null,
              child: AnimatedContainer(
                duration: expandDuration,
                curve: expandCurve,
                width: isCollapsed ? effectiveCollapsedWidth : expandedWidth,
                clipBehavior: Clip.hardEdge,
                decoration: const BoxDecoration(),
                child: Stack(
                  children: [
                    // Rail surface. A docked rail is transparent on TV so the
                    // full-bleed backdrop continues behind it; content is
                    // pushed clear of it, never covered. A floating panel
                    // covers content, so it paints its surface on every
                    // platform (#2079).
                    Positioned.fill(
                      child: AnimatedOpacity(
                        opacity: PlatformDetector.isTV() && !_isFloatingPanel ? 0.0 : 1.0,
                        // Shares the width morph's duration/curve: a shorter
                        // fade strands a fully grown, fully transparent panel
                        // over the content part-way through the collapse.
                        duration: expandDuration,
                        curve: expandCurve,
                        child: AnimatedContainer(
                          duration: expandDuration,
                          curve: expandCurve,
                          decoration: BoxDecoration(
                            color: t.surface,
                            // Open rails read as an M3E panel: rounded
                            // trailing corners, extra-rounded plus an edge
                            // shadow while floating over content (modal)
                            // instead of pushing it.
                            borderRadius: isCollapsed
                                ? BorderRadius.zero
                                : BorderRadius.horizontal(
                                    right: Radius.circular(_isFloatingPanel ? overlayCornerRadius : t.radiusLg),
                                  ),
                            boxShadow: _isFloatingPanel
                                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 24)]
                                : const [],
                          ),
                        ),
                      ),
                    ),
                    IgnorePointer(
                      ignoring: isCollapsed,
                      child: Focus(
                        canRequestFocus: false,
                        skipTraversal: true,
                        onKeyEvent: (node, event) => _handleVerticalNavigation(node, event, focusOrder),
                        child: Column(
                          children: [
                            SizedBox(height: _getTopPadding(context)),
                            Expanded(
                              child: AnimatedPadding(
                                padding: .symmetric(horizontal: horizontalPadding),
                                duration: expandDuration,
                                curve: expandCurve,
                                child: ListView(
                                  padding: EdgeInsets.zero,
                                  clipBehavior: Clip.hardEdge,
                                  children: [
                                    if (widget.isOfflineMode && widget.onReconnect != null) ...[
                                      _buildReconnectItem(isCollapsed: isCollapsed),
                                      const SizedBox(height: _itemGap),
                                    ],
                                    if (!widget.isOfflineMode) ...[
                                      _buildNavItem(
                                        icon: Symbols.home_rounded,
                                        selectedIcon: Symbols.home_rounded,
                                        label: Translations.of(context).common.home,
                                        isSelected: widget.selectedTab == NavigationTabId.discover,
                                        onTap: () => widget.onDestinationSelected(NavigationTabId.discover),
                                        focusNode: _focusTracker.get(_kHome),
                                        isCollapsed: isCollapsed,
                                      ),
                                      const SizedBox(height: _itemGap),
                                      if (hasWatchlist) ...[
                                        _buildNavItem(
                                          icon: Symbols.bookmark_rounded,
                                          selectedIcon: Symbols.bookmark_rounded,
                                          label: Translations.of(context).navigation.watchlist,
                                          isSelected: widget.selectedTab == NavigationTabId.watchlist,
                                          onTap: () => widget.onDestinationSelected(NavigationTabId.watchlist),
                                          focusNode: _focusTracker.get(_kWatchlist),
                                          isCollapsed: isCollapsed,
                                        ),
                                        const SizedBox(height: _itemGap),
                                      ],
                                      // Now Playing — only while a music session is live.
                                      if (nowPlayingTrack != null && musicService != null) ...[
                                        _buildNowPlayingItem(nowPlayingTrack, musicService, isCollapsed: isCollapsed),
                                        const SizedBox(height: _itemGap),
                                      ],
                                      ..._buildLibraryNavRows(libraryRows, t, isCollapsed: isCollapsed),
                                      if (context.watch<MultiServerProvider>().hasLiveTv) ...[
                                        _buildNavItem(
                                          icon: Symbols.live_tv_rounded,
                                          selectedIcon: Symbols.live_tv_rounded,
                                          label: Translations.of(context).navigation.liveTv,
                                          isSelected: widget.selectedTab == NavigationTabId.liveTv,
                                          onTap: () => widget.onDestinationSelected(NavigationTabId.liveTv),
                                          focusNode: _focusTracker.get('liveTv'),
                                          isCollapsed: isCollapsed,
                                        ),
                                        const SizedBox(height: _itemGap),
                                      ],
                                      if (hasExplore) ...[
                                        _buildNavItem(
                                          icon: Symbols.explore_rounded,
                                          selectedIcon: Symbols.explore_rounded,
                                          label: Translations.of(context).navigation.explore,
                                          isSelected: widget.selectedTab == NavigationTabId.explore,
                                          onTap: () => widget.onDestinationSelected(NavigationTabId.explore),
                                          focusNode: _focusTracker.get(_kExplore),
                                          isCollapsed: isCollapsed,
                                        ),
                                        const SizedBox(height: _itemGap),
                                      ],
                                      _buildNavItem(
                                        icon: Symbols.search_rounded,
                                        selectedIcon: Symbols.search_rounded,
                                        label: Translations.of(context).common.search,
                                        isSelected: widget.selectedTab == NavigationTabId.search,
                                        onTap: () => widget.onDestinationSelected(NavigationTabId.search),
                                        focusNode: _focusTracker.get(_kSearch),
                                        isCollapsed: isCollapsed,
                                      ),
                                      const SizedBox(height: _itemGap),
                                    ],
                                    // Downloads (hidden on Apple TV — no user
                                    // file storage)
                                    if (_showDownloads) ...[
                                      _buildNavItem(
                                        icon: Symbols.download_rounded,
                                        selectedIcon: Symbols.download_rounded,
                                        label: Translations.of(context).navigation.downloads,
                                        isSelected: widget.selectedTab == NavigationTabId.downloads,
                                        onTap: () => widget.onDestinationSelected(NavigationTabId.downloads),
                                        focusNode: _focusTracker.get(_kDownloads),
                                        isCollapsed: isCollapsed,
                                      ),
                                      const SizedBox(height: _itemGap),
                                    ],
                                    _buildNavItem(
                                      icon: Symbols.settings_rounded,
                                      selectedIcon: Symbols.settings_rounded,
                                      label: Translations.of(context).common.settings,
                                      isSelected: widget.selectedTab == NavigationTabId.settings,
                                      onTap: () => widget.onDestinationSelected(NavigationTabId.settings),
                                      focusNode: _focusTracker.get(_kSettings),
                                      isCollapsed: isCollapsed,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_showFullscreenToggle)
                              AnimatedPadding(
                                padding: .fromLTRB(horizontalPadding, 0, horizontalPadding, 12),
                                duration: expandDuration,
                                curve: expandCurve,
                                child: _buildFullscreenItem(isCollapsed: isCollapsed),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required FocusNode focusNode,
    required bool isCollapsed,
    bool autofocus = false,
  }) {
    final t = tokens(context);

    return NavigationRailItem(
      icon: icon,
      selectedIcon: selectedIcon,
      label: Text(
        label,
        style: TextStyle(fontSize: 14, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400),
        overflow: .ellipsis,
        maxLines: 1,
      ),
      labelColor: isSelected ? t.text : t.textMuted,
      collapsedLabel: label,
      isSelected: isSelected,
      isCollapsed: isCollapsed,
      onTap: onTap,
      focusNode: focusNode,
      autofocus: autofocus,
      suppressSelectedBackground: widget.isSidebarFocused,
      onNavigateRight: widget.onNavigateToContent,
    );
  }

  /// "Now Playing" rail item — the shared equalizer as its icon (animating
  /// while audio plays), the current track's title as its label. SELECT/tap
  /// opens the now-playing screen.
  Widget _buildNowPlayingItem(MediaItem track, MusicPlaybackService musicService, {required bool isCollapsed}) {
    final t = tokens(context);
    final nowPlayingLabel = Translations.of(context).music.nowPlaying;
    final trackTitle = track.title ?? '';

    Widget buildLabel(double opacity) {
      return Column(
        crossAxisAlignment: .start,
        mainAxisSize: .min,
        children: [
          Text(
            nowPlayingLabel,
            style: TextStyle(
              fontSize: 14,
              fontWeight: .w600,
              color: t.text.withValues(alpha: t.text.a * opacity),
            ),
            overflow: .ellipsis,
            maxLines: 1,
          ),
          Text(
            trackTitle,
            style: TextStyle(fontSize: 11, color: t.textMuted.withValues(alpha: t.textMuted.a * opacity)),
            overflow: .ellipsis,
            maxLines: 1,
          ),
        ],
      );
    }

    return NavigationRailItem(
      icon: Symbols.music_note_rounded,
      iconWidget: SizedBox(
        width: 22,
        child: Center(
          child: EqualizerIcon(animate: musicService.isPlaying, color: t.text),
        ),
      ),
      label: buildLabel(1),
      labelBuilder: buildLabel,
      collapsedLabel: Translations.of(context).music.nowPlaying,
      isSelected: false,
      isCollapsed: isCollapsed,
      onTap: () => unawaited(openNowPlaying(context)),
      focusNode: _focusTracker.get(_kNowPlaying),
      onNavigateRight: widget.onNavigateToContent,
    );
  }

  Widget _buildReconnectItem({required bool isCollapsed}) {
    final t = tokens(context);

    return NavigationRailItem(
      icon: widget.isReconnecting ? Symbols.sync_rounded : Symbols.wifi_rounded,
      label: widget.isReconnecting
          ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: t.text))
          : Text(
              Translations.of(context).common.reconnect,
              style: const TextStyle(fontSize: 14, fontWeight: .w400),
              overflow: .ellipsis,
              maxLines: 1,
            ),
      labelColor: widget.isReconnecting ? null : t.textMuted,
      collapsedLabel: Translations.of(context).common.reconnect,
      isSelected: false,
      isCollapsed: isCollapsed,
      // ignore: no-empty-block - no-op tap handler while reconnecting
      onTap: widget.isReconnecting ? () {} : () => widget.onReconnect?.call(),
      focusNode: _focusTracker.get(_kReconnect),
      onNavigateRight: widget.onNavigateToContent,
    );
  }

  Widget _buildFullscreenItem({required bool isCollapsed}) {
    final t = tokens(context);
    final isFullscreen = FullscreenStateManager().isFullscreen;
    final label = isFullscreen
        ? Translations.of(context).common.exitFullscreen
        : Translations.of(context).common.fullscreen;

    return NavigationRailItem(
      icon: isFullscreen ? Symbols.fullscreen_exit_rounded : Symbols.fullscreen_rounded,
      label: Text(
        label,
        style: const TextStyle(fontSize: 14, fontWeight: .w400),
        overflow: .ellipsis,
        maxLines: 1,
      ),
      labelColor: t.textMuted,
      collapsedLabel: label,
      isSelected: false,
      isCollapsed: isCollapsed,
      onTap: () => unawaited(FullscreenStateManager().toggleFullscreen()),
      focusNode: _focusTracker.get(_kFullscreen),
      onNavigateRight: widget.onNavigateToContent,
    );
  }

  /// The libraries the user keeps visible, as top-level destinations beside
  /// Home and Search. Server headers show only in the open rail; the collapsed
  /// rail is icons only.
  ///
  /// One column rather than a list child per row: the rail's list builds only
  /// the rows near the viewport, and D-pad focus can only land on a built row,
  /// so a library scrolled out of view would be unreachable.
  List<Widget> _buildLibraryNavRows(List<_LibraryNavRow> rows, dynamic t, {required bool isCollapsed}) {
    if (rows.isEmpty) return const [];
    final widgets = <Widget>[];
    for (final row in rows) {
      switch (row) {
        case _LibraryServerHeaderRow(:final serverId, :final serverName):
          if (!isCollapsed) widgets.add(_buildServerHeader(ServerId(serverId), serverName, t));
        case _LibraryItemRow(:final library, :final showServerName):
          widgets.add(_buildLibraryItem(library, t, isCollapsed: isCollapsed, showServerName: showServerName));
          widgets.add(const SizedBox(height: _itemGap));
      }
    }
    return [Column(crossAxisAlignment: .start, children: widgets)];
  }

  /// Get set of library names that appear more than once (not globally unique)
  Set<String> _getNonUniqueLibraryNames(List<MediaLibrary> libraries) {
    final nameCounts = <String, int>{};
    for (final lib in libraries) {
      nameCounts[lib.title] = (nameCounts[lib.title] ?? 0) + 1;
    }
    return nameCounts.entries.where((e) => e.value > 1).map((e) => e.key).toSet();
  }

  Widget _buildServerHeader(ServerId serverId, String serverName, dynamic t) {
    // Resolve backend per server so the badge matches the brand. Falls back
    // to the generic `dns` icon if the client isn't registered yet (rare —
    // can happen during a profile switch before the manager rehydrates).
    final backend = context.read<MultiServerProvider>().serverManager.getClient(serverId)?.backend;
    return _buildCollapsibleHeader(
      focusKey: _serverHeaderFocusKey(serverId),
      icon: Symbols.dns_rounded,
      iconSize: 14,
      leading: backend == null ? null : BackendBadge(backend: backend, size: 14, color: t.textMuted),
      label: serverName,
      labelStyle: TextStyle(fontSize: 11, fontWeight: .w600, letterSpacing: 0.4, color: t.textMuted),
      verticalPadding: 6,
      isExpanded: !_collapsedServerGroupKeys.contains(_serverGroupStateKey(serverId)),
      onToggle: () => _toggleServerCollapse(serverId),
      t: t,
    );
  }

  void _toggleServerCollapse(ServerId serverId) {
    final groupKey = _serverGroupStateKey(serverId);
    setState(() {
      if (!_collapsedServerGroupKeys.add(groupKey)) {
        _collapsedServerGroupKeys.remove(groupKey);
      }
    });
  }

  Widget _buildCollapsibleHeader({
    required String focusKey,
    required IconData icon,
    required double iconSize,
    Widget? leading,
    required String label,
    required TextStyle labelStyle,
    required double verticalPadding,
    required bool isExpanded,
    required VoidCallback onToggle,
    required dynamic t,
  }) {
    final focusNode = _focusTracker.get(focusKey);
    final radius = BorderRadius.circular(MonoTokens.radiusFull);
    // Sub-section header at full rail width; the smaller type alone carries
    // the hierarchy, matching M3E expanded-rail sections.
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, _) => Focus(
        focusNode: focusNode,
        onKeyEvent: (node, event) =>
            _handleRailItemKey(event, onSelect: onToggle, onNavigateRight: widget.onNavigateToContent),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            canRequestFocus: false,
            onTap: onToggle,
            borderRadius: radius,
            child: Container(
              decoration: BoxDecoration(
                color: focusNode.hasFocus && InputModeTracker.isKeyboardMode(context)
                    ? t.text.withValues(alpha: 0.08)
                    : null,
                borderRadius: radius,
              ),
              clipBehavior: Clip.hardEdge,
              child: UnconstrainedBox(
                alignment: .centerLeft,
                constrainedAxis: Axis.vertical,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: expandedWidth - 24,
                  child: Padding(
                    padding: .symmetric(vertical: verticalPadding, horizontal: 17),
                    child: Row(
                      children: [
                        leading ?? AppIcon(icon, fill: 1, size: iconSize, color: t.textMuted),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Text(label, style: labelStyle, overflow: .ellipsis),
                        ),
                        AppIcon(
                          isExpanded ? Symbols.expand_less_rounded : Symbols.expand_more_rounded,
                          fill: 1,
                          size: 16,
                          color: t.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLibraryItem(MediaLibrary library, dynamic t, {required bool isCollapsed, bool showServerName = false}) {
    final isSelected =
        widget.selectedTab == NavigationTabId.libraries && widget.selectedLibraryKey == library.globalKey;
    final icon = ContentTypeHelper.getLibraryIcon(library.kind.id);

    Widget buildLabel(double opacity) {
      final titleColor = (isSelected ? t.text : t.textMuted) as Color;
      final titleStyle = TextStyle(
        fontSize: 14,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
        color: titleColor.withValues(alpha: titleColor.a * opacity),
      );
      final mutedColor = t.textMuted as Color;
      return Column(
        crossAxisAlignment: .start,
        mainAxisSize: .min,
        children: [
          Text(library.title, style: titleStyle, overflow: .ellipsis, maxLines: 1),
          if (showServerName)
            Text(
              library.serverName!,
              style: TextStyle(fontSize: 10, color: mutedColor.withValues(alpha: mutedColor.a * 0.6 * opacity)),
              overflow: .ellipsis,
              maxLines: 1,
            ),
        ],
      );
    }

    return NavigationRailItem(
      icon: icon,
      selectedIcon: icon,
      label: buildLabel(1),
      labelBuilder: buildLabel,
      collapsedLabel: library.title,
      isSelected: isSelected,
      isCollapsed: isCollapsed,
      onTap: () => widget.onLibrarySelected(library.globalKey),
      focusNode: _focusTracker.get(_libraryItemFocusKey(library.globalKey)),
      suppressSelectedBackground: widget.isSidebarFocused,
      onNavigateRight: widget.onNavigateToContent,
    );
  }
}
