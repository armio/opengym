/// The app side of the Coach (specs/coach.md §7, contract §4.3 and §5.4): plan fingerprint,
/// staleness, applying and dismissing proposals, snapshots, revert, the decision log and the
/// Spanish display text. Everything operates on the typed `PlanDoc` / `CoachDoc` of a proposal
/// draft.
library;

export 'apply.dart';
export 'changes.dart';
export 'coach_log.dart';
export 'display.dart';
export 'plan_hash.dart';
export 'staleness.dart';
