import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/library.dart';
import 'package:opengym/data/models/models.dart';

import 'fake_server.dart';

void main() {
  final library = loadTestLibrary();
  final customs = [
    CustomExercise(id: 'cNordic', n: 'Nordic curl', bp: 'upper legs', desc: 'Rodillas en el suelo, baja despacio'),
    // Old plan-file shape (no tg/eq/custom): must not break search (data-B3).
    CustomExercise.fromJson({'id': 'x9', 'n': 'Remo raro', 'bp': 'back'}),
  ];
  final catalog = ExerciseCatalog(library, customs);
  List<String> ids(ExerciseSearch s) => [for (final e in s.results) e.id];

  test('loads the 1,324 built-ins in dataset order with Spanish labels', () {
    expect(library.builtIns, hasLength(1324));
    expect(library.builtIns.first.id, '0001');
    final bench = library.byId('0025')!;
    expect(bench.name, 'barbell bench press');
    expect(bench.bodyPartEs, 'pecho');
    expect(bench.equipmentEs, 'barra');
    expect(bench.targetEs, 'pectorales');
    expect(bench.steps.first, startsWith('Túmbate'));
    expect(library.bodyParts, [
      'back',
      'cardio',
      'chest',
      'lower arms',
      'lower legs',
      'neck',
      'shoulders',
      'upper arms',
      'upper legs',
      'waist',
    ]);
  });

  test('customs come first and are indexed by id', () {
    expect(catalog.all.take(2).map((e) => e.id), ['cNordic', 'x9']);
    expect(catalog.length, 1326);
    final nordic = catalog.byId('cNordic')!;
    expect(nordic.custom, isTrue);
    expect(nordic.equipment, 'custom');
    expect(nordic.equipmentEs, 'propio');
    expect(nordic.bodyPartEs, 'piernas');
    expect(nordic.hasMedia, isFalse);
  });

  test('unknown ids render as a placeholder', () {
    final ex = catalog.exOr('nope');
    expect(ex.missing, isTrue);
    expect(ex.name, 'Ejercicio desconocido');
    expect(catalog.byId('nope'), isNull);
  });

  test('isCardio follows the body part', () {
    expect(catalog.isCardio('0685'), isTrue);
    expect(catalog.isCardio('0025'), isFalse);
    expect(catalog.isCardio('nope'), isFalse);
  });

  group('search', () {
    test('matches English names, case-insensitively', () {
      final lower = catalog.search(query: 'bench press');
      final upper = catalog.search(query: '  BENCH PRESS ');
      expect(ids(lower), contains('0025'));
      expect(ids(upper), ids(lower));
      expect(lower.results.every((e) => e.name.contains('bench press') || e.target.contains('bench press')), isTrue);
    });

    test('matches target and equipment like the original', () {
      expect(ids(catalog.search(query: 'pectorals')), contains('0025'));
      expect(
        catalog
            .search(query: 'kettlebell')
            .results
            .every((e) => e.equipment == 'kettlebell' || e.name.contains('kettlebell')),
        isTrue,
      );
    });

    test('also matches the Spanish labels, ignoring accents', () {
      final withAccent = catalog.search(query: 'bíceps');
      final without = catalog.search(query: 'Biceps');
      expect(ids(withAccent), ids(without));
      expect(withAccent.results, isNotEmpty);
      final dumbbells = catalog.search(query: 'mancuerna').results;
      expect(dumbbells, isNotEmpty);
      expect(dumbbells.every((e) => e.equipment == 'dumbbell'), isTrue);
      expect(ids(catalog.search(query: 'pecho')), contains('0025'));
    });

    test('matches custom descriptions and tolerates old-shape customs', () {
      expect(ids(catalog.search(query: 'despacio')), ['cNordic']);
      expect(ids(catalog.search(query: 'remo raro')), ['x9']);
    });

    test('filters by body part and offers equipment by frequency', () {
      final chest = catalog.search(bodyPart: 'chest');
      expect(chest.results.every((e) => e.bodyPart == 'chest'), isTrue);
      expect(chest.results.length, 163);
      expect(chest.equipmentOptions, equipmentOf(chest.base));
      final counts = {for (final eq in chest.equipmentOptions) eq: chest.base.where((e) => e.equipment == eq).length};
      final values = counts.values.toList();
      for (var i = 1; i < values.length; i++) {
        expect(values[i] <= values[i - 1], isTrue);
      }
      final barbell = catalog.search(bodyPart: 'chest', equipment: 'barbell');
      expect(barbell.equipment, 'barbell');
      expect(barbell.results.every((e) => e.equipment == 'barbell' && e.bodyPart == 'chest'), isTrue);
    });

    test('drops an equipment filter the search emptied', () {
      final s = catalog.search(query: 'nordic', equipment: 'barbell');
      expect(s.equipment, isNull);
      expect(ids(s), ['cNordic']);
    });

    test('a custom filter and sort replace the body-part filter (the picker\'s "Elegidos")', () {
      final usage = {'0025': 1, '0043': 3};
      final s = catalog.search(
        bodyPart: 'chest',
        where: (e) => usage.containsKey(e.id),
        sort: (a, b) => usage[b.id]!.compareTo(usage[a.id]!),
      );
      expect(ids(s), ['0043', '0025']);
    });
  });

  test('equipmentOf breaks ties alphabetically', () {
    Exercise ex(String eq) => Exercise(
      id: eq,
      name: eq,
      bodyPart: 'x',
      equipment: eq,
      target: '',
      bodyPartEs: '',
      equipmentEs: '',
      targetEs: '',
    );
    expect(equipmentOf([ex('rope'), ex('band'), ex('band'), ex('cable'), ex('rope'), ex('')]), [
      'band',
      'rope',
      'cable',
    ]);
  });

  test('media URLs use the pinned jsDelivr mirror', () {
    final bench = library.byId('0025')!;
    expect(bench.imageUrl, '$mediaBase/images/0025-EIeI8Vf.jpg');
    expect(bench.gifUrl, '$mediaBase/videos/0025-EIeI8Vf.gif');
    expect(mediaBase, contains('@7455efae41b330c265e7cd4b78dfa848e7ce5ebd'));
    expect(catalog.byId('cNordic')!.gifUrl, isNull);
  });

  test('Spanish label helpers pass unknown values through', () {
    expect(bodyPartLabel('upper legs'), 'piernas');
    expect(equipmentLabel('custom'), 'propio');
    expect(targetLabel('glutes'), 'glúteos');
    expect(muscleLabel('rear deltoids'), 'deltoides posterior');
    expect(bodyPartLabel('tail'), 'tail');
  });

  test('foldForSearch strips case and accents', () {
    expect(foldForSearch('Cuádriceps ÑÜ'), 'cuadriceps nu');
  });
}
