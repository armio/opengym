import '../dates.dart';
import 'json.dart';
import 'plan.dart';

/// One logged set (specs/data-model.md §1.5). Which fields are used depends on the mode:
/// reps `{w, r, done, rir?|rpe?}`, time `{sec, w, done}`, cardio `{min, speed, done}`.
///
/// Optional fields are **deleted, never stored as null**: setting one to null removes the key
/// from [toJson]'s output. A set carries at most one of [rir] and [rpe].
class SetRecord implements JsonModel {
  SetRecord({this.w, this.r, this.sec, this.min, this.speed, this.rir, this.rpe, this.done = false, JsonMap? extra})
    : extra = extra ?? {};

  factory SetRecord.fromJson(Object? json) {
    final m = asMap(json);
    return SetRecord(
      w: asNum(m['w']),
      r: asNum(m['r']),
      sec: asNum(m['sec']),
      min: asNum(m['min']),
      speed: asNum(m['speed']),
      rir: asNum(m['rir']),
      rpe: asNum(m['rpe']),
      done: asBool(m['done']) ?? false,
      extra: extraOf(m, _known),
    );
  }

  static const _known = {'w', 'r', 'sec', 'min', 'speed', 'rir', 'rpe', 'done'};

  num? w;
  num? r;
  num? sec;
  num? min;

  /// km/h.
  num? speed;
  num? rir;
  num? rpe;
  bool done;
  JsonMap extra;

  SetRecord copy() => SetRecord.fromJson(toJson());

  @override
  JsonMap toJson() {
    final out = <String, dynamic>{...deepCopyMap(extra)};
    putIfNotNull(out, 'w', w);
    putIfNotNull(out, 'r', r);
    putIfNotNull(out, 'sec', sec);
    putIfNotNull(out, 'min', min);
    putIfNotNull(out, 'speed', speed);
    out['done'] = done;
    putIfNotNull(out, 'rir', rir);
    putIfNotNull(out, 'rpe', rpe);
    return out;
  }
}

/// One exercise of a finished workout.
class WorkoutEntry implements JsonModel {
  WorkoutEntry({required this.id, List<SetRecord>? sets, this.topW, this.target, this.n, JsonMap? extra})
    : sets = sets ?? [],
      extra = extra ?? {};

  factory WorkoutEntry.fromJson(Object? json) {
    final m = asMap(json);
    return WorkoutEntry(
      id: asString(m['id']) ?? '',
      sets: [
        for (final s in asList(m['sets']))
          if (s is Map) SetRecord.fromJson(s),
      ],
      topW: asNum(m['topW']),
      target: asMapOrNull(m['target']),
      n: asString(m['n']),
      extra: extraOf(m, _known),
    );
  }

  static const _known = {'id', 'sets', 'topW', 'target', 'n'};

  /// Exercise id.
  String id;

  /// All sets of the session, including undone ones — readers filter on `done`.
  List<SetRecord> sets;

  /// Confirmed working weight (reps entries), else null. Always written, even when null.
  num? topW;

  /// Copy of the plan config the session prescribed (open shape). The port writes it with `id`
  /// and an explicit `mode` (engine-Q4); old, imported and demo data may lack it.
  JsonMap? target;

  /// Exercise name, stamped in only when its custom exercise was deleted.
  String? n;
  JsonMap extra;

  /// [target] as a typed config with `id` filled in — `{...target, id}`, the view `modeOf` reads.
  /// Returns a copy: edits to it are not written back.
  RoutineExercise? get targetConfig =>
      target == null ? null : RoutineExercise.fromJson({...target!, 'id': target!['id'] ?? id});

  Iterable<SetRecord> get doneSets => sets.where((s) => s.done);

  WorkoutEntry copy() => WorkoutEntry.fromJson(toJson());

  @override
  JsonMap toJson() {
    final out = <String, dynamic>{
      ...deepCopyMap(extra),
      'id': id,
      'sets': [for (final s in sets) s.toJson()],
      'topW': topW == null ? null : jsNum(topW!),
    };
    if (target != null) out['target'] = deepCopyMap(target!);
    putIfNotNull(out, 'n', n);
    return out;
  }
}

/// A finished workout (specs/data-model.md §1.5, contract §2.1).
class Workout implements JsonModel {
  Workout({
    required this.id,
    required this.d,
    required this.start,
    required this.end,
    this.routineId,
    this.name = '',
    this.bw,
    List<WorkoutEntry>? entries,
    List<String>? prs,
    this.vol = 0,
    this.rating,
    this.note,
    JsonMap? extra,
  }) : entries = entries ?? [],
       prs = prs ?? [],
       extra = extra ?? {};

  /// A missing `start` reads as local noon of `d` (engine-Q7); a missing `end` as `start`.
  factory Workout.fromJson(Object? json) {
    final m = asMap(json);
    final d = asString(m['d']) ?? '';
    final start = asInt(m['start']) ?? localNoonMs(d);
    return Workout(
      id: asString(m['id']) ?? '',
      d: d,
      start: start,
      end: asInt(m['end']) ?? start,
      routineId: asString(m['routineId']),
      name: asString(m['name']) ?? '',
      bw: asNum(m['bw']),
      entries: [
        for (final e in asList(m['entries']))
          if (e is Map) WorkoutEntry.fromJson(e),
      ],
      prs: asStringList(m['prs']),
      vol: asNum(m['vol']) ?? 0,
      rating: asString(m['rating']),
      note: asString(m['note']),
      extra: extraOf(m, _known),
    );
  }

  static const _known = {
    'id',
    'd',
    'start',
    'end',
    'routineId',
    'name',
    'bw',
    'entries',
    'prs',
    'vol',
    'rating',
    'note',
  };

  String id;

  /// Local `'YYYY-MM-DD'` the session started.
  String d;

  /// Epoch ms.
  int start;

  /// Epoch ms; equals [start] when the duration is unknown (imports).
  int end;

  /// Null for freestyle or imported sessions.
  String? routineId;
  String name;

  /// Body weight from the pre-workout check-in, else null.
  num? bw;

  /// Only entries with at least one done set.
  List<WorkoutEntry> entries;

  /// Exercise ids that set a load record in this session (a frozen snapshot, critic-G13).
  List<String> prs;

  /// Σ over done sets of `w × r`.
  num vol;

  /// `'easy' | 'right' | 'hard'`, or null (key deleted).
  String? rating;

  /// Trimmed, ≤ 300 chars; null when empty (key deleted).
  String? note;
  JsonMap extra;

  Workout copy() => Workout.fromJson(toJson());

  /// Orders workouts by `(d, start)` ascending (engine-Q6).
  static int compare(Workout a, Workout b) {
    final byDate = a.d.compareTo(b.d);
    return byDate != 0 ? byDate : a.start.compareTo(b.start);
  }

  @override
  JsonMap toJson() {
    final out = <String, dynamic>{
      ...deepCopyMap(extra),
      'id': id,
      'd': d,
      'start': start,
      'end': end,
      'routineId': routineId,
      'name': name,
      'bw': bw == null ? null : jsNum(bw!),
      'entries': [for (final e in entries) e.toJson()],
      'prs': [...prs],
      'vol': jsNum(vol),
    };
    putIfNotNull(out, 'rating', rating);
    putIfNotNull(out, 'note', note);
    return out;
  }
}
