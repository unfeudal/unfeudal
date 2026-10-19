// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';
import 'describe_error.dart';

/// A form that runs one action at a time: [busy] while it runs, [problem] when it fails.
mixin BusyAction<T extends StatefulWidget> on State<T> {
  bool busy = false;
  String? problem;

  /// Clears [problem], then sets it to the failure's sentence if [action] throws.
  Future<void> run(Future<void> Function() action) async {
    final l = AppLocalizations.of(context);
    setState(() {
      busy = true;
      problem = null;
    });
    try {
      await action();
    } on Exception catch (e) {
      if (mounted) setState(() => problem = describeError(l, e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}
