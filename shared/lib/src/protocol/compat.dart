// SPDX-License-Identifier: Apache-2.0
import 'api_info.dart';
import 'version.dart';

enum CompatMode { full, readOnly }

class Compat {
  const Compat(this.mode, this.api, this.reason);

  final CompatMode mode;

  /// The highest common API, null when none.
  final int? api;

  /// 'no-common-api' or 'client-too-old' when [mode] is read-only.
  final String? reason;
}

Compat negotiate(String clientVersion, List<int> clientApis, ApiInfo info) {
  final common = clientApis.where(info.api.contains).toList()..sort();
  // Without a common API the client can neither push nor pull.
  if (common.isEmpty) {
    return const Compat(CompatMode.readOnly, null, 'no-common-api');
  }
  if (compareVersions(clientVersion, info.minClient) < 0) {
    return Compat(CompatMode.readOnly, common.last, 'client-too-old');
  }
  return Compat(CompatMode.full, common.last, null);
}
