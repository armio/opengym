import 'json.dart';

/// One exercise in a routine — the per-exercise plan config (`cfg`, specs/data-model.md §1.4.2).
///
/// Numeric fields are `num` because JSON has one number type and imports may carry decimals;
/// the writers (config sheet, Coach apply) keep `sets`, `reps`, `sec` and `min` integral.
class RoutineExercise implements JsonModel {
  RoutineExercise({
    required this.id,
    this.sets = 3,
    this.mode,
    this.reps,
    this.sec,
    this.min,
    this.speed,
    this.weight,
    this.prog,
    this.inc,
    this.repsMin,
    this.sg,
    JsonMap? extra,
  }) : extra = extra ?? {};

  factory RoutineExercise.fromJson(Object? json) {
    final m = asMap(json);
    return RoutineExercise(
      id: asString(m['id']) ?? '',
      sets: asInt(m['sets']) ?? asNum(m['sets'])?.round() ?? 0,
      mode: asString(m['mode']),
      reps: asNum(m['reps']),
      sec: asNum(m['sec']),
      min: asNum(m['min']),
      speed: asNum(m['speed']),
      weight: asNum(m['weight']),
      prog: asString(m['prog']),
      inc: asNum(m['inc']),
      repsMin: asNum(m['repsMin']),
      sg: asString(m['sg']),
      extra: extraOf(m, _known),
    );
  }

  static const _known = {'id', 'sets', 'mode', 'reps', 'sec', 'min', 'speed', 'weight', 'prog', 'inc', 'repsMin', 'sg'};

  /// Library id (`"0025"`) or custom exercise id.
  String id;
  int sets;

  /// `'reps'`, `'time'`, `'cardio'` or absent (then the body part decides: see `modeOf`).
  String? mode;
  num? reps;
  num? sec;
  num? min;

  /// km/h, whatever the profile unit.
  num? speed;
  num? weight;

  /// Progression policy override; absent = follow the routine.
  String? prog;
  num? inc;
  num? repsMin;

  /// Superset group id shared with the adjacent partner(s).
  String? sg;
  JsonMap extra;

  RoutineExercise copy() => RoutineExercise.fromJson(toJson());

  @override
  JsonMap toJson() {
    final out = <String, dynamic>{...deepCopyMap(extra), 'id': id, 'sets': sets};
    putIfNotNull(out, 'mode', mode);
    putIfNotNull(out, 'reps', reps);
    putIfNotNull(out, 'sec', sec);
    putIfNotNull(out, 'min', min);
    putIfNotNull(out, 'speed', speed);
    putIfNotNull(out, 'weight', weight);
    putIfNotNull(out, 'prog', prog);
    putIfNotNull(out, 'inc', inc);
    putIfNotNull(out, 'repsMin', repsMin);
    putIfNotNull(out, 'sg', sg);
    return out;
  }
}

/// A routine of the plan (specs/data-model.md §1.4.1).
class Routine implements JsonModel {
  Routine({required this.id, required this.name, this.emoji, this.prog, List<RoutineExercise>? ex, JsonMap? extra})
    : ex = ex ?? [],
      extra = extra ?? {};

  factory Routine.fromJson(Object? json) {
    final m = asMap(json);
    return Routine(
      id: asString(m['id']) ?? '',
      name: asString(m['name']) ?? '',
      emoji: asString(m['emoji']),
      prog: asString(m['prog']),
      ex: [
        for (final e in asList(m['ex']))
          if (e is Map) RoutineExercise.fromJson(e),
      ],
      extra: extraOf(m, _known),
    );
  }

  static const _known = {'id', 'name', 'emoji', 'prog', 'ex'};

  String id;
  String name;

  /// An icon key (e.g. `'barbell'`) or a legacy literal emoji — see `glyphOf`.
  String? emoji;

  /// Routine-level progression default (a reps policy).
  String? prog;
  List<RoutineExercise> ex;
  JsonMap extra;

  Routine copy() => Routine.fromJson(toJson());

  /// Drops every `sg` that no longer has an adjacent partner (`cleanupSg`, run after every
  /// move, remove or unlink). Sequential and in place, like the original.
  static void cleanupSupersets(List<RoutineExercise> ex) {
    for (var i = 0; i < ex.length; i++) {
      final sg = ex[i].sg;
      if (sg == null || sg.isEmpty) continue;
      final prev = i > 0 ? ex[i - 1].sg : null;
      final next = i + 1 < ex.length ? ex[i + 1].sg : null;
      if (prev != sg && next != sg) ex[i].sg = null;
    }
  }

  @override
  JsonMap toJson() {
    final out = <String, dynamic>{...deepCopyMap(extra), 'id': id, 'name': name};
    putIfNotNull(out, 'emoji', emoji);
    putIfNotNull(out, 'prog', prog);
    out['ex'] = [for (final e in ex) e.toJson()];
    return out;
  }
}

/// A user-created exercise, stored in the plan doc (`customEx`, contract §2.1 / data-B3).
class CustomExercise implements JsonModel {
  CustomExercise({
    required this.id,
    required this.n,
    required this.bp,
    this.desc = '',
    this.tg = '',
    this.eq = 'custom',
    this.custom = true,
    JsonMap? extra,
  }) : extra = extra ?? {};

  /// Tolerates the old plan-file shape `{id, n, bp, desc?}` (no `tg`/`eq`/`custom`).
  factory CustomExercise.fromJson(Object? json) {
    final m = asMap(json);
    return CustomExercise(
      id: asString(m['id']) ?? '',
      n: asString(m['n']) ?? '',
      bp: asString(m['bp']) ?? '',
      desc: asString(m['desc']) ?? '',
      tg: asString(m['tg']) ?? '',
      eq: asString(m['eq']) ?? 'custom',
      custom: asBool(m['custom']) ?? true,
      extra: extraOf(m, _known),
    );
  }

  static const _known = {'id', 'n', 'bp', 'desc', 'tg', 'eq', 'custom'};

  String id;

  /// Display name (trimmed as typed).
  String n;

  /// Body part — one of the library body parts.
  String bp;
  String desc;
  String tg;
  String eq;
  bool custom;
  JsonMap extra;

  CustomExercise copy() => CustomExercise.fromJson(toJson());

  /// Always the full shape `{id, n, bp, desc, tg, eq, custom}` (data-B3).
  @override
  JsonMap toJson() => {
    ...deepCopyMap(extra),
    'id': id,
    'n': n,
    'bp': bp,
    'desc': desc,
    'tg': tg,
    'eq': eq,
    'custom': custom,
  };
}

/// The `plan` doc: routines, the weekly schedule and custom exercises.
class PlanDoc implements JsonModel {
  PlanDoc({List<Routine>? routines, Map<String, String>? week, List<CustomExercise>? customEx, JsonMap? extra})
    : routines = routines ?? [],
      week = week ?? {},
      customEx = customEx ?? [],
      extra = extra ?? {};

  factory PlanDoc.fromJson(Object? json) {
    final m = asMap(json);
    return PlanDoc(
      routines: [
        for (final r in asList(m['routines']))
          if (r is Map) Routine.fromJson(r),
      ],
      week: asStringMap(m['week']),
      customEx: [
        for (final c in asList(m['customEx']))
          if (c is Map) CustomExercise.fromJson(c),
      ],
      extra: extraOf(m, _known),
    );
  }

  static const _known = {'routines', 'week', 'customEx'};

  /// Display order is array order.
  List<Routine> routines;

  /// Weekday (`'0'` = Sunday … `'6'`) → routine id; a missing key is a rest day. A key may hold
  /// the id of a routine that no longer exists.
  Map<String, String> week;
  List<CustomExercise> customEx;
  JsonMap extra;

  Routine? routineById(String? id) {
    if (id == null) return null;
    for (final r in routines) {
      if (r.id == id) return r;
    }
    return null;
  }

  CustomExercise? customById(String id) {
    for (final c in customEx) {
      if (c.id == id) return c;
    }
    return null;
  }

  PlanDoc copy() => PlanDoc.fromJson(toJson());

  @override
  JsonMap toJson() => {
    ...deepCopyMap(extra),
    'routines': [for (final r in routines) r.toJson()],
    'week': {...week},
    'customEx': [for (final c in customEx) c.toJson()],
  };
}
