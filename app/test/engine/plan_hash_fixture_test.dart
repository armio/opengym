import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/models/models.dart';
import 'package:opengym/engine/engine.dart';

import 'fixture_support.dart';

void main() {
  final library = indexWith();

  group('plan-hash.json', () {
    final vectors = asList(loadFixture('plan-hash.json')['vectors']);
    for (var i = 0; i < vectors.length; i++) {
      final v = asMap(vectors[i]);
      test('#$i ${v['name']}', () {
        final plan = asMap(v['plan']);
        final customs = [for (final c in asList(plan['customEx'])) CustomExercise.fromJson(c)];
        final canonical = canonicalPlan(plan, library.withCustoms(customs));
        expectJson(canonical, v['canonical']);
        expect(canonString(canonical), v['canon']);
        expect(hashPlan(canonical), v['hash']);
        expect(planHashOfJson(plan, library), v['hash']);
      });
    }

    // The typed plan doc hashes like its JSON whenever the JSON holds well-typed values: the
    // seven golden vectors of coach.md §7.1 and the custom-exercise one.
    for (var i = 0; i < 8; i++) {
      final v = asMap(vectors[i]);
      test('typed PlanDoc #$i ${v['name']}', () => expect(planHash(PlanDoc.fromJson(v['plan']), library), v['hash']));
    }
  });

  group('current-value.json', () {
    final fixture = loadFixture('current-value.json');
    final plan = PlanDoc.fromJson(fixture['plan']);
    for (final raw in asList(fixture['vectors'])) {
      final v = asMap(raw);
      test('${v['name']}', () {
        final change = asMap(v['change']);
        final expected = fromJs(v['expected']);
        final structural = v['expected'] is Map;
        expect(isScalarChange(change['type'] as String), !structural);
        expect(currentValue(plan, change), structural ? isNull : expected);
      });
    }
  });

  test('the change types are the Worker validator\'s', () {
    final serverTypes = asStringList(asMap(loadFixture('validate.json')['constants'])['CHANGE_TYPES']);
    expect([...changeTypes]..sort(), [...serverTypes]..sort());
  });

  test('imul32 keeps the low 32 bits like Math.imul(...) >>> 0', () {
    // The VM's 64-bit ints hold these products exactly, so plain arithmetic is the reference.
    expect(imul32(0xffffffff, 0xffffffff), 1);
    expect(imul32(0x811c9dc5 ^ 0x7b, 0x01000193), ((0x811c9dc5 ^ 0x7b) * 0x01000193) % 0x100000000);
    expect(imul32(123456789, 987654321), (123456789 * 987654321) % 0x100000000);
  });
}
