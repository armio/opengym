/// Calendar dates (`'YYYY-MM-DD'`), ISO weeks and the local time zone.
///
/// Dates are the owner's local calendar dates. A calendar date has the same weekday and ISO
/// week in every zone, so date arithmetic runs in UTC and never depends on the device zone. Only
/// the mapping between instants and dates needs a zone: that is [LocalCalendar].
library;

import '../data/dates.dart';

/// Milliseconds in a day.
const int dayMs = 86400000;

/// Maps instants to local calendar dates. The app uses [deviceCalendar]; tests pin a zone.
abstract class LocalCalendar {
  const LocalCalendar();

  /// The local `'YYYY-MM-DD'` of the instant [epochMs].
  String dateOf(int epochMs);

  /// Epoch ms of local noon on [iso] — the instant a date-only workout counts as (engine-Q7).
  int noonOf(String iso);

  /// Today's local date at [now].
  String today(DateTime now) => dateOf(now.millisecondsSinceEpoch);
}

/// The device's own time zone.
class DeviceCalendar extends LocalCalendar {
  const DeviceCalendar();

  @override
  String dateOf(int epochMs) => isoDate(DateTime.fromMillisecondsSinceEpoch(epochMs));

  @override
  int noonOf(String iso) => localNoonMs(iso);
}

const LocalCalendar deviceCalendar = DeviceCalendar();

DateTime _utcNoon(String iso) {
  final d = parseIsoDate(iso);
  if (d == null) throw FormatException('Fecha no válida', iso);
  return DateTime.utc(d.year, d.month, d.day, 12);
}

String _isoOfUtc(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 0 = Sunday … 6 = Saturday (JavaScript's `getDay`).
int weekdayOf(String iso) => _utcNoon(iso).weekday % 7;

/// [iso] moved by [days] calendar days.
String addDays(String iso, int days) {
  final d = _utcNoon(iso);
  return _isoOfUtc(DateTime.utc(d.year, d.month, d.day + days, 12));
}

/// The Monday of the Monday–Sunday week containing [iso].
String mondayOf(String iso) => addDays(iso, -((weekdayOf(iso) + 6) % 7));

/// ISO-8601 week as `"<week-year>-<week>"`, the week not zero-padded (`2027-01-01 → "2026-53"`).
String weekKey(String iso) {
  final noon = _utcNoon(iso);
  final thursday = DateTime.utc(noon.year, noon.month, noon.day - (noon.weekday - 1) + 3, 12);
  final year = thursday.year;
  final jan4 = DateTime.utc(year, 1, 4);
  final days = (thursday.millisecondsSinceEpoch - jan4.millisecondsSinceEpoch) / dayMs;
  final week = 1 + ((days - 3 + (jan4.weekday - 1)) / 7).round();
  return '$year-$week';
}
