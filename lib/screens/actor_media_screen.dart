import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../media/ids.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../media/library_query.dart';
import '../media/media_backend.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_server_client.dart';
import '../mixins/paginated_item_loader.dart';
import '../mixins/standard_paginated_view.dart';
import '../utils/app_logger.dart';
import '../utils/media_server_http_client.dart';
import '../utils/provider_extensions.dart';
import '../widgets/desktop_app_bar.dart';
import '../widgets/optimized_media_image.dart';
import '../utils/media_image_helper.dart';
import '../i18n/strings.g.dart';
import '../utils/formatters.dart';
import '../widgets/collapsible_text.dart';
import 'base_media_list_detail_screen.dart';
import 'focusable_detail_screen_mixin.dart';
import '../mixins/grid_focus_node_mixin.dart';
import '../focus/focusable_action_bar.dart';
import '../database/app_database.dart';
import '../models/tmdb/tmdb_person.dart';
import '../services/tmdb_cast_matcher.dart';

/// Screen to browse all media featuring a specific actor.
class ActorMediaScreen extends StatefulWidget {
  final String actorName;
  final String personId;
  final String? actorThumb;
  final String? characterName;
  final String serverId;
  final String? serverName;
  final MediaBackend backend;
  final MediaItem? sourceMediaItem;

  const ActorMediaScreen({
    super.key,
    required this.actorName,
    required this.personId,
    this.actorThumb,
    this.characterName,
    required this.serverId,
    this.serverName,
    required this.backend,
    this.sourceMediaItem,
  });

  @override
  State<ActorMediaScreen> createState() => _ActorMediaScreenState();
}

class _ActorMediaScreenState extends BaseMediaListDetailScreen<ActorMediaScreen>
    with
        GridFocusNodeMixin<ActorMediaScreen>,
        FocusableDetailScreenMixin<ActorMediaScreen>,
        PaginatedItemLoader<MediaItem, ActorMediaScreen>,
        PaginatedItemUpdatable<ActorMediaScreen>,
        StandardPaginatedView<MediaItem, ActorMediaScreen> {
  static const int _pageSize = 200;

  late final _tmdbMatcher = TmdbCastMatcher(database: context.read<AppDatabase>());
  TmdbPerson? _tmdbPerson;
  bool _tmdbLoading = false;

  @override
  void initState() {
    super.initState();
    final source = widget.sourceMediaItem;
    if (source != null) {
      _tmdbLoading = true;
      _tmdbMatcher
          .resolveCastMember(metadata: source, actorName: widget.actorName, client: _mediaClient)
          .then((person) {
            if (!mounted) return;
            setState(() {
              _tmdbPerson = person;
              _tmdbLoading = false;
            });
          })
          .catchError((_) {
            if (!mounted) return;
            setState(() => _tmdbLoading = false);
          });
    }
  }

  @override
  MediaItem get mediaItem => MediaItem(
    id: '',
    backend: widget.backend,
    kind: MediaKind.unknown,
    serverId: widget.serverId,
    serverName: widget.serverName,
  );

  @override
  String get title => widget.actorName;

  @override
  String get emptyMessage => t.discover.noContentAvailable;

  @override
  bool get hasItems => totalSize > 0;

  @override
  void dispose() {
    _tmdbMatcher.dispose();
    disposePagination();
    disposeFocusResources();
    super.dispose();
  }

  MediaServerClient get _mediaClient => context.getMediaClientForServer(ServerId(widget.serverId));

  @override
  Future<LibraryPage<MediaItem>> fetchPage(int start, int size, AbortController? abort) {
    return _mediaClient.fetchPersonMediaPage(widget.personId, start: start, size: size, abort: abort);
  }

  @override
  Future<void> loadItems() {
    return loadStandardPaginatedItems(
      pageSize: _pageSize,
      errorMessageFor: (error, stackTrace) {
        appLogger.e('Failed to load actor media', error: error, stackTrace: stackTrace);
        return t.messages.errorLoading(error: error.toString());
      },
      onLoaded: (loadedCount, totalCount) {
        appLogger.d('Loaded $loadedCount of $totalCount items for actor: ${widget.actorName}');
        autoFocusFirstItemAfterLoad();
      },
    );
  }

  @override
  List<FocusableAction> getAppBarActions() {
    return [];
  }

  int? _ageInYears(String birthday, String? asOf) {
    try {
      final birth = DateTime.parse(birthday);
      final end = asOf != null ? DateTime.parse(asOf) : DateTime.now();
      var age = end.year - birth.year;
      if (end.month < birth.month || (end.month == birth.month && end.day < birth.day)) age--;
      return age;
    } catch (_) {
      return null;
    }
  }

  String? _departmentLabel(String? department) {
    return switch (department) {
      'Acting' => 'Actor',
      'Directing' => 'Director',
      'Production' => 'Producer',
      'Writing' => 'Writer',
      _ => department,
    };
  }

  Widget _buildActorHeader() {
    final theme = Theme.of(context);
    final person = _tmdbPerson;
    final photoUrl = person?.profilePath != null ? 'https://image.tmdb.org/t/p/w500${person!.profilePath}' : null;
    final occupation = _departmentLabel(person?.knownForDepartment);
    final birthday = person?.birthday;
    final deathday = person?.deathday;

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: .start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: OptimizedMediaImage(
                client: photoUrl == null ? _mediaClient : null,
                imagePath: photoUrl ?? widget.actorThumb,
                width: 160,
                height: 240,
                fit: BoxFit.cover,
                imageType: ImageType.avatar,
                fallbackIcon: Symbols.person_rounded,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  Text(
                    widget.actorName,
                    style: theme.textTheme.headlineMedium?.copyWith(fontWeight: .bold),
                    maxLines: 2,
                    overflow: .ellipsis,
                  ),
                  if (occupation != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      occupation,
                      style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                  if (birthday != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      deathday != null
                          ? 'Born ${formatFullDate(birthday)}\nDied ${formatFullDate(deathday)} (${_ageInYears(birthday, deathday)})'
                          : 'Born ${formatFullDate(birthday)} (${_ageInYears(birthday, null)} years)',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                  if (person?.biography != null) ...[
                    const SizedBox(height: 12),
                    CollapsibleText(text: person!.biography!, maxLines: 4, style: theme.textTheme.bodyMedium),
                  ],
                  if (widget.characterName != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      widget.characterName!,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: .ellipsis,
                    ),
                  ],
                  if (totalSize > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      '$totalSize ${totalSize == 1 ? 'title' : 'titles'}',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return buildDetailScaffold(
      slivers: [
        CustomAppBar(title: Text(widget.actorName), pinned: true, actions: buildFocusableAppBarActions()),
        _buildActorHeader(),
        ...buildStateSlivers(),
        if (hasItems)
          buildSparseFocusableGrid(
            totalItems: totalSize,
            itemAt: (index) => loadedItems[index],
            onRefresh: updateItem,
            onSkeletonVisible: (index) => ensureIndexLoaded(index, pageSize: _pageSize),
          ),
      ],
    );
  }
}
