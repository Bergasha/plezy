import 'package:flutter/material.dart';

/// A single "This was Good" / "This was Shit" vote direction.
enum VoteDirection {
  good,
  bad;

  String get wireValue => switch (this) {
    VoteDirection.good => 'good',
    VoteDirection.bad => 'bad',
  };

  static VoteDirection? fromWire(String? value) => switch (value) {
    'good' => VoteDirection.good,
    'bad' => VoteDirection.bad,
    _ => null,
  };
}

/// Everyone's votes on one media item, as returned by the ratings service.
///
/// Border color follows `good - bad`: strictly positive is green, strictly
/// negative is red, zero (including no votes at all) is neutral — an equal
/// split cancels out rather than showing either color.
@immutable
class VoteAggregate {
  final int good;
  final int bad;
  final VoteDirection? mine;

  const VoteAggregate({this.good = 0, this.bad = 0, this.mine});

  int get net => good - bad;

  Color? get borderColor {
    if (net > 0) return Colors.green;
    if (net < 0) return Colors.red;
    return null;
  }

  factory VoteAggregate.fromJson(Map<String, dynamic> json) => VoteAggregate(
    good: (json['good'] as num?)?.toInt() ?? 0,
    bad: (json['bad'] as num?)?.toInt() ?? 0,
    mine: VoteDirection.fromWire(json['mine'] as String?),
  );

  VoteAggregate copyWith({int? good, int? bad, VoteDirection? Function()? mine}) =>
      VoteAggregate(good: good ?? this.good, bad: bad ?? this.bad, mine: mine != null ? mine() : this.mine);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VoteAggregate && other.good == good && other.bad == bad && other.mine == mine);

  @override
  int get hashCode => Object.hash(good, bad, mine);

  @override
  String toString() => 'VoteAggregate(good: $good, bad: $bad, mine: $mine)';
}
