// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:unfeudal_shared/unfeudal_shared.dart';

/// 32 random bytes in base64url (43 characters).
String randomToken() => b64(secureBytes(32));
