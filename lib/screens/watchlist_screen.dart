import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.g.dart';
import '../mixins/refreshable.dart';
import '../providers/explore_provider.dart';
import '../services/catalog/catalog_source.dart';
import 'hub_detail_screen.dart';
import 'libraries/state_messages.dart';

/// Sidebar tab wrapping the active catalog source's watchlist row in the
/// same grid/pagination machinery the Explore tab's "View All" uses, so the
/// watchlist is reachable without going through Explore first.
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
  @override
  void initState() {
    super.initState();
    unawaited(context.read<ExploreProvider>().load());
  }

  @override
  void refresh() {
    unawaited(context.read<ExploreProvider>().load());
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ExploreProvider>(
      builder: (context, explore, _) {
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
