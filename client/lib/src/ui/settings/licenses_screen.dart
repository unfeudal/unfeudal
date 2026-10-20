// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';
import '../../version.dart';
import '../manage_frame.dart';

const _fontLicenses = {
  'Alegreya': 'assets/fonts/Alegreya-OFL.txt',
  'Hanken Grotesk': 'assets/fonts/HankenGrotesk-OFL.txt',
  'JetBrains Mono': 'assets/fonts/JetBrainsMono-OFL.txt',
  'Phosphor': 'assets/fonts/Phosphor-LICENSE.txt',
};

/// The bundled fonts ship with their licence: it shows in the full licence list.
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final MapEntry(key: family, value: path) in _fontLicenses.entries) {
      yield LicenseEntryWithLineBreaks([
        family,
      ], await rootBundle.loadString(path));
    }
  });
}

/// The client and server licences, the server's source link, and every licence of what the app bundles.
class LicensesScreen extends StatelessWidget {
  const LicensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final source = AppScope.of(context).serverSource;
    return ManageFrame(
      title: l.settingsLicenses,
      maxWidth: 520,
      child: ListView(
        shrinkWrap: true,
        children: [
          Text(l.licenseClient),
          const SizedBox(height: 12),
          Text(l.licenseServer),
          if (source != null)
            Row(
              children: [
                Expanded(child: SelectableText(source, style: monoStyle)),
                IconButton(
                  key: const Key('licenses-copy-source'),
                  tooltip: MaterialLocalizations.of(context).copyButtonLabel,
                  icon: const Icon(UfIcons.copy),
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: source)),
                ),
              ],
            ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              key: const Key('licenses-all'),
              onPressed: () => showLicensePage(
                context: context,
                applicationName: 'Unfeudal',
                applicationVersion: clientVersion,
              ),
              child: Text(l.licensesAll),
            ),
          ),
        ],
      ),
    );
  }
}
