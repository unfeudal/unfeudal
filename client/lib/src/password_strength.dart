// SPDX-License-Identifier: Apache-2.0
import 'package:unfeudal_shared/unfeudal_shared.dart';

/// 0 when empty, 1 under the minimum length or guessable, then up to 4 with length and character classes.
int passwordScore(String password) {
  final length = passwordLength(password);
  if (length == 0) return 0;
  if (length < AccountCrypto.minPasswordLength || isGuessable(password)) {
    return 1;
  }
  final classes = [
    RegExp('[a-z]'),
    RegExp('[A-Z]'),
    RegExp(r'\d'),
    RegExp(r'[^a-zA-Z\d]'),
  ].where((c) => c.hasMatch(password)).length;
  return 2 + (length >= 12 ? 1 : 0) + (length >= 16 || classes >= 3 ? 1 : 0);
}

/// Whether [password] is among the first an attacker tries: a common password, look-alike digits and
/// symbols included, or nothing but a repeat, a run of letters or digits, or a keyboard row, with digits
/// and symbols around it.
bool isGuessable(String password) {
  final lower = password.toLowerCase();
  final core = lower.replaceAll(_edges, '');
  return _common.contains(_unleet(lower)) ||
      _common.contains(_unleet(core)) ||
      _isPattern(lower) ||
      (core.length >= 4 && _isPattern(core));
}

// Digits and symbols at either end, as in `password123` or `!qwerty!`.
final _edges = RegExp(r'^[\d\W_]+|[\d\W_]+$');

// A short chunk repeated, as in `aaaa` or `abcabc`.
final _repeat = RegExp(r'^(.{1,3})\1+$');

// Letters, digits and the rows of QWERTY and AZERTY keyboards, read both ways.
const _runs = [
  'abcdefghijklmnopqrstuvwxyz',
  '01234567890',
  'qwertyuiop',
  'asdfghjkl',
  'zxcvbnm',
  'azertyuiop',
  'qsdfghjklm',
  'wxcvbn',
];

bool _isPattern(String s) =>
    s.length >= 3 &&
    (_repeat.hasMatch(s) ||
        _runs.any(
          (run) => run.contains(s) || run.split('').reversed.join().contains(s),
        ));

// The look-alikes of `p@ssw0rd`.
String _unleet(String s) => s
    .replaceAll('0', 'o')
    .replaceAll('1', 'i')
    .replaceAll('3', 'e')
    .replaceAll('4', 'a')
    .replaceAll('5', 's')
    .replaceAll('7', 't')
    .replaceAll('@', 'a')
    .replaceAll(r'$', 's')
    .replaceAll('!', 'i');

// The most used passwords in English and French leak lists, look-alikes folded.
const _common = {
  'password',
  'passwort',
  'motdepasse',
  'iloveyou',
  'jetaime',
  'admin',
  'administrator',
  'welcome',
  'bienvenue',
  'letmein',
  'monkey',
  'dragon',
  'football',
  'baseball',
  'soccer',
  'sunshine',
  'soleil',
  'princess',
  'princesse',
  'master',
  'shadow',
  'superman',
  'batman',
  'trustnoi',
  'starwars',
  'whatever',
  'bonjour',
  'doudou',
  'chouchou',
  'loulou',
  'marseille',
  'paris',
  'secret',
  'changeme',
  'default',
  'login',
  'azerty',
  'qwerty',
  'qwertz',
  'unfeudal',
};
