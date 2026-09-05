import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../i18n/strings.g.dart';
import '../widgets/app_icon.dart';
import '../widgets/dialog_action_button.dart';
import 'dialogs.dart';

/// Shows a short, plain-language "what's new" popup once per version — see
/// [WhatsNewService]. Dismiss is autofocused so a single remote press
/// closes it.
Future<void> showWhatsNewDialog(BuildContext context, List<String> points) {
  return showScopedDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(t.whatsNew.title),
      content: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        children: [
          Center(child: Image.asset('assets/shayno_thumbsup.png', height: 96, fit: BoxFit.contain)),
          const SizedBox(height: 12),
          for (final point in points)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: .start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2, right: 8),
                    child: AppIcon(
                      Symbols.circle,
                      size: 6,
                      fill: 1,
                      color: Theme.of(dialogContext).colorScheme.primary,
                    ),
                  ),
                  Expanded(child: Text(point)),
                ],
              ),
            ),
        ],
      ),
      actions: [
        DialogActionButton(
          autofocus: true,
          isPrimary: true,
          onPressed: () => Navigator.pop(dialogContext),
          label: t.common.close,
        ),
      ],
    ),
  );
}
