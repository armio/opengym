/// Typed models of every synced document and row (contract §2.1). Each one:
///
/// * reads tolerant JSON with `fromJson` (wrong types fall back to defaults),
/// * keeps unknown keys in `extra` and writes them back in `toJson`,
/// * keeps the original JSON key names so openGym backups round-trip,
/// * is mutable, with `copy()` for a deep copy (mutations go through AppState on a copy).
library;

export 'active_workout.dart';
export 'athlete.dart';
export 'body_weight.dart';
export 'coach_doc.dart';
export 'json.dart';
export 'plan.dart';
export 'proposal.dart';
export 'schedule.dart';
export 'settings.dart';
export 'workout.dart';
