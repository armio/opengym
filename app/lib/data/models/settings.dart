import 'json.dart';

/// The `reminder` object of the settings doc. Not used by the port (the workout-day reminder is
/// not ported) but preserved for backup round-trips.
class Reminder implements JsonModel {
  Reminder({this.on = false, this.time = '08:00', this.tz, JsonMap? extra}) : extra = extra ?? {};

  factory Reminder.fromJson(Object? json) {
    final m = asMap(json);
    return Reminder(
      on: asBool(m['on']) ?? false,
      time: asString(m['time']) ?? '08:00',
      tz: asString(m['tz']),
      extra: extraOf(m, _known),
    );
  }

  static const _known = {'on', 'time', 'tz'};

  bool on;
  String time;
  String? tz;
  JsonMap extra;

  @override
  JsonMap toJson() => {...deepCopyMap(extra), 'on': on, 'time': time, 'tz': tz};
}

/// The `settings` doc (contract §2.1). Missing keys take the defaults, unknown keys are kept.
class Settings implements JsonModel {
  Settings({
    this.unit = 'kg',
    this.restSec = 90,
    this.sound = true,
    this.keepAwake = true,
    this.theme = 'dark',
    this.accent = 'lime',
    this.body = 'male',
    this.gifSize = 'full',
    this.effort,
    this.targetW,
    this.lang = 'es',
    Reminder? reminder,
    this.showRir,
    JsonMap? extra,
  }) : reminder = reminder ?? Reminder(),
       extra = extra ?? {};

  factory Settings.fromJson(Object? json) {
    final m = asMap(json);
    return Settings(
      unit: asString(m['unit']) ?? 'kg',
      restSec: asInt(m['restSec']) ?? 90,
      sound: asBool(m['sound']) ?? true,
      keepAwake: asBool(m['keepAwake']) ?? true,
      theme: asString(m['theme']) ?? 'dark',
      accent: asString(m['accent']) ?? 'lime',
      body: asString(m['body']) ?? 'male',
      gifSize: asString(m['gifSize']) ?? 'full',
      effort: asString(m['effort']),
      targetW: asNum(m['targetW']),
      lang: asString(m['lang']) ?? 'es',
      reminder: m.containsKey('reminder') ? Reminder.fromJson(m['reminder']) : null,
      showRir: asBool(m['showRir']),
      extra: extraOf(m, _known),
    );
  }

  static const _known = {
    'unit', 'restSec', 'sound', 'keepAwake', 'theme', 'accent', 'body', 'gifSize', 'effort', //
    'targetW', 'lang', 'reminder', 'showRir',
  };

  /// `'kg'` or `'lb'` — a label only; switching never converts stored numbers.
  String unit;

  /// Rest-timer seconds (the UI offers 60, 90, 120, 150, 180).
  int restSec;
  bool sound;
  bool keepAwake;

  /// `'dark'` or `'light'`; anything else renders dark.
  String theme;

  /// One of the eight accent keys; unknown keys render as lime.
  String accent;

  /// `'male'` or `'female'` — only changes the body-map drawing.
  String body;

  /// `'full'` or `'mini'` — size of the exercise animation during a workout.
  String gifSize;

  /// `null` (never chose), `'none'`, `'rir'` or `'rpe'`. Use [effortScale] to read it.
  String? effort;

  /// Goal body weight (> 0), or null.
  num? targetW;

  /// Always `'es'` in the port.
  String lang;
  Reminder reminder;

  /// Legacy flag `effort` replaced; kept when present. Saving the effort setting clears it.
  bool? showRir;
  JsonMap extra;

  /// `effortOf(S)`: the effective per-set effort scale — `'none'`, `'rir'` or `'rpe'`.
  String get effortScale {
    final e = effort;
    if (e == 'none' || e == 'rir' || e == 'rpe') return e!;
    return showRir == true ? 'rir' : 'none';
  }

  /// Sets the effort scale the way the Settings screen does (`s.effort = v; delete s.showRir`).
  void setEffortScale(String scale) {
    effort = scale;
    showRir = null;
  }

  bool get isLight => theme == 'light';

  Settings copy() => Settings.fromJson(toJson());

  @override
  JsonMap toJson() {
    final out = <String, dynamic>{
      ...deepCopyMap(extra),
      'unit': unit,
      'restSec': restSec,
      'sound': sound,
      'keepAwake': keepAwake,
      'theme': theme,
      'accent': accent,
      'body': body,
      'gifSize': gifSize,
      'effort': effort,
      'targetW': targetW == null ? null : jsNum(targetW!),
      'lang': lang,
      'reminder': reminder.toJson(),
    };
    putIfNotNull(out, 'showRir', showRir);
    return out;
  }
}
