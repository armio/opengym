/// Port of `effort.js` (specs/engine.md §6): RIR/RPE statistics. Everything aggregates in RIR
/// (it has a real zero) and converts back for display. Windows count back from `now`; a
/// date-only workout sits at local noon of its date (engine-Q7, applied when it is read).
library;

import 'dart:math';

import '../data/models/settings.dart';
import '../data/models/workout.dart';
import 'calendar.dart';
import 'history.dart';
import 'js.dart';

/// RIR ≤ 3 is a hard set.
const hardRir = 3;

/// Fewer rated sets than this and averages are null (the UI shows "—").
const minRated = 5;

/// Histogram bins 0, 1, 2, 3 and a "4+" tail.
const effortBuckets = 4;

/// A set's effort in RIR (RPE 8 = RIR 2), or null when never rated. RIR wins when both exist.
num? rirOf(SetRecord? s) {
  if (s == null) return null;
  final rir = s.rir, rpe = s.rpe;
  if (rir != null) return rir;
  return rpe != null ? normNum(10 - rpe) : null;
}

/// A RIR value on [kind]'s scale, to one decimal.
num? toScale(String kind, num? rir) => rir == null ? null : round1(kind == 'rpe' ? 10 - rir : rir);

bool isHardSet(SetRecord s) {
  final r = rirOf(s);
  return r != null && r <= hardRir;
}

/// `'RIR'` or `'RPE'`.
String scaleName(String kind) => effortScales[kind]?.label ?? 'RIR';

Iterable<SetRecord> _doneSets(Workout w) => w.entries.expand((e) => e.sets).where((s) => s.done);

/// Workouts inside the last [days] days of [now] (0 = everything); strictly newer than the cut.
Iterable<Workout> _inWindow(Iterable<Workout> workouts, int days, DateTime now) {
  if (days == 0) return workouts;
  final cutoff = now.millisecondsSinceEpoch - days * dayMs;
  return workouts.where((w) => w.start > cutoff);
}

/// The scale to label aggregates with: the profile's own, else whichever the history uses more
/// (a tie is RIR).
String displayScale(Settings? settings, Iterable<Workout> workouts) {
  final kind = effortOf(settings);
  if (kind != 'none') return kind;
  var rir = 0, rpe = 0;
  for (final s in workouts.expand(_doneSets)) {
    if (s.rir != null) {
      rir++;
    } else if (s.rpe != null) {
      rpe++;
    }
  }
  return rpe > rir ? 'rpe' : 'rir';
}

/// Mean RIR of the rated sets, or null when none is rated.
num? avgRir(Iterable<SetRecord>? sets) {
  final values = [for (final s in sets ?? const <SetRecord>[]) ?rirOf(s)];
  return values.isEmpty ? null : values.reduce((a, b) => a + b) / values.length;
}

/// Effort over a window.
class EffortSummary {
  const EffortSummary({required this.done, required this.rated, required this.hard, this.avg, this.hardPct});

  /// Done sets in the window.
  final int done;

  /// Of those, the rated ones.
  final int rated;
  final int hard;

  /// Mean RIR, or null under [minRated] rated sets.
  final num? avg;

  /// Share of rated sets at RIR ≤ 3, or null under [minRated] rated sets.
  final num? hardPct;
}

EffortSummary effortSummary(Iterable<Workout> workouts, int days, {required DateTime now}) {
  var done = 0, rated = 0, hard = 0;
  num sum = 0;
  for (final s in _inWindow(workouts, days, now).expand(_doneSets)) {
    done++;
    final r = rirOf(s);
    if (r == null) continue;
    rated++;
    sum += r;
    if (r <= hardRir) hard++;
  }
  final enough = rated >= minRated;
  return EffortSummary(
    done: done,
    rated: rated,
    hard: hard,
    avg: enough ? sum / rated : null,
    hardPct: enough ? hard / rated : null,
  );
}

/// Does any done set carry a rating? Decides whether the Effort card exists.
bool hasEffort(Iterable<Workout> workouts) => workouts.expand(_doneSets).any((s) => rirOf(s) != null);

/// Average effort of one ISO week.
class EffortWeek {
  const EffortWeek({required this.t, required this.rir, required this.n, required this.sets});

  /// Local noon of the week's Monday (epoch ms).
  final int t;
  final num rir;

  /// Rated sets.
  final int n;

  /// Done sets.
  final int sets;
}

/// Average RIR per ISO week, oldest first; weeks with fewer than 2 rated sets are dropped.
List<EffortWeek> effortWeeks(
  Iterable<Workout> workouts,
  int days, {
  required DateTime now,
  LocalCalendar calendar = deviceCalendar,
}) {
  final weeks = <String, ({int t, num sum, int n, int sets})>{};
  for (final w in _inWindow(workouts, days, now)) {
    for (final s in _doneSets(w)) {
      final key = weekKey(w.d);
      final week = weeks[key] ?? (t: calendar.noonOf(mondayOf(w.d)), sum: 0, n: 0, sets: 0);
      final r = rirOf(s);
      weeks[key] = (t: week.t, sum: week.sum + (r ?? 0), n: week.n + (r == null ? 0 : 1), sets: week.sets + 1);
    }
  }
  final kept = weeks.values.where((w) => w.n >= 2).toList()..sort((a, b) => a.t.compareTo(b.t));
  return [for (final w in kept) EffortWeek(t: w.t, rir: w.sum / w.n, n: w.n, sets: w.sets)];
}

/// One histogram bin.
class EffortBin {
  const EffortBin({required this.rir, required this.tail, required this.n, required this.pct});

  /// 0–3, or 4 for the "4+" tail.
  final int rir;
  final bool tail;
  final int n;

  /// Share of the rated sets (0 when none).
  final num pct;
}

/// Rated sets binned by whole RIR steps, everything from 4 up in the tail.
List<EffortBin> effortHistogram(Iterable<Workout> workouts, int days, {required DateTime now}) {
  final bins = List.filled(effortBuckets + 1, 0);
  var rated = 0;
  for (final s in _inWindow(workouts, days, now).expand(_doneSets)) {
    final r = rirOf(s);
    if (r == null) continue;
    rated++;
    bins[min(effortBuckets, max(0, r.floor()))]++;
  }
  return [
    for (var i = 0; i <= effortBuckets; i++)
      EffortBin(rir: i, tail: i == effortBuckets, n: bins[i], pct: rated == 0 ? 0 : bins[i] / rated),
  ];
}
