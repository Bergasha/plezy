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
      final details = TmdbTvDetails.fromJson({'status': 'Ended', 'in_production': false, 'next_episode_to_air': null});

      expect(details.nextEpisodeToAir, isNull);
    });

    test('defaults status to empty and in_production to false when absent', () {
      final details = TmdbTvDetails.fromJson(const {});

      expect(details.status, '');
      expect(details.inProduction, isFalse);
    });

    test('parses the seasons list', () {
      final details = TmdbTvDetails.fromJson({
        'seasons': [
          {'season_number': 0, 'air_date': '2020-01-01'},
          {'season_number': 1, 'air_date': '2021-01-01'},
          {'season_number': 2, 'air_date': null},
        ],
      });

      expect(details.seasons, hasLength(3));
      expect(details.seasons[1].seasonNumber, 1);
      expect(details.seasons[1].airDate, '2021-01-01');
      expect(details.seasons[2].airDate, isNull);
    });

    test('tolerates a missing seasons list', () {
      final details = TmdbTvDetails.fromJson(const {});
      expect(details.seasons, isEmpty);
    });
  });

  group('TmdbTvDetails.upcomingSeasonAirDate', () {
    test('finds the earliest dated season after the given number', () {
      const details = TmdbTvDetails(
        status: 'Returning Series',
        inProduction: true,
        seasons: [
          TmdbSeasonSummary(seasonNumber: 3, airDate: '2025-01-01'),
          TmdbSeasonSummary(seasonNumber: 5, airDate: '2027-06-01'),
          TmdbSeasonSummary(seasonNumber: 4, airDate: '2026-03-15'),
        ],
      );

      expect(details.upcomingSeasonAirDate(3), '2026-03-15');
    });

    test('skips seasons TMDb has stubbed but not dated yet', () {
      const details = TmdbTvDetails(
        status: 'Returning Series',
        inProduction: true,
        seasons: [
          TmdbSeasonSummary(seasonNumber: 4, airDate: null),
          TmdbSeasonSummary(seasonNumber: 5, airDate: '2027-06-01'),
        ],
      );

      expect(details.upcomingSeasonAirDate(3), '2027-06-01');
    });

    test('returns null when nothing after that season has a date', () {
      const details = TmdbTvDetails(
        status: 'Returning Series',
        inProduction: true,
        seasons: [TmdbSeasonSummary(seasonNumber: 3, airDate: '2025-01-01')],
      );

      expect(details.upcomingSeasonAirDate(3), isNull);
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
