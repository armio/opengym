/// Calendar-date helpers for the `'YYYY-MM-DD'` strings used everywhere in the data model.
///
/// Dates are the device's local calendar dates; a date-only instant is local noon of that date
/// (engine-Q7), never UTC midnight.
library;

String _pad2(int n) => n < 10 ? '0$n' : '$n';

/// `'YYYY-MM-DD'` of [t] in local time.
String isoDate(DateTime t) {
  final l = t.toLocal();
  return '${l.year.toString().padLeft(4, '0')}-${_pad2(l.month)}-${_pad2(l.day)}';
}

/// Parses `'YYYY-MM-DD'` as local noon; null when malformed.
DateTime? parseIsoDate(String? iso) {
  if (iso == null) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(iso);
  if (m == null) return null;
  final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  return DateTime(y, mo, d, 12);
}

/// Epoch ms of local noon on [iso] (0 when malformed).
int localNoonMs(String iso) => parseIsoDate(iso)?.millisecondsSinceEpoch ?? 0;

/// True when [iso] is a well-formed `'YYYY-MM-DD'`.
bool isIsoDate(String? iso) => parseIsoDate(iso) != null;
