import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../i18n/strings.g.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_server_client.dart';
import '../models/seerr/seerr_issue.dart';
import '../services/seerr/seerr_client.dart';
import '../services/seerr/seerr_exceptions.dart';
import '../utils/app_logger.dart';
import '../utils/snackbar_helper.dart';
import 'app_icon.dart';
import 'overlay_sheet.dart';

/// Open the "Report an Issue" sheet for [item], sent through Seerr so it
/// lands as the same email notification Seerr already sends for other
/// issues, with the title (and episode, if applicable) attached.
Future<void> showSeerrIssueSheet(
  BuildContext context, {
  required MediaItem item,
  required MediaServerClient mediaClient,
  required SeerrClient seerrClient,
}) {
  return OverlaySheetController.showAdaptive<void>(
    context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => SeerrIssueSheet(item: item, mediaClient: mediaClient, seerrClient: seerrClient),
  );
}

class SeerrIssueSheet extends StatefulWidget {
  final MediaItem item;
  final MediaServerClient mediaClient;
  final SeerrClient seerrClient;

  const SeerrIssueSheet({super.key, required this.item, required this.mediaClient, required this.seerrClient});

  @override
  State<SeerrIssueSheet> createState() => _SeerrIssueSheetState();
}

enum _LoadState { loading, ready, unavailable, failed }

class _SeerrIssueSheetState extends State<SeerrIssueSheet> {
  _LoadState _loadState = _LoadState.loading;
  int? _seerrMediaId;
  SeerrIssueType? _selectedType;
  late final TextEditingController _messageController;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController();
    _resolveMedia();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _resolveMedia() async {
    try {
      final item = widget.item;
      // Seerr tracks a show, not individual episodes, as its own media row —
      // an episode report still resolves against the parent show's tmdbId.
      final lookupId = item.kind == MediaKind.episode ? item.grandparentId : item.id;
      if (lookupId == null) {
        if (mounted) setState(() => _loadState = _LoadState.unavailable);
        return;
      }

      final externalIds = await widget.mediaClient.fetchExternalIds(lookupId);
      final tmdbId = externalIds.tmdb;
      if (tmdbId == null) {
        if (mounted) setState(() => _loadState = _LoadState.unavailable);
        return;
      }

      final isMovie = item.kind == MediaKind.movie;
      final details = isMovie ? await widget.seerrClient.getMovie(tmdbId) : await widget.seerrClient.getTv(tmdbId);
      final mediaId = details.mediaInfo?.id;
      if (mediaId == null) {
        if (mounted) setState(() => _loadState = _LoadState.unavailable);
        return;
      }

      if (mounted) {
        setState(() {
          _seerrMediaId = mediaId;
          _loadState = _LoadState.ready;
        });
      }
    } catch (e, stackTrace) {
      appLogger.w('Seerr issue sheet: media resolution failed', error: e, stackTrace: stackTrace);
      if (mounted) setState(() => _loadState = _LoadState.failed);
    }
  }

  void _selectType(SeerrIssueType type) {
    setState(() {
      _selectedType = type;
      _messageController.text = type == SeerrIssueType.other ? '' : _defaultMessage(type);
    });
  }

  String _defaultMessage(SeerrIssueType type) => switch (type) {
    SeerrIssueType.video => t.seerrIssue.presetVideo,
    SeerrIssueType.audio => t.seerrIssue.presetAudio,
    SeerrIssueType.subtitles => t.seerrIssue.presetSubtitles,
    SeerrIssueType.other => '',
  };

  bool get _canSubmit =>
      !_submitting && _selectedType != null && _messageController.text.trim().isNotEmpty && _seerrMediaId != null;

  Future<void> _submit() async {
    final type = _selectedType;
    final mediaId = _seerrMediaId;
    final message = _messageController.text.trim();
    if (type == null || mediaId == null || message.isEmpty) return;

    setState(() => _submitting = true);
    try {
      final item = widget.item;
      await widget.seerrClient.createIssue(
        mediaId: mediaId,
        issueType: type,
        problemSeason: item.kind == MediaKind.episode ? (item.parentIndex ?? 0) : 0,
        problemEpisode: item.kind == MediaKind.episode ? (item.index ?? 0) : 0,
        message: message,
      );
      if (mounted) {
        Navigator.pop(context);
        showAppSnackBar(context, t.seerrIssue.submitted);
      }
    } on SeerrApiException catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        showErrorSnackBar(context, e.message);
      }
    } catch (e, stackTrace) {
      appLogger.w('Seerr issue sheet: submit failed', error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() => _submitting = false);
        showErrorSnackBar(context, t.seerrIssue.submitFailed);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          children: [
            Text(t.seerrIssue.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              widget.item.title ?? '',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              maxLines: 1,
              overflow: .ellipsis,
            ),
            const SizedBox(height: 16),
            _buildBody(context),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_loadState) {
      case _LoadState.loading:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        );
      case _LoadState.unavailable:
        return Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(t.seerrIssue.unavailable));
      case _LoadState.failed:
        return Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(t.seerrIssue.loadFailed));
      case _LoadState.ready:
        return _buildForm(context);
    }
  }

  Widget _buildForm(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final type in SeerrIssueType.values)
              ChoiceChip(
                label: Text(_typeLabel(type)),
                selected: _selectedType == type,
                onSelected: (_) => _selectType(type),
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _messageController,
          minLines: 2,
          maxLines: 4,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(hintText: t.seerrIssue.messageHint, border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _canSubmit ? _submit : null,
            icon: _submitting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const AppIcon(Symbols.send_rounded),
            label: Text(t.seerrIssue.submit),
          ),
        ),
      ],
    );
  }

  String _typeLabel(SeerrIssueType type) => switch (type) {
    SeerrIssueType.video => t.seerrIssue.typeVideo,
    SeerrIssueType.audio => t.seerrIssue.typeAudio,
    SeerrIssueType.subtitles => t.seerrIssue.typeSubtitles,
    SeerrIssueType.other => t.seerrIssue.typeOther,
  };
}
