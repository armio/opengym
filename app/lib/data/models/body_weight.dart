import 'json.dart';

/// One weigh-in: at most one per date (specs/data-model.md §1.7).
class BodyWeight implements JsonModel {
  BodyWeight({required this.d, required this.w, required this.t, JsonMap? extra}) : extra = extra ?? {};

  factory BodyWeight.fromJson(Object? json) {
    final m = asMap(json);
    return BodyWeight(
      d: asString(m['d']) ?? '',
      w: asNum(m['w']) ?? 0,
      t: asInt(m['t']) ?? 0,
      extra: extraOf(m, const {'d', 'w', 't'}),
    );
  }

  /// Local `'YYYY-MM-DD'`.
  String d;

  /// Weight in the profile unit, 0.1 precision.
  num w;

  /// Epoch ms of the entry.
  int t;
  JsonMap extra;

  BodyWeight copy() => BodyWeight.fromJson(toJson());

  @override
  JsonMap toJson() => {...deepCopyMap(extra), 'd': d, 'w': jsNum(w), 't': t};
}

/// The working-weight memory of one exercise: `exWeights[exId] = {w, d}` (§1.8).
class ExWeight implements JsonModel {
  ExWeight({required this.w, required this.d, JsonMap? extra}) : extra = extra ?? {};

  factory ExWeight.fromJson(Object? json) {
    final m = asMap(json);
    return ExWeight(w: asNum(m['w']) ?? 0, d: asString(m['d']) ?? '', extra: extraOf(m, const {'w', 'd'}));
  }

  num w;

  /// Local `'YYYY-MM-DD'` it was set.
  String d;
  JsonMap extra;

  ExWeight copy() => ExWeight.fromJson(toJson());

  @override
  JsonMap toJson() => {...deepCopyMap(extra), 'w': jsNum(w), 'd': d};
}
