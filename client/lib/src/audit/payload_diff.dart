// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

typedef FieldChange = ({String field, Object? before, Object? after});

/// Fields that differ between two payloads, by name; lists and maps compare by value; schemaVersion is ignored.
List<FieldChange> diffPayloads(
  Map<String, Object?>? before,
  Map<String, Object?>? after,
) {
  final fields = {...?before?.keys, ...?after?.keys}..remove('schemaVersion');
  return [
    for (final field in fields.toList()..sort())
      if (jsonEncode(before?[field]) != jsonEncode(after?[field]))
        (field: field, before: before?[field], after: after?[field]),
  ];
}
