// SPDX-License-Identifier: AGPL-3.0-or-later
final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

bool isEmailAddress(String text) => _email.hasMatch(text);

String canonicalEmail(String text) => text.trim().toLowerCase();
