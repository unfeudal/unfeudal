// SPDX-License-Identifier: Apache-2.0

import '../api/api_client.dart';
import '../events/app_events.dart';

/// Reports SSH sessions, forwards and shown secrets to the server's audit: ids and ports only, never what the
/// terminal carries. Best effort: one at a time in event order, a refused report is dropped, nothing is queued.
class EventReporter {
  EventReporter({
    required this._events,
    required this._api,
    required this._enabled,
  });

  final Stream<AppEvent> _events;
  final ApiClient? Function() _api;
  final bool Function() _enabled;

  // Maps a hostId to the jump hosts of the connection being opened.
  final _hops = <String, List<String>>{};
  Future<void> _tail = Future.value();

  void start() => _events.listen(_on);

  void _on(AppEvent event) {
    switch (event) {
      case JumpUsed(:final hostId, :final hopIds):
        _hops[hostId] = hopIds;
      case ConnectFailed(:final hostId):
        _hops.remove(hostId);
      case ConnectSucceeded(:final hostId):
        final hops = _hops.remove(hostId) ?? const [];
        _send(
          (api) => api.reportSsh(
            event: 'open',
            hostItemId: hostId,
            jumpHostItemIds: hops,
          ),
        );
      case SessionClosed(:final hostId):
        _send((api) => api.reportSsh(event: 'close', hostItemId: hostId));
      case ForwardStarted(:final hostId, :final forward):
        _send(
          (api) => api.reportSsh(
            event: 'forward_start',
            hostItemId: hostId,
            localPort: forward.localPort,
          ),
        );
      case ForwardStopped(:final hostId, :final localPort):
        _send(
          (api) => api.reportSsh(
            event: 'forward_stop',
            hostItemId: hostId,
            localPort: localPort,
          ),
        );
      case SecretRevealed(:final itemId):
        _send((api) => api.reportReveal(itemId));
      default:
        break;
    }
  }

  void _send(Future<void> Function(ApiClient api) report) {
    if (!_enabled()) return;
    final api = _api();
    if (api == null) return;
    _tail = _tail.then((_) async {
      try {
        await report(api);
      } on Exception {
        // dropped: a host not yet on the server answers 404, a 429 is lost
      }
    });
  }
}
