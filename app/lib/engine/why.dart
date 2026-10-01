/// The `why` line of a prescription. The engine keeps the original English i18n keys as
/// templates (engine.md §12 item 12, contract §2.3); [whyText] renders them in Spanish with the
/// translations of `frontend/src/locales/es.js`.
library;

import 'format.dart';

/// The `why` templates, `{0}`, `{1}`… standing for the arguments that follow the template.
abstract final class WhyTemplate {
  static const first = 'Nothing logged yet — this session sets the baseline.';
  static const targetChanged = 'Plan target changed — this session sets the new baseline.';
  static const timeUp = 'Held every set for the full time — target up by {0}s.';
  static const timeDeload = 'Short {0} sessions in a row — back off to {1}s and build up again.';
  static const timeHold = 'Last time came up short — same target again.';
  static const bodyweightUp = 'Bodyweight — every rep last time, so go for {0} this time.';
  static const bodyweightHold = 'Bodyweight — same target again until every set is clean.';
  static const doubleUp = 'Top of the rep range in every set — {0} {1} more, back to {2} reps.';
  static const doubleDeload = 'Stalled {0} sessions — deload to {1} {2}.';
  static const doubleHold = 'Same weight — aim for {0} reps this time.';
  static const greyskullDoubleJump = 'Last set hit {0} reps — twice the target, so take a double jump of {1} {2}.';
  static const up = 'Every rep last time — {0} {1} more.';
  static const deloadRunning = 'Missed reps {0} sessions running — reset to {1} {2} and work back up.';
  static const deloadOnce = 'Missed reps — reset to {0} {1} and work back up.';
  static const hold = 'Missed reps last time — same weight again ({0} of {1} to go).';
}

const _spanish = {
  WhyTemplate.first: 'Aún no hay nada registrado: esta sesión marca el punto de partida.',
  WhyTemplate.targetChanged: 'El objetivo del plan cambió: esta sesión marca el nuevo punto de partida.',
  WhyTemplate.timeUp: 'Aguantaste todas las series el tiempo completo: objetivo +{0} s.',
  WhyTemplate.timeDeload: '{0} sesiones seguidas por debajo: baja a {1} s y vuelve a subir.',
  WhyTemplate.timeHold: 'La última vez te quedaste corto: el mismo objetivo otra vez.',
  WhyTemplate.bodyweightUp: 'Peso corporal: la última vez todas las repeticiones, así que ve a por {0} esta vez.',
  WhyTemplate.bodyweightHold: 'Peso corporal: el mismo objetivo hasta que todas las series salgan limpias.',
  WhyTemplate.doubleUp: 'Tope del rango en todas las series: {0} {1} más, vuelta a {2} repeticiones.',
  WhyTemplate.doubleDeload: '{0} sesiones estancado: descarga a {1} {2}.',
  WhyTemplate.doubleHold: 'Mismo peso: esta vez apunta a {0} repeticiones.',
  WhyTemplate.greyskullDoubleJump:
      'La última serie llegó a {0} repeticiones: el doble del objetivo, así que sube el doble, {1} {2}.',
  WhyTemplate.up: 'La última vez, todas las repeticiones: {0} {1} más.',
  WhyTemplate.deloadRunning: '{0} sesiones seguidas fallando repeticiones: vuelve a {1} {2} y sube de nuevo.',
  WhyTemplate.deloadOnce: 'Fallaste repeticiones: vuelve a {0} {1} y sube de nuevo.',
  WhyTemplate.hold: 'Fallaste repeticiones la última vez: el mismo peso otra vez (quedan {0} de {1}).',
};

/// Fills `{0}`, `{1}`… in [template] with [args] (numbers with a decimal comma, not rounded).
String fillTemplate(String template, List<Object?> args) {
  var text = template;
  for (var i = 0; i < args.length; i++) {
    text = text.replaceAll('{$i}', fmtArg(args[i]));
  }
  return text;
}

/// A prescription's `why` (`[template, ...args]`) as Spanish text, or null when there is none.
/// An unknown template (a newer engine) is shown as is.
String? whyText(List<dynamic>? why) {
  if (why == null || why.isEmpty || why.first is! String) return null;
  final template = why.first as String;
  return fillTemplate(_spanish[template] ?? template, why.sublist(1));
}
