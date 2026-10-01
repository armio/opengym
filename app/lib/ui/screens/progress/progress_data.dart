/// Data preparation for the Progress tab (specs/ui.md §3.6, §3.7, §7.1): chart series and their
/// frame, weekly counts, the exercise-progress bundle and the history grouping. Pure Dart over
/// the engine, so it is unit-tested without widgets.
library;

import 'dart:math' as math;

import 'package:collection/collection.dart';

import '../../../data/dates.dart';
import '../../../data/models/models.dart';
import '../../../engine/engine.dart';

// ---------------------------------------------------------------------------------------------
// Line chart.

/// One point of a trend chart: `{t, y, d?, m?, note?}` of the original `LineChart`.
class ChartPoint {
  const ChartPoint({required this.t, required this.y, this.d, this.m, this.note});

  /// Epoch ms (the x axis).
  final int t;
  final num y;

  /// The date the tooltip names; derived from [t] when null.
  final String? d;

  /// Marker strength 0–1: a second reading carried by the dot (bigger and more solid = more).
  final double? m;

  /// Extra tooltip text.
  final String? note;
}

/// Where an x-axis label sits relative to its tick.
enum TickAnchor { start, middle, end }

/// An x-axis tick: a dashed vertical line with a label under the plot.
class ChartTick {
  const ChartTick(this.t, this.label, {this.anchor = TickAnchor.middle});

  final int t;
  final String label;
  final TickAnchor anchor;
}

/// The axes of a trend chart, computed exactly like the original (specs/ui.md §7.1): the y range
/// covers the points and the goal, padded 12 % each side; gridlines sit on multiples of a "nice"
/// step; x ticks fall on the 1st of each month, or on the start, middle and end of a short span.
class ChartFrame {
  const ChartFrame._({
    required this.t0,
    required this.t1,
    required this.yMin,
    required this.yMax,
    required this.step,
    required this.gridValues,
    required this.ticks,
  });

  factory ChartFrame.of(List<ChartPoint> points, {num? goal}) {
    assert(points.isNotEmpty, 'an empty chart has no frame');
    final t0 = points.first.t;
    final t1 = points.last.t == 0 ? t0 + 1 : points.last.t;
    var lo = points.map((p) => p.y.toDouble()).reduce(math.min);
    var hi = points.map((p) => p.y.toDouble()).reduce(math.max);
    if (goal != null && goal.isFinite) {
      lo = math.min(lo, goal.toDouble());
      hi = math.max(hi, goal.toDouble());
    }
    if (lo == hi) {
      lo -= 1;
      hi += 1;
    }
    final pad = (hi - lo) * .12;
    lo -= pad;
    hi += pad;
    final step = niceStep((hi - lo) / 3);
    final grid = [for (var k = (lo / step).ceil(); k * step <= hi + 1e-9; k++) _clean(k * step)];
    return ChartFrame._(
      t0: t0,
      t1: t1,
      yMin: lo,
      yMax: hi,
      step: step,
      gridValues: grid,
      ticks: _ticks(t0, t1, single: points.length == 1),
    );
  }

  final int t0;
  final int t1;
  final double yMin;
  final double yMax;

  /// Gridline spacing.
  final double step;
  final List<double> gridValues;
  final List<ChartTick> ticks;

  /// [t] as a share of the time span; a zero span (one point) sits in the middle.
  double xFraction(int t) => t1 == t0 ? .5 : (t - t0) / (t1 - t0);

  /// [y] as a share of the value range, 0 at [yMin].
  double yFraction(num y) => (y - yMin) / (yMax - yMin);

  /// The first of `1, 2, 2.5, 5, 10 × 10ⁿ` that is at least [raw].
  static double niceStep(double raw) {
    final pow = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    for (final m in const [1, 2, 2.5, 5, 10]) {
      if (raw <= m * pow) return m * pow;
    }
    return 10 * pow;
  }

  /// Strips floating-point dust (`0.30000000000000004` → `0.3`).
  static double _clean(double v) => double.parse(v.toStringAsFixed(6));

  static List<ChartTick> _ticks(int t0, int t1, {required bool single}) {
    final first = DateTime.fromMillisecondsSinceEpoch(t0);
    final last = DateTime.fromMillisecondsSinceEpoch(t1);
    final ticks = <ChartTick>[];
    for (var m = DateTime(first.year, first.month + 1); !m.isAfter(last); m = DateTime(m.year, m.month + 1)) {
      ticks.add(ChartTick(m.millisecondsSinceEpoch, monthNamesShort[m.month - 1]));
    }
    if (ticks.isEmpty && !single) {
      for (var i = 0; i <= 2; i++) {
        final t = t0 + ((t1 - t0) * i / 2).round();
        final d = DateTime.fromMillisecondsSinceEpoch(t);
        final anchor = i == 0 ? TickAnchor.start : (i == 2 ? TickAnchor.end : TickAnchor.middle);
        ticks.add(ChartTick(t, '${d.day} ${monthNamesShort[d.month - 1]}', anchor: anchor));
      }
    }
    final every = math.max(1, (ticks.length / 7).ceil());
    return [for (var i = 0; i < ticks.length; i += every) ticks[i]];
  }
}

// ---------------------------------------------------------------------------------------------
// Body weight.

/// The weigh-ins of the last [days] days (0 = all) as chart points, oldest first.
List<ChartPoint> bodyWeightPoints(
  List<BodyWeight> entries,
  int days, {
  required DateTime now,
  LocalCalendar calendar = deviceCalendar,
}) => [
  for (final b in bodyWeightsWithinDays(entries, days, now: now, calendar: calendar))
    ChartPoint(
      t: weighInTime(b, calendar: calendar),
      y: b.w,
      d: b.d,
    ),
];

/// The change across a list of weigh-ins (last minus first), or null with fewer than two.
num? weightChange(List<ChartPoint> points) => points.length < 2 ? null : round1(points.last.y - points.first.y);

/// One weigh-in of the log with its change since the previous one.
class WeighIn {
  const WeighIn(this.entry, this.change);

  final BodyWeight entry;

  /// Versus the previous weigh-in; null for the first.
  final num? change;
}

/// The weigh-ins newest first, each with its change since the one before.
List<WeighIn> weighInLog(List<BodyWeight> entries) => [
  for (var i = entries.length - 1; i >= 0; i--)
    WeighIn(entries[i], i == 0 ? null : round1(entries[i].w - entries[i - 1].w)),
];

// ---------------------------------------------------------------------------------------------
// Summary.

/// Workouts started in one ISO week.
class WeekCount {
  const WeekCount(this.monday, this.count);

  /// The week's Monday, `'YYYY-MM-DD'`.
  final String monday;
  final int count;
}

/// Workouts per ISO week for the [weeks] weeks ending with the current one, oldest first.
List<WeekCount> weeklyCounts(
  Iterable<Workout> workouts, {
  required DateTime now,
  int weeks = 12,
  LocalCalendar calendar = deviceCalendar,
}) {
  final current = mondayOf(calendar.today(now));
  final mondays = [for (var i = weeks - 1; i >= 0; i--) addDays(current, -7 * i)];
  final counts = <String, int>{};
  for (final w in workouts) {
    if (!isIsoDate(w.d)) continue;
    final monday = mondayOf(w.d);
    counts[monday] = (counts[monday] ?? 0) + 1;
  }
  return [for (final m in mondays) WeekCount(m, counts[m] ?? 0)];
}

/// Σ `vol` over [workouts].
num totalVolume(Iterable<Workout> workouts) => workouts.fold<num>(0, (a, w) => a + w.vol);

/// Σ session time over [workouts] (imports without a clock add nothing), in ms.
int totalDuration(Iterable<Workout> workouts) => workouts.fold<int>(0, (a, w) => a + math.max(0, w.end - w.start));

// ---------------------------------------------------------------------------------------------
// Exercise progress.

/// What the exercise curve shows.
enum ExerciseMetric { top, e1rm, effort }

/// Everything the exercise-progress view reads for one exercise (specs/ui.md §3.6, engine.md
/// §8.4): the top-set curve in the mode it was logged in last, the e1RM curve, effort per session
/// and the records.
class ExerciseProgress {
  ExerciseProgress._({
    required this.exId,
    required this.mode,
    required this.sessions,
    required this.e1rm,
    required this.best1rm,
    required this.bestLoad,
  });

  /// [state] must hold the workouts in `(d, start)` order (as `AppState.workouts` gives them).
  factory ExerciseProgress.of(TrainingState state, String exId) {
    final mode = latestModeOf(state, exId);
    return ExerciseProgress._(
      exId: exId,
      mode: mode,
      sessions: progressSeries(state, exId, mode),
      e1rm: e1rmSeries(state.workouts, exId),
      best1rm: best1RM(state.workouts, exId),
      bestLoad: bestWeightFor(state, exId),
    );
  }

  final String exId;

  /// How it was logged most recently: `reps`, `time` or `cardio`.
  final String mode;

  /// One point per workout with a positive metric, oldest first.
  final List<ProgressPoint> sessions;
  final List<E1rmPoint> e1rm;
  final BestEstimate? best1rm;

  /// The heaviest load in reps mode (engine-Q5); 0 when never loaded.
  final num bestLoad;

  /// The best top-set value (`exBest`): top weight, longest hold or top speed.
  num get bestTop => sessions.fold<num>(0, (a, p) => math.max(a, p.y));

  bool get hasE1rm => e1rm.isNotEmpty;

  /// The effort curve needs at least three rated sessions.
  bool get hasEffort => sessions.where((p) => p.avgRir != null).length >= 3;

  List<ExerciseMetric> get metrics => [
    ExerciseMetric.top,
    if (hasE1rm) ExerciseMetric.e1rm,
    if (hasEffort) ExerciseMetric.effort,
  ];

  /// [wanted], or the top set when it is not available for this exercise.
  ExerciseMetric resolve(ExerciseMetric wanted) => metrics.contains(wanted) ? wanted : ExerciseMetric.top;

  /// The unit of the top-set curve.
  String unitFor(String weightUnit) => switch (mode) {
    ExerciseMode.cardio => 'km/h',
    ExerciseMode.time => 's',
    _ => weightUnit,
  };

  /// The top-set curve; a rated session carries a marker (fuller = less left in the tank) and
  /// its effort in the tooltip.
  List<ChartPoint> topPoints(String effortKind) => [
    for (final p in sessions)
      ChartPoint(
        t: p.t,
        y: p.y,
        d: p.d,
        m: p.avgRir == null ? null : 1 - math.min(4, math.max(0, p.avgRir!)) / 4,
        note: p.avgRir == null ? null : '${scaleName(effortKind)} ${fmtNum(toScale(effortKind, p.avgRir)!)}',
      ),
  ];

  List<ChartPoint> get e1rmPoints => [for (final p in e1rm) ChartPoint(t: p.t, y: p.y, d: p.d)];

  List<ChartPoint> effortPoints(String effortKind) => [
    for (final p in sessions)
      if (p.avgRir != null) ChartPoint(t: p.t, y: toScale(effortKind, p.avgRir)!, d: p.d),
  ];

  /// The last five sessions, newest first.
  List<ProgressPoint> get recent => sessions.reversed.take(5).toList();
}

// ---------------------------------------------------------------------------------------------
// History.

/// The workouts of one calendar month.
class WorkoutMonth {
  const WorkoutMonth(this.key, this.workouts);

  /// `'YYYY-MM'`.
  final String key;

  /// Newest first.
  final List<Workout> workouts;

  /// `"Septiembre 2026"`.
  String get label {
    final month = int.tryParse(key.length >= 7 ? key.substring(5, 7) : '') ?? 0;
    final year = key.length >= 4 ? key.substring(0, 4) : key;
    return month >= 1 && month <= 12 ? '${monthNames[month - 1]} $year' : key;
  }
}

/// Every workout newest first by `(d, start)`, grouped by month.
List<WorkoutMonth> workoutsByMonth(Iterable<Workout> workouts) {
  final newest = [...workouts]..sort((a, b) => Workout.compare(b, a));
  final months = <WorkoutMonth>[];
  for (final w in newest) {
    final key = w.d.length >= 7 ? w.d.substring(0, 7) : w.d;
    if (months.isEmpty || months.last.key != key) months.add(WorkoutMonth(key, []));
    months.last.workouts.add(w);
  }
  return months;
}

/// The last [n] workouts, newest first.
List<Workout> recentWorkouts(List<Workout> workouts, [int n = 6]) => workouts.reversed.take(n).toList();

/// `"1 entrenamiento"`, `"3 entrenamientos"`.
String workoutCount(int n) => n == 1 ? '1 entrenamiento' : '$n entrenamientos';

/// How a session felt (`Workout.rating`) in Spanish.
const ratingLabels = {'easy': 'Muy fácil', 'right': 'Bien', 'hard': 'Brutal'};

/// The rating's icon.
const ratingIcons = {'easy': 'arrowDown', 'right': 'check', 'hard': 'flame'};

/// `"60×10 (RIR 2)  ·  62,5×8"` — the done sets of an entry, or "sin series".
String doneSetsLine(ExerciseIndex catalog, WorkoutEntry entry, {String separator = '  ·  '}) {
  final labels = [for (final s in entry.doneSets) setLabel(catalog, entry.id, s, entry.targetConfig)];
  return labels.isEmpty ? 'sin series' : joinSetLabels(labels, separator);
}

/// Joins set labels so a line only ever breaks between sets, never inside one.
String joinSetLabels(Iterable<String> labels, [String separator = '  ']) =>
    labels.map((l) => l.replaceAll(' ', '\u00A0')).join(separator);

/// The entry of [exId] in [workout], if any.
WorkoutEntry? entryOf(Workout workout, String exId) => workout.entries.firstWhereOrNull((e) => e.id == exId);
