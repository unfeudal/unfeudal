// SPDX-License-Identifier: Apache-2.0
import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

void main() {
  final r = JsonReader({
    'n': 1,
    'd': 1.5,
    's': '  hi  ',
    'e': '\u{1F600}' * 3,
    'b': true,
    'l': ['a', 'b'],
    'o': {'k': 1},
    'u': '6f1c2b9a-3d4e-4f50-8a61-7b8c9d0e1f20',
    'nul': null,
    'x': 'extra',
  }, 'thing');

  test('a non-object root is a FormatException', () {
    expect(() => JsonReader('str', 'thing'), throwsFormatException);
    expect(() => JsonReader([1], 'thing'), throwsFormatException);
  });

  test('type mismatches are FormatException, never TypeError', () {
    expect(() => r.req<String>('n'), throwsFormatException);
    expect(() => r.req<int>('d'), throwsFormatException);
    expect(() => r.req<int>('missing'), throwsFormatException);
    expect(() => r.list<int>('l', max: 5), throwsFormatException);
    expect(() => r.object('l'), throwsFormatException);
    expect(() => r.flag('n'), throwsFormatException);
  });

  test('an optional null or missing field reads as null', () {
    expect(r.opt<int>('nul'), isNull);
    expect(r.opt<int>('missing'), isNull);
  });

  test('integers are range-checked', () {
    expect(r.integer('n', min: 1, max: 1), 1);
    expect(() => r.integer('n', min: 2), throwsFormatException);
    expect(() => r.integer('n', max: 0), throwsFormatException);
  });

  test('text counts code points; trimmed text is non-empty', () {
    expect(r.text('e', max: 3), '\u{1F600}' * 3);
    expect(() => r.text('e', max: 2), throwsFormatException);
    expect(r.trimmedText('s', max: 2), 'hi');
    expect(r.text('s', max: 6), '  hi  ');
    expect(
      () => JsonReader({'s': '   '}, 't').trimmedText('s', max: 9),
      throwsFormatException,
    );
    expect(r.optText('nul', max: 1), isNull);
  });

  test('uuids are checked; an optional null uuid reads as null', () {
    expect(r.uuid('u'), '6f1c2b9a-3d4e-4f50-8a61-7b8c9d0e1f20');
    expect(() => r.uuid('s'), throwsFormatException);
    expect(r.optUuid('nul'), isNull);
  });

  test('lists are bounded', () {
    expect(r.list<String>('l', max: 2), ['a', 'b']);
    expect(() => r.list<String>('l', max: 1), throwsFormatException);
  });

  test('a missing flag reads as its fallback', () {
    expect(r.flag('b'), isTrue);
    expect(r.flag('missing', orElse: false), isFalse);
  });

  test('extra returns the fields outside the known keys', () {
    expect(r.extra({'n', 'd', 's', 'e', 'b', 'l', 'o', 'u', 'nul'}), {
      'x': 'extra',
    });
  });

  test('bytes are base64url with an optional exact length', () {
    final b = JsonReader({'k': '-_8', 'bad': '+/8'}, 'thing');
    expect(b.bytes('k'), [0xfb, 0xff]);
    expect(b.bytes('k', length: 2), [0xfb, 0xff]);
    expect(() => b.bytes('k', length: 3), throwsFormatException);
    expect(() => b.bytes('bad'), throwsFormatException);
    expect(() => b.bytes('missing'), throwsFormatException);
  });
}
