/// The Stats and Home computations that lived in view code (specs/engine.md §8.3–§8.4,
/// specs/ui.md §3.2, §3.6, §7.2): the activity heatmap, analysis windows, tiles, the week strip
/// and exercise progress.
library;

import 'dart:math';

import 'package:collection/collection.dart';

import '../data/dates.dart';
import '../data/models/body_weight.dart';
import '../data/models/plan.dart';
import '../data/models/schedule.dart';
import '../data/models/workout.dart';
import 'calendar.dart';
import 'effort.dart';
import 'history.dart';
import 'js.dart';
import 'training_state.dart';

// ---------------------------------------------------------------------------------------------
// Activity heatmap (last 12 months, shaded by minutes trained).

/// What one date holds.
class HeatmapDay {
  const HeatmapDay({required this.workouts, required this.volume, required this.minutes});

  final int workouts;
  final num volume;

  /// Minutes trained (a session imported without a clock adds 0).
  final int minutes;
}

/// Per-date totals of [workouts].
Map<String, HeatmapDay> heatmapDays(Iterable<Workout> workouts) {
  final days = <String, HeatmapDay>{};
  for (final w in workouts) {
    final day = days[w.d];
    final minutes = max(0, jsRound((w.end - w.start) / 60000)).toInt();
    days[w.d] = HeatmapDay(
      workouts: (day?.workouts ?? 0) + 1,
      volume: (day?.volume ?? 0) + w.vol,
      minutes: (day?.minutes ?? 0) + minutes,
    );
  }
  return days;
}

/// Shade thresholds: quartiles of the owner's own positive-minute days.
class HeatmapScale {
  const HeatmapScale(this.t1, this.t2, this.t3);

  factory HeatmapScale.fromMinutes(Iterable<num> minutes) {
    final sorted = minutes.where((m) => m > 0).toList()..sort();
    num q(double p) => sorted.isEmpty ? 0 : sorted[min(sorted.length - 1, (p * sorted.length).floor())];
    return HeatmapScale(q(.25), q(.5), q(.75));
  }

  factory HeatmapScale.of(Map<String, HeatmapDay> days) => HeatmapScale.fromMinutes(days.values.map((d) => d.minutes));

  final num t1;
  final num t2;
  final num t3;

  /// 0 without a workout; 1 for a workout day without minutes; else 1–4 by quartile.
  int levelOf(HeatmapDay? day) {
    if (day == null) return 0;
    final m = day.minutes;
    if (m == 0) return 1;
    if (m >= t3) return 4;
    if (m >= t2) return 3;
    if (m >= t1) return 2;
    return 1;
  }
}

/// The heatmap's calendar: 53 Monday-to-Sunday columns ending with the current week.
class HeatmapGrid {
  const HeatmapGrid({required this.weeks, required this.monthLabels, required this.today});

  /// Oldest first; each holds the 7 dates Monday → Sunday.
  final List<List<String>> weeks;

  /// The month (1–12) labelled above each column, or null.
  final List<int?> monthLabels;
  final String today;

  bool isFuture(String iso) => iso.compareTo(today) > 0;
}

HeatmapGrid heatmapGrid({required DateTime now, LocalCalendar calendar = deviceCalendar}) {
  final today = calendar.today(now);
  final start = addDays(mondayOf(today), -52 * 7);
  final weeks = <List<String>>[];
  final labels = <int?>[];
  int? lastMonth;
  for (var wk = 0; wk <= 52; wk++) {
    final first = addDays(start, wk * 7);
    final date = parseIsoDate(first)!;
    final opensMonth = date.day <= 7;
    labels.add(opensMonth && date.month != lastMonth && wk < 51 ? date.month : null);
    if (opensMonth) lastMonth = date.month;
    weeks.add([for (var d = 0; d < 7; d++) addDays(first, d)]);
  }
  return HeatmapGrid(weeks: weeks, monthLabels: labels, today: today);
}

// ---------------------------------------------------------------------------------------------
// Windows.

/// Workouts started strictly within the last [days] days of [now]; 0 keeps everything.
List<Workout> workoutsWithinDays(Iterable<Workout> workouts, int days, {required DateTime now}) {
  if (days == 0) return [...workouts];
  final cutoff = now.millisecondsSinceEpoch - days * dayMs;
  return [
    for (final w in workouts)
      if (w.start > cutoff) w,
  ];
}

/// The Muscle balance window: 7 is the **current ISO week** (not the last 7 days), 30 and 90 roll
/// back from [now], 0 is everything.
List<Workout> muscleBalanceWorkouts(
  Iterable<Workout> workouts,
  int window, {
  required DateTime now,
  LocalCalendar calendar = deviceCalendar,
}) {
  if (window != 7) return workoutsWithinDays(workouts, window, now: now);
  final week = weekKey(calendar.today(now));
  return [
    for (final w in workouts)
      if (isIsoDate(w.d) && weekKey(w.d) == week) w,
  ];
}

/// Does the window hold a done hard set? Only then is the "hard sets" map offered.
bool hasHardSets(Iterable<Workout> workouts) =>
    workouts.any((w) => w.entries.any((e) => e.sets.any((s) => s.done && isHardSet(s))));

/// The instant of a weigh-in (`t`, else local noon of its date).
int weighInTime(BodyWeight b, {LocalCalendar calendar = deviceCalendar}) => b.t != 0 ? b.t : calendar.noonOf(b.d);

/// Weigh-ins (sorted by date) within the last [days] days of [now]; 0 keeps everything.
List<BodyWeight> bodyWeightsWithinDays(
  Iterable<BodyWeight> entries,
  int days, {
  required DateTime now,
  LocalCalendar calendar = deviceCalendar,
}) {
  if (days == 0) return [...entries];
  final cutoff = now.millisecondsSinceEpoch - days * dayMs;
  return [
    for (final b in entries)
      if (weighInTime(b, calendar: calendar) > cutoff) b,
  ];
}

// ---------------------------------------------------------------------------------------------
// Tiles and Home.

/// The four Stats tiles.
class StatsTiles {
  const StatsTiles({required this.workouts, required this.thisMonth, required this.streakWeeks, this.weightChange30d});

  final int workouts;

  /// Workouts in the current calendar month.
  final int thisMonth;
  final int streakWeeks;

  /// Last minus first weigh-in of the last 30 days; null with fewer than two.
  final num? weightChange30d;
}

StatsTiles statsTiles(
  List<Workout> workouts,
  List<BodyWeight> bodyWeights, {
  required DateTime now,
  LocalCalendar calendar = deviceCalendar,
}) {
  final month = calendar.today(now).substring(0, 7);
  final recent = bodyWeightsWithinDays(bodyWeights, 30, now: now, calendar: calendar);
  return StatsTiles(
    workouts: workouts.length,
    thisMonth: workouts.where((w) => w.d.startsWith(month)).length,
    streakWeeks: streakWeeks(workouts, now: now, calendar: calendar),
    weightChange30d: recent.length > 1 ? normNum(recent.last.w - recent.first.w) : null,
  );
}

/// Workouts in the ISO week of [now].
int workoutsThisWeek(Iterable<Workout> workouts, {required DateTime now, LocalCalendar calendar = deviceCalendar}) {
  final week = weekKey(calendar.today(now));
  return workouts.where((w) => isIsoDate(w.d) && weekKey(w.d) == week).length;
}

/// Training days in the weekly plan.
int plannedPerWeek(PlanDoc plan) => plan.week.values.where((id) => id.isNotEmpty).length;

/// The Monday → Sunday dates of the week containing [iso].
List<String> weekDates(String iso) {
  final monday = mondayOf(iso);
  return [for (var d = 0; d < 7; d++) addDays(monday, d)];
}

/// The dot under a day of the Home week strip.
enum DayMark {
  none,

  /// A routine is planned by the weekly schedule.
  planned,

  /// The day was rescheduled to a routine.
  rescheduled,

  /// A workout was logged that day.
  done,
}

DayMark dayMark(
  String iso, {
  required Iterable<Workout> workouts,
  required PlanDoc plan,
  required ScheduleDoc schedule,
}) {
  if (workouts.any((w) => w.d == iso)) return DayMark.done;
  final planned = effectiveRoutineId(plan, schedule, iso) != null;
  if (!planned) return DayMark.none;
  return schedule.dayPlan.containsKey(iso) ? DayMark.rescheduled : DayMark.planned;
}

// ---------------------------------------------------------------------------------------------
// Exercise progress.

/// Exercises that appear in any workout and still resolve (library or existing custom), by name.
List<String> progressExercises(TrainingState state) {
  final ids = <String>{
    for (final w in state.workouts)
      for (final e in w.entries)
        if (state.catalog.lookup(e.id) != null) e.id,
  }.toList();
  return ids..sort((a, b) => state.catalog.nameOf(a).compareTo(state.catalog.nameOf(b)));
}

/// How [exId] was logged most recently: it decides what its curve means.
String latestModeOf(TrainingState state, String exId) {
  for (final w in state.workouts.reversed) {
    final entry = w.entries.firstWhereOrNull((e) => e.id == exId);
    if (entry != null) return targetModeOf(state.catalog, entry.target, exId);
  }
  return modeFor(state.catalog, id: exId);
}

/// One session on the exercise-progress curve.
class ProgressPoint {
  const ProgressPoint({
    required this.t,
    required this.d,
    required this.y,
    required this.sets,
    this.target,
    this.avgRir,
  });

  /// The workout's start.
  final int t;
  final String d;

  /// Top weight, longest hold or top speed, by [latestModeOf].
  final num y;

  /// The session's done sets.
  final List<SetRecord> sets;

  /// The session's stored target, for `setLabel`.
  final Map<String, dynamic>? target;

  /// Mean RIR of the rated sets, or null.
  final num? avgRir;
}

/// The top-set curve of [exId] in workout order: per workout, the best of the done sets' metric
/// for [mode] (speed, seconds or weight — reps also count a confirmed `topW`); sessions scoring 0
/// are left out. The last five, newest first, are the session list under the chart.
List<ProgressPoint> progressSeries(TrainingState state, String exId, String mode) {
  num metric(SetRecord s) => switch (mode) {
    ExerciseMode.cardio => s.speed ?? 0,
    ExerciseMode.time => s.sec ?? 0,
    _ => s.w ?? 0,
  };
  final points = <ProgressPoint>[];
  for (final w in state.workouts) {
    final entry = w.entries.firstWhereOrNull((e) => e.id == exId);
    if (entry == null) continue;
    final done = [...entry.sets.where((s) => s.done)];
    final y = done.map(metric).fold<num>(mode == ExerciseMode.reps ? (entry.topW ?? 0) : 0, max);
    if (y > 0) {
      points.add(ProgressPoint(t: w.start, d: w.d, y: y, sets: done, target: entry.target, avgRir: avgRir(done)));
    }
  }
  return points;
}
