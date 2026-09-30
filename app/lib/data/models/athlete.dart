import 'json.dart';

/// The `athlete` doc: the Coach intake profile (contract §2.1, specs/coach.md §2).
///
/// Written by the app (intake "Guardar") and by Claude through MCP. The app never pushes it
/// while [savedAt] is null.
class AthleteProfile implements JsonModel {
  AthleteProfile({
    this.goal,
    this.experience,
    this.daysPerWeek = 3,
    List<int>? preferredDays,
    this.sessionMin = 45,
    List<String>? equipment,
    this.limitations = '',
    this.likes = '',
    this.dislikes = '',
    this.notes = '',
    this.savedAt,
    this.updatedBy,
    JsonMap? extra,
  }) : preferredDays = preferredDays ?? [1, 3, 5],
       equipment = equipment ?? [],
       extra = extra ?? {};

  factory AthleteProfile.fromJson(Object? json) {
    final m = asMap(json);
    return AthleteProfile(
      goal: asString(m['goal']),
      experience: asString(m['experience']),
      daysPerWeek: asInt(m['daysPerWeek']) ?? 3,
      preferredDays: m['preferredDays'] is List
          ? [
              for (final d in asList(m['preferredDays']))
                if (asInt(d) != null) asInt(d)!,
            ]
          : null,
      sessionMin: asInt(m['sessionMin']) ?? 45,
      equipment: m['equipment'] is List ? asStringList(m['equipment']) : null,
      limitations: asString(m['limitations']) ?? '',
      likes: asString(m['likes']) ?? '',
      dislikes: asString(m['dislikes']) ?? '',
      notes: asString(m['notes']) ?? '',
      savedAt: asInt(m['savedAt']),
      updatedBy: asString(m['updatedBy']),
      extra: extraOf(m, _known),
    );
  }

  static const _known = {
    'goal', 'experience', 'daysPerWeek', 'preferredDays', 'sessionMin', 'equipment', //
    'limitations', 'likes', 'dislikes', 'notes', 'savedAt', 'updatedBy',
  };

  /// `'strength'|'muscle'|'general'|'fatloss'|'endurance'` or null.
  String? goal;

  /// `'new'|'returning'|'regular'` or null.
  String? experience;

  /// 1..7.
  int daysPerWeek;

  /// Weekday ints, 0 = Sunday, sorted ascending.
  List<int> preferredDays;

  /// 15..180 minutes.
  int sessionMin;

  /// Library `eq` values; empty = everything.
  List<String> equipment;
  String limitations;
  String likes;
  String dislikes;
  String notes;

  /// Epoch ms of the last explicit save (intake, Claude, import); null = never.
  int? savedAt;

  /// `'app' | 'claude' | 'import'`.
  String? updatedBy;
  JsonMap extra;

  AthleteProfile copy() => AthleteProfile.fromJson(toJson());

  @override
  JsonMap toJson() => {
    ...deepCopyMap(extra),
    'goal': goal,
    'experience': experience,
    'daysPerWeek': daysPerWeek,
    'preferredDays': [...preferredDays],
    'sessionMin': sessionMin,
    'equipment': [...equipment],
    'limitations': limitations,
    'likes': likes,
    'dislikes': dislikes,
    'notes': notes,
    'savedAt': savedAt,
    'updatedBy': updatedBy,
  };
}
