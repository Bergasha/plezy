import 'dart:async';

import 'package:flutter/material.dart';

import '../focus/dpad_navigator.dart';
import '../focus/key_event_utils.dart';
import '../media/media_item.dart';
import '../theme/mono_tokens.dart';
import '../utils/scroll_utils.dart';
import '../utils/video_player_navigation.dart';
import 'focus_builders.dart';
import 'horizontal_scroll_with_arrows.dart';
import 'media_card.dart';

/// Horizontal "Trailers & Extras" strip for the TV detail layout.
///
/// Mirrors `PlexReviewStrip`'s locked-focus row model (focus node,
/// highlighted index, horizontal scrolling, D-pad handling) but renders
/// [MediaCard]s and activates them on select — the TV-specific counterpart to
/// the non-TV Column's `_buildExtrasSectionContent`. Extracted as its own
/// directly-placed Stack section because `TvBrowseRail` stacks every hub it's
/// given into one shared vertical navigation model, which made Extras
/// inseparable from Cast when both lived inside it (see history: Reviews had
/// to move between Cast and Extras, which is impossible while both are hubs
/// in the same rail).
class TvExtrasStrip extends StatefulWidget {
  static const double _baseCardWidth = 280;
  static const double _baseLabelHeight = 44;

  final List<MediaItem> extras;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;
  final void Function(MediaItem source)? onRefresh;

  /// Uniform size multiplier, matching `PlexReviewStrip.cardScale` — TV call
  /// sites pass the screen's own layout scale so this strip's footprint
  /// stays proportional to every other TV-scaled element.
  final double cardScale;

  final String debugLabel;

  const TvExtrasStrip({
    super.key,
    required this.extras,
    this.onNavigateUp,
    this.onNavigateDown,
    this.onRefresh,
    this.cardScale = 1.0,
    this.debugLabel = 'tv_extras_row',
  });

  double get _cardWidth => _baseCardWidth * cardScale;

  double get _posterHeight => _cardWidth * 9 / 16;

  double get _cardGap => 12 * cardScale;

  double get _itemExtent => _cardWidth + _cardGap;

  /// The strip's fixed height for a given [cardScale]: 16:9 poster height
  /// plus the title label area, list padding, and focus-scale headroom —
  /// mirrors `PlexReviewStrip.heightForScale`. Callers that need to reserve
  /// layout space before constructing the widget (the TV detail screen's
  /// bottom-docked section budget) use this instead of an instance.
  static double heightForScale(double cardScale) {
    final width = _baseCardWidth * cardScale;
    final posterHeight = width * 9 / 16;
    return posterHeight + (_baseLabelHeight * cardScale) + 10;
  }

  @override
  State<TvExtrasStrip> createState() => TvExtrasStripState();
}

class TvExtrasStripState extends State<TvExtrasStrip> {
  late final FocusNode _focusNode;
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey<MediaCardState>> _cardKeys = {};
  int _focusedIndex = 0;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: widget.debugLabel)..addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(TvExtrasStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.debugLabel != oldWidget.debugLabel) {
      _focusNode.debugLabel = widget.debugLabel;
    }
    if (widget.extras.isEmpty) {
      _focusedIndex = 0;
    } else if (_focusedIndex >= widget.extras.length) {
      _focusedIndex = widget.extras.length - 1;
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (mounted) setState(() {});
  }

  /// Move focus into the strip and scroll the currently-highlighted card
  /// into view. Called via `GlobalKey<TvExtrasStripState>` from the parent
  /// screen's vertical navigation chain, mirroring `PlexReviewStripState`.
  void requestFocus() {
    if (widget.extras.isEmpty) return;
    _focusNode.requestFocus();
    _scrollToFocused();
  }

  void _scrollToFocused() {
    scrollListToIndex(_scrollController, _focusedIndex, itemExtent: widget._itemExtent, leadingPadding: 0);
  }

  void _moveFocus(int delta) {
    if (widget.extras.isEmpty) return;
    final target = (_focusedIndex + delta).clamp(0, widget.extras.length - 1).toInt();
    if (target == _focusedIndex) return;
    setState(() => _focusedIndex = target);
    _scrollToFocused();
  }

  void _activate(int index) {
    if (index < 0 || index >= widget.extras.length) return;
    unawaited(navigateToVideoPlayer(context, metadata: widget.extras[index]));
  }

  KeyEventResult _handleKeyEvent(FocusNode _, KeyEvent event) {
    final key = event.logicalKey;
    if (key.isBackKey || widget.extras.isEmpty) return KeyEventResult.ignored;

    final selectResult = handleOneShotSelect(event, () => _activate(_focusedIndex));
    if (selectResult != KeyEventResult.ignored) return selectResult;

    if (!event.isActionable) return KeyEventResult.ignored;

    if (key.isLeftKey) {
      _moveFocus(-1);
      return KeyEventResult.handled;
    }
    if (key.isRightKey) {
      _moveFocus(1);
      return KeyEventResult.handled;
    }
    if (key.isUpKey && widget.onNavigateUp != null) {
      widget.onNavigateUp!();
      return KeyEventResult.handled;
    }
    if (key.isDownKey && widget.onNavigateDown != null) {
      widget.onNavigateDown!();
      return KeyEventResult.handled;
    }
    if (key.isContextMenuKey) {
      _cardKeys[_focusedIndex]?.currentState?.showContextMenu();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      descendantsAreFocusable: false,
      onKeyEvent: _handleKeyEvent,
      child: SizedBox(
        height: TvExtrasStrip.heightForScale(widget.cardScale),
        child: HorizontalScrollWithArrows(
          controller: _scrollController,
          builder: (scrollController) => ListView.builder(
            addAutomaticKeepAlives: false,
            addSemanticIndexes: false,
            controller: scrollController,
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: const EdgeInsets.symmetric(vertical: 5),
            itemCount: widget.extras.length,
            itemBuilder: (context, index) {
              final cardKey = _cardKeys.putIfAbsent(index, () => GlobalKey<MediaCardState>());
              return Padding(
                padding: EdgeInsets.only(right: widget._cardGap),
                child: FocusBuilders.buildLockedFocusWrapper(
                  context: context,
                  isFocused: _focusNode.hasFocus && index == _focusedIndex,
                  borderRadius: tokens(context).radiusSm,
                  delegateFocusBorder: true,
                  onTap: () {
                    setState(() => _focusedIndex = index);
                    _focusNode.requestFocus();
                    _activate(index);
                  },
                  onLongPress: () {
                    setState(() => _focusedIndex = index);
                    _focusNode.requestFocus();
                    cardKey.currentState?.showContextMenu();
                  },
                  // No `onTap` on the card itself — the outer wrapper above
                  // owns activation, mirroring `TvBrowseRail`'s own cards.
                  child: MediaCard(
                    key: cardKey,
                    item: widget.extras[index],
                    width: widget._cardWidth,
                    height: widget._posterHeight,
                    onRefresh: widget.onRefresh,
                    forceGridMode: true,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
