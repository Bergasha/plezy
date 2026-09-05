import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../focus/key_event_utils.dart';
import '../i18n/strings.g.dart';
import '../models/tautulli/tautulli_session.dart';
import '../services/tautulli/tautulli_client.dart';
import '../theme/mono_tokens.dart';
import 'app_icon.dart';

enum _FetchState { loading, loaded, error }

class _PanelData {
  final _FetchState fetchState;
  final List<TautulliSession> sessions;

  const _PanelData({required this.fetchState, required this.sessions});

  static const loading = _PanelData(fetchState: _FetchState.loading, sessions: []);
}

/// Admin-only "who's watching what" panel, sourced from the user's own
/// Tautulli instance rather than Plex directly (see [TautulliClient]).
/// Naturally scoped to whoever configures Settings > Advanced > Tautulli
/// Server on their own device — nothing else gates visibility, and no other
/// user's copy of the app ever sees this button since nothing shares that
/// configuration.
class TautulliActivityButton extends StatefulWidget {
  final String baseUrl;
  final String apiKey;

  const TautulliActivityButton({super.key, required this.baseUrl, required this.apiKey});

  @override
  State<TautulliActivityButton> createState() => TautulliActivityButtonState();
}

class TautulliActivityButtonState extends State<TautulliActivityButton> {
  final _buttonKey = GlobalKey();
  OverlayEntry? _overlayEntry;
  final _panelNotifier = ValueNotifier<_PanelData>(_PanelData.loading);
  Timer? _pollTimer;
  late TautulliClient _client;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _client = TautulliClient(baseUrl: widget.baseUrl, apiKey: widget.apiKey);
  }

  @override
  void didUpdateWidget(TautulliActivityButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.baseUrl != widget.baseUrl || oldWidget.apiKey != widget.apiKey) {
      _client.dispose();
      _client = TautulliClient(baseUrl: widget.baseUrl, apiKey: widget.apiKey);
      if (_overlayEntry != null) _startRefresh(silent: false);
    }
  }

  @override
  void deactivate() {
    _removeOverlay();
    super.deactivate();
  }

  @override
  void dispose() {
    _removeOverlay();
    _panelNotifier.dispose();
    _client.dispose();
    super.dispose();
  }

  void _removeOverlay() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _loadGeneration++;
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void togglePanel() {
    if (_overlayEntry != null) {
      _removeOverlay();
      return;
    }

    final renderBox = _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final buttonOffset = renderBox.localToGlobal(Offset.zero);
    final buttonSize = renderBox.size;
    final screenSize = MediaQuery.sizeOf(context);

    final right = screenSize.width - (buttonOffset.dx + buttonSize.width);
    final top = buttonOffset.dy + buttonSize.height + 4;

    _panelNotifier.value = _PanelData.loading;
    _overlayEntry = OverlayEntry(
      builder: (_) => _buildOverlay(right: right, top: top),
    );
    Overlay.of(context).insert(_overlayEntry!);
    _startRefresh(silent: false);
  }

  void _startRefresh({required bool silent}) {
    if (!mounted || _overlayEntry == null) return;
    _pollTimer?.cancel();
    _pollTimer = null;
    final generation = ++_loadGeneration;
    if (!silent) _panelNotifier.value = _PanelData.loading;
    unawaited(_runRefresh(generation));
  }

  Future<void> _runRefresh(int generation) async {
    try {
      final sessions = await _client.getActivity();
      if (!_isCurrentGeneration(generation)) return;
      _panelNotifier.value = _PanelData(fetchState: _FetchState.loaded, sessions: sessions);
    } catch (_) {
      if (!_isCurrentGeneration(generation)) return;
      _panelNotifier.value = const _PanelData(fetchState: _FetchState.error, sessions: []);
    } finally {
      if (_isCurrentGeneration(generation)) _schedulePoll(generation);
    }
  }

  bool _isCurrentGeneration(int generation) => mounted && _overlayEntry != null && _loadGeneration == generation;

  void _schedulePoll(int generation) {
    _pollTimer?.cancel();
    if (!_isCurrentGeneration(generation)) return;
    // Slower than the 3s Plex-tasks poll (ServerActivitiesButton): this is a
    // personal admin glance, not a control surface where cancel-in-progress
    // actions need snappy feedback.
    _pollTimer = Timer(const Duration(seconds: 5), () {
      if (!_isCurrentGeneration(generation)) return;
      _pollTimer = null;
      _startRefresh(silent: true);
    });
  }

  Widget _buildOverlay({required double right, required double top}) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(onTap: _removeOverlay, behavior: HitTestBehavior.opaque),
        ),
        Positioned(
          right: right,
          top: top,
          child: Focus(
            autofocus: true,
            onKeyEvent: (_, event) => handleBackKeyAction(event, _removeOverlay),
            child: ValueListenableBuilder<_PanelData>(
              valueListenable: _panelNotifier,
              builder: (context, data, _) => _buildPanel(context, data),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPanel(BuildContext context, _PanelData data) {
    final theme = Theme.of(context);
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.surface,
      child: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: [
            _buildPanelHeader(context, data),
            Divider(height: 1, color: theme.dividerColor),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: SingleChildScrollView(child: _buildPanelBody(context, data)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanelHeader(BuildContext context, _PanelData data) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          AppIcon(Symbols.monitor_heart_rounded, size: 18, color: theme.colorScheme.onSurface),
          const SizedBox(width: 8),
          Expanded(
            child: Text(t.tautulli.activeStreams, style: theme.textTheme.titleSmall?.copyWith(fontWeight: .bold)),
          ),
          if (data.fetchState == _FetchState.loaded && data.sessions.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: tokens(context).text, borderRadius: BorderRadius.circular(10)),
              child: Text(
                '${data.sessions.length}',
                style: theme.textTheme.labelSmall?.copyWith(color: tokens(context).bg, fontWeight: .bold),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPanelBody(BuildContext context, _PanelData data) {
    final theme = Theme.of(context);

    if (data.fetchState == _FetchState.loading) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            t.common.loading,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.55)),
          ),
        ),
      );
    }

    if (data.fetchState == _FetchState.error) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: .min,
          children: [
            AppIcon(Symbols.error_outline_rounded, color: theme.colorScheme.error),
            const SizedBox(height: 8),
            Text(t.tautulli.failedToLoad, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
          ],
        ),
      );
    }

    if (data.sessions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            t.tautulli.noActiveStreams,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.55)),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: .stretch,
      children: [for (final session in data.sessions) _buildSessionTile(context, session), const SizedBox(height: 8)],
    );
  }

  Widget _buildSessionTile(BuildContext context, TautulliSession session) {
    final theme = Theme.of(context);
    final isTranscode = session.transcodeDecision.toLowerCase() == 'transcode';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: .start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  session.friendlyName,
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: .w600),
                  maxLines: 1,
                  overflow: .ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: (isTranscode ? Colors.orange : Colors.green).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isTranscode ? t.tautulli.transcode : t.tautulli.directPlay,
                  style: theme.textTheme.labelSmall?.copyWith(color: isTranscode ? Colors.orange : Colors.green),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            session.displayTitle,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
            maxLines: 1,
            overflow: .ellipsis,
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: (session.progressPercent / 100.0).clamp(0.0, 1.0),
            borderRadius: BorderRadius.circular(4),
            minHeight: 4,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: _buttonKey,
      icon: const AppIcon(Symbols.monitor_heart_rounded, color: Colors.white),
      onPressed: togglePanel,
      tooltip: t.tautulli.activeStreams,
    );
  }
}
