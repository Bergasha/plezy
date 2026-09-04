import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n/strings.g.dart';
import '../services/update_service.dart';
import '../widgets/dialog_action_button.dart';
import 'dialogs.dart';
import 'notification_permission.dart';

Future<void> showUpdateAvailableDialog(
  BuildContext context,
  Map<String, dynamic> updateInfo, {
  required String title,
  required String dismissLabel,
  bool showSkipVersion = false,
}) {
  return showScopedDialog<void>(
    context: context,
    builder: (dialogContext) => _UpdateDialog(
      updateInfo: updateInfo,
      title: title,
      dismissLabel: dismissLabel,
      showSkipVersion: showSkipVersion,
    ),
  );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({
    required this.updateInfo,
    required this.title,
    required this.dismissLabel,
    required this.showSkipVersion,
  });

  final Map<String, dynamic> updateInfo;
  final String title;
  final String dismissLabel;
  final bool showSkipVersion;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _downloading = false;
  double? _progress;
  bool _failed = false;

  String get _latestVersion => widget.updateInfo['latestVersion'] as String;
  String get _releaseUrl => widget.updateInfo['releaseUrl'] as String;

  Future<void> _handleUpdatePressed() async {
    // Android downloads and installs in place (see UpdateService); every
    // other platform keeps the plain download-link handoff, since there's
    // nowhere else to point them but their browser.
    if (!Platform.isAndroid) {
      final url = Uri.parse(_releaseUrl);
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
      if (mounted) Navigator.pop(context);
      return;
    }

    setState(() {
      _downloading = true;
      _progress = null;
      _failed = false;
    });

    // Best-effort, while the app is still alive and interactive: the
    // relaunch-after-install notification (SystemShelfUpdateReceiver) can't
    // ask for this itself, since by the time it needs to post, the update
    // has already killed this process. Already-granted or already-denied
    // resolves instantly (see NotificationPermission.ensure).
    await NotificationPermission.ensure();

    try {
      await UpdateService.downloadAndInstallAndroidUpdate(
        url: _releaseUrl,
        onProgress: (fraction) {
          if (mounted) setState(() => _progress = fraction);
        },
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_downloading,
      child: AlertDialog(
        title: Text(widget.title),
        content: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          children: [
            Text(t.update.versionAvailable(version: _latestVersion), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              t.update.currentVersion(version: widget.updateInfo['currentVersion']),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_downloading) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text(
                _progress != null
                    ? t.update.downloadingPercent(percent: (_progress! * 100).round())
                    : t.update.downloading,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_failed) ...[
              const SizedBox(height: 8),
              Text(t.update.downloadFailed, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
        actions: _downloading
            ? const []
            : [
                DialogActionButton(onPressed: () => Navigator.pop(context), label: widget.dismissLabel),
                if (widget.showSkipVersion)
                  DialogActionButton(
                    onPressed: () async {
                      await UpdateService.skipVersion(_latestVersion);
                      if (context.mounted) Navigator.pop(context);
                    },
                    label: t.update.skipVersion,
                  ),
                DialogActionButton(
                  autofocus: true,
                  onPressed: _handleUpdatePressed,
                  label: t.update.viewRelease,
                  isPrimary: true,
                ),
              ],
      ),
    );
  }
}
