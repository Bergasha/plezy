import 'dart:async';

import 'package:flutter/material.dart';

import 'focus_theme.dart';

const _spotlightDimAlpha = 0.45;

/// Which card holds the OLED spotlight, and the fade between cards.
///
/// While one card is focused every other card dims; moving focus fades the old
/// card down and the new one up. One controller serves every card: each card
/// reads its own dim through a [SpotlightDim], so no card needs a ticker.
class OledSpotlightModel {
  OledSpotlightModel({required TickerProvider vsync, required Duration duration}) : _duration = duration {
    controller = AnimationController(vsync: vsync, duration: duration, value: 1);
  }

  final Duration _duration;
  late final AnimationController controller;
  Object? _focused;
  Object? _previous;
  bool _disposed = false;

  void dispose() {
    _disposed = true;
    controller.dispose();
  }

  void focus(Object token) {
    if (_disposed || identical(_focused, token)) return;
    _previous = _focused;
    _focused = token;
    _restart();
  }

  /// Releases [token]'s hold on the spotlight. Deferred a microtask so a move
  /// between two cards, which blurs one and focuses the other in a single
  /// step, fades once instead of dipping to no spotlight in between.
  void blur(Object token) {
    scheduleMicrotask(() {
      if (_disposed || !identical(_focused, token)) return;
      _previous = _focused;
      _focused = null;
      _restart();
    });
  }

  void _restart() {
    if (_duration == Duration.zero) {
      controller.value = 0;
      controller.value = 1;
    } else {
      unawaited(controller.forward(from: 0));
    }
  }

  static double _alphaFor(Object token, Object? focused) {
    if (focused == null || identical(focused, token)) return 0;
    return _spotlightDimAlpha;
  }

  double valueFor(Object token) {
    final from = _alphaFor(token, _previous);
    final to = _alphaFor(token, _focused);
    if (from == to) return to;
    return from + (to - from) * Curves.easeOutCubic.transform(controller.value);
  }
}

/// A card's artwork dim: 0 for the spotlit card, a shade of black for the rest.
class SpotlightDim extends Animation<double> {
  SpotlightDim(this._model, this._token);

  final OledSpotlightModel _model;
  final Object _token;

  @override
  double get value => _model.valueFor(_token);

  @override
  AnimationStatus get status => _model.controller.status;

  @override
  void addListener(VoidCallback listener) => _model.controller.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _model.controller.removeListener(listener);

  @override
  void addStatusListener(AnimationStatusListener listener) => _model.controller.addStatusListener(listener);

  @override
  void removeStatusListener(AnimationStatusListener listener) => _model.controller.removeStatusListener(listener);
}

/// Owns the [OledSpotlightModel] for everything below it. Cards outside a host
/// (and tests) simply never dim.
class OledSpotlightHost extends StatefulWidget {
  const OledSpotlightHost({super.key, required this.child});

  final Widget child;

  /// The enclosing model, or null. Reads without subscribing, so a card does
  /// not rebuild when the spotlight moves.
  static OledSpotlightModel? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_OledSpotlightScope>()?.model;

  @override
  State<OledSpotlightHost> createState() => _OledSpotlightHostState();
}

class _OledSpotlightHostState extends State<OledSpotlightHost> with SingleTickerProviderStateMixin {
  OledSpotlightModel? _model;

  @override
  void dispose() {
    _model?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = _model ??= OledSpotlightModel(vsync: this, duration: FocusTheme.getAnimationDuration(context));
    return _OledSpotlightScope(model: model, child: widget.child);
  }
}

class _OledSpotlightScope extends InheritedWidget {
  const _OledSpotlightScope({required this.model, required super.child});

  final OledSpotlightModel model;

  @override
  bool updateShouldNotify(_OledSpotlightScope oldWidget) => model != oldWidget.model;
}
