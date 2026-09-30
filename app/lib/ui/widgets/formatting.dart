/// Spanish display formatting used by the shared widgets (es-ES conventions of the original's
/// `fmtNum` / `fmtDate`). Deterministic: no locale data needs to be initialised.
library;

import '../../data/dates.dart';

const _weekdaysShort = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
const _weekdaysLong = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
const _monthsShort = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sept', 'oct', 'nov', 'dic'];
const _monthsLong = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', //
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

/// `fmtNum`: rounded to one decimal, Spanish separators (`62.25` → `"62,3"`, `60` → `"60"`,
/// `12345` → `"12.345"`; four-digit numbers are not grouped, as in es-ES).
String formatNum(num value) {
  // JavaScript's Math.round: halves go towards +∞ (-1.25 → -1.2, not -1.3).
  final rounded = (value * 10 + .5).floor() / 10;
  final negative = rounded < 0;
  final abs = rounded.abs();
  final whole = abs.truncate();
  final tenth = ((abs - whole) * 10).round();
  var digits = '$whole';
  if (digits.length >= 5) {
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
      buf.write(digits[i]);
    }
    digits = buf.toString();
  }
  final text = tenth == 0 ? digits : '$digits,$tenth';
  return negative && text != '0' ? '-$text' : text;
}

/// `fmtNum(v) + ' ' + unit`.
String formatWeight(num value, String unit) => '${formatNum(value)} $unit';

/// `fmtDate(iso)`: `"30 sept"`; with [long]: `"mié, 30 sept"`. Returns [iso] when malformed.
String formatDate(String iso, {bool long = false}) {
  final d = parseIsoDate(iso);
  if (d == null) return iso;
  final base = '${d.day} ${_monthsShort[d.month - 1]}';
  return long ? '${_weekdaysShort[d.weekday - 1]}, $base' : base;
}

/// `"miércoles, 30 de septiembre"` — the Home header style.
String formatDateFull(DateTime d) => '${_weekdaysLong[d.weekday - 1]}, ${d.day} de ${_monthsLong[d.month - 1]}';

/// Title Case like CSS `text-transform: capitalize` (dataset names arrive lowercase): the first
/// letter of each whitespace-separated word is uppercased, so `"(male)"` → `"(Male)"` and
/// `"3/4 sit-up"` → `"3/4 Sit-up"`.
String capitalizeWords(String text) {
  final out = StringBuffer();
  var pending = true;
  for (final ch in text.split('')) {
    if (ch.trim().isEmpty) {
      pending = true;
      out.write(ch);
    } else if (pending && ch.toUpperCase() != ch.toLowerCase()) {
      pending = false;
      out.write(ch.toUpperCase());
    } else {
      out.write(ch);
    }
  }
  return out.toString();
}

/// Capitalises the first letter only (`"peso corporal"` → `"Peso corporal"`).
String capitalizeFirst(String text) => text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
