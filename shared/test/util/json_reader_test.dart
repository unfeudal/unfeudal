// SPDX-License-Identifier: Apache-2.0
import 'package:test/test.dart';
import 'package:unfeudal_shared/src/util/json_reader.dart';

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

  test('type mismatches are FormatException, never TypeError', () {
    expect(() => JsonReader('str', 'thing'), throwsFormatException);
    expect(() => JsonReader([1], 'thing'), throwsFormatException);
    expect(() => r.req<String>('n'), throwsFormatException);
    expect(() => r.req<int>('d'), throwsFormatException);
    expect(() => r.req<int>('missing'), throwsFormatException);
    expect(() => r.list<int>('l', max: 5), throwsFormatException);
    expect(() => r.object('l'), throwsFormatException);
    expect(() => r.flag('n'), throwsFormatException);
    expect(r.opt<int>('nul'), isNull);
    expect(r.opt<int>('missing'), isNull);
  });

  test('integers are range-checked', () {
    expect(r.integer('n', min: 1, max: 1), 1);
    expect(() => r.integer('n', min: 2), throwsFormatException);
    expect(() => r.integer('n', max: 0), throwsFormatException);
  });

  test('text counts code points; required text is trimmed and non-empty', () {
    expect(r.text('e', max: 3), '\u{1F600}' * 3);
    expect(() => r.text('e', max: 2), throwsFormatException);
    expect(r.text('s', max: 2, required: true), 'hi');
    expect(r.text('s', max: 6), '  hi  ');
    expect(
      () => JsonReader({'s': '   '}, 't').text('s', max: 9, required: true),
      throwsFormatException,
    );
    expect(r.optText('nul', max: 1), isNull);
  });

  test('uuids, bounded lists, flags and extra', () {
    expect(r.uuid('u'), '6f1c2b9a-3d4e-4f50-8a61-7b8c9d0e1f20');
    expect(() => r.uuid('s'), throwsFormatException);
    expect(r.optUuid('nul'), isNull);
    expect(r.list<String>('l', max: 2), ['a', 'b']);
    expect(() => r.list<String>('l', max: 1), throwsFormatException);
    expect(r.flag('b'), isTrue);
    expect(r.flag('missing', orElse: false), isFalse);
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
