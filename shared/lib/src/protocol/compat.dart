// SPDX-License-Identifier: Apache-2.0
import 'api_info.dart';
import 'version.dart';

enum CompatMode { full, readOnly }

class Compat {
  const Compat(this.mode, this.api, this.reason);

  final CompatMode mode;
  final int? api; // highest common API, null when none
  final String? reason; // 'no-common-api' | 'client-too-old'
}

Compat negotiate(String clientVersion, List<int> clientApis, ApiInfo info) {
  final common = clientApis.where(info.api.contains).toList()..sort();
  // No common API: no push, no pull.
  if (common.isEmpty) {
    return const Compat(CompatMode.readOnly, null, 'no-common-api');
  }
  // Below minClient: pull only.
  if (compareVersions(clientVersion, info.minClient) < 0) {
    return Compat(CompatMode.readOnly, common.last, 'client-too-old');
  }
  return Compat(CompatMode.full, common.last, null);
}
