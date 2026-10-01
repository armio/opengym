/// Spanish display formatting used by the shared widgets. The number and date helpers are the
/// engine's `format.dart` (the port of `format.js`) under the names the widgets already use.
library;

import '../../engine/format.dart';

const _weekdaysLong = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
const _monthsLong = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', //
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

/// `fmtNum`: rounded to one decimal, Spanish separators (`62.25` → `"62,3"`, `60` → `"60"`,
/// `12345` → `"12.345"`; four-digit numbers are not grouped, as in es-ES).
String formatNum(num value) => fmtNum(value);

/// `fmtVol`: `fmtNum(v) + ' ' + unit`.
String formatWeight(num value, String unit) => fmtVol(value, unit);

/// `fmtDate(iso)`: `"30 sept"`; with [long]: `"mié, 30 sept"`. Returns [iso] when malformed.
String formatDate(String iso, {bool long = false}) => fmtDate(iso, long: long);

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
