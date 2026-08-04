import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/formatters.dart';

/// A small live clock for display in a toolbar. Ticks once a minute, aligned
/// to the start of the next minute rather than polling, since the display
/// only has minute resolution.
class HomeClock extends StatefulWidget {
  const HomeClock({super.key, this.color});

  final Color? color;

  @override
  State<HomeClock> createState() => _HomeClockState();
}

class _HomeClockState extends State<HomeClock> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _scheduleNextTick();
  }

  void _scheduleNextTick() {
    final now = DateTime.now();
    final nextMinute = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    ).add(const Duration(minutes: 1));
    _timer = Timer(nextMinute.difference(now), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _scheduleNextTick();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.titleMedium?.copyWith(
      color: widget.color ?? colorScheme.onSurface,
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Text(
      formatClockTime(_now, is24Hour: MediaQuery.alwaysUse24HourFormatOf(context)),
      style: style,
    );
  }
}
