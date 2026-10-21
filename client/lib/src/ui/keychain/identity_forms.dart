// SPDX-License-Identifier: Apache-2.0
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/motion.dart';
import '../../keys/key_tools.dart';
import '../form_dialog.dart';

/// Where a new identity goes: the personal vault (no org), or one folder of an org.
typedef IdentityPlace = ({String? orgId, String? folderId});

/// Reads a key file the user picks; null when none was picked. Replaced in tests.
@visibleForTesting
Future<String?> Function() openKeyFile = () async =>
    (await openFile())?.readAsString();

/// Generates an Ed25519 or RSA key into [place]; the new identity's id, null when cancelled.
Future<String?> showGenerateKey(BuildContext context, IdentityPlace place) {
  final l = AppLocalizations.of(context);
  final save = _saverFor(context, place);
  return _form(
    context,
    title: l.keyGenerate,
    fields: [
      FormDialogField('gen-name', l.keyName),
      FormDialogField(
        'gen-passphrase',
        l.keyPassphrase,
        kind: FormFieldKind.secret,
      ),
      FormDialogField(
        'gen-type-rsa',
        l.keyTypeRsa,
        kind: FormFieldKind.toggle,
        offLabel: l.keyTypeEd25519,
      ),
    ],
    saveKey: 'gen-save',
    onSave: (v) async {
      final passphrase = _optional(v['gen-passphrase']!);
      final name = v['gen-name']!.trim();
      final key = v['gen-type-rsa'] == 'true'
          ? await generateRsa(comment: name, passphrase: passphrase)
          : await generateEd25519(comment: name, passphrase: passphrase);
      return _savePrivateKey(
        save,
        name: name,
        pem: key.privateKeyPem,
        passphrase: passphrase,
        publicKey: key.publicKey,
      );
    },
  );
}

/// Imports a pasted or opened private key into [place]; the new identity's id, null when cancelled.
Future<String?> showImportKey(BuildContext context, IdentityPlace place) {
  final l = AppLocalizations.of(context);
  final save = _saverFor(context, place);
  return _form(
    context,
    title: l.keyImport,
    fields: [
      FormDialogField('import-name', l.keyName),
      FormDialogField(
        'import-pem',
        l.keyPem,
        lines: 6,
        mono: true,
        fromFile: (label: l.keyPemFromFile, open: openKeyFile),
      ),
      FormDialogField(
        'import-passphrase',
        l.keyPassphrase,
        kind: FormFieldKind.secret,
      ),
    ],
    saveKey: 'import-save',
    // The key is read (and its passphrase checked) before anything is stored; the original text is kept.
    onSave: (v) {
      final passphrase = _optional(v['import-passphrase']!);
      final pem = v['import-pem']!.trim();
      return _savePrivateKey(
        save,
        name: v['import-name']!.trim(),
        pem: pem,
        passphrase: passphrase,
        publicKey: publicKeyOf(pem, passphrase: passphrase),
      );
    },
  );
}

/// Adds a password identity to [place]; the new identity's id, null when cancelled.
Future<String?> showAddPassword(BuildContext context, IdentityPlace place) {
  final l = AppLocalizations.of(context);
  final save = _saverFor(context, place);
  return _form(
    context,
    title: l.keyPassword,
    fields: [
      FormDialogField('pw-name', l.keyName),
      FormDialogField(
        'pw-value',
        l.keyKindPassword,
        kind: FormFieldKind.secret,
      ),
    ],
    saveKey: 'pw-save',
    onSave: (v) => save(
      IdentityMeta(name: v['pw-name']!.trim(), kind: IdentityKind.password),
      IdentitySecret(kind: IdentityKind.password, password: v['pw-value']),
    ),
  );
}

String? _optional(String text) => text.isEmpty ? null : text;

Future<String?> _form(
  BuildContext context, {
  required String title,
  required List<FormDialogField> fields,
  required String saveKey,
  required Future<String> Function(Map<String, String>) onSave,
}) async {
  String? id;
  final saved = await showUfDialog<bool>(
    context,
    (_) => FormDialog(
      title: title,
      fields: fields,
      saveKey: saveKey,
      saveLabel: AppLocalizations.of(context).keySave,
      onSave: (v) async => id = await onSave(v),
    ),
  );
  return saved == true ? id : null;
}

Future<String> _savePrivateKey(
  _Save save, {
  required String name,
  required String pem,
  required String? passphrase,
  required String publicKey,
}) => save(
  IdentityMeta(name: name, kind: IdentityKind.privateKey, publicKey: publicKey),
  IdentitySecret(
    kind: IdentityKind.privateKey,
    privateKeyPem: pem,
    passphrase: passphrase,
  ),
);

typedef _Save = Future<String> Function(
  IdentityMeta meta,
  IdentitySecret secret,
);

_Save _saverFor(BuildContext context, IdentityPlace place) {
  final orgs = AppScope.read(context).orgs!;
  return (meta, secret) => orgs.saveItem(
    type: 'identity',
    orgId: place.orgId,
    folderId: place.folderId,
    meta: meta.toJson(),
    secret: secret.toJson(),
  );
}
