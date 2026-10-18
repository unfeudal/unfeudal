// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/widgets.dart';

import 'app_state.dart';

/// Hands [AppState] down the widget tree.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);

  /// Rebuilds the caller when the state changes.
  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Reads without listening (callbacks, initState).
  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
