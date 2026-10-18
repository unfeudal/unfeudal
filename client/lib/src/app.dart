// SPDX-License-Identifier: Apache-2.0
import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'app_scope.dart';
import 'app_state.dart';
import 'design/empty_state.dart';
import 'design/motion.dart';
import 'design/tokens.dart';
import 'ui/lock/login_screen.dart';
import 'ui/onboarding/join_screen.dart';
import 'ui/onboarding/setup_screen.dart';
import 'ui/lock/unlock_screen.dart';

/// Theme, language and motion from the cached settings (usable before unlock), then the screen of the stage.
class UnfeudalApp extends StatefulWidget {
  const UnfeudalApp({super.key, required this.state, this.locale, this.home});

  final AppState state;

  /// Wins over the settings (tests).
  final Locale? locale;

  /// Shown instead of the stage screens (widget tests).
  final Widget? home;

  @override
  State<UnfeudalApp> createState() => _UnfeudalAppState();
}

class _UnfeudalAppState extends State<UnfeudalApp> {
  final _navigator = GlobalKey<NavigatorState>();
  late AppStage _stage = widget.state.stage;

  @override
  void initState() {
    super.initState();
    widget.state
      ..confirmPlainHttp = _confirmPlainHttp
      ..addListener(_onState);
  }

  @override
  void dispose() {
    widget.state.removeListener(_onState);
    super.dispose();
  }

  /// Leaving home closes every dialog and pushed screen (lock, sign-out, revoked device).
  void _onState() {
    final stage = widget.state.stage;
    if (_stage == AppStage.home && stage != AppStage.home) {
      _navigator.currentState?.popUntil((route) => route.isFirst);
    }
    _stage = stage;
  }

  Future<bool> _confirmPlainHttp(Uri server) async {
    final context = _navigator.currentContext;
    if (context == null) return false;
    final l = AppLocalizations.of(context);
    return await showUfDialog<bool>(context, alert: true, (dialog) {
          void answer(bool value) => Navigator.pop(dialog, value);
          return Actions(
            actions: {
              DismissIntent: CallbackAction<DismissIntent>(
                onInvoke: (_) => answer(false),
              ),
            },
            child: Focus(
              autofocus: true,
              child: AlertDialog(
                title: Text(l.plainHttpTitle),
                content: Text(l.plainHttpBody('$server')),
                actions: [
                  TextButton(
                    onPressed: () => answer(false),
                    child: Text(
                      MaterialLocalizations.of(dialog).cancelButtonLabel,
                    ),
                  ),
                  FilledButton(
                    key: const Key('plain-http-continue'),
                    onPressed: () => answer(true),
                    child: Text(l.plainHttpContinue),
                  ),
                ],
              ),
            ),
          );
        }) ??
        false;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) {
      final settings = widget.state.settings;
      return MaterialApp(
        navigatorKey: _navigator,
        onGenerateTitle: (context) => AppLocalizations.of(context).appName,
        theme: ufTheme(Brightness.light),
        darkTheme: ufTheme(Brightness.dark),
        themeMode: settings.themeMode,
        locale:
            widget.locale ??
            switch (settings.locale) {
              final String code => Locale(code),
              null => null,
            },
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MotionScope(
          performanceMode: settings.performanceMode,
          child: AppScope(
            state: widget.state,
            child: Listener(
              onPointerDown: (_) => widget.state.activity(),
              child: Focus(
                onKeyEvent: (_, _) {
                  widget.state.activity();
                  return KeyEventResult.ignored;
                },
                child: child!,
              ),
            ),
          ),
        ),
        home: widget.home ?? const _StageScreen(),
      );
    },
  );
}

class _StageScreen extends StatelessWidget {
  const _StageScreen();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final l = AppLocalizations.of(context);
    return PageTransitionSwitcher(
      duration: UfMotion.of(context).slow,
      transitionBuilder: (child, animation, secondary) => FadeThroughTransition(
        animation: animation,
        secondaryAnimation: secondary,
        child: child,
      ),
      child: KeyedSubtree(
        key: ValueKey(state.stage),
        child: switch (state.stage) {
          AppStage.booting => const Scaffold(),
          AppStage.login => const LoginScreen(),
          AppStage.unlock => const UnlockScreen(),
          AppStage.mirrorTooNew => Scaffold(
            body: EmptyState(
              title: l.mirrorTooNewTitle,
              body: l.mirrorTooNewBody,
            ),
          ),
          AppStage.setup => const SetupScreen(),
          AppStage.join => const JoinScreen(),
          // Task 29 brings the home shell
          AppStage.home => const SizedBox.shrink(),
        },
      ),
    );
  }
}
