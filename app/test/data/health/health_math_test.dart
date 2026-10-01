import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/health/health_bridge.dart';
import 'package:opengym/data/health/health_math.dart';

HealthReading reading(DateTime at, double value) => HealthReading(uuid: '$at', start: at, end: at, value: value);

SleepSegment segment(DateTime start, DateTime end, SleepStage stage) =>
    SleepSegment(start: start, end: end, stage: stage);

void main() {
  test('converts weights between the owner unit and kg', () {
    expect(toKg(80, 'kg'), 80);
    expect(toKg(176.4, 'lb'), closeTo(80.01, .01));
    expect(fromKg(80.04, 'kg'), 80.0);
    expect(fromKg(80, 'lb'), 176.4);
  });

  test('estimates active calories at 2.5 MET-hours per kg, capping a forgotten session at 3 h', () {
    expect(estimateActiveKcal(durationMs: 3600000, bodyKg: 80), 200);
    expect(estimateActiveKcal(durationMs: 45 * 60000, bodyKg: 70), 131);
    expect(estimateActiveKcal(durationMs: 10 * 3600000, bodyKg: 80), 600);
    expect(estimateActiveKcal(durationMs: 3600000, bodyKg: null), isNull);
    expect(estimateActiveKcal(durationMs: 0, bodyKg: 80), isNull);
  });

  test('moves dates by calendar days', () {
    expect(nextIsoDate('2026-02-28'), '2026-03-01');
    expect(addIsoDays('2026-10-01', -90), '2026-07-03');
    expect(startOfIsoDate('2026-10-01'), DateTime(2026, 10, 1));
  });

  test('averages readings per local day', () {
    final means = dailyMeans([
      reading(DateTime(2026, 9, 29, 3), 50),
      reading(DateTime(2026, 9, 29, 23), 70),
      reading(DateTime(2026, 9, 30, 4), 64),
    ]);
    expect(means, {'2026-09-29': 60, '2026-09-30': 64});
  });

  test('a night counts toward the morning it ends; a nap toward its own day', () {
    expect(sleepDayOf(DateTime(2026, 9, 29, 23, 30)), '2026-09-30');
    expect(sleepDayOf(DateTime(2026, 9, 30, 6, 45)), '2026-09-30');
    expect(sleepDayOf(DateTime(2026, 9, 30, 15)), '2026-09-30');
    expect(sleepDayOf(DateTime(2026, 9, 30, 18)), '2026-10-01');
  });

  test('overlapping intervals count once', () {
    expect(
      unionMinutes([
        (DateTime(2026, 9, 29, 22), DateTime(2026, 9, 30, 6)),
        (DateTime(2026, 9, 29, 23), DateTime(2026, 9, 30, 7)),
        (DateTime(2026, 9, 30, 8), DateTime(2026, 9, 30, 8, 30)),
        (DateTime(2026, 9, 30, 9), DateTime(2026, 9, 30, 9)),
      ]),
      9 * 60 + 30,
    );
  });

  test('merges the iPhone and the Watch into asleep and in-bed minutes per night', () {
    final nights = sleepByDay([
      // iPhone: in bed 22:30–06:45.
      segment(DateTime(2026, 9, 29, 22, 30), DateTime(2026, 9, 30, 6, 45), SleepStage.inBed),
      // Watch: core, deep and REM with a 10-minute awake gap, overlapping each other once.
      segment(DateTime(2026, 9, 29, 23), DateTime(2026, 9, 30, 2), SleepStage.asleep),
      segment(DateTime(2026, 9, 30, 1, 30), DateTime(2026, 9, 30, 2, 30), SleepStage.asleep),
      segment(DateTime(2026, 9, 30, 2, 30), DateTime(2026, 9, 30, 2, 40), SleepStage.awake),
      segment(DateTime(2026, 9, 30, 2, 40), DateTime(2026, 9, 30, 6, 30), SleepStage.asleep),
      // The next night: only the iPhone.
      segment(DateTime(2026, 9, 30, 23), DateTime(2026, 10, 1, 7), SleepStage.inBed),
    ]);
    expect(nights['2026-09-30'], (asleep: 3 * 60 + 30 + 3 * 60 + 50, inBed: 8 * 60 + 15));
    expect(nights['2026-10-01'], (asleep: null, inBed: 8 * 60));
  });

  test('builds every day of the range, dropping impossible values', () {
    final days = buildRecoveryDays(
      from: '2026-09-28',
      to: '2026-09-30',
      restingHeartRate: [reading(DateTime(2026, 9, 28, 8), 54.26), reading(DateTime(2026, 9, 30, 8), 300)],
      heartRateVariability: [reading(DateTime(2026, 9, 28, 3), 61.04), reading(DateTime(2026, 9, 28, 4), 63)],
      sleep: [segment(DateTime(2026, 9, 29, 23), DateTime(2026, 9, 30, 7), SleepStage.asleep)],
    );
    expect(
      [for (final d in days) d.toJson()],
      [
        {'d': '2026-09-28', 'rhr': 54.3, 'hrv': 62.0},
        {'d': '2026-09-29'},
        {'d': '2026-09-30', 'sleepMin': 480, 'inBedMin': 480},
      ],
    );
    expect(days[1].isEmpty, isTrue);
  });
}
