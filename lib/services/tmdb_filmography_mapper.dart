import '../media/media_kind.dart';
import '../models/catalog/catalog_item.dart';
import '../models/tmdb/tmdb_filmography_credit.dart';
import 'catalog/seerr_catalog_source.dart';

/// Converts TMDb's `/person/{id}/combined_credits` cast list into
/// [CatalogItem]s, so it can flow straight into the app's existing
/// [CatalogItemDetailScreen] — no separate "TMDb detail view" needed, and
/// library-match / request-eligibility comes for free from the machinery
/// that screen already has.
///
/// Tagged [CatalogSourceId.seerr] rather than a new source id: these items
/// are TMDb data that, when not already in the library, get requested
/// through Seerr — the same role Seerr's own catalog source already plays.
List<CatalogItem> mapTmdbFilmography(List<TmdbFilmographyCredit> credits) {
  final seen = <String>{};
  final items = <CatalogItem>[];

  for (final credit in credits) {
    final title = credit.title;
    if (title == null || title.trim().isEmpty) continue;

    final dedupeKey = '${credit.mediaType}:${credit.id}';
    if (!seen.add(dedupeKey)) continue;

    final kind = credit.mediaType == 'tv' ? MediaKind.show : MediaKind.movie;
    final year = _yearFrom(credit.releaseDate);

    items.add(
      CatalogItem(
        source: CatalogSourceId.seerr,
        kind: kind,
        title: title,
        year: year,
        overview: credit.overview,
        rating: credit.voteAverage,
        votes: credit.voteCount,
        ids: CatalogItemIds(tmdb: credit.id),
        posterUrl: SeerrCatalogSource.tmdbImageUrl(credit.posterPath, 'w600_and_h900_bestv2'),
        backdropUrl: SeerrCatalogSource.tmdbImageUrl(credit.backdropPath, 'w1920_and_h800_multi_faces'),
        releaseDate: _dateFrom(credit.releaseDate),
      ),
    );
  }

  items.sort((a, b) => (b.releaseDate ?? DateTime(0)).compareTo(a.releaseDate ?? DateTime(0)));
  return items;
}

int? _yearFrom(String? date) => date == null || date.length < 4 ? null : int.tryParse(date.substring(0, 4));

DateTime? _dateFrom(String? date) => date == null ? null : DateTime.tryParse(date);