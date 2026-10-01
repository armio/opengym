import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models/models.dart';
import 'taxonomy_es.dart';

export 'taxonomy_es.dart';

/// Pinned jsDelivr mirror of the exercise dataset's media (contract §6). Hot-linked, never
/// re-hosted; always shown with [mediaAttribution].
const mediaBase = 'https://cdn.jsdelivr.net/gh/hasaneyldrm/exercises-dataset@7455efae41b330c265e7cd4b78dfa848e7ce5ebd';

/// Required wherever the GIFs/JPGs appear (specs/library.md §5.3).
const mediaAttribution = '© Gym visual — gymvisual.com';

/// One exercise: a built-in catalogue record, a custom exercise from the plan doc, or the
/// placeholder for an unknown id. The short-key getters ([n], [bp], [eq], [tg]) mirror the
/// original JS records so ported code reads naturally.
@immutable
class Exercise {
  const Exercise({
    required this.id,
    required this.name,
    required this.bodyPart,
    required this.equipment,
    required this.target,
    this.secondary = const [],
    this.instructions = const [],
    this.instructionsEs = const [],
    required this.bodyPartEs,
    required this.equipmentEs,
    required this.targetEs,
    this.secondaryEs = const [],
    this.img,
    this.gif,
    this.desc = '',
    this.custom = false,
    this.missing = false,
  });

  /// A record of `assets/exercises.json`.
  factory Exercise.fromCatalogJson(Map<String, dynamic> m) => Exercise(
    id: asString(m['id']) ?? '',
    name: asString(m['name']) ?? '',
    bodyPart: asString(m['bodyPart']) ?? '',
    equipment: asString(m['equipment']) ?? '',
    target: asString(m['target']) ?? '',
    secondary: asStringList(m['secondary']),
    instructions: asStringList(m['instructions']),
    instructionsEs: asStringList(m['instructions_es']),
    bodyPartEs: asString(m['bodyPart_es']) ?? bodyPartLabel(asString(m['bodyPart']) ?? ''),
    equipmentEs: asString(m['equipment_es']) ?? equipmentLabel(asString(m['equipment']) ?? ''),
    targetEs: asString(m['target_es']) ?? targetLabel(asString(m['target']) ?? ''),
    secondaryEs: asStringList(m['secondary_es']),
    img: asString(m['img']),
    gif: asString(m['gif']),
  );

  /// A custom exercise of the plan doc (`{id, n, bp, desc, tg: '', eq: 'custom', custom: true}`).
  factory Exercise.fromCustom(CustomExercise c) => Exercise(
    id: c.id,
    name: c.n,
    bodyPart: c.bp,
    equipment: c.eq.isEmpty ? 'custom' : c.eq,
    target: c.tg,
    bodyPartEs: bodyPartLabel(c.bp),
    equipmentEs: equipmentLabel(c.eq.isEmpty ? 'custom' : c.eq),
    targetEs: c.tg.isEmpty ? '' : targetLabel(c.tg),
    desc: c.desc,
    custom: true,
  );

  /// What an unknown id renders as, so a view never crashes (`exOr`).
  factory Exercise.placeholder(String id) => Exercise(
    id: id,
    name: 'Ejercicio desconocido',
    bodyPart: '',
    equipment: '',
    target: '',
    bodyPartEs: '',
    equipmentEs: '',
    targetEs: '',
    missing: true,
  );

  final String id;

  /// English, lowercase (the dataset has no translated names).
  final String name;
  final String bodyPart;
  final String equipment;
  final String target;
  final List<String> secondary;
  final List<String> instructions;
  final List<String> instructionsEs;
  final String bodyPartEs;
  final String equipmentEs;
  final String targetEs;
  final List<String> secondaryEs;

  /// Still JPG file name (built-ins only).
  final String? img;

  /// Animated GIF file name (built-ins only).
  final String? gif;

  /// Custom exercises' description.
  final String desc;
  final bool custom;

  /// True for the placeholder of an unknown id.
  final bool missing;

  String get n => name;
  String get bp => bodyPart;
  String get eq => equipment;
  String get tg => target;

  bool get isCardio => bodyPart == 'cardio';
  bool get hasMedia => gif != null && img != null;

  /// Spanish steps when available, else English.
  List<String> get steps => instructionsEs.isNotEmpty ? instructionsEs : instructions;

  /// URL of the still frame, or null for custom exercises.
  String? get imageUrl => img == null ? null : '$mediaBase/images/$img';

  /// URL of the animation, or null for custom exercises.
  String? get gifUrl => gif == null ? null : '$mediaBase/videos/$gif';

  /// Subtitle used in lists: "`{target or body part} · {equipment}`" in Spanish.
  String get subtitleEs {
    final first = targetEs.isNotEmpty ? targetEs : bodyPartEs;
    return [first, equipmentEs].where((s) => s.isNotEmpty).join(' · ');
  }

  @override
  bool operator ==(Object other) => other is Exercise && other.id == id && other.custom == custom && other.name == name;

  @override
  int get hashCode => Object.hash(id, custom, name);
}

/// Lowercases and strips diacritics so "Bíceps", "biceps" and "BICEPS" compare equal.
String foldForSearch(String s) {
  final lower = s.toLowerCase();
  final out = StringBuffer();
  for (final r in lower.runes) {
    out.write(_fold[r] ?? String.fromCharCode(r));
  }
  return out.toString();
}

const Map<int, String> _fold = {
  0xe0: 'a', 0xe1: 'a', 0xe2: 'a', 0xe3: 'a', 0xe4: 'a', 0xe5: 'a', //
  0xe8: 'e', 0xe9: 'e', 0xea: 'e', 0xeb: 'e',
  0xec: 'i', 0xed: 'i', 0xee: 'i', 0xef: 'i',
  0xf2: 'o', 0xf3: 'o', 0xf4: 'o', 0xf5: 'o', 0xf6: 'o',
  0xf9: 'u', 0xfa: 'u', 0xfb: 'u', 0xfc: 'u',
  0xf1: 'n', 0xe7: 'c',
};

/// The built-in catalogue (1,324 exercises, dataset order). Immutable; load once.
class ExerciseLibrary {
  ExerciseLibrary(List<Exercise> builtIns)
    : builtIns = List.unmodifiable(builtIns),
      _byId = {for (final e in builtIns) e.id: e},
      bodyParts = List.unmodifiable(({for (final e in builtIns) e.bodyPart}.toList())..sort());

  /// Parses the decoded `assets/exercises.json` array.
  factory ExerciseLibrary.fromJson(List<dynamic> json) => ExerciseLibrary([
    for (final r in json)
      if (r is Map<String, dynamic>) Exercise.fromCatalogJson(r),
  ]);

  /// Loads `assets/exercises.json` (parsed off the UI isolate where the platform allows).
  static Future<ExerciseLibrary> load({AssetBundle? bundle}) async {
    final text = await (bundle ?? rootBundle).loadString('assets/exercises.json');
    final records = await compute(_decode, text);
    return ExerciseLibrary.fromJson(records);
  }

  static List<dynamic> _decode(String text) => jsonDecode(text) as List<dynamic>;

  final List<Exercise> builtIns;
  final Map<String, Exercise> _byId;

  /// The 10 body parts, sorted by their English key (the original's `BODYPARTS` order).
  final List<String> bodyParts;

  Exercise? byId(String id) => _byId[id];
}

/// Result of [ExerciseCatalog.search].
class ExerciseSearch {
  const ExerciseSearch({
    required this.base,
    required this.equipmentOptions,
    required this.equipment,
    required this.results,
  });

  /// Matches for the query and body part, before the equipment filter.
  final List<Exercise> base;

  /// Equipment values present in [base], most common first (`equipmentOf`). Show the equipment
  /// chips only when there is more than one.
  final List<String> equipmentOptions;

  /// The equipment filter actually applied: the requested one if [base] still has it, else null
  /// (a filter the search emptied is dropped, so the user never hits a dead end).
  final String? equipment;
  final List<Exercise> results;
}

/// The built-in library plus the owner's custom exercises (customs first), indexed by id.
/// AppState rebuilds it whenever `plan.customEx` changes.
class ExerciseCatalog {
  ExerciseCatalog(this.library, List<CustomExercise> customs)
    : customs = List.unmodifiable([for (final c in customs) Exercise.fromCustom(c)]) {
    for (final c in this.customs) {
      _customById[c.id] = c;
    }
  }

  final ExerciseLibrary library;
  final List<Exercise> customs;
  final Map<String, Exercise> _customById = {};

  /// `allExercises(S)`: customs first, then the built-ins in dataset order.
  List<Exercise> get all => [...customs, ...library.builtIns];

  int get length => customs.length + library.builtIns.length;

  List<String> get bodyParts => library.bodyParts;

  /// The exercise with [id], or null when unknown.
  Exercise? byId(String id) => _customById[id] ?? library.byId(id);

  /// `exOr(id)`: the exercise, or a placeholder named "Ejercicio desconocido".
  Exercise exOr(String id) => byId(id) ?? Exercise.placeholder(id);

  /// `isCardio(id)`: body part is cardio.
  bool isCardio(String id) => byId(id)?.isCardio ?? false;

  /// Library/picker search (specs/library.md §2.1): body part equal, and the query (trimmed,
  /// case- and accent-insensitive) contained in the English name, target or equipment, the
  /// custom description, or the Spanish body part / target / equipment labels. [where] replaces
  /// the body-part filter (the picker's "Elegidos" chip); [sort] reorders the base list.
  ExerciseSearch search({
    String query = '',
    String? bodyPart,
    String? equipment,
    bool Function(Exercise e)? where,
    Comparator<Exercise>? sort,
  }) {
    final q = foldForSearch(query.trim());
    final base = [
      for (final e in all)
        if ((where != null ? where(e) : (bodyPart == null || bodyPart.isEmpty || e.bodyPart == bodyPart)) &&
            (q.isEmpty || _matches(e, q)))
          e,
    ];
    if (sort != null) base.sort(sort);
    final options = equipmentOf(base);
    final eqOn = equipment != null && options.contains(equipment) ? equipment : null;
    return ExerciseSearch(
      base: base,
      equipmentOptions: options,
      equipment: eqOn,
      results: eqOn == null
          ? base
          : [
              for (final e in base)
                if (e.equipment == eqOn) e,
            ],
    );
  }

  static bool _matches(Exercise e, String q) => _haystack(e).contains(q);

  // The searchable fields, folded once per exercise and joined with a separator no query can
  // contain, so a match never spans two fields.
  static final _haystacks = Expando<String>();
  static String _haystack(Exercise e) => _haystacks[e] ??= [
    e.name, e.target, e.equipment, e.desc, e.bodyPartEs, e.targetEs, e.equipmentEs, //
  ].map(foldForSearch).join('\u0000');
}

/// Equipment values present in [list], most common first, ties by code-unit order.
List<String> equipmentOf(Iterable<Exercise> list) {
  final counts = <String, int>{};
  for (final e in list) {
    if (e.equipment.isNotEmpty) counts[e.equipment] = (counts[e.equipment] ?? 0) + 1;
  }
  final keys = counts.keys.toList()
    ..sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      return byCount != 0 ? byCount : a.compareTo(b);
    });
  return keys;
}
