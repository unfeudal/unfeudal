// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';
import 'describe_error.dart';

/// A form that runs one action at a time: [busy] while it runs, [problem] when it fails.
mixin BusyAction<T extends StatefulWidget> on State<T> {
  bool busy = false;
  String? problem;

  /// Clears [problem], then sets it to the failure's sentence if [action] throws.
  /// Does nothing while an action already runs.
  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      problem = null;
    });
    try {
      await action();
    } on Exception catch (e) {
      if (mounted) {
        setState(
          () => problem = describeError(AppLocalizations.of(context), e),
        );
        failed(e);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// Called after [problem] is set by a failed action, while still mounted.
  void failed(Object error) {}
}
