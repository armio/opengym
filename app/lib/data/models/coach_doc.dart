import 'json.dart';
import 'plan.dart';

/// A plan snapshot taken before Coach changes were applied (specs/coach.md §7.4).
class CoachSnapshot implements JsonModel {
  CoachSnapshot({
    required this.at,
    this.proposalId,
    this.label = '',
    List<Routine>? routines,
    Map<String, String>? week,
    JsonMap? extra,
  }) : routines = routines ?? [],
       week = week ?? {},
       extra = extra ?? {};

  factory CoachSnapshot.fromJson(Object? json) {
    final m = asMap(json);
    return CoachSnapshot(
      at: asInt(m['at']) ?? 0,
      proposalId: asString(m['proposalId']),
      label: asString(m['label']) ?? '',
      routines: [
        for (final r in asList(m['routines']))
          if (r is Map) Routine.fromJson(r),
      ],
      week: asStringMap(m['week']),
      extra: extraOf(m, const {'at', 'proposalId', 'label', 'routines', 'week'}),
    );
  }

  int at;
  String? proposalId;
  String label;
  List<Routine> routines;
  Map<String, String> week;
  JsonMap extra;

  @override
  JsonMap toJson() => {
    ...deepCopyMap(extra),
    'at': at,
    'proposalId': proposalId,
    'label': label,
    'routines': [for (final r in routines) r.toJson()],
    'week': {...week},
  };
}

/// The `coach` doc: decision log, plan snapshots and the last review time
/// (contract §2.1, specs/coach.md §1.2). Written only through proposal resolve/revert.
///
/// Log entries have several open shapes (specs/coach.md §7.8) and stay plain JSON maps.
class CoachDoc implements JsonModel {
  CoachDoc({List<JsonMap>? log, List<CoachSnapshot>? snapshots, this.lastReview, JsonMap? extra})
    : log = log ?? [],
      snapshots = snapshots ?? [],
      extra = extra ?? {};

  factory CoachDoc.fromJson(Object? json) {
    final m = asMap(json);
    return CoachDoc(
      log: [
        for (final e in asList(m['log']))
          if (e is Map) deepCopyMap(e),
      ],
      snapshots: [
        for (final s in asList(m['snapshots']))
          if (s is Map) CoachSnapshot.fromJson(s),
      ],
      lastReview: asMapOrNull(m['lastReview']),
      extra: extraOf(m, const {'log', 'snapshots', 'lastReview'}),
    );
  }

  /// Newest last, at most 50.
  List<JsonMap> log;

  /// Newest last, at most 3.
  List<CoachSnapshot> snapshots;

  /// `{at: epochMs}` or null.
  JsonMap? lastReview;
  JsonMap extra;

  /// Epoch ms of the last review, if any.
  int? get lastReviewAt => asInt(lastReview?['at']);

  CoachDoc copy() => CoachDoc.fromJson(toJson());

  @override
  JsonMap toJson() => {
    ...deepCopyMap(extra),
    'log': [for (final e in log) deepCopyMap(e)],
    'snapshots': [for (final s in snapshots) s.toJson()],
    'lastReview': lastReview == null ? null : deepCopyMap(lastReview!),
  };
}
