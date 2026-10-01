import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/dates.dart';
import 'package:opengym/data/local_data.dart';
import 'package:opengym/data/models/models.dart';
import 'package:opengym/data/sync_protocol.dart';

/// JSON as the wire/disk sees it (so `60` and `60.0` compare equal after a round trip).
Object? wire(Object? v) => jsonDecode(jsonEncode(v));

void main() {
  group('round trips keep every key, including unknown ones', () {
    test('settings', () {
      final json = {
        'unit': 'lb',
        'restSec': 120,
        'sound': false,
        'keepAwake': true,
        'theme': 'light',
        'accent': 'sky',
        'body': 'female',
        'gifSize': 'mini',
        'effort': 'rpe',
        'targetW': 77.5,
        'lang': 'es',
        'reminder': {'on': true, 'time': '07:30', 'tz': 'America/Puerto_Rico', 'future': 1},
        'showRir': true,
        'newerClientKey': {
          'a': [1, 2],
        },
      };
      expect(wire(Settings.fromJson(json).toJson()), json);
    });

    test('settings defaults are the contract defaults', () {
      expect(Settings.fromJson({}).toJson(), {
        'unit': 'kg',
        'restSec': 90,
        'sound': true,
        'keepAwake': true,
        'theme': 'dark',
        'accent': 'lime',
        'body': 'male',
        'gifSize': 'full',
        'effort': null,
        'targetW': null,
        'lang': 'es',
        'reminder': {'on': false, 'time': '08:00', 'tz': null},
      });
    });

    test('plan with routines, supersets and custom exercises', () {
      final json = {
        'routines': [
          {
            'id': 'muo979oo50vo1',
            'name': 'Push Day',
            'emoji': 'barbell',
            'prog': 'linear',
            'note': 'from Claude',
            'ex': [
              {'id': '0025', 'sets': 4, 'mode': 'reps', 'reps': 8, 'weight': 60, 'inc': 2.5},
              {'id': '0334', 'sets': 3, 'mode': 'reps', 'reps': 12, 'weight': 10, 'sg': 'sgA', 'why': 'x'},
              {'id': '0241', 'sets': 3, 'mode': 'reps', 'reps': 12, 'weight': 25, 'sg': 'sgA'},
              {'id': '0001', 'sets': 3, 'mode': 'time', 'sec': 45, 'weight': 0, 'prog': 'time'},
              {'id': 'cX', 'sets': 3, 'mode': 'reps', 'reps': 10, 'weight': 0, 'prog': 'double', 'repsMin': 8},
              {'id': '0685', 'sets': 1, 'min': 20, 'speed': 8.5},
            ],
          },
        ],
        'week': {'1': 'muo979oo50vo1', '5': 'gone'},
        'customEx': [
          {
            'id': 'cX',
            'n': 'Nordic curl',
            'bp': 'upper legs',
            'desc': '',
            'tg': '',
            'eq': 'custom',
            'custom': true,
            'x': 1,
          },
        ],
        'unknownPlanKey': true,
      };
      expect(wire(PlanDoc.fromJson(json).toJson()), json);
    });

    test('schedule, athlete and coach', () {
      final schedule = {
        'dayPlan': {'2026-09-30': 'r1', '2026-10-02': 'rest'},
        'k': 'v',
      };
      expect(wire(ScheduleDoc.fromJson(schedule).toJson()), schedule);

      final athlete = {
        'goal': 'strength',
        'experience': 'regular',
        'daysPerWeek': 4,
        'preferredDays': [1, 2, 4, 6],
        'sessionMin': 60,
        'equipment': ['barbell', 'dumbbell'],
        'limitations': 'rodilla',
        'likes': '',
        'dislikes': 'burpees',
        'notes': '',
        'savedAt': 1790000000000,
        'updatedBy': 'claude',
        'extraField': [1],
      };
      expect(wire(AthleteProfile.fromJson(athlete).toJson()), athlete);

      final coach = {
        'log': [
          {
            'id': 'l1',
            'kind': 'review',
            'at': 1,
            'decisions': [
              {'id': 'c1', 'status': 'accepted'},
            ],
          },
        ],
        'snapshots': [
          {
            'at': 2,
            'proposalId': 'p1',
            'label': 'Antes',
            'routines': [],
            'week': {'1': 'r1'},
            'extra': 'y',
          },
        ],
        'lastReview': {'at': 3},
        'k': null,
      };
      expect(wire(CoachDoc.fromJson(coach).toJson()), coach);
    });

    test('workout with entries, targets, efforts and stamped names', () {
      final json = {
        'id': 'muo979osyicjp',
        'd': '2026-09-28',
        'start': 1790618820000,
        'end': 1790622240000,
        'routineId': 'muo979oo50vo1',
        'name': 'Push Day',
        'bw': 78.7,
        'entries': [
          {
            'id': '0025',
            'sets': [
              {'w': 75, 'r': 8, 'done': true, 'rir': 3},
              {'w': 75, 'r': 7, 'done': true, 'rpe': 9.5},
              {'w': 75, 'r': 8, 'done': false},
            ],
            'topW': 75,
            'target': {'id': '0025', 'sets': 4, 'mode': 'reps', 'reps': 8, 'weight': 60},
          },
          {
            'id': 'cGone',
            'sets': [
              {'sec': 38, 'w': 0, 'done': true, 'unknownSetKey': 'x'},
            ],
            'topW': null,
            'n': 'Nordic curl',
          },
        ],
        'prs': ['0025'],
        'vol': 1125,
        'rating': 'right',
        'note': 'Felt strong',
        'importedFrom': 'x',
      };
      expect(wire(Workout.fromJson(json).toJson()), json);
    });

    test('body weight, working weight, proposal, active workout', () {
      final bw = {'d': '2026-09-30', 'w': 78.7, 't': 1790580600000};
      expect(wire(BodyWeight.fromJson(bw).toJson()), bw);
      final ex = {'w': 75, 'd': '2026-09-28'};
      expect(wire(ExWeight.fromJson(ex).toJson()), ex);

      final proposal = {
        'id': 'p1a2b3c4d5e6f7a8b',
        'kind': 'changes',
        'status': 'pending',
        'createdAt': 1790622242000,
        'expiresAt': 1791831842000,
        'planHash': 'f784c8ca82c205eb',
        'unit': 'kg',
        'iteration': 1,
        'summary': 'Sube el press',
        'resolution': null,
        'resolvedAt': null,
        'revertedAt': null,
        'seq': 128,
        'evidence': {'from': '2026-09-01', 'to': '2026-09-28', 'sessions': 9},
        'changes': [
          {
            'id': 'c1',
            'type': 'reps',
            'target': {'routineId': 'r1', 'exId': '0025'},
            'before': 8,
            'after': 10,
            'why': 'porque',
          },
        ],
        'notes': ['Duerme más'],
      };
      final p = Proposal.fromJson(proposal);
      expect(wire(p.toJson()), proposal);
      expect(p.changes.single.type, 'reps');
      expect(p.changes.single.target.exId, '0025');
      expect(p.evidence!['sessions'], 9);
      expect(p.notes, ['Duerme más']);

      final active = {
        'id': 'a1',
        'd': '2026-09-30',
        'start': 1790600000000,
        'routineId': 'r1',
        'name': 'Push',
        'bw': null,
        'cur': 1,
        'entries': [
          {
            'id': '0025',
            'sg': 'sgA',
            'target': {'id': '0025', 'sets': 3, 'mode': 'reps', 'reps': 8},
            'plan': {
              'policy': 'linear',
              'kind': 'up',
              'weight': 62.5,
              'why': ['Every rep last time — {0} {1} more.', 2.5, 'kg'],
            },
            'sets': [
              {'w': 62.5, 'r': 8, 'done': false},
            ],
            'topW': 62.5,
            'asked': true,
          },
        ],
      };
      expect(wire(ActiveWorkout.fromJson(active).toJson()), active);
    });
  });

  group('set records delete optional keys instead of storing null', () {
    test('clearing an effort removes the key', () {
      final s = SetRecord.fromJson({'w': 60, 'r': 10, 'done': true, 'rir': 2});
      s.rir = null;
      expect(s.toJson(), {'w': 60, 'r': 10, 'done': true});
      expect(s.toJson().containsKey('rir'), isFalse);
    });

    test('a null in stored data reads as absent and is not written back', () {
      final s = SetRecord.fromJson({'w': 60, 'r': 10, 'done': false, 'rpe': null});
      expect(s.toJson().containsKey('rpe'), isFalse);
    });

    test('mode-specific shapes stay minimal', () {
      expect(SetRecord(min: 20, speed: 8.5).toJson(), {'min': 20, 'speed': 8.5, 'done': false});
      expect(SetRecord(sec: 45, w: 0, done: true).toJson(), {'w': 0, 'sec': 45, 'done': true});
    });

    test('optional workout fields are deleted, always-present ones kept as null', () {
      final w = Workout.fromJson(workoutJson())
        ..rating = null
        ..note = null;
      final json = w.toJson();
      expect(json.containsKey('rating'), isFalse);
      expect(json.containsKey('note'), isFalse);
      expect(json.containsKey('bw'), isTrue);
      expect(json['bw'], isNull);
      expect(json['entries'][0].containsKey('topW'), isTrue);
    });
  });

  group('tolerant readers', () {
    test('a workout without start reads as local noon of d', () {
      final w = Workout.fromJson({'id': 'x', 'd': '2026-09-28', 'entries': []});
      expect(w.start, DateTime(2026, 9, 28, 12).millisecondsSinceEpoch);
      expect(w.end, w.start);
      expect(localNoonMs('2026-09-28'), w.start);
    });

    test('wrong types fall back to defaults', () {
      final s = Settings.fromJson({'restSec': 'ninety', 'sound': 'yes', 'targetW': 'x'});
      expect(s.restSec, 90);
      expect(s.sound, isTrue);
      expect(s.targetW, isNull);
    });

    test('a plan-file custom exercise gains the full shape (data-B3)', () {
      expect(CustomExercise.fromJson({'id': 'x1', 'n': 'Curl raro', 'bp': 'upper arms'}).toJson(), {
        'id': 'x1',
        'n': 'Curl raro',
        'bp': 'upper arms',
        'desc': '',
        'tg': '',
        'eq': 'custom',
        'custom': true,
      });
    });

    test('integral doubles are stored as ints, like JavaScript', () {
      final e = RoutineExercise(id: '0025', reps: 8.0, weight: 60.0, inc: 2.5);
      final json = e.toJson();
      expect(json['reps'], isA<int>());
      expect(json['weight'], isA<int>());
      expect(json['inc'], 2.5);
      expect(jsonEncode(json), '{"id":"0025","sets":3,"reps":8,"weight":60,"inc":2.5}');
    });

    test('target config merges the entry id', () {
      final entry = WorkoutEntry.fromJson({
        'id': '0025',
        'sets': [],
        'target': {'sets': 3, 'reps': 8},
      });
      expect(entry.targetConfig!.id, '0025');
      expect(entry.targetConfig!.reps, 8);
    });
  });

  group('settings.effortScale (effortOf)', () {
    String scale(Map<String, dynamic> json) => Settings.fromJson(json).effortScale;

    test('vectors of specs/ui.md §8', () {
      expect(scale({'effort': 'rpe'}), 'rpe');
      expect(scale({'effort': 'rir'}), 'rir');
      expect(scale({'effort': 'none'}), 'none');
      expect(scale({}), 'none');
      expect(scale({'showRir': true}), 'rir');
      expect(scale({'effort': null, 'showRir': true}), 'rir');
      expect(scale({'showRir': false}), 'none');
      expect(scale({'showRir': true, 'effort': 'rpe'}), 'rpe');
      expect(scale({'showRir': true, 'effort': 'none'}), 'none');
      expect(scale({'effort': 'rpe10'}), 'none');
      expect(scale({'effort': 'nope', 'showRir': true}), 'rir');
    });

    test('saving a scale deletes the legacy flag', () {
      final s = Settings.fromJson({'showRir': true})..setEffortScale('rpe');
      expect(s.toJson().containsKey('showRir'), isFalse);
      expect(s.effortScale, 'rpe');
    });
  });

  group('superset cleanup (cleanupSg)', () {
    List<String?> sgs(List<RoutineExercise> ex) => [for (final e in ex) e.sg];

    test('unlinking the middle of a three-chain dissolves the group', () {
      final ex = [RoutineExercise(id: 'a', sg: 'g'), RoutineExercise(id: 'b'), RoutineExercise(id: 'c', sg: 'g')];
      Routine.cleanupSupersets(ex);
      expect(sgs(ex), [null, null, null]);
    });

    test('adjacent partners keep their tag', () {
      final ex = [
        RoutineExercise(id: 'a', sg: 'g'),
        RoutineExercise(id: 'b', sg: 'g'),
        RoutineExercise(id: 'c', sg: 'h'),
      ];
      Routine.cleanupSupersets(ex);
      expect(sgs(ex), ['g', 'g', null]);
    });
  });

  test('copies are deep', () {
    final plan = PlanDoc.fromJson({
      'routines': [
        {
          'id': 'r1',
          'name': 'A',
          'ex': [
            {'id': '0025', 'sets': 3},
          ],
        },
      ],
    });
    final copy = plan.copy();
    copy.routines.first.ex.first.sets = 5;
    copy.week['1'] = 'r1';
    expect(plan.routines.first.ex.first.sets, 3);
    expect(plan.week, isEmpty);
  });

  test('local data round-trips through state.json', () {
    final data = LocalData()
      ..lastSeq = 131
      ..epoch = 4815162342
      ..clockOffset = -250
      ..hasClockOffset = true
      ..needsInitialSync = true;
    data.docs[DocKey.plan] = DocRecord(data: PlanDoc(week: {'1': 'r1'}), baseSeq: 118, updatedAt: 1790622241000);
    data.workouts['w1'] = RowRecord(data: Workout.fromJson(workoutJson()), updatedAt: 5);
    data.workouts['w2'] = RowRecord(data: Workout.fromJson(workoutJson()..['id'] = 'w2'), updatedAt: 6, deleted: true);
    data.bodyWeight['2026-09-30'] = RowRecord(data: BodyWeight(d: '2026-09-30', w: 78.7, t: 1), updatedAt: 7);
    data.exWeights['0025'] = RowRecord(data: ExWeight(w: 75, d: '2026-09-28'), updatedAt: 8);
    data.proposals['p1'] = Proposal(id: 'p1', kind: 'nochange', status: 'pending', extra: {'reading': 'Bien'});
    data.dirtyDocs.add(DocKey.plan);
    data.dirtyWorkouts.add('w2');

    final back = LocalData.fromJson(wire(data.toJson()));
    expect(wire(back.toJson()), wire(data.toJson()));
    expect(back.docs[DocKey.plan]!.baseSeq, 118);
    expect(back.workouts['w2']!.deleted, isTrue);
    expect(back.dirtyDocs, {DocKey.plan});
    expect(back.proposals['p1']!.reading, 'Bien');
    expect(back.needsInitialSync, isTrue);
  });
}

Map<String, dynamic> workoutJson() => {
  'id': 'w1',
  'd': '2026-09-28',
  'start': 1790618820000,
  'end': 1790622240000,
  'routineId': 'r1',
  'name': 'Push',
  'bw': null,
  'entries': [
    {
      'id': '0025',
      'sets': [
        {'w': 60, 'r': 8, 'done': true},
      ],
      'topW': null,
    },
  ],
  'prs': <String>[],
  'vol': 480,
};
