/// Port of `onerm.js` (specs/engine.md §5): estimated one-rep max. Only reps-mode sets carry
/// both a weight and a rep count, so timed and cardio sets drop out on their own.
library;

import 'dart:math';

import 'package:collection/collection.dart';

import '../data/models/workout.dart';
import 'js.dart';

/// Above this many reps an estimate says more about work capacity than maximal strength.
const repCap = 12;

/// The estimate formulas by name.
final Map<String, num Function(num w, num r)> formulas = {
  'epley': (w, r) => w * (1 + r / 30),
  'brzycki': (w, r) => w * 36 / (37 - r),
  'lombardi': (w, r) => w * pow(r, 0.1),
};

const defaultFormula = 'epley';

/// `Number(x)`: numeric strings parse, `''` and null are 0, junk is NaN.
num jsToNumber(Object? value) => switch (value) {
  null => 0,
  num n => n,
  bool b => b ? 1 : 0,
  String s => s.trim().isEmpty ? 0 : (num.tryParse(s.trim()) ?? double.nan),
  _ => double.nan,
};

/// The estimate from one set, to one decimal; null for anything it cannot honestly answer
/// (no weight, under one rep, over [repCap] reps). A single rep is the measurement itself;
/// fractional reps are rounded for the formula. An unknown formula is Epley.
num? estimate1RM(Object? w, Object? r, [String formula = defaultFormula]) {
  final weight = jsToNumber(w), reps = jsToNumber(r);
  if (!weight.isFinite || !reps.isFinite) return null;
  if (weight <= 0 || reps < 1 || reps > repCap) return null;
  final fn = formulas[formula] ?? formulas[defaultFormula]!;
  final est = reps == 1 ? weight : fn(weight, jsRound(reps));
  if (!est.isFinite || est <= 0) return null;
  return round1(est);
}

/// The set behind an estimate.
class BestSet {
  const BestSet({required this.est, required this.w, required this.r});

  final num est;
  final num w;
  final num r;
}

/// The done set with the highest estimate (the first wins ties); `topW` has no reps and is
/// ignored. Null when no set yields an estimate.
BestSet? bestSetOf(List<SetRecord>? sets, [String formula = defaultFormula]) {
  BestSet? best;
  for (final s in sets ?? const <SetRecord>[]) {
    if (!s.done) continue;
    final est = estimate1RM(s.w, s.r, formula);
    if (est != null && (best == null || est > best.est)) {
      best = BestSet(est: est, w: jsToNumber(s.w), r: normNum(jsRound(jsToNumber(s.r))));
    }
  }
  return best;
}

/// One point of the e1RM curve.
class E1rmPoint {
  const E1rmPoint({required this.t, required this.d, required this.y, required this.w, required this.r});

  /// The workout's `start`.
  final int t;
  final String d;
  final num y;
  final num w;
  final num r;
}

/// One point per workout whose first entry of [exId] produced an estimate, in workout order.
List<E1rmPoint> e1rmSeries(Iterable<Workout> workouts, String exId, [String formula = defaultFormula]) => [
  for (final w in workouts)
    if (bestSetOf(w.entries.firstWhereOrNull((e) => e.id == exId)?.sets, formula) case final best?)
      E1rmPoint(t: w.start, d: w.d, y: best.est, w: best.w, r: best.r),
];

/// The all-time best estimate with the set and date behind it.
class BestEstimate extends BestSet {
  const BestEstimate({required super.est, required super.w, required super.r, required this.d, required this.t});

  final String d;
  final int t;
}

/// The all-time best estimate of [exId]; the earliest wins ties. Null when there is none.
BestEstimate? best1RM(Iterable<Workout> workouts, String exId, [String formula = defaultFormula]) {
  BestEstimate? best;
  for (final p in e1rmSeries(workouts, exId, formula)) {
    if (best == null || p.y > best.est) best = BestEstimate(est: p.y, w: p.w, r: p.r, d: p.d, t: p.t);
  }
  return best;
}

/// An estimate that beats every earlier one, with the previous best (0 for the first ever).
class OneRmRecord extends BestSet {
  const OneRmRecord({required super.est, required super.w, required super.r, required this.prev});

  final num prev;
}

/// Whether [sets] beat every estimate in [history] (which must not contain them yet).
OneRmRecord? is1RMRecord(
  Iterable<Workout> history,
  String exId,
  List<SetRecord> sets, [
  String formula = defaultFormula,
]) {
  final now = bestSetOf(sets, formula);
  if (now == null) return null;
  final prev = best1RM(history, exId, formula);
  if (prev != null && now.est <= prev.est) return null;
  return OneRmRecord(est: now.est, w: now.w, r: now.r, prev: prev?.est ?? 0);
}
