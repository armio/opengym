/// Tolerant JSON helpers shared by every model.
///
/// The synced documents come from several writers (this app, the Worker, Claude through MCP,
/// openGym backups), so readers never throw on an unexpected shape: a wrong type reads as
/// "absent" and the model falls back to its default. Writers emit plain JSON values only.
library;

typedef JsonMap = Map<String, dynamic>;

/// Deep copy of a JSON value — the Dart twin of `JSON.parse(JSON.stringify(v))`.
///
/// Integral doubles become ints (`60.0` → `60`), as a JavaScript round trip would print them.
dynamic deepCopyJson(dynamic value) {
  if (value is Map) {
    return <String, dynamic>{for (final e in value.entries) '${e.key}': deepCopyJson(e.value)};
  }
  if (value is List) return [for (final v in value) deepCopyJson(v)];
  if (value is num) return jsNum(value);
  return value;
}

/// Deep copy of a JSON object.
JsonMap deepCopyMap(Map value) => deepCopyJson(value) as JsonMap;

/// Normalises a number the way JavaScript stores it: integral finite doubles become ints.
num jsNum(num value) {
  if (value is double && value.isFinite && value == value.truncateToDouble() && value.abs() < 9007199254740992) {
    return value.toInt();
  }
  return value;
}

/// [value] as a JSON object, or an empty map when it is not one.
JsonMap asMap(Object? value) => value is Map ? deepCopyMap(value) : <String, dynamic>{};

/// [value] as a JSON object, or null when it is not one.
JsonMap? asMapOrNull(Object? value) => value is Map ? deepCopyMap(value) : null;

/// [value] as a list, or an empty list when it is not one.
List<dynamic> asList(Object? value) => value is List ? value : const [];

/// A finite number, or null.
num? asNum(Object? value) => value is num && value.isFinite ? jsNum(value) : null;

/// An integer (a finite integral number), or null. `3.0` reads as `3`; `3.5` reads as null.
int? asInt(Object? value) {
  final n = asNum(value);
  if (n == null) return null;
  if (n is int) return n;
  return n == n.truncateToDouble() ? n.toInt() : null;
}

/// A string, or null.
String? asString(Object? value) => value is String ? value : null;

/// A boolean, or null.
bool? asBool(Object? value) => value is bool ? value : null;

/// A list of strings (non-strings dropped).
List<String> asStringList(Object? value) => [
  for (final v in asList(value))
    if (v is String) v,
];

/// A string-to-string map (entries with non-string values dropped).
Map<String, String> asStringMap(Object? value) => {
  if (value is Map)
    for (final e in value.entries)
      if (e.value is String) '${e.key}': e.value as String,
};

/// The entries of [json] whose keys are not in [known], deep-copied.
JsonMap extraOf(Map json, Set<String> known) => <String, dynamic>{
  for (final e in json.entries)
    if (!known.contains(e.key)) '${e.key}': deepCopyJson(e.value),
};

/// Writes [value] under [key] unless it is null — "delete the key rather than store null".
void putIfNotNull(JsonMap out, String key, Object? value) {
  if (value != null) out[key] = value is num ? jsNum(value) : value;
}

/// Something that serialises to a JSON object and can be deep-copied.
abstract interface class JsonModel {
  JsonMap toJson();
}
