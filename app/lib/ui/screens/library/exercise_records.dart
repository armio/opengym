/// What the training log says about one exercise — its best load, its last session and its
/// best estimated 1RM — for the library list and the exercise detail sheet.
///
/// These follow the engine rules (specs/engine.md §2.7, §2.11, §2.12 with engine-Q5, §5 and
/// engine-Q6 ordering). They are kept local to the library until `lib/engine` lands; then
/// they should delegate to it.
library;

import 'dart:math' as math;

import '../../../data/models/models.dart';
import '../../widgets/formatting.dart';

/// `modeOf(cfg)`: an explicit `reps` / `time` / `cardio` mode wins; otherwise cardio exercises
/// log cardio and everything else logs reps.
String modeOf(String? mode, {required bool cardio}) {
  if (mode == 'reps' || mode == 'time' || mode == 'cardio') return mode!;
  return cardio ? 'cardio' : 'reps';
}

/// The best load of every exercise (`bestWeightFor`): the heaviest done-set `w` or `topW`
/// over the entries logged in reps mode (engine-Q5). Exercises without one are absent.
Map<String, num> bestWeights(Iterable<Workout> workouts, {required bool Function(String id) isCardio}) {
  final best = <String, num>{};
  for (final w in workouts) {
    for (final e in w.entries) {
      if (modeOf(asString(e.target?['mode']), cardio: isCardio(e.id)) != 'reps') continue;
      var top = best[e.id] ?? 0;
      for (final s in e.sets) {
        final load = s.w;
        if (s.done && load != null && load > top) top = load;
      }
      final confirmed = e.topW;
      if (confirmed != null && confirmed > top) top = confirmed;
      if (top > 0) best[e.id] = top;
    }
  }
  return best;
}

/// The done sets of an exercise's most recent session (`lastEntryFor`).
class LastSession {
  const LastSession({required this.d, required this.sets, this.mode});

  final String d;
  final List<SetRecord> sets;

  /// The mode the session prescribed (`target.mode`), when recorded.
  final String? mode;
}

/// The latest workout (in `(d, start)` order) whose first entry for [exId] has a done set.
LastSession? lastSessionFor(List<Workout> workouts, String exId) {
  for (final w in workouts.reversed) {
    for (final e in w.entries) {
      if (e.id != exId) continue;
      final done = e.doneSets.toList();
      if (done.isNotEmpty) return LastSession(d: w.d, sets: done, mode: asString(e.target?['mode']));
      break;
    }
  }
  return null;
}

/// `fmtSec`: `m:ss` of a duration in seconds (`90` → `"1:30"`), never negative.
String formatSeconds(num? sec) {
  final n = math.max(0, (sec ?? 0).round());
  return '${n ~/ 60}:${(n % 60).toString().padLeft(2, '0')}';
}

/// `setLabel`: `"60×10 (RIR 2)"`, `"1:30 · 20"` or `"20 min @ 9 km/h"` depending on [mode].
String setLabel(SetRecord s, String mode) => switch (mode) {
  'cardio' => '${formatNum(s.min ?? 0)} min @ ${formatNum(s.speed ?? 0)} km/h',
  'time' => formatSeconds(s.sec) + ((s.w ?? 0) > 0 ? ' · ${formatNum(s.w!)}' : ''),
  _ => '${formatNum(s.w ?? 0)}×${s.r ?? 0}${_effortTail(s)}',
};

String _effortTail(SetRecord s) {
  if (s.rir != null) return ' (RIR ${formatNum(s.rir!)})';
  if (s.rpe != null) return ' (RPE ${formatNum(s.rpe!)})';
  return '';
}

/// Above this many reps an estimated max is guesswork (`REP_CAP`).
const oneRepMaxRepCap = 12;

/// `estimate1RM` with the Epley formula: null without a positive load, for fewer than 1 or
/// more than [oneRepMaxRepCap] reps; exactly one rep is the load itself. Rounded to 0.1.
num? estimateOneRepMax(num? w, num? r) {
  if (w == null || r == null || !w.isFinite || !r.isFinite) return null;
  if (w <= 0 || r < 1 || r > oneRepMaxRepCap) return null;
  final est = r == 1 ? w : w * (1 + r.round() / 30);
  if (!est.isFinite || est <= 0) return null;
  return jsNum((est * 10).round() / 10);
}

/// The set behind an exercise's best estimated 1RM.
class OneRepMaxRecord {
  const OneRepMaxRecord({required this.est, required this.w, required this.r, required this.d});

  final num est;
  final num w;
  final int r;
  final String d;
}

/// `best1RM`: the highest estimate over the first entry for [exId] of each workout, in
/// `(d, start)` order; the earliest wins ties.
OneRepMaxRecord? bestOneRepMax(List<Workout> workouts, String exId) {
  OneRepMaxRecord? best;
  for (final w in workouts) {
    final entry = w.entries.where((e) => e.id == exId).firstOrNull;
    if (entry == null) continue;
    for (final s in entry.doneSets) {
      final est = estimateOneRepMax(s.w, s.r);
      if (est != null && (best == null || est > best.est)) {
        best = OneRepMaxRecord(est: est, w: s.w!, r: s.r!.round(), d: w.d);
      }
    }
  }
  return best;
}
