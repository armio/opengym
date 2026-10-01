import 'dart:math';

import 'dates.dart';

/// Source of the current time, injectable so tests can control it.
class Clock {
  const Clock();

  DateTime now() => DateTime.now();

  int nowMs() => now().millisecondsSinceEpoch;

  /// Today's local `'YYYY-MM-DD'`.
  String todayIso() => isoDate(now());
}

/// A clock tests can set and advance.
class FakeClock extends Clock {
  FakeClock(this.current);

  DateTime current;

  @override
  DateTime now() => current;

  void advance(Duration d) => current = current.add(d);
}

final _random = Random();

/// The original `uid()`: base-36 epoch ms followed by 5 random base-36 characters, e.g.
/// `"muo979oo50vo1"`. Used for routines, workouts, log entries and superset tags.
String uid([Clock clock = const Clock()]) {
  final time = clock.nowMs().toRadixString(36);
  final rand = StringBuffer();
  for (var i = 0; i < 5; i++) {
    rand.write(_random.nextInt(36).toRadixString(36));
  }
  return '$time$rand';
}
