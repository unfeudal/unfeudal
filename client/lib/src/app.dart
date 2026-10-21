// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'app_scope.dart';
import 'app_state.dart';
import 'debug_trace.dart';
import 'design/dialog.dart';
import 'design/motion.dart';
import 'design/tokens.dart';
import 'settings/settings.dart';
import 'ui/lock/lock_frame.dart';
import 'ui/lock/login_screen.dart';
import 'ui/lock/unlock_screen.dart';
import 'ui/onboarding/join_screen.dart';
import 'ui/onboarding/setup_screen.dart';
import 'ui/shell/home_shell.dart';
import 'ui/shell/shell_chrome.dart';
import 'ui/title_bar.dart';
import 'window/window_chrome.dart';

/// Theme, language and motion from the cached settings (usable before unlock), then the screen of the stage.
class UnfeudalApp extends StatefulWidget {
  const UnfeudalApp({
    super.key,
    required this.state,
    this.locale,
    this.home,
    this.chrome,
  });

  final AppState state;

  /// Wins over the settings (tests).
  final Locale? locale;

  /// Shown instead of the stage screens (widget tests).
  final Widget? home;

  /// The OS window when the system title bar is replaced by ours; null in tests.
  final WindowChrome? chrome;

  @override
  State<UnfeudalApp> createState() => _UnfeudalAppState();
}

class _UnfeudalAppState extends State<UnfeudalApp> {
  final _navigator = GlobalKey<NavigatorState>();
  final _shellChrome = ShellChrome();
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
    _shellChrome.dispose();
    super.dispose();
  }

  // Leaving home closes every dialog and pushed screen (lock, sign-out, revoked device).
  void _onState() {
    final stage = widget.state.stage;
    if (stage != _stage) {
      trace(TraceArea.ui, 'screen ${_stage.name} -> ${stage.name}');
    }
    if (_stage == AppStage.home && stage != AppStage.home) {
      _navigator.currentState?.popUntil((route) => route.isFirst);
    }
    _stage = stage;
  }

  Future<bool> _confirmPlainHttp(Uri server) async {
    final context = _navigator.currentContext;
    if (context == null) return false;
    final l = AppLocalizations.of(context);
    return confirmDanger(
      context,
      question: l.plainHttpTitle,
      message: l.plainHttpBody('$server'),
      action: l.plainHttpContinue,
    );
  }

  // The custom title bar follows the home shell's sidebar, else the access screens.
  Widget _framed(BuildContext context, Widget screen) {
    final chrome = widget.chrome;
    final scoped = ShellChromeScope(chrome: _shellChrome, child: screen);
    if (chrome == null) return scoped;
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UfTitleBar(
          chrome: chrome,
          shell: _shellChrome,
          title: l.appName,
          background: LockFrame.background(context),
        ),
        Expanded(child: scoped),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) {
      final settings = widget.state.settings;
      return MaterialApp(
        navigatorKey: _navigator,
        onGenerateTitle: (context) => AppLocalizations.of(context).appName,
        theme: _theme(Brightness.light, settings),
        darkTheme: _theme(Brightness.dark, settings),
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
              onPointerDown: (_) => widget.state.recordActivity(),
              child: Focus(
                onKeyEvent: (_, _) {
                  widget.state.recordActivity();
                  return KeyEventResult.ignored;
                },
                child: _framed(context, child!),
              ),
            ),
          ),
        ),
        home: widget.home ?? const _StageScreen(),
      );
    },
  );
}

// Performance mode also drops Material's ink ripples.
ThemeData _theme(Brightness brightness, Settings settings) {
  final theme = ufTheme(brightness);
  return settings.performanceMode
      ? theme.copyWith(splashFactory: NoSplash.splashFactory)
      : theme;
}

class _StageScreen extends StatelessWidget {
  const _StageScreen();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final l = AppLocalizations.of(context);
    return AnimatedSwitcher(
      duration: UfMotion.of(context).slow,
      child: KeyedSubtree(
        key: ValueKey(state.stage),
        child: switch (state.stage) {
          AppStage.booting => const Scaffold(),
          AppStage.login => const LoginScreen(),
          AppStage.unlock => const UnlockScreen(),
          AppStage.mirrorTooNew => Scaffold(
            body: LockFrame(
              title: l.mirrorTooNewTitle,
              subtitle: l.mirrorTooNewBody,
              children: const [],
            ),
          ),
          AppStage.setup => const SetupScreen(),
          AppStage.join => const JoinScreen(),
          AppStage.home => const HomeShell(),
        },
      ),
    );
  }
}
