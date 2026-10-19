// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:timezone/data/latest_all.dart';
import 'package:timezone/timezone.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import 'mailer.dart';

typedef _Template = ({String subject, String text});

const _en = <MailKind, _Template>{
  MailKind.newDevice: (
    subject: 'New sign-in to an Unfeudal account',
    text:
        'A new device signed in to this Unfeudal account.\n\nDevice: {device} ({platform})\nTime: {time}\n\n'
        'Not expected? Change the master password and revoke the device in the app (Settings, Devices).',
  ),
  MailKind.passwordChanged: (
    subject: 'Master password changed',
    text:
        'The master password of this Unfeudal account was changed and every other device was signed out.\n\n'
        'Time: {time}\n\nNot expected? Use the recovery kit to take the account back.',
  ),
  MailKind.recoveryUsed: (
    subject: 'Recovery key used',
    text:
        'The recovery key of this Unfeudal account was used: the master password and the recovery key were '
        'replaced and every device was signed out.\n\nTime: {time}\n\n'
        'Not expected? Contact the administrator of this server at once.',
  ),
  MailKind.lockout: (
    subject: 'Sign-in paused after failed attempts',
    text:
        'Too many failed sign-in attempts on this Unfeudal account from one network. Sign-in from that network '
        'is paused for a while.\n\nTime: {time}\n\nThe vault stays encrypted. If the master password is weak, change it.',
  ),
  MailKind.invite: (
    subject: 'Invitation to {orgName} on Unfeudal',
    text:
        'Open this link in the Unfeudal app to join {orgName}:\n{link}\n\n'
        'The invitation expires; ask for a new one if needed.',
  ),
};

const _fr = <MailKind, _Template>{
  MailKind.newDevice: (
    subject: 'Nouvelle connexion à un compte Unfeudal',
    text:
        "Un nouvel appareil s'est connecté à ce compte Unfeudal.\n\nAppareil : {device} ({platform})\nHeure : {time}\n\n"
        "Connexion inattendue ? Changer le mot de passe maître et révoquer l'appareil dans l'application "
        '(Réglages, Appareils).',
  ),
  MailKind.passwordChanged: (
    subject: 'Mot de passe maître changé',
    text:
        'Le mot de passe maître de ce compte Unfeudal a été changé et tous les autres appareils ont été '
        'déconnectés.\n\nHeure : {time}\n\nChangement inattendu ? Utiliser le kit de récupération pour reprendre le compte.',
  ),
  MailKind.recoveryUsed: (
    subject: 'Clé de récupération utilisée',
    text:
        'La clé de récupération de ce compte Unfeudal a été utilisée : le mot de passe maître et la clé de '
        'récupération ont été remplacés, tous les appareils ont été déconnectés.\n\nHeure : {time}\n\n'
        "Utilisation inattendue ? Contacter tout de suite l'administrateur de ce serveur.",
  ),
  MailKind.lockout: (
    subject: 'Connexion suspendue après des échecs',
    text:
        'Trop de tentatives de connexion échouées sur ce compte Unfeudal depuis un même réseau. La connexion '
        'depuis ce réseau est suspendue un moment.\n\nHeure : {time}\n\n'
        'Le coffre reste chiffré. Si le mot de passe maître est faible, le changer.',
  ),
  MailKind.invite: (
    subject: 'Invitation à {orgName} sur Unfeudal',
    text:
        "Ouvrir ce lien dans l'application Unfeudal pour rejoindre {orgName} :\n{link}\n\n"
        "L'invitation expire ; en demander une nouvelle si besoin.",
  ),
};

const _instanceInvite = {
  'en': (
    subject: 'Invitation to an Unfeudal server',
    orgName: 'this Unfeudal server',
  ),
  'fr': (
    subject: 'Invitation à un serveur Unfeudal',
    orgName: 'ce serveur Unfeudal',
  ),
};

bool _zonesLoaded = false;

/// Plain text in the user's language (`en` unless `fr`); `{time}` is shown in [timezone].
({String subject, String text}) renderMail(Mail mail, String timezone) {
  final locale = mail.locale == 'fr' ? 'fr' : 'en';
  final template = (locale == 'fr' ? _fr : _en)[mail.kind]!;
  final vars = {...mail.vars};
  var subject = template.subject;
  if (mail.kind == MailKind.invite && vars['orgName'] == null) {
    subject = _instanceInvite[locale]!.subject;
    vars['orgName'] = _instanceInvite[locale]!.orgName;
  }
  final time = vars['time'];
  if (time != null) vars['time'] = _localTime(time, timezone);
  String fill(String s) =>
      s.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) => vars[m[1]] ?? m[0]!);
  return (subject: fill(subject), text: fill(template.text));
}

String _localTime(String time, String timezone) {
  if (!_zonesLoaded) {
    initializeTimeZones();
    _zonesLoaded = true;
  }
  final t = TZDateTime.from(parseIso(time), getLocation(timezone));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)} ($timezone)';
}
