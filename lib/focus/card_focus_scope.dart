import 'package:flutter/material.dart';

import '../services/device_performance.dart';
import '../services/settings_service.dart';
import 'focus_glow_overlay.dart';
import 'focus_theme.dart';

/// What a [CardFocusGlow] should draw around its card's artwork.
@immutable
class CardGlow {
  const CardGlow({required this.visible, this.bleed = false});

  /// Whether the glow is showing now. Held back by the TV rail while its
  /// viewport scrolls vertically.
  final bool visible;

  /// Adds the wide colour-bleed halo.
  final bool bleed;

  @override
  bool operator ==(Object other) => other is CardGlow && other.visible == visible && other.bleed == bleed;

  @override
  int get hashCode => Object.hash(visible, bleed);
}

/// Exposes the focus state of an enclosing focus wrapper to a descendant
/// [CardFocusBorder] that draws the focus border itself.
///
/// The shared focus chrome ([buildFocusChrome]) inserts this instead of painting
/// a border when `delegateFocusBorder` is set, so cards can
/// put the border on the exact rect the design highlights (the poster image,
/// not the card-plus-captions rect — issue #1278). Only the [CardFocusBorder]
/// element registers a dependency, so a focus flip rebuilds just that border
/// box: a stable `child:` card subtree (e.g. the TV rail's MediaCard) is not
/// rebuilt.
class CardFocusScope extends InheritedWidget {
  const CardFocusScope({super.key, required this.showFocus, this.color, this.glow, required super.child});

  /// Whether the enclosing wrapper currently shows focus visuals
  /// (focused while in keyboard/d-pad input mode).
  final bool showFocus;

  /// Overrides the theme's focus colour for the border (the OLED poster colour).
  final Color? color;

  /// Set when the card should glow around its artwork (the OLED effects).
  final CardGlow? glow;

  /// Null when no delegating wrapper is above (touch mode skips the focus
  /// wrappers entirely) — [CardFocusBorder] then renders its child bare.
  static bool? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<CardFocusScope>()?.showFocus;

  static CardFocusScope? maybeScopeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CardFocusScope>();

  @override
  bool updateShouldNotify(CardFocusScope oldWidget) =>
      showFocus != oldWidget.showFocus || color != oldWidget.color || glow != oldWidget.glow;
}

/// Draws the focus border around its child based on the enclosing
/// [CardFocusScope], letting the card decide which rect gets highlighted.
///
/// Defaults to an outside stroke so the border hugs the child exactly like the
/// full-bleed card treatment (the child's own corner radius nests inside it).
/// Decoration only — never affects layout. Renders the child unchanged when no
/// scope is present.
class CardFocusBorder extends StatelessWidget {
  const CardFocusBorder({
    super.key,
    this.borderRadius = FocusTheme.defaultBorderRadius,
    this.borderRadii,
    this.strokeAlign = BorderSide.strokeAlignOutside,
    required this.child,
  });

  final double borderRadius;

  /// Per-corner radii; overrides [borderRadius] when set (M3E grouped cards).
  final BorderRadius? borderRadii;

  final double strokeAlign;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = CardFocusScope.maybeScopeOf(context);
    if (scope == null) return child;

    return AnimatedContainer(
      duration: FocusTheme.getAnimationDuration(context),
      curve: Curves.easeOutCubic,
      foregroundDecoration: FocusTheme.focusDecoration(
        context,
        isFocused: scope.showFocus,
        borderRadius: borderRadius,
        radii: borderRadii,
        borderStrokeAlign: strokeAlign,
        color: scope.color,
      ),
      child: child,
    );
  }
}

/// Glows around its child while the enclosing [CardFocusScope] asks for it,
/// so the light hugs the artwork rather than the whole card and its captions.
///
/// Renders the child unchanged when no scope, or no glow, is requested, or
/// when glow is switched off or unaffordable on this device.
class CardFocusGlow extends StatelessWidget {
  const CardFocusGlow({super.key, this.borderRadius = FocusTheme.defaultBorderRadius, required this.child});

  final double borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = CardFocusScope.maybeScopeOf(context);
    final glow = scope?.glow;
    if (scope == null || glow == null) return child;
    if (DevicePerformance.isReduced || !SettingsService.instance.read(SettingsService.focusGlow)) return child;

    return FocusGlowOverlay(
      isFocused: scope.showFocus && glow.visible,
      borderRadius: borderRadius,
      color: scope.color ?? FocusTheme.getFocusBorderColor(context),
      bleed: glow.bleed,
      child: child,
    );
  }
}
