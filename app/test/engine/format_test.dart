/// The locale-dependent helpers the fixtures leave out (their README: the original tests assume
/// en-GB). These are the spec tables of engine.md §10.18 with es-ES number formatting.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/models/models.dart';
import 'package:opengym/engine/engine.dart';

import 'fixture_support.dart';

void main() {
  final index = indexWith();
  const lift = '0001', cardio = '3220';
  SetRecord set(JsonMap json) => SetRecord.fromJson(json);

  group('fmtNum (es-ES)', () {
    test('one decimal, decimal comma, no grouping under 10 000', () {
      expect(fmtNum(60), '60');
      expect(fmtNum(62.25), '62,3');
      expect(fmtNum(62.5), '62,5');
      expect(fmtNum(0.30000000000000004), '0,3');
      expect(fmtNum(1234.56), '1234,6');
      expect(fmtNum(12345), '12.345');
      expect(fmtNum(1234567.89), '1.234.567,9');
      expect(fmtNum(-1.25), '-1,2'); // Math.round: halves towards +∞
      expect(fmtNum(-0.04), '0');
      expect(fmtVol(7535, 'kg'), '7535 kg');
    });

    test('arguments keep every digit', () {
      expect(fmtArg(1.25), '1,25');
      expect(fmtArg(55), '55');
      expect(fmtArg('kg'), 'kg');
    });
  });

  test('fmtDate: es-ES short forms, local noon', () {
    expect(fmtDate('2026-09-30'), '30 sept');
    expect(fmtDate('2026-09-30', long: true), 'mié, 30 sept');
    expect(fmtDate('2026-01-04', long: true), 'dom, 4 ene');
    expect(fmtDate('nope'), 'nope');
  });

  test('exCount and names', () {
    expect(exCount(1), '1 ejercicio');
    expect(exCount(3), '3 ejercicios');
    expect(dayNames[0], 'Domingo');
    expect(dayLetters[weekdayOf('2026-09-30')], 'Mi');
    expect(monthNamesShort[11], 'Dic');
  });

  test('uid: base-36 time plus five random characters', () {
    final now = DateTime.utc(2026, 9, 30, 8);
    final id = uid(now);
    expect(id, startsWith(now.millisecondsSinceEpoch.toRadixString(36)));
    expect(id, matches(RegExp(r'^[0-9a-z]+$')));
    expect(id.length, now.millisecondsSinceEpoch.toRadixString(36).length + 5);
    final taken = <String>{};
    for (var i = 0; i < 200; i++) {
      taken.add(freshId(now, taken.contains, prefix: 'sg'));
    }
    expect(taken, hasLength(200));
  });

  group('setLabel (engine.md §10.18, es-ES)', () {
    test('by mode', () {
      expect(setLabel(index, lift, set({'w': 60, 'r': 10})), '60×10');
      expect(setLabel(index, cardio, set({'min': 20, 'speed': 9})), '20 min @ 9 km/h');
      expect(setLabel(index, lift, set({'sec': 45, 'w': 0}), RoutineExercise(id: lift, mode: 'time')), '0:45');
      expect(setLabel(index, lift, set({'sec': 90, 'w': 20}), RoutineExercise(id: lift, mode: 'time')), '1:30 · 20');
      expect(setLabel(index, lift, set({'w': 0, 'r': 0})), '0×0');
      expect(setLabel(index, cardio, set({})), '0 min @ 0 km/h');
      expect(setLabel(index, lift, set({'w': 1234.56, 'r': 5})), '1234,6×5');
      expect(setLabel(index, cardio, set({'min': 20, 'speed': 8.5})), '20 min @ 8,5 km/h');
    });

    test('effort tail: RIR wins, cardio and time never show it', () {
      expect(setLabel(index, lift, set({'w': 60, 'r': 10, 'rir': 2})), '60×10 (RIR 2)');
      expect(setLabel(index, lift, set({'w': 60, 'r': 10, 'rir': 1.5})), '60×10 (RIR 1,5)');
      expect(setLabel(index, lift, set({'w': 60, 'r': 10, 'rir': 0})), '60×10 (RIR 0)');
      expect(setLabel(index, lift, set({'w': 60, 'r': 10, 'rir': null})), '60×10');
      expect(setLabel(index, lift, set({'w': 60, 'r': 10, 'rpe': 8})), '60×10 (RPE 8)');
      expect(setLabel(index, lift, set({'w': 60, 'r': 10, 'rpe': 9.5})), '60×10 (RPE 9,5)');
      expect(setLabel(index, lift, set({'w': 60, 'r': 10, 'rir': 2, 'rpe': 8})), '60×10 (RIR 2)');
      expect(setLabel(index, cardio, set({'min': 20, 'speed': 9, 'rpe': 8})), '20 min @ 9 km/h');
      expect(setLabel(index, lift, set({'sec': 45, 'rir': 2}), RoutineExercise(id: lift, mode: 'time')), '0:45');
    });

    test('effort logging end to end', () {
      num? v;
      for (var i = 0; i < 4; i++) {
        v = stepEffort('rpe', v, 1);
      }
      expect(setLabel(index, lift, set({'w': 80, 'r': 5, 'rpe': v})), '80×5 (RPE 7,5)');
      expect(setLabel(index, lift, set({'w': 100, 'r': 3, 'rir': stepEffort('rir', null, 1)})), '100×3 (RIR 0)');
    });
  });

  test('exLine (engine.md §10.18)', () {
    expect(exLine(index, RoutineExercise(id: lift, sets: 3, reps: 10), 'kg'), '3 × 10');
    expect(exLine(index, RoutineExercise(id: lift, sets: 3, reps: 10, weight: 60), 'kg'), '3 × 10 · 60 kg');
    expect(exLine(index, RoutineExercise(id: lift, sets: 3, sec: 45, mode: 'time'), 'kg'), '3 × 0:45');
    expect(
      exLine(index, RoutineExercise(id: lift, sets: 2, sec: 90, weight: 20, mode: 'time'), 'kg'),
      '2 × 1:30 · 20 kg',
    );
    expect(exLine(index, RoutineExercise(id: cardio, sets: 1, min: 20, speed: 8), 'kg'), '1 × 20 min @ 8 km/h');
    expect(exLine(index, RoutineExercise(id: lift, sets: 3, reps: 10, weight: 62.5), 'lb'), '3 × 10 · 62,5 lb');
    expect(exLine(index, RoutineExercise(id: lift, sets: 3), 'kg'), '3 × ');
  });

  group('why', () {
    test('renders every template in Spanish with its arguments', () {
      expect(whyText([WhyTemplate.up, 2.5, 'kg']), 'La última vez, todas las repeticiones: 2,5 kg más.');
      expect(
        whyText([WhyTemplate.hold, 2, 3]),
        'Fallaste repeticiones la última vez: el mismo peso otra vez (quedan 2 de 3).',
      );
      expect(whyText([WhyTemplate.timeUp, 5]), 'Aguantaste todas las series el tiempo completo: objetivo +5 s.');
      expect(
        whyText([WhyTemplate.targetChanged]),
        'El objetivo del plan cambió: esta sesión marca el nuevo punto de partida.',
      );
      expect(
        whyText([WhyTemplate.doubleUp, 1.25, 'kg', 8]),
        'Tope del rango en todas las series: 1,25 kg más, vuelta a 8 repeticiones.',
      );
    });

    test('no why, or an unknown template shown as is', () {
      expect(whyText(null), isNull);
      expect(whyText(const []), isNull);
      expect(whyText(['Something new {0}', 3]), 'Something new 3');
    });

    test('policy names and descriptions exist for every policy', () {
      for (final p in policies) {
        expect(policyNames[p], isNotEmpty);
        expect(policyDescriptions[p], isNotEmpty);
      }
      expect(policyNames['double'], 'Progresión doble');
    });
  });
}
