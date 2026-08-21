import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/models/tmdb/tmdb_tv_details.dart';

void main() {
  group('TmdbNextEpisode.fromJson', () {
    test('parses air date, episode number, and season number', () {
      final next = TmdbNextEpisode.fromJson({'air_date': '2026-02-15', 'episode_number': 8, 'season_number': 2});

      expect(next.airDate, '2026-02-15');
      expect(next.episodeNumber, 8);
      expect(next.seasonNumber, 2);
    });

    test('tolerates missing fields', () {
      final next = TmdbNextEpisode.fromJson(const {});

      expect(next.airDate, isNull);
      expect(next.episodeNumber, isNull);
      expect(next.seasonNumber, isNull);
    });
  });

  group('TmdbTvDetails.fromJson', () {
    test('parses status, in_production, and a present next_episode_to_air', () {
      final details = TmdbTvDetails.fromJson({
        'status': 'Returning Series',
        'in_production': true,
        'next_episode_to_air': {'air_date': '2026-02-15', 'episode_number': 8, 'season_number': 2},
      });

      expect(details.status, 'Returning Series');
      expect(details.inProduction, isTrue);
      expect(details.nextEpisodeToAir?.episodeNumber, 8);
    });

    test('a null next_episode_to_air stays null', () {
      final details = TmdbTvDetails.fromJson({
        'status': 'Ended',
        'in_production': false,
        'next_episode_to_air': null,
      });

      expect(details.nextEpisodeToAir, isNull);
    });

    test('defaults status to empty and in_production to false when absent', () {
      final details = TmdbTvDetails.fromJson(const {});

      expect(details.status, '');
      expect(details.inProduction, isFalse);
    });
  });

  group('TmdbTvDetails.isAiring', () {
    test('true when in production and not ended or canceled', () {
      const details = TmdbTvDetails(status: 'Returning Series', inProduction: true);
      expect(details.isAiring, isTrue);
    });

    test('false once status reads Ended, even if in_production lagged true', () {
      const details = TmdbTvDetails(status: 'Ended', inProduction: true);
      expect(details.isAiring, isFalse);
    });

    test('false once status reads Canceled', () {
      const details = TmdbTvDetails(status: 'Canceled', inProduction: true);
      expect(details.isAiring, isFalse);
    });

    test('false when not in production, regardless of status', () {
      const details = TmdbTvDetails(status: 'Returning Series', inProduction: false);
      expect(details.isAiring, isFalse);
    });
  });
}
