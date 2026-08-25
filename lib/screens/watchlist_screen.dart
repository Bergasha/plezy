import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.g.dart';
import '../mixins/refreshable.dart';
import '../providers/catalog_sources_provider.dart';
import '../providers/explore_provider.dart';
import '../services/catalog/catalog_source.dart';
import 'hub_detail_screen.dart';
import 'libraries/state_messages.dart';

/// Sidebar tab wrapping a watchlist-capable source's watchlist row in the
/// same grid/pagination machinery the Explore tab's "View All" uses, so the
/// watchlist is reachable without going through Explore first.
///
/// Deliberately its own [ExploreProvider] instance, pinned to
/// [CatalogSourcesProvider.watchlistCapableSource] rather than reading the
/// shared Explore-tab one: that instance follows whatever source Explore is
/// currently browsing, which empties this tab the moment Explore points at a
/// source with no watchlist (Seerr) even though a perfectly good watchlist
/// (Plex, a tracker, ...) is still connected.
///
/// [HubDetailScreen] normally shows a back button when pushed as a route; as
/// a tab root there is nothing to pop, so [CustomAppBar]'s automatic leading
/// behaviour (via `Navigator.canPop`) hides it here for free.
class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> with Refreshable {
  late final ExploreProvider _explore;

  @override
  void initState() {
    super.initState();
    _explore = ExploreProvider(
      context.read<CatalogSourcesProvider>(),
      sourceSelector: (sources) => sources.watchlistCapableSource,
    );
    unawaited(_explore.load());
  }

  @override
  void dispose() {
    _explore.dispose();
    super.dispose();
  }

  @override
  void refresh() {
    unawaited(_explore.load());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _explore,
      builder: (context, _) {
        final explore = _explore;
        final rowHub = explore.rowHubs.where((r) => r.row == CatalogRowId.watchlist).firstOrNull;
        if (rowHub != null) {
          return HubDetailScreen(
            hub: rowHub.hub,
            loadItems: rowHub.hub.more ? () => explore.loadAllForHub(rowHub) : null,
          );
        }

        if (explore.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (explore.state == ExploreLoadState.error) {
          return ErrorStateWidget(
            message: explore.errorMessage ?? t.explore.watchlistEmptyTitle,
            icon: Symbols.error_outline_rounded,
            onRetry: () => unawaited(explore.load()),
          );
        }

        return EmptyStateWidget(
          message: t.explore.watchlistEmptyTitle,
          subtitle: t.explore.watchlistEmptyMessage,
          icon: Symbols.bookmark_rounded,
        );
      },
    );
  }
}
