// SPDX-License-Identifier: Apache-2.0
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../api/api_client.dart';
import '../debug_trace.dart';
import '../storage/local_mirror.dart';
import 'conflict_resolver.dart';

/// Sends the pending outbox entries in order, backing off after a network error, 429 or 5xx.
class OutboxPusher {
  OutboxPusher({
    required this.api,
    required this.mirror,
    required this.resolver,
    required this.markChanged,
    required this.onClientTooOld,
    required this._now,
    required this.interval,
    required this.maxAttempts,
    required this.maxBackoff,
  });

  final ApiClient api;
  final LocalMirror mirror;
  final ConflictResolver resolver;
  final void Function() markChanged;
  final Duration interval;
  final int maxAttempts;
  final Duration maxBackoff;

  /// A write answered 409 `client_too_old` although the info said compatible.
  final void Function() onClientTooOld;
  final DateTime Function() _now;
  int _failures = 0;
  DateTime? _pushAfter;

  Future<void> push() async {
    if (_pushAfter case final after? when _now().isBefore(after)) return;
    for (final entry in mirror.outbox().where(
      (e) => e.state == OutboxState.pending,
    )) {
      try {
        resolver.settle(
          entry.item,
          await api.putItem(entry.item, ifMatch: entry.baseRevision),
        );
        trace(
          TraceArea.sync,
          'pushed ${entry.item.kind.name} ${shortId(entry.item.id)}',
        );
        _failures = 0;
        _pushAfter = null;
      } on NetworkException {
        // Nothing is counted on the entry; the round then marks the client offline.
        _backOff(null);
        rethrow;
      } on ApiException catch (refusal) {
        if (refusal.status == 401) rethrow;
        trace(
          TraceArea.sync,
          'push ${shortId(entry.item.id)} refused: ${refusal.status} ${refusal.reason ?? refusal.code}',
        );
        if (refusal.conflictReason == ConflictReason.clientTooOld) {
          return onClientTooOld();
        }
        if (refusal.status == 409) {
          await resolver.resolve(entry.item, refusal.item);
        } else if (refusal.status == 429 || refusal.status >= 500) {
          // Nothing is counted on the entry.
          return _backOff(refusal.retryAfter);
        } else {
          mirror.recordOutboxFailure(entry.item.id, refusal.code);
          if (mirror.outboxEntry(entry.item.id)!.attempts >= maxAttempts) {
            // Other refusals (400, 403, 413 and the like) reject the entry after maxAttempts.
            mirror.rejectOutbox(entry.item.id);
            markChanged();
          }
        }
      }
    }
  }

  // interval * 2^(failures - 1), capped at maxBackoff; a longer `retry-after` wins.
  void _backOff(Duration? retryAfter) {
    _failures++;
    final doubled = interval * (1 << (_failures - 1).clamp(0, 20));
    var wait = doubled < maxBackoff ? doubled : maxBackoff;
    if (retryAfter != null && retryAfter > wait) wait = retryAfter;
    _pushAfter = _now().add(wait);
    trace(TraceArea.sync, 'push backs off ${wait.inSeconds} s');
  }
}
