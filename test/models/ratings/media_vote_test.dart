import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/models/ratings/media_vote.dart';

void main() {
  group('VoteDirection', () {
    test('wireValue round-trips through fromWire', () {
      for (final direction in VoteDirection.values) {
        expect(VoteDirection.fromWire(direction.wireValue), direction);
      }
    });

    test('fromWire is null for unrecognized or missing values', () {
      expect(VoteDirection.fromWire(null), isNull);
      expect(VoteDirection.fromWire(''), isNull);
      expect(VoteDirection.fromWire('meh'), isNull);
    });
  });

  group('VoteAggregate.borderColor', () {
    test('more good than bad is green', () {
      expect(const VoteAggregate(good: 2, bad: 1).borderColor, Colors.green);
    });

    test('more bad than good is red', () {
      expect(const VoteAggregate(good: 1, bad: 2).borderColor, Colors.red);
    });

    test('an equal split cancels out to no border', () {
      expect(const VoteAggregate(good: 3, bad: 3).borderColor, isNull);
    });

    test('no votes at all is no border', () {
      expect(const VoteAggregate().borderColor, isNull);
    });
  });

  group('VoteAggregate.fromJson', () {
    test('parses counts and mine', () {
      final agg = VoteAggregate.fromJson({'good': 4, 'bad': 1, 'mine': 'good'});
      expect(agg.good, 4);
      expect(agg.bad, 1);
      expect(agg.mine, VoteDirection.good);
    });

    test('missing fields default to zero counts and no vote', () {
      final agg = VoteAggregate.fromJson(const {});
      expect(agg, const VoteAggregate());
    });

    test('an unrecognized mine value reads as no vote rather than throwing', () {
      final agg = VoteAggregate.fromJson({'mine': 'sideways'});
      expect(agg.mine, isNull);
    });
  });

  group('VoteAggregate equality', () {
    test('two aggregates with the same fields are equal', () {
      expect(
        const VoteAggregate(good: 1, bad: 2, mine: VoteDirection.good),
        const VoteAggregate(good: 1, bad: 2, mine: VoteDirection.good),
      );
    });

    test('differing mine breaks equality even with the same counts', () {
      expect(
        const VoteAggregate(good: 1, bad: 2, mine: VoteDirection.good) ==
            const VoteAggregate(good: 1, bad: 2, mine: VoteDirection.bad),
        isFalse,
      );
    });
  });
}
