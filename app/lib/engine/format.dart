/// Spanish display formatting: the port of `format.js` for the es-ES locale the app ships
/// (specs/engine.md §3, specs/ui.md §2.9). Deterministic; no locale data to initialise.
library;

import 'dart:math';

import '../data/dates.dart';
import 'js.dart';

/// Weekday names indexed like `getDay()` (0 = domingo).
const dayNames = ['Domingo', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado'];

/// Two-letter weekday labels indexed like `getDay()`.
const dayLetters = ['Do', 'Lu', 'Ma', 'Mi', 'Ju', 'Vi', 'Sá'];

/// Month abbreviations, January first.
const monthNamesShort = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

/// Month names, January first.
const monthNames = [
  'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', //
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
];

const _dateWeekdays = ['dom', 'lun', 'mar', 'mié', 'jue', 'vie', 'sáb'];
const _dateMonths = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sept', 'oct', 'nov', 'dic'];

/// `fmtNum`: one decimal at most, es-ES separators — `62.25 → "62,3"`, `60 → "60"`,
/// `12345 → "12.345"`. Four-digit numbers are not grouped, as `toLocaleString('es-ES')` does.
String fmtNum(num n) {
  if (!n.isFinite) return n.isNaN ? 'NaN' : (n > 0 ? '∞' : '-∞');
  final tenths = jsRound(n * 10).abs();
  final whole = (tenths / 10).floor();
  final tenth = (tenths - whole * 10).round();
  var digits = _group(whole.toStringAsFixed(0));
  if (tenth != 0) digits = '$digits,$tenth';
  return n < 0 && digits != '0' ? '-$digits' : digits;
}

String _group(String digits) {
  if (digits.length < 5) return digits;
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write('.');
    out.write(digits[i]);
  }
  return out.toString();
}

/// A number as-is with a decimal comma (`1.25 → "1,25"`, `55 → "55"`): the arguments of the
/// progression and Coach texts, which must not be rounded.
String fmtArg(Object? value) => value is num ? jsNumberString(value).replaceFirst('.', ',') : jsString(value);

/// `fmtVol`: a volume or weight in the profile unit, never abbreviated (`"7535 kg"`).
String fmtVol(num v, String unit) => '${fmtNum(v)} $unit';

/// `fmtDate`: `"30 sept"`, or with [long] `"mié, 30 sept"` (es-ES short forms). Malformed dates
/// are returned unchanged.
String fmtDate(String iso, {bool long = false}) {
  final d = parseIsoDate(iso);
  if (d == null) return iso;
  final base = '${d.day} ${_dateMonths[d.month - 1]}';
  return long ? '${_dateWeekdays[d.weekday % 7]}, $base' : base;
}

/// `fmtDur`: `"45 min"`, `"1h 30m"`.
String fmtDur(num ms) {
  final m = (ms / 60000).floor();
  return m >= 60 ? '${m ~/ 60}h ${m % 60}m' : '$m min';
}

/// The duration of a session as a list part: empty when unknown or under a minute (imports).
List<String> durPart(num ms) => ms >= 60000 ? [fmtDur(ms)] : const [];

/// `fmtSec`: `m:ss` of a work duration (`605 → "10:05"`); junk reads as `0:00`.
String fmtSec(num? sec) {
  final value = (sec == null || !sec.isFinite) ? 0 : sec;
  final n = max(0, jsRound(value)).toInt();
  return '${n ~/ 60}:${(n % 60).toString().padLeft(2, '0')}';
}

/// `"1 ejercicio"`, `"3 ejercicios"`.
String exCount(int n) => n == 1 ? '1 ejercicio' : '$n ejercicios';

final _random = Random();

/// The original `uid()`: base-36 epoch ms plus 5 random base-36 characters
/// (`"muo979oo50vo1"`). Ids for routines, log entries, superset tags and custom exercises.
String uid(DateTime now) {
  final rand = StringBuffer();
  for (var i = 0; i < 5; i++) {
    rand.write(_random.nextInt(36).toRadixString(36));
  }
  return '${now.millisecondsSinceEpoch.toRadixString(36)}$rand';
}

/// `prefix + uid(now)`, drawn again until [taken] rejects it — ids minted in the same
/// millisecond stay distinct.
String freshId(DateTime now, bool Function(String id) taken, {String prefix = ''}) {
  while (true) {
    final id = '$prefix${uid(now)}';
    if (!taken(id)) return id;
  }
}
