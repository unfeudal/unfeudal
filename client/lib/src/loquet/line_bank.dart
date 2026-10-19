// SPDX-License-Identifier: Apache-2.0
import 'dart:math';

import '../../l10n/app_localizations.dart';
import 'loquet_pose.dart';

enum LineKey {
  welcome,
  notLooking,
  peeking,
  checking,
  wrongPassword,
  waitingHello,
  connected,
  keyChanged,
  offline,
  lock,
  idleClick,
  emptyVault,
  emptySearch,
  earlyYawn,
  night,
  fridayProd,
  root,
  localhost,
  host42,
  dizzy,
  firstHost,
  secondDevice,
  sharedVault,
  connections100,
  connections1000,
  firstKeyRotation,
  oneYear,
}

typedef _Line = String Function(AppLocalizations l, Map<String, String> p);

/// Loquet's lines from the ARB files: a random variant, never the one this bank just gave for that key.
class LineBank {
  LineBank({Random? random}) : _random = random ?? Random();

  final Random _random;
  final _last = <LineKey, int>{};

  static final Map<LineKey, List<_Line>> _lines = {
    LineKey.welcome: [
      (l, p) => l.loquetWelcome1(p['name']!),
      (l, p) => l.loquetWelcome2(p['name']!),
    ],
    LineKey.notLooking: [
      (l, _) => l.loquetNotLooking1,
      (l, _) => l.loquetNotLooking2,
    ],
    LineKey.peeking: [(l, _) => l.loquetPeeking1],
    LineKey.checking: [(l, _) => l.loquetChecking1],
    LineKey.wrongPassword: [(l, _) => l.loquetWrongPassword1],
    LineKey.waitingHello: [(l, p) => l.loquetWaitingHello1(p['method'] ?? '')],
    LineKey.connected: [
      (l, _) => l.loquetConnected1,
      (l, _) => l.loquetConnected2,
    ],
    LineKey.keyChanged: [(l, _) => l.loquetKeyChanged1],
    LineKey.offline: [(l, _) => l.loquetOffline1],
    LineKey.lock: [(l, _) => l.loquetLock1],
    LineKey.idleClick: [
      (l, _) => l.loquetIdleClick1,
      (l, _) => l.loquetIdleClick2,
      (l, _) => l.loquetIdleClick3,
    ],
    LineKey.emptyVault: [(l, _) => l.loquetEmptyVault1],
    LineKey.emptySearch: [(l, _) => l.loquetEmptySearch1],
    LineKey.earlyYawn: [(l, _) => l.loquetEarlyYawn1],
    LineKey.night: [(l, _) => l.loquetNight1],
    LineKey.fridayProd: [(l, _) => l.loquetFridayProd1],
    LineKey.root: [(l, _) => l.loquetRoot1],
    LineKey.localhost: [(l, _) => l.loquetLocalhost1],
    LineKey.host42: [(l, _) => l.loquetHost421],
    LineKey.dizzy: [(l, _) => l.loquetDizzy1],
    LineKey.firstHost: [(l, _) => l.loquetFirstHost1],
    LineKey.secondDevice: [(l, _) => l.loquetSecondDevice1],
    LineKey.sharedVault: [(l, _) => l.loquetSharedVault1],
    LineKey.connections100: [(l, _) => l.loquetConnections1001],
    LineKey.connections1000: [(l, _) => l.loquetConnections10001],
    LineKey.firstKeyRotation: [(l, _) => l.loquetFirstKeyRotation1],
    LineKey.oneYear: [(l, _) => l.loquetOneYear1],
  };

  String text(
    AppLocalizations l,
    LineKey key, [
    Map<String, String> params = const {},
  ]) {
    if (key == LineKey.welcome && params['name'] == null) {
      return l.loquetWelcomeAnon;
    }
    final variants = _lines[key]!;
    var i = _random.nextInt(variants.length);
    if (variants.length > 1 && i == _last[key]) {
      i = (i + 1 + _random.nextInt(variants.length - 1)) % variants.length;
    }
    _last[key] = i;
    return variants[i](l, params);
  }
}

/// What the face shows, for screen readers.
String loquetLabel(AppLocalizations l, LoquetMood mood) => switch (mood) {
  LoquetMood.idle => l.loquetMoodIdle,
  LoquetMood.watching => l.loquetMoodWatching,
  LoquetMood.covering => l.loquetMoodCovering,
  LoquetMood.peeking => l.loquetMoodPeeking,
  LoquetMood.happy => l.loquetMoodHappy,
  LoquetMood.sad => l.loquetMoodSad,
  LoquetMood.alert => l.loquetMoodAlert,
  LoquetMood.connecting => l.loquetMoodConnecting,
  LoquetMood.search => l.loquetMoodSearch,
  LoquetMood.offline => l.loquetMoodOffline,
  LoquetMood.sleep => l.loquetMoodSleep,
  LoquetMood.sleepy => l.loquetMoodSleepy,
  LoquetMood.yawn => l.loquetMoodYawn,
  LoquetMood.cheerful => l.loquetMoodCheerful,
  LoquetMood.concerned => l.loquetMoodConcerned,
  LoquetMood.dizzy => l.loquetMoodDizzy,
};
