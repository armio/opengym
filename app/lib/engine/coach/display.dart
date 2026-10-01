/// Spanish text for proposals and the coach log (specs/coach.md §7.10, translations from
/// `frontend/src/locales/es.js`, "Coach" for "the Coach"). Change and decision maps are the raw
/// JSON of a proposal change or a log decision; they share the fields read here.
library;

import '../../data/models/json.dart';
import '../catalog.dart';
import '../format.dart';
import '../js.dart';
import '../progression.dart';

String _name(ExerciseIndex catalog, Object? id) => catalog.nameOf(id is String ? id : null);

/// The headline of a change: "Añadir barbell bench press", "3/4 sit-up: series"… Exercise names
/// are the dataset's lowercase English ones; capitalise them for display.
String changeTitle(JsonMap change, ExerciseIndex catalog) {
  final target = asMap(change['target']);
  final after = change['after'];
  final afterMap = asMap(after);
  final ex = jsTruthy(target['exId']) ? _name(catalog, target['exId']) : null;
  return switch (change['type']) {
    'add-exercise' => 'Añadir ${_name(catalog, afterMap['id'])}',
    'remove-exercise' => 'Quitar $ex',
    'swap-exercise' => 'Cambiar $ex por ${_name(catalog, afterMap['id'])}',
    'sets' => '$ex: series',
    'reps' => '$ex: repeticiones',
    'repsMin' => '$ex: mínimo del rango de repeticiones',
    'sec' => '$ex: tiempo de sostén',
    'cardio' => '$ex: duración y ritmo',
    'inc' => '$ex: incremento de carga',
    'exercise-prog' => '$ex: progresión',
    'routine-prog' => 'Progresión de la rutina',
    'reorder' => 'Reordenar ejercicios',
    'superset' when jsTruthy(afterMap['link']) => 'Superserie de $ex con ${_name(catalog, afterMap['with'])}',
    'superset' => 'Deshacer la superserie de $ex',
    'add-routine' => 'Añadir rutina «${jsString(afterMap['name'], nullText: '')}»',
    'remove-routine' => 'Eliminar una rutina',
    'rename-routine' => 'Renombrar la rutina a «${jsString(after, nullText: '')}»',
    'week' => 'Cambiar lo planificado en un día',
    final type => jsString(type, nullText: ''),
  };
}

const _noValue = '—';

/// Before → after strings for the diff chips, or null for the changes shown without them (adding,
/// removing and reordering). [routineName] resolves routine ids for `week` changes; without it
/// the ids are shown.
({String before, String after})? changeValues(
  JsonMap change,
  ExerciseIndex catalog, {
  String? Function(String routineId)? routineName,
}) {
  final type = change['type'];
  if (const ['add-exercise', 'add-routine', 'reorder', 'remove-exercise', 'remove-routine'].contains(type)) return null;
  String format(Object? v) => _formatValue(type, v, catalog, routineName);
  return (before: format(change['before']), after: format(change['after']));
}

String _formatValue(Object? type, Object? v, ExerciseIndex catalog, String? Function(String)? routineName) {
  if (v == null) return type == 'week' ? 'Descanso' : _noValue;
  switch (type) {
    case 'week':
      final id = jsString(v);
      return id == 'rest' ? 'Descanso' : (routineName?.call(id) ?? id);
    case 'exercise-prog' || 'routine-prog':
      return policyNames[v] ?? jsString(v);
    case 'sec':
      return v is num ? '${fmtArg(v)} s' : jsString(v);
    case 'cardio':
      final m = asMap(v);
      final parts = [
        if (asNum(m['min']) case final min?) '${fmtArg(min)} min',
        if (asNum(m['speed']) case final speed?) '${fmtArg(speed)} km/h',
      ];
      return parts.isEmpty ? _noValue : parts.join(' @ ');
    case 'superset':
      final m = asMap(v);
      return jsTruthy(m['link']) ? 'con ${_name(catalog, m['with'])}' : 'sin superserie';
  }
  if (v is Map) {
    if (jsTruthy(v['id'])) return _name(catalog, v['id']);
    return jsTruthy(v['name']) ? jsString(v['name']) : jsonStringify(v);
  }
  if (v is List) return jsonStringify(v);
  return fmtArg(v);
}

/// Title of a coach log entry in the history list.
String logEntryTitle(JsonMap entry) => switch (entry['kind']) {
  'create' => 'Creó un plan',
  'revert' => 'Deshizo los últimos cambios',
  _ => 'Revisó tu entrenamiento',
};

/// Title of a coach log entry's detail sheet.
String logEntryHeading(JsonMap entry) => switch (entry['kind']) {
  'create' => 'Plan del Coach',
  'revert' => 'Deshacer',
  _ => 'Revisión del Coach',
};

/// The decisions of a log entry, in order.
List<JsonMap> logDecisions(JsonMap entry) => [
  for (final d in asList(entry['decisions']))
    if (d is Map) asMap(d),
];

/// How many changes a `review` entry applied.
int appliedCount(JsonMap entry) => logDecisions(entry).where((d) => d['status'] == 'accepted').length;

/// Tag of one decision: "aplicado", "rechazado" or "no aplicable".
String decisionLabel(Object? status) => switch (status) {
  'accepted' => 'aplicado',
  'stale' => 'no aplicable',
  _ => 'rechazado',
};

/// Button of a change set: "Aplicar 1 cambio", "Aplicar 3 cambios" or "No aplicar nada".
String applyButtonLabel(int count) => switch (count) {
  0 => 'No aplicar nada',
  1 => 'Aplicar 1 cambio',
  _ => 'Aplicar $count cambios',
};

/// Toast after applying: "1 cambio aplicado", "3 cambios aplicados".
String appliedToast(int count) => count == 1 ? '1 cambio aplicado' : '$count cambios aplicados';

/// Shown on a stale change.
const staleChangeNote = 'Ya no coincide con tu plan: no se puede aplicar.';

/// The plan-moved banner.
const planMovedNote =
    'Tu plan cambió desde que Claude lo revisó. Las sugerencias que ya no encajan aparecen atenuadas: pide a Claude una revisión nueva para verlas de nuevo.';
