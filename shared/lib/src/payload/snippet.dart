// SPDX-License-Identifier: Apache-2.0
import '../util/json_reader.dart';
import 'payload.dart';

class SnippetMeta extends Payload {
  SnippetMeta({
    super.schemaVersion = 1,
    required this.name,
    required this.command,
    this.tags = const [],
    super.extra = const {},
  });

  factory SnippetMeta.fromJson(Object? json) {
    final r = JsonReader(json, 'snippet');
    final command = r.text('command', max: PayloadLimits.command);
    if (command.trim().isEmpty) {
      throw const FormatException('snippet.command: empty');
    }
    final tags = r.opt<List<Object?>>('tags') == null
        ? const <String>[]
        : r.list<String>('tags', max: PayloadLimits.tags);
    if (tags.any((t) => t.runes.length > PayloadLimits.tag)) {
      throw const FormatException('snippet.tags: tag too long');
    }
    return SnippetMeta(
      schemaVersion: r.integer('schemaVersion', min: 1),
      name: r.text('name', max: PayloadLimits.snippetName, required: true),
      command: command,
      tags: tags,
      extra: r.extra(const {'schemaVersion', 'name', 'command', 'tags'}),
    );
  }

  final String name;

  /// Stored as typed: leading spaces and newlines matter to a shell.
  final String command;
  final List<String> tags;

  @override
  Map<String, Object?> toJson() => {
    ...extra,
    'schemaVersion': schemaVersion,
    'name': name,
    'command': command,
    'tags': tags,
  };
}
