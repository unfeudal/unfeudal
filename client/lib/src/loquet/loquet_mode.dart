// SPDX-License-Identifier: Apache-2.0
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../settings/settings.dart';

/// Server flag, then any org, then the user: strongest first; a user can only lower it.
/// `serverFlag` = `AppState.serverInfo.has(Flag.mascot)`; `orgSettings` = every membership of the org block.
LoquetMode effectiveLoquetMode({
  required bool serverFlag,
  required Iterable<OrgSummary> orgSettings,
  required LoquetMode pref,
}) {
  if (!serverFlag) return LoquetMode.off;
  if (orgSettings.any((o) => !o.mascot)) {
    return LoquetMode.off; // OrgSummary.mascot: missing key = true
  }
  return pref;
}
