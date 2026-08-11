import 'dart:async';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../focus/dpad_navigator.dart';
import '../i18n/app_locale_utils.dart';
import '../i18n/strings.g.dart';
import '../models/plex/plex_community_review.dart';
import '../theme/mono_tokens.dart';
import '../utils/scroll_utils.dart';
import 'app_icon.dart';
import 'focus_builders.dart';
import 'horizontal_scroll_with_arrows.dart';

/// Horizontal fan-review strip for the "Ratings & Reviews" section on the
/// movie/show detail screen.
///
/// Owns the locked-focus row model — focus node, highlighted index,
/// horizontal scrolling, and D-pad handling — mirroring
/// `CastMemberStrip`/the Extras row so this section behaves the same on a
/// remote as every other horizontal shelf on this screen: reachable via
/// UP/DOWN from its neighbors, scrollable via LEFT/RIGHT, with the standard
/// focus chrome on the highlighted card. There is no per-review activation
/// target (no "open review" link in the data Plex's community API returns
/// here), so cards highlight on focus but do not respond to select.
class PlexReviewStrip extends StatefulWidget {
  static const double _baseCardWidth = 260;
  static const double _baseCardHeight = 172;
  static const double _baseCardGap = 12;

  final List<PlexCommunityReview> reviews;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;
  final String debugLabel;

  /// Uniform size multiplier applied to card width/height/gap. Defaults to
  /// the phone/desktop size (1.0); TV call sites pass their own layout scale
  /// so this strip's footprint shrinks/grows in proportion to every other
  /// TV-scaled element instead of reserving a fixed desktop-sized chunk of
  /// the (much smaller, already-scaled) TV screen budget.
  final double cardScale;

  const PlexReviewStrip({
    super.key,
    required this.reviews,
    this.onNavigateUp,
    this.onNavigateDown,
    this.debugLabel = 'reviews_row',
    this.cardScale = 1.0,
  });

  double get _cardWidth => _baseCardWidth * cardScale;

  double get _cardGap => _baseCardGap * cardScale;

  /// The strip's fixed height for a given [cardScale]: card height plus list
  /// padding and focus-scale headroom (mirrors
  /// `CastMemberStrip.heightForCardWidth`). Callers that need to reserve
  /// layout space before constructing the widget (e.g. the TV detail
  /// screen's bottom-docked section budget) use this instead of an instance.
  static double heightForScale(double cardScale) => (_baseCardHeight * cardScale) + 10;

  double get _itemExtent => _cardWidth + _cardGap;

  @override
  State<PlexReviewStrip> createState() => PlexReviewStripState();
}

class PlexReviewStripState extends State<PlexReviewStrip> {
  late final FocusNode _focusNode;
  final ScrollController _scrollController = ScrollController();
  int _focusedIndex = 0;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: widget.debugLabel)..addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(PlexReviewStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.debugLabel != oldWidget.debugLabel) {
      _focusNode.debugLabel = widget.debugLabel;
    }
    if (widget.reviews.isEmpty) {
      _focusedIndex = 0;
    } else if (_focusedIndex >= widget.reviews.length) {
      _focusedIndex = widget.reviews.length - 1;
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
  /// into view. Called via `GlobalKey<PlexReviewStripState>` from the parent
  /// screen's vertical navigation chain, mirroring `CastMemberStripState`.
  void requestFocus() {
    if (widget.reviews.isEmpty) return;
    _focusNode.requestFocus();
    _scrollToFocusedReview();
  }

  void _scrollToFocusedReview() {
    scrollListToIndex(_scrollController, _focusedIndex, itemExtent: widget._itemExtent, leadingPadding: 0);
  }

  void _moveFocus(int delta) {
    if (widget.reviews.isEmpty) return;
    final target = (_focusedIndex + delta).clamp(0, widget.reviews.length - 1).toInt();
    if (target == _focusedIndex) return;
    setState(() => _focusedIndex = target);
    _scrollToFocusedReview();
  }

  KeyEventResult _handleKeyEvent(FocusNode _, KeyEvent event) {
    final key = event.logicalKey;
    if (key.isBackKey || widget.reviews.isEmpty) return KeyEventResult.ignored;
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

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      descendantsAreFocusable: false,
      onKeyEvent: _handleKeyEvent,
      child: SizedBox(
        height: PlexReviewStrip.heightForScale(widget.cardScale),
        child: HorizontalScrollWithArrows(
          controller: _scrollController,
          builder: (scrollController) => ListView.builder(
            addAutomaticKeepAlives: false,
            addSemanticIndexes: false,
            controller: scrollController,
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: const EdgeInsets.symmetric(vertical: 5),
            itemCount: widget.reviews.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: EdgeInsets.only(right: widget._cardGap),
                child: FocusBuilders.buildLockedFocusWrapper(
                  context: context,
                  isFocused: _focusNode.hasFocus && index == _focusedIndex,
                  borderRadius: tokens(context).radiusMd,
                  child: PlexReviewCard(
                    review: widget.reviews[index],
                    width: widget._cardWidth,
                    isFocused: _focusNode.hasFocus && index == _focusedIndex,
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

/// A single fan review card: avatar, display name, relative date, star
/// rating, truncated review text, and reaction icons + count — matching the
/// layout Plex's own HTPC/web apps use for community reviews.
class PlexReviewCard extends StatelessWidget {
  const PlexReviewCard({super.key, required this.review, this.width = 260, this.isFocused = false});

  final PlexCommunityReview review;
  final double width;

  /// Whether this card is the currently d-pad/keyboard-focused card in its
  /// strip. Drives the slow auto-scroll on the message text so a long review
  /// can be read in full without needing per-review text truncation UI.
  final bool isFocused;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final name = review.displayName.isEmpty ? t.discover.plexCommunityUser : review.displayName;

    return Container(
      width: width,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(tokens(context).radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Avatar(avatarUrl: review.avatarUrl, name: name),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      _formatReviewDate(review.date),
                      style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (review.starRating != null) ...[
            const SizedBox(height: 8),
            _StarRow(rating: review.starRating!),
          ],
          const SizedBox(height: 8),
          Expanded(
            child: _AutoScrollingReviewText(
              text: review.message ?? '',
              style: theme.textTheme.bodySmall,
              focused: isFocused,
            ),
          ),
          if (review.reactionsCount > 0) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(
                  _leadingReactionIcon(review.reactionsTypes),
                  size: 14,
                  fill: 1,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  '${review.reactionsCount}',
                  style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Review-body text that, once its card is focused, pauses briefly then
/// slowly auto-scrolls from top to bottom so a review longer than the
/// card's fixed height can be read in full without truncation. Scrolls back
/// to the top (and cancels any pending start) as soon as focus leaves —
/// otherwise re-focusing a card would always resume mid-review. A no-op when
/// the text already fits without overflowing.
class _AutoScrollingReviewText extends StatefulWidget {
  const _AutoScrollingReviewText({required this.text, required this.style, required this.focused});

  final String text;
  final TextStyle? style;
  final bool focused;

  static const _startDelay = Duration(milliseconds: 900);
  // Constant reading speed — no min/max duration clamp. A duration cap made
  // long reviews scroll noticeably faster than short ones once the cap
  // bound, since the same time budget had to cover more distance.
  static const _pixelsPerSecond = 13.0;

  @override
  State<_AutoScrollingReviewText> createState() => _AutoScrollingReviewTextState();
}

class _AutoScrollingReviewTextState extends State<_AutoScrollingReviewText> {
  final _scrollController = ScrollController();
  Timer? _startTimer;

  @override
  void initState() {
    super.initState();
    if (widget.focused) _scheduleAutoScroll();
  }

  @override
  void didUpdateWidget(_AutoScrollingReviewText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focused == oldWidget.focused) return;
    if (widget.focused) {
      _scheduleAutoScroll();
    } else {
      _resetScroll();
    }
  }

  @override
  void dispose() {
    _startTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleAutoScroll() {
    _startTimer?.cancel();
    _startTimer = Timer(_AutoScrollingReviewText._startDelay, _startAutoScroll);
  }

  Future<void> _startAutoScroll() async {
    if (!mounted || !widget.focused || !_scrollController.hasClients) return;
    final maxExtent = _scrollController.position.maxScrollExtent;
    if (maxExtent <= 0) return;

    final estimatedMs = (maxExtent / _AutoScrollingReviewText._pixelsPerSecond * 1000).round();
    final duration = Duration(milliseconds: estimatedMs);

    await _scrollController.animateTo(maxExtent, duration: duration, curve: Curves.linear);
  }

  void _resetScroll() {
    _startTimer?.cancel();
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels == 0) return;
    unawaited(
      _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      physics: const NeverScrollableScrollPhysics(),
      child: Text(widget.text, style: widget.style),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.avatarUrl, required this.name});

  final String? avatarUrl;
  final String name;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const radius = 16.0;
    if (avatarUrl != null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: colorScheme.surfaceContainerHighest,
        foregroundImage: CachedNetworkImageProvider(avatarUrl!),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: colorScheme.surfaceContainerHighest,
      child: AppIcon(Symbols.person_rounded, size: 18, color: colorScheme.onSurfaceVariant),
    );
  }
}

/// Row of 5 star glyphs, filled/half-filled/empty per [rating] (0-5).
class _StarRow extends StatelessWidget {
  const _StarRow({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final filledColor = colorScheme.tertiary;
    final emptyColor = colorScheme.outlineVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final isFilled = rating >= i + 1;
        final isHalf = !isFilled && rating > i && rating < i + 1;
        return Padding(
          padding: EdgeInsets.only(right: i == 4 ? 0 : 2),
          child: AppIcon(
            isHalf ? Symbols.star_half_rounded : Symbols.star_rounded,
            size: 14,
            fill: isFilled || isHalf ? 1 : 0,
            color: isFilled || isHalf ? filledColor : emptyColor,
          ),
        );
      }),
    );
  }
}

/// Reaction icon for the leading reaction type, falling back to a generic
/// "like" glyph when the API sent no recognizable type.
IconData _leadingReactionIcon(List<String> reactionsTypes) {
  if (reactionsTypes.isEmpty) return Symbols.thumb_up_rounded;
  return switch (reactionsTypes.first.toUpperCase()) {
    'LOVE' => Symbols.favorite_rounded,
    'LAUGH' => Symbols.sentiment_very_satisfied_rounded,
    'APPLAUD' => Symbols.front_hand_rounded,
    'QUESTION' => Symbols.help_rounded,
    'DISLIKE' => Symbols.thumb_down_rounded,
    _ => Symbols.thumb_up_rounded,
  };
}

/// Compact relative date like Plex's own review timestamps: "3d", "2w",
/// "5mo", "1y", falling back to an absolute locale-aware date once older than
/// a few years.
String _formatReviewDate(DateTime? date) {
  if (date == null) return '';
  final now = DateTime.now();
  final diff = now.difference(date);

  if (diff.inDays < 1) {
    if (diff.inHours >= 1) return '${diff.inHours}h';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}m';
    return 'now';
  }
  if (diff.inDays < 7) return '${diff.inDays}d';
  if (diff.inDays < 30) return '${diff.inDays ~/ 7}w';
  if (diff.inDays < 365) return '${diff.inDays ~/ 30}mo';
  if (diff.inDays < 365 * 3) return '${diff.inDays ~/ 365}y';

  return DateFormat.yMMMd(LocaleSettings.currentLocale.intlLocaleName).format(date);
}
