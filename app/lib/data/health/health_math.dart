import 'dart:math' as math;

import '../dates.dart';
import 'health_bridge.dart';

/// Pure helpers behind the Apple Health sync: unit conversion, the workout calorie estimate and
/// the daily recovery summaries uploaded to the server (contract §8).

const kgPerLb = 0.45359237;

/// [w] in the owner's [unit] → kg.
double toKg(num w, String unit) => unit == 'lb' ? w * kgPerLb : w.toDouble();

/// [kg] → the owner's [unit], rounded to 0.1 like every weigh-in.
double fromKg(double kg, String unit) => ((unit == 'lb' ? kg / kgPerLb : kg) * 10).round() / 10;

/// Strength training at moderate effort is about 3.5 MET; Apple Health's "active" energy leaves
/// out the resting 1 MET. Sessions longer than 3 h (a workout left running) count as 3 h.
int? estimateActiveKcal({required int durationMs, required double? bodyKg}) {
  if (bodyKg == null || bodyKg <= 0 || durationMs <= 0) return null;
  final hours = math.min(durationMs, const Duration(hours: 3).inMilliseconds) / Duration.millisecondsPerHour;
  return (2.5 * bodyKg * hours).round();
}

/// The local date after [iso] (DST-safe: built from calendar fields, at noon).
String nextIsoDate(String iso) {
  final d = parseIsoDate(iso)!;
  return isoDate(DateTime(d.year, d.month, d.day + 1, 12));
}

/// [iso] moved by [days] calendar days.
String addIsoDays(String iso, int days) {
  final d = parseIsoDate(iso)!;
  return isoDate(DateTime(d.year, d.month, d.day + days, 12));
}

/// Local midnight starting [iso].
DateTime startOfIsoDate(String iso) {
  final d = parseIsoDate(iso)!;
  return DateTime(d.year, d.month, d.day);
}

/// Mean value per local date of each reading's start.
Map<String, double> dailyMeans(Iterable<HealthReading> readings) {
  final sums = <String, (double, int)>{};
  for (final r in readings) {
    final d = isoDate(r.start);
    final (sum, n) = sums[d] ?? (0.0, 0);
    sums[d] = (sum + r.value, n + 1);
  }
  return {for (final e in sums.entries) e.key: e.value.$1 / e.value.$2};
}

/// The "sleep day" an instant belongs to: the 24 h that end at 18:00 local on that date, so a
/// night counts toward the morning it ends and an afternoon nap toward the same day.
String sleepDayOf(DateTime t) {
  final l = t.toLocal();
  return l.hour >= 18 ? isoDate(DateTime(l.year, l.month, l.day + 1, 12)) : isoDate(l);
}

/// Minutes covered by the union of [intervals] (overlaps — iPhone and Watch both recording the
/// same night — count once).
int unionMinutes(Iterable<(DateTime, DateTime)> intervals) {
  final sorted = intervals.where((i) => i.$2.isAfter(i.$1)).toList()..sort((a, b) => a.$1.compareTo(b.$1));
  var totalMs = 0;
  DateTime? start;
  DateTime? end;
  for (final (s, e) in sorted) {
    if (end == null || s.isAfter(end)) {
      if (start != null) totalMs += end!.difference(start).inMilliseconds;
      start = s;
      end = e;
    } else if (e.isAfter(end)) {
      end = e;
    }
  }
  if (start != null) totalMs += end!.difference(start).inMilliseconds;
  return (totalMs / Duration.millisecondsPerMinute).round();
}

/// Sleep per sleep day: minutes asleep (any asleep stage) and in bed (any stage at all). Each
/// segment counts toward the sleep day of its midpoint. Days without an asleep stage have
/// `asleep == null` (an iPhone alone only records time in bed).
Map<String, ({int? asleep, int inBed})> sleepByDay(Iterable<SleepSegment> segments) {
  final byDay = <String, List<SleepSegment>>{};
  for (final s in segments) {
    final mid = s.start.add(Duration(milliseconds: s.end.difference(s.start).inMilliseconds ~/ 2));
    byDay.putIfAbsent(sleepDayOf(mid), () => []).add(s);
  }
  return {
    for (final e in byDay.entries)
      e.key: (
        asleep: e.value.any((s) => s.stage == SleepStage.asleep)
            ? unionMinutes([
                for (final s in e.value)
                  if (s.stage == SleepStage.asleep) (s.start, s.end),
              ])
            : null,
        inBed: unionMinutes([for (final s in e.value) (s.start, s.end)]),
      ),
  };
}

/// One day of `POST /api/recovery`.
class RecoveryDayData {
  const RecoveryDayData({required this.d, this.rhr, this.hrv, this.sleepMin, this.inBedMin});

  final String d;
  final double? rhr;
  final double? hrv;
  final int? sleepMin;
  final int? inBedMin;

  bool get isEmpty => rhr == null && hrv == null && sleepMin == null && inBedMin == null;

  Map<String, dynamic> toJson() => {
    'd': d,
    if (rhr != null) 'rhr': (rhr! * 10).round() / 10,
    if (hrv != null) 'hrv': (hrv! * 10).round() / 10,
    'sleepMin': ?sleepMin,
    'inBedMin': ?inBedMin,
  };
}

/// Every date from [from] to [to] (inclusive), with whatever Apple Health has for it. Empty days
/// are kept: uploading them deletes stale days on the server. Values outside what the server
/// accepts (a sensor glitch) are dropped.
List<RecoveryDayData> buildRecoveryDays({
  required String from,
  required String to,
  required Iterable<HealthReading> restingHeartRate,
  required Iterable<HealthReading> heartRateVariability,
  required Iterable<SleepSegment> sleep,
}) {
  final rhr = dailyMeans(restingHeartRate);
  final hrv = dailyMeans(heartRateVariability);
  final nights = sleepByDay(sleep);
  double? within(double? v, double min, double max) => v == null || v < min || v > max ? null : v;
  final out = <RecoveryDayData>[];
  for (var d = from; d.compareTo(to) <= 0; d = nextIsoDate(d)) {
    final night = nights[d];
    out.add(
      RecoveryDayData(
        d: d,
        rhr: within(rhr[d], 20, 250),
        hrv: within(hrv[d], 1, 500),
        sleepMin: night?.asleep == null ? null : math.min(night!.asleep!, 1440),
        inBedMin: night == null ? null : math.min(night.inBed, 1440),
      ),
    );
  }
  return out;
}
