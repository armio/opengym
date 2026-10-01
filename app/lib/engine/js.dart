/// JavaScript semantics the engine reproduces (specs/engine.md §0, specs/coach.md §7.1).
///
/// The rules being ported were written in JavaScript and their outputs are pinned by fixtures
/// generated from that code, so rounding, number printing and JSON escaping must match it byte
/// for byte. Everything here is pure and works the same on the VM and on the web.
library;

/// `Math.round`: halves go towards +∞ (`2.5 → 3`, `-2.5 → -2`), unlike Dart's `round()`.
double jsRound(num x) {
  final floor = x.floorToDouble();
  return x - floor >= 0.5 ? floor + 1 : floor;
}

/// An integral finite double as an int (`60.0 → 60`), the way JavaScript prints and stores it.
num normNum(num value) {
  if (value is double && value.isFinite && value == value.truncateToDouble() && value.abs() < 9007199254740992) {
    return value.toInt();
  }
  return value;
}

/// `Math.round(v * 10) / 10`: one decimal, JavaScript rounding.
num round1(num v) => normNum(jsRound(v * 10) / 10);

/// JavaScript's `a || b` for numbers: zero, NaN and null fall through to [fallback].
num numOr(num? value, num fallback) => (value == null || value == 0 || value.isNaN) ? fallback : value;

/// JavaScript truthiness of a JSON value.
bool jsTruthy(Object? value) => switch (value) {
  null => false,
  bool b => b,
  num n => n != 0 && !n.isNaN,
  String s => s.isNotEmpty,
  _ => true,
};

/// JavaScript's `a || b` for any JSON value.
Object? jsOr(Object? value, Object? fallback) => jsTruthy(value) ? value : fallback;

/// `String(n)`: `55 → "55"`, `62.5 → "62.5"`, `1e21 → "1e+21"`, `1.5e-7 → "1.5e-7"`.
///
/// Dart and JavaScript both print the shortest round-trip digits and switch to exponent form at
/// the same thresholds; the only difference is Dart's trailing `.0` on integral doubles.
String jsNumberString(num n) {
  if (n == 0) return '0';
  if (n is int) return '$n';
  final text = n.toString();
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

/// `String(v)` of a JSON value, as used by `Array.prototype.join` and string concatenation.
/// `null` prints as [nullText] (join prints `''`, concatenation prints `'null'`).
String jsString(Object? value, {String nullText = 'null'}) => switch (value) {
  null => nullText,
  String s => s,
  num n => jsNumberString(n),
  bool b => '$b',
  List l => l.map((v) => jsString(v, nullText: '')).join(','),
  _ => '[object Object]',
};

/// `JSON.stringify` of a JSON value (maps, lists, strings, numbers, booleans, null), byte for
/// byte: non-finite numbers become `null`, strings use JavaScript's escapes.
String jsonStringify(Object? value) {
  final out = StringBuffer();
  _stringify(value, out);
  return out.toString();
}

void _stringify(Object? value, StringBuffer out) {
  switch (value) {
    case null:
      out.write('null');
    case bool b:
      out.write('$b');
    case num n:
      out.write(n.isFinite ? jsNumberString(n) : 'null');
    case String s:
      out.write(jsonQuote(s));
    case List l:
      out.write('[');
      for (var i = 0; i < l.length; i++) {
        if (i > 0) out.write(',');
        _stringify(l[i], out);
      }
      out.write(']');
    case Map m:
      out.write('{');
      var first = true;
      for (final e in m.entries) {
        if (!first) out.write(',');
        first = false;
        out.write(jsonQuote('${e.key}'));
        out.write(':');
        _stringify(e.value, out);
      }
      out.write('}');
    default:
      out.write('null');
  }
}

const _shortEscapes = {0x08: r'\b', 0x09: r'\t', 0x0a: r'\n', 0x0c: r'\f', 0x0d: r'\r', 0x22: r'\"', 0x5c: r'\\'};

/// A string literal as `JSON.stringify` writes it: `"` `\` and control characters escaped (the
/// short forms where JSON has them, else lowercase `\u00xx`), lone surrogates as `\udxxx`,
/// everything else raw.
String jsonQuote(String s) {
  final out = StringBuffer('"');
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    final short = _shortEscapes[c];
    if (short != null) {
      out.write(short);
    } else if (c < 0x20 || _isLoneSurrogate(s, i)) {
      out.write(r'\u');
      out.write(c.toRadixString(16).padLeft(4, '0'));
    } else {
      out.writeCharCode(c);
    }
  }
  out.write('"');
  return out.toString();
}

bool _isLoneSurrogate(String s, int i) {
  final c = s.codeUnitAt(i);
  if (c >= 0xd800 && c <= 0xdbff) {
    return i + 1 >= s.length || !_isLow(s.codeUnitAt(i + 1));
  }
  if (_isLow(c)) return i == 0 || !(s.codeUnitAt(i - 1) >= 0xd800 && s.codeUnitAt(i - 1) <= 0xdbff);
  return false;
}

bool _isLow(int c) => c >= 0xdc00 && c <= 0xdfff;

/// `Math.imul(a, b) >>> 0`: the low 32 bits of the product, unsigned. Split into 16-bit halves so
/// no intermediate exceeds 2^53 (exact on the web, where ints are doubles).
int imul32(int a, int b) {
  final aHi = (a >> 16) & 0xffff, aLo = a & 0xffff;
  final bHi = (b >> 16) & 0xffff, bLo = b & 0xffff;
  final mid = ((aHi * bLo + aLo * bHi) & 0xffff) * 0x10000;
  return (aLo * bLo + mid) % 0x100000000;
}
