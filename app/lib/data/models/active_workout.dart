import 'json.dart';
import 'plan.dart';
import 'workout.dart';

/// What the progression engine decided for an entry when the session was built
/// (specs/data-model.md §1.6). [why] is `[template, ...args]` with the English template key.
class Prescription implements JsonModel {
  Prescription({required this.policy, required this.kind, this.weight, this.reps, this.sec, this.why, JsonMap? extra})
    : extra = extra ?? {};

  factory Prescription.fromJson(Object? json) {
    final m = asMap(json);
    return Prescription(
      policy: asString(m['policy']) ?? 'off',
      kind: asString(m['kind']) ?? 'off',
      weight: asNum(m['weight']),
      reps: asNum(m['reps']),
      sec: asNum(m['sec']),
      why: m['why'] is List ? List<dynamic>.from(asList(m['why'])) : null,
      extra: extraOf(m, const {'policy', 'kind', 'weight', 'reps', 'sec', 'why'}),
    );
  }

  /// `'off'|'linear'|'greyskull'|'double'|'time'`.
  String policy;

  /// `'off'|'first'|'up'|'hold'|'deload'`.
  String kind;
  num? weight;
  num? reps;
  num? sec;
  List<dynamic>? why;
  JsonMap extra;

  Prescription copy() => Prescription.fromJson(toJson());

  @override
  JsonMap toJson() {
    final out = <String, dynamic>{...deepCopyMap(extra), 'policy': policy, 'kind': kind};
    putIfNotNull(out, 'weight', weight);
    putIfNotNull(out, 'reps', reps);
    putIfNotNull(out, 'sec', sec);
    if (why != null) out['why'] = deepCopyJson(why);
    return out;
  }
}

/// One exercise of the workout in progress.
class ActiveEntry implements JsonModel {
  ActiveEntry({
    required this.id,
    this.sg,
    JsonMap? target,
    Prescription? plan,
    List<SetRecord>? sets,
    this.topW,
    this.asked = false,
    JsonMap? extra,
  }) : target = target ?? {},
       plan = plan ?? Prescription(policy: 'off', kind: 'off'),
       sets = sets ?? [],
       extra = extra ?? {};

  factory ActiveEntry.fromJson(Object? json) {
    final m = asMap(json);
    return ActiveEntry(
      id: asString(m['id']) ?? '',
      sg: asString(m['sg']),
      target: asMap(m['target']),
      plan: Prescription.fromJson(m['plan']),
      sets: [
        for (final s in asList(m['sets']))
          if (s is Map) SetRecord.fromJson(s),
      ],
      topW: asNum(m['topW']),
      asked: asBool(m['asked']) ?? false,
      extra: extraOf(m, const {'id', 'sg', 'target', 'plan', 'sets', 'topW', 'asked'}),
    );
  }

  String id;

  /// Superset group copied from the routine config (absent for mid-workout additions).
  String? sg;

  /// `{...cfg}` of the routine exercise (open shape).
  JsonMap target;
  Prescription plan;
  List<SetRecord> sets;

  /// Set by the "confirm working weight" sheet.
  num? topW;

  /// The weight-confirm sheet was already shown for this entry.
  bool asked;
  JsonMap extra;

  /// `{...target, id}` as a typed config (a copy).
  RoutineExercise get targetConfig => RoutineExercise.fromJson({...target, 'id': target['id'] ?? id});

  ActiveEntry copy() => ActiveEntry.fromJson(toJson());

  @override
  JsonMap toJson() {
    final out = <String, dynamic>{...deepCopyMap(extra), 'id': id};
    putIfNotNull(out, 'sg', sg);
    out['target'] = deepCopyMap(target);
    out['plan'] = plan.toJson();
    out['sets'] = [for (final s in sets) s.toJson()];
    putIfNotNull(out, 'topW', topW);
    if (asked) out['asked'] = true;
    return out;
  }
}

/// The in-progress session. Device-only: stored in `active.json`, never synced.
class ActiveWorkout implements JsonModel {
  ActiveWorkout({
    required this.id,
    required this.d,
    required this.start,
    this.routineId,
    this.name = '',
    this.bw,
    this.cur = 0,
    List<ActiveEntry>? entries,
    JsonMap? extra,
  }) : entries = entries ?? [],
       extra = extra ?? {};

  factory ActiveWorkout.fromJson(Object? json) {
    final m = asMap(json);
    return ActiveWorkout(
      id: asString(m['id']) ?? '',
      d: asString(m['d']) ?? '',
      start: asInt(m['start']) ?? 0,
      routineId: asString(m['routineId']),
      name: asString(m['name']) ?? '',
      bw: asNum(m['bw']),
      cur: asInt(m['cur']) ?? 0,
      entries: [
        for (final e in asList(m['entries']))
          if (e is Map) ActiveEntry.fromJson(e),
      ],
      extra: extraOf(m, const {'id', 'd', 'start', 'routineId', 'name', 'bw', 'cur', 'entries'}),
    );
  }

  String id;
  String d;
  int start;
  String? routineId;
  String name;
  num? bw;

  /// Index into [entries] of the exercise on screen.
  int cur;
  List<ActiveEntry> entries;
  JsonMap extra;

  ActiveWorkout copy() => ActiveWorkout.fromJson(toJson());

  @override
  JsonMap toJson() => {
    ...deepCopyMap(extra),
    'id': id,
    'd': d,
    'start': start,
    'routineId': routineId,
    'name': name,
    'bw': bw == null ? null : jsNum(bw!),
    'cur': cur,
    'entries': [for (final e in entries) e.toJson()],
  };
}
