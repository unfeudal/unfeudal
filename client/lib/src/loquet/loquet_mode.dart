// SPDX-License-Identifier: Apache-2.0
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../settings/settings.dart';

/// Server flag, then the shown org, then the user: strongest first; a user can only lower it.
/// `serverFlag` = `AppState.serverInfo.has(Flag.mascot)`; `org` = the selected org, null in the personal vault,
/// so an org that turns him off does it only while it is shown.
LoquetMode effectiveLoquetMode({
  required bool serverFlag,
  required OrgSummary? org,
  required LoquetMode pref,
}) {
  if (!serverFlag) return LoquetMode.off;
  // OrgSummary.isMascotEnabled is true when the org setting is missing.
  if (org != null && !org.isMascotEnabled) return LoquetMode.off;
  return pref;
}
