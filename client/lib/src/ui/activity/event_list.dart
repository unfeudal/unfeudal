// SPDX-License-Identifier: Apache-2.0
part of 'activity_screen.dart';

class _EventList extends StatelessWidget {
  const _EventList({
    required this.events,
    required this.nameOf,
    required this.canOpenDeletedOrgs,
    required this.onOpenOrg,
  });

  final List<AuditEvent> events;
  final String Function(String) nameOf;
  final bool canOpenDeletedOrgs;
  final ValueChanged<String> onOpenOrg;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final dates = MaterialLocalizations.of(context);
    return UfStagger(
      child: ListView.builder(
        itemCount: events.length,
        itemBuilder: (context, i) {
          final e = events[i];
          final ts = DateTime.parse(e.ts).toLocal();
          return UfStaggerItem(
            index: i,
            child: EventRow(
              when:
                  '${dates.formatShortDate(ts)} ${dates.formatTimeOfDay(TimeOfDay.fromDateTime(ts))}',
              text: describeEvent(l, e, nameOf),
              who: [
                if (e.actorUser case final actor?) nameOf(actor),
                ?e.ipAddress,
              ].join(' · '),
              trailing:
                  e.action == 'org.deleted' &&
                      canOpenDeletedOrgs &&
                      e.targetIds.isNotEmpty
                  ? OutlinedButton(
                      key: Key('activity-open-org-${e.targetIds.first}'),
                      style: smallButton,
                      onPressed: () => onOpenOrg(e.targetIds.first),
                      child: Text(l.activityOpenDeletedOrg),
                    )
                  : null,
            ),
          );
        },
      ),
    );
  }
}

/// One audit event: when, what, who; the same row for every chain.
class EventRow extends StatelessWidget {
  const EventRow({
    super.key,
    required this.when,
    required this.text,
    required this.who,
    this.trailing,
  });

  final String when;
  final String text;
  final String who;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final muted = Theme.of(context).textTheme.bodySmall!
        .copyWith(color: colors.muted);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          spacing: 16,
          children: [
            SizedBox(width: 130, child: Text(when, style: muted)),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium!
                    .copyWith(fontSize: 13.5),
              ),
            ),
            if (who.isNotEmpty) Text(who, style: muted),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
