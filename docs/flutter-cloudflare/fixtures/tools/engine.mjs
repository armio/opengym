// Vector specs for fixtures/engine/*.json: every case of specs/engine.md §10–§11 plus the
// cases each fix of contract §2.3 adds. Ids are real catalogue ids, exactly as the original
// tests pick them: LIFT = first non-cardio, non-heavy exercise, HEAVY = first `upper legs`,
// CARDIO = first `cardio`.

import { js } from './json.mjs'

export const LIFT = '0001'     // 3/4 sit-up, waist
export const HEAVY = '1512'    // upper legs
export const CARDIO = '3220'   // cardio
export const BENCH = '0025'    // barbell bench press
export const SQUAT = '0043'    // barbell full squat

/** A custom exercise in the data-B3 shape; heavy by body part. */
const CUSTOM_LEGS = { id: 'cx-legs', n: 'sled push', bp: 'upper legs', desc: '', tg: '', eq: 'custom', custom: true }

/* ------------------------------------------------------------------ state builders */

const set = (w, r, done = true) => ({ w, r, done })

/** progression.test.js `hist`: one workout per row [weight, ...reps]; a null rep = unchecked set. */
function hist(id, rows, target) {
  return {
    unit: 'kg',
    workouts: rows.map((row, i) => ({
      d: '2026-01-0' + (i + 1),
      entries: [{
        id,
        target: target || { sets: 3, reps: 5, weight: row[0] },
        sets: row.slice(1).map(r => (r === null ? set(row[0], 0, false) : set(row[0], r))),
      }],
    })),
  }
}

/** progression.test.js `timeHist`: timed sessions of LIFT against {sets:2, sec:45}. */
function timeHist(rows, target = { sets: 2, sec: 45, mode: 'time' }) {
  return {
    unit: 'kg',
    workouts: rows.map((row, i) => ({
      d: '2026-02-0' + (i + 1),
      entries: [{ id: LIFT, target, sets: row.map(sec => ({ sec, w: 0, done: true })) }],
    })),
  }
}

/** progression.test.js `legacy`: sessions logged before targets were stored. */
function legacy(rows) {
  return {
    unit: 'kg',
    workouts: rows.map((row, i) => ({
      d: '2026-03-' + String(i + 1).padStart(2, '0'),
      entries: [{ id: LIFT, sets: row.slice(1).map(r => set(row[0], r)) }],
    })),
  }
}

const times = (n, row) => Array.from({ length: n }, () => row)

/* ------------------------------------------------------------------ call adapters */

/** The original keeps custom exercises in a global index; each call registers the vector's own. */
function prepare(mod, state) {
  mod.exercises.registerCustom(state?.customEx || [])
  return state
}

const history = fn => (mod, a) => mod.history[fn](prepare(mod, a.state), a.exId)

/* ================================================================== history.json */

export function historyFile(clock) {
  return {
    about: 'frontend/src/lib/history.js (engine.md §2, §10.18) and workout ordering (engine-Q6/Q7).',
    clock,
    groups: {
      modeOf: {
        call: (mod, a) => { prepare(mod, a); return mod.history.modeOf(a.cfg) },
        vectors: [
          { name: 'cardio body part', ref: '§10.18', args: { cfg: { id: CARDIO } }, golden: 'cardio' },
          { name: 'non-cardio body part', args: { cfg: { id: LIFT } }, golden: 'reps' },
          { name: 'unknown id', args: { cfg: { id: 'no-such-exercise' } }, golden: 'reps' },
          { name: 'empty cfg', args: { cfg: {} }, golden: 'reps' },
          { name: 'null cfg', args: { cfg: null }, golden: 'reps' },
          { name: 'undefined cfg', args: { cfg: js('undefined') }, golden: 'reps' },
          { name: 'explicit time wins', args: { cfg: { id: LIFT, mode: 'time' } }, golden: 'time' },
          { name: 'explicit reps on cardio wins', args: { cfg: { id: CARDIO, mode: 'reps' } }, golden: 'reps' },
          { name: 'explicit time on cardio wins', args: { cfg: { id: CARDIO, mode: 'time' } }, golden: 'time' },
          { name: 'unknown mode falls back (lift)', args: { cfg: { id: LIFT, mode: 'nonsense' } }, golden: 'reps' },
          { name: 'empty mode falls back (cardio)', args: { cfg: { id: CARDIO, mode: '' } }, golden: 'cardio' },
          {
            name: 'custom exercise resolves through its body part',
            args: { cfg: { id: 'cx-run' }, customEx: [{ id: 'cx-run', n: 'sled run', bp: 'cardio', desc: '', tg: '', eq: 'custom', custom: true }] },
            golden: 'cardio',
          },
        ],
      },
      isTimed: {
        scope: 'app',
        call: (mod, a) => mod.history.isTimed(a.cfg),
        vectors: [
          { name: 'time mode', args: { cfg: { id: LIFT, mode: 'time' } }, golden: true },
          { name: 'no mode', args: { cfg: { id: LIFT } }, golden: false },
        ],
      },
      effortOf: {
        call: (mod, a) => mod.history.effortOf(a.settings),
        vectors: [
          ...[['rpe', 'rpe'], ['rir', 'rir'], ['none', 'none']].map(([effort, out]) => ({ name: `effort ${effort}`, args: { settings: { effort } }, golden: out })),
          { name: 'empty settings', args: { settings: {} }, golden: 'none' },
          { name: 'legacy showRir', args: { settings: { showRir: true } }, golden: 'rir' },
          { name: 'effort null + showRir', args: { settings: { effort: null, showRir: true } }, golden: 'rir' },
          { name: 'effort null', args: { settings: { effort: null } }, golden: 'none' },
          { name: 'showRir false', args: { settings: { showRir: false } }, golden: 'none' },
          { name: 'effort beats showRir', args: { settings: { showRir: true, effort: 'rpe' } }, golden: 'rpe' },
          { name: 'explicit none beats showRir', args: { settings: { showRir: true, effort: 'none' } }, golden: 'none' },
          { name: 'overlay of stored {showRir:true}', args: { settings: { unit: 'kg', effort: null, showRir: true } }, golden: 'rir' },
          { name: 'overlay of stored {}', args: { settings: { unit: 'kg', effort: null } }, golden: 'none' },
          { name: 'overlay of stored {showRir:true, effort:undefined}', args: { settings: { unit: 'kg', showRir: true } }, golden: 'rir' },
          { name: 'junk rpe10', args: { settings: { effort: 'rpe10' } }, golden: 'none' },
          { name: 'junk RIR (case)', args: { settings: { effort: 'RIR' } }, golden: 'none' },
          { name: 'junk f', args: { settings: { effort: 'f' } }, golden: 'none' },
          { name: 'null settings', args: { settings: null }, golden: 'none' },
          { name: 'junk + showRir falls back', args: { settings: { effort: 'nope', showRir: true } }, golden: 'rir' },
        ],
      },
      stepEffort: {
        scope: 'app',
        call: (mod, a) => mod.history.stepEffort(a.kind, a.cur, a.dir),
        vectors: [
          ['rir', null, 1, 0], ['rpe', null, 1, 6], ['rir', 0, 1, 0.5], ['rir', 0.5, 1, 1], ['rpe', 6, 1, 6.5],
          ['rir', null, -1, null], ['rpe', null, -1, null], ['rir', js('undefined'), -1, null],
          ['rir', 0, -1, null], ['rpe', 6, -1, null], ['rir', 0.5, -1, 0], ['rpe', 6.5, -1, 6],
          ['rir', 9.5, 1, 10], ['rir', 10, 1, 10], ['rpe', 10, 1, 10], ['rir', 0.1 + 0.2, 1, 0.8],
          ['rpe', 3, 1, 3.5], ['rpe', 3, -1, null], ['none', null, 1, null], ['none', 2, 1, 2], [js('undefined'), 2, -1, 2],
          ['rpe', 10.2, 1, 10], ['rpe', 10.2, -1, 9.7], ['rir', 12, -1, 11.5],
        ].map(([kind, cur, dir, out]) => ({ name: `${JSON.stringify(kind)} ${JSON.stringify(cur)} ${dir > 0 ? '+' : '−'}`, args: { kind, cur, dir }, golden: out })),
      },
      stepEffortSequence: {
        scope: 'app',
        note: 'Apply stepEffort(kind, value, dir) for each dir in order, starting from `start`.',
        call: (mod, a) => a.dirs.reduce((v, dir) => mod.history.stepEffort(a.kind, v, dir), a.start),
        vectors: [
          { name: 'six + taps on rpe from empty', args: { kind: 'rpe', start: null, dirs: [1, 1, 1, 1, 1, 1] }, golden: 8.5 },
          { name: 'four + taps on rpe from empty', args: { kind: 'rpe', start: null, dirs: [1, 1, 1, 1] }, golden: 7.5 },
        ],
      },
      capEffort: {
        scope: 'app',
        call: (mod, a) => mod.history.capEffort(a.kind, a.value),
        vectors: [['rir', 12, 10], ['rpe', 99, 10], ['rpe', 8, 8], ['rpe', 1, 1], ['rir', 0, 0], ['rir', null, null],
          ['rpe', js('undefined'), js('undefined')], ['none', 12, 12]]
          .map(([kind, value, out]) => ({ name: `${kind} ${JSON.stringify(value)}`, args: { kind, value }, golden: out })),
      },
      defaultConfig: {
        scope: 'app',
        call: (mod, a) => mod.history.defaultConfig(a.id, a.mode),
        vectors: [
          { name: 'reps by default', args: { id: LIFT }, golden: { sets: 3, reps: 10, weight: 0, mode: 'reps' } },
          { name: 'cardio by body part', args: { id: CARDIO }, golden: { sets: 1, min: 20, speed: 8 } },
          { name: 'time on request', args: { id: LIFT, mode: 'time' }, golden: { sets: 3, sec: 45, weight: 0, mode: 'time' } },
        ],
      },
      cleanupSg: {
        scope: 'app',
        note: 'cleanupSg mutates its argument; `expected` is the list afterwards.',
        call: (mod, a) => { mod.history.cleanupSg(a.ex); return a.ex },
        vectors: [
          { name: 'orphans lose their tag', ref: '§2.10', args: { ex: [{ sg: 'a' }, { sg: 'b' }, { sg: 'b' }, { sg: 'c' }] }, golden: [{}, { sg: 'b' }, { sg: 'b' }, {}] },
          { name: 'non-adjacent equal tags are orphans', args: { ex: [{ id: '1', sg: 'a' }, { id: '2' }, { id: '3', sg: 'a' }] }, golden: [{ id: '1' }, { id: '2' }, { id: '3' }] },
          { name: 'three-member superset survives', args: { ex: [{ id: '1', sg: 'a' }, { id: '2', sg: 'a' }, { id: '3', sg: 'a' }, { id: '4' }] } },
        ],
      },
      supersetUnits: {
        scope: 'app',
        call: (mod, a) => mod.history.supersetUnits(a.items),
        vectors: [
          { name: 'groups consecutive equal tags', ref: '§2.16', args: { items: [{}, { sg: 'a' }, { sg: 'a' }, { sg: 'b' }, { sg: 'a' }, {}] }, golden: [[0], [1, 2], [3], [4], [5]] },
          { name: 'empty', args: { items: [] }, golden: [] },
        ],
      },
      lastEntryFor: {
        call: history('lastEntryFor'),
        vectors: [
          {
            name: 'latest entry with a done set, done sets only',
            args: {
              exId: LIFT,
              state: {
                workouts: [
                  { d: '2026-01-01', entries: [{ id: LIFT, target: { sets: 2, reps: 5 }, sets: [set(60, 5), set(60, 5)] }] },
                  { d: '2026-01-02', entries: [{ id: LIFT, target: { sets: 2, reps: 5, mode: 'reps' }, sets: [set(62.5, 5), set(62.5, 3, false)] }] },
                  { d: '2026-01-03', entries: [{ id: LIFT, sets: [set(65, 0, false)] }] },
                ],
              },
            },
            golden: { d: '2026-01-02', sets: [set(62.5, 5)], target: { sets: 2, reps: 5, mode: 'reps' } },
          },
          {
            name: 'first entry of the id inside a workout; missing target reads as null',
            args: { exId: LIFT, state: { workouts: [{ d: '2026-01-01', entries: [{ id: LIFT, sets: [set(40, 8)] }, { id: LIFT, sets: [set(99, 1)] }] }] } },
            golden: { d: '2026-01-01', sets: [set(40, 8)], target: null },
          },
          { name: 'never logged', args: { exId: LIFT, state: { workouts: [] } }, golden: null },
        ],
      },
      bestWeightFor: {
        call: history('bestWeightFor'),
        vectors: [
          {
            name: 'heaviest done set or confirmed topW',
            args: {
              exId: LIFT,
              state: {
                workouts: [
                  { d: '2026-01-01', entries: [{ id: LIFT, topW: 70, sets: [set(60, 5), set(80, 5, false)] }] },
                  { d: '2026-01-02', entries: [{ id: LIFT, target: { mode: 'reps' }, sets: [set(65, 5)] }] },
                ],
              },
            },
            golden: 70,
          },
          {
            name: 'a weighted timed entry does not count (target mode time)',
            args: {
              exId: LIFT,
              state: {
                workouts: [
                  { d: '2026-01-01', entries: [{ id: LIFT, sets: [set(40, 8)] }] },
                  { d: '2026-01-02', entries: [{ id: LIFT, target: { sets: 1, sec: 60, mode: 'time' }, sets: [{ sec: 60, w: 50, done: true }] }] },
                ],
              },
            },
            fix: 'engine-Q5',
            golden: 40,
          },
          {
            name: 'a timed entry with only topW does not count',
            args: { exId: LIFT, state: { workouts: [{ d: '2026-01-01', entries: [{ id: LIFT, topW: 30, target: { mode: 'time' }, sets: [{ sec: 45, w: 0, done: true }] }] }] } },
            fix: 'engine-Q5',
            golden: 0,
          },
          {
            name: 'cardio by body part never counts',
            args: { exId: CARDIO, state: { workouts: [{ d: '2026-01-01', entries: [{ id: CARDIO, sets: [{ min: 20, speed: 9, w: 5, done: true }] }] }] } },
            fix: 'engine-Q5',
            golden: 0,
          },
          {
            name: 'a cardio exercise logged in explicit reps mode counts',
            args: { exId: CARDIO, state: { workouts: [{ d: '2026-01-01', entries: [{ id: CARDIO, target: { mode: 'reps', reps: 10 }, sets: [set(20, 10)] }] }] } },
            golden: 20,
          },
          { name: 'nothing logged', args: { exId: LIFT, state: { workouts: [] } }, golden: 0 },
        ],
      },
      effectiveRoutineId: {
        call: (mod, a) => mod.history.effectiveRoutineId(a.plan, a.date),
        vectors: effectiveRoutineVectors(),
      },
      effectiveRoutine: {
        call: (mod, a) => mod.history.effectiveRoutine(a.plan, a.date),
        vectors: effectiveRoutineVectors(),
      },
      buildSets: {
        scope: 'app',
        call: (mod, a) => mod.history.buildSets(prepare(mod, a.state), a.cfg),
        vectors: buildSetsVectors(),
      },
      applyPrescription: {
        scope: 'app',
        note: '`sameInstance` is true when the function must return the very list it was given.',
        call: (mod, a) => mod.progression.applyPrescription(a.sets, a.prescription),
        sameInstance: (a, result) => result === a.sets,
        vectors: applyPrescriptionVectors(),
      },
      workoutVolume: {
        call: (mod, a) => mod.history.workoutVolume(a.workout),
        vectors: [{
          name: 'reps only; timed and cardio sets add nothing',
          ref: '§10.18',
          args: {
            workout: {
              entries: [
                { id: LIFT, sets: [set(60, 10), set(60, 10, false)] },
                { id: LIFT, target: { mode: 'time' }, sets: [{ sec: 60, w: 20, done: true }] },
                { id: CARDIO, sets: [{ min: 20, speed: 9, done: true }] },
              ],
            },
          },
          golden: 600,
        }],
      },
      setsDone: {
        call: (mod, a) => mod.history.setsDone(a.workout),
        vectors: [{
          name: 'counts done sets across entries',
          args: { workout: { entries: [{ id: LIFT, sets: [set(60, 10), set(60, 10, false)] }, { id: CARDIO, sets: [{ min: 20, speed: 9, done: true }] }] } },
          golden: 2,
        }],
      },
    },
  }
}

function effectiveRoutineVectors() {
  const plan = {
    routines: [{ id: 'r1', name: 'Empuje', ex: [] }, { id: 'r2', name: 'Tirón', ex: [] }],
    week: { 1: 'r1', 3: 'r2', 5: 'gone' },
    dayPlan: { '2026-09-28': 'rest', '2026-09-29': 'r1', '2026-09-30': 'gone' },
  }
  return [
    ['2026-09-28', 'Monday overridden to rest'],
    ['2026-09-29', 'Tuesday rescheduled to an existing routine'],
    ['2026-09-30', 'override to a deleted routine falls back to the week'],
    ['2026-10-02', 'the week may hold a stale id'],
    ['2026-10-03', 'Saturday with nothing planned'],
    ['2026-10-04', 'Sunday (weekday 0) with nothing planned'],
    ['2026-10-05', 'Monday from the week'],
  ].map(([date, name]) => ({ name, args: { plan, date } }))
}

function buildSetsVectors() {
  const emptyS = { workouts: [], exWeights: {} }
  const one = (entry, exWeights = {}) => ({ exWeights, workouts: [{ d: '2026-01-01', entries: [entry] }] })
  return [
    { name: 'reps from the plan without history', ref: '§10.18', args: { state: emptyS, cfg: { id: LIFT, sets: 3, reps: 8, weight: 50 } }, golden: times(3, { w: 50, r: 8, done: false }) },
    { name: 'timed from the plan without history', args: { state: emptyS, cfg: { id: LIFT, mode: 'time', sets: 2, sec: 60, weight: 20 } }, golden: times(2, { sec: 60, w: 20, done: false }) },
    { name: 'cardio from the plan without history', args: { state: emptyS, cfg: { id: CARDIO, sets: 1, min: 25, speed: 9 } }, golden: [{ min: 25, speed: 9, done: false }] },
    {
      name: 'carries a timed set forward (history.test.js:288, target without sec)',
      args: { state: one({ id: LIFT, target: { mode: 'time' }, sets: [{ sec: 70, w: 10, done: true }] }), cfg: { id: LIFT, mode: 'time', sets: 2, sec: 45, weight: 0 } },
      golden: times(2, { sec: 70, w: 10, done: false }),
    },
    {
      name: 'no duration seeded from a rep set',
      args: { state: one({ id: LIFT, sets: [set(60, 10)] }), cfg: { id: LIFT, mode: 'time', sets: 1, sec: 45, weight: 0 } },
      golden: [{ sec: 45, w: 0, done: false }],
    },
    {
      name: 'no reps seeded from a timed set',
      args: { state: one({ id: LIFT, target: { mode: 'time' }, sets: [{ sec: 70, w: 10, done: true }] }), cfg: { id: LIFT, mode: 'reps', sets: 1, reps: 8, weight: 40 } },
      golden: [{ w: 40, r: 8, done: false }],
    },
    {
      name: 'working weight beats last session (history.test.js:306, no target)',
      args: { state: one({ id: LIFT, sets: [set(60, 10)] }, { [LIFT]: { w: 75 } }), cfg: { id: LIFT, sets: 1, reps: 8, weight: 50 } },
      golden: [{ w: 75, r: 10, done: false }],
    },
    {
      name: 'extra planned sets reuse the final done set',
      ref: '§11',
      args: { state: one({ id: LIFT, sets: [set(60, 10), set(62.5, 8), set(62.5, 8, false)] }), cfg: { id: LIFT, sets: 4, reps: 5, weight: 50 } },
      golden: [{ w: 60, r: 10, done: false }, { w: 62.5, r: 8, done: false }, { w: 62.5, r: 8, done: false }, { w: 62.5, r: 8, done: false }],
    },
    {
      name: 'a done set with 0 reps is not usable: plan values',
      ref: '§11',
      args: { state: one({ id: LIFT, sets: [set(60, 0)] }), cfg: { id: LIFT, sets: 1, reps: 5, weight: 50 } },
      golden: [{ w: 50, r: 5, done: false }],
    },
    {
      name: 'cardio carries last minutes and speed',
      args: { state: one({ id: CARDIO, sets: [{ min: 30, speed: 10, done: true }] }), cfg: { id: CARDIO, sets: 2, min: 20, speed: 8 } },
      golden: times(2, { min: 30, speed: 10, done: false }),
    },
    {
      name: 'plan reps changed since last session: reps come from the plan',
      args: { state: one({ id: LIFT, target: { id: LIFT, mode: 'reps', sets: 2, reps: 5, weight: 60 }, sets: [set(60, 5), set(60, 5)] }), cfg: { id: LIFT, mode: 'reps', sets: 2, reps: 8, weight: 60 } },
      fix: 'critic-G3',
      golden: times(2, { w: 60, r: 8, done: false }),
    },
    {
      name: 'plan reps changed: the working weight still wins for w',
      args: { state: one({ id: LIFT, target: { id: LIFT, mode: 'reps', sets: 1, reps: 10 }, sets: [set(60, 10)] }, { [LIFT]: { w: 75, d: '2026-01-01' } }), cfg: { id: LIFT, sets: 1, reps: 8, weight: 50 } },
      fix: 'critic-G3',
      golden: [{ w: 75, r: 8, done: false }],
    },
    {
      name: 'plan seconds changed since last session: seconds come from the plan',
      args: { state: one({ id: LIFT, target: { id: LIFT, mode: 'time', sets: 2, sec: 45 }, sets: [{ sec: 45, w: 10, done: true }, { sec: 40, w: 10, done: true }] }), cfg: { id: LIFT, mode: 'time', sets: 2, sec: 60, weight: 0 } },
      fix: 'critic-G3',
      golden: times(2, { sec: 60, w: 10, done: false }),
    },
    {
      name: 'unchanged plan reps: last session reps as before',
      args: { state: one({ id: LIFT, target: { id: LIFT, mode: 'reps', sets: 1, reps: 8 }, sets: [set(60, 9)] }), cfg: { id: LIFT, mode: 'reps', sets: 1, reps: 8, weight: 60 } },
      golden: [{ w: 60, r: 9, done: false }],
    },
  ]
}

function applyPrescriptionVectors() {
  const sets = [set(60, 5), set(60, 5, false)]
  return [
    { name: 'only undone sets, only decided fields', ref: '§10.13', args: { sets, prescription: { kind: 'up', weight: 62.5 } }, golden: [set(60, 5), { w: 62.5, r: 5, done: false }] },
    { name: 'reps too when decided', args: { sets, prescription: { kind: 'up', weight: 42.5, reps: 8 } }, golden: [set(60, 5), { w: 42.5, r: 8, done: false }] },
    { name: 'off returns the same list', args: { sets, prescription: { kind: 'off' } }, golden: sets },
    { name: 'first returns the same list', args: { sets, prescription: { kind: 'first' } }, golden: sets },
    { name: 'null returns the same list', args: { sets, prescription: null }, golden: sets },
    { name: 'timed set', args: { sets: [{ sec: 45, w: 0, done: false }], prescription: { kind: 'up', sec: 50 } }, golden: [{ sec: 50, w: 0, done: false }] },
  ]
}

/* ================================================================== progression.json */

export function progressionFile() {
  const T = { sets: 3, reps: 5 }
  const TT = { sets: 2, sec: 45, mode: 'time' }
  const linear = { id: LIFT, sets: 3, reps: 5, weight: 60, prog: 'linear' }
  const greyskull = { ...linear, prog: 'greyskull' }
  const double = { id: LIFT, sets: 3, reps: 12, repsMin: 8, weight: 40, prog: 'double' }
  const bodyweight = { id: LIFT, sets: 3, reps: 10, weight: 0, prog: 'linear' }
  const timed = { id: LIFT, mode: 'time', sets: 2, sec: 45, prog: 'time' }
  const bw = rows => hist(LIFT, rows, { sets: 3, reps: 10 })
  const dbl = rows => hist(LIFT, rows, { sets: 3, reps: 12 })
  const np = (name, state, cfg, extra = {}) => ({ name, args: { state, cfg, ...(extra.routine !== undefined ? { routine: extra.routine } : {}) }, ...extra.spec })

  return {
    about: 'frontend/src/lib/progression.js (engine.md §4, §10.1–§10.13, §11) with engine-Q1, engine-Q2 and critic-G3.',
    constants: null,   // filled in by generate.mjs from the module
    groups: {
      readSession: {
        call: (mod, a) => { prepare(mod, null); return mod.progression.readSession(a.entry, a.fallback) },
        vectors: [
          { name: 'every set made its reps: hit', ref: '§10.1 #1', args: { entry: { id: LIFT, target: T, sets: [set(60, 5), set(60, 5), set(60, 6)] } }, golden: { ok: true, weight: 60, amrap: 6, low: 5 } },
          { name: 'short reps on a checked set: miss', ref: '§10.1 #2', args: { entry: { id: LIFT, target: T, sets: [set(60, 5), set(60, 5), set(60, 3)] } }, golden: { ok: false } },
          { name: 'unchecked set: miss, weight from done sets', ref: '§10.1 #3', args: { entry: { id: LIFT, target: T, sets: [set(60, 5), set(60, 5), set(60, 0, false)] } }, golden: { ok: false, weight: 60 } },
          { name: 'fewer sets than prescribed: miss', ref: '§10.1 #4', args: { entry: { id: LIFT, target: T, sets: [set(60, 5), set(60, 5)] } }, golden: { ok: false } },
          { name: 'nothing prescribed: miss', ref: '§10.1 #5', args: { entry: { id: LIFT, target: {}, sets: [set(60, 5)] } }, golden: { ok: false } },
          { name: 'timed session by the hold', ref: '§10.1 #6', args: { entry: { id: LIFT, target: TT, sets: [{ sec: 45, w: 0, done: true }, { sec: 50, w: 0, done: true }] } }, golden: { mode: 'time', ok: true, best: 50 } },
          { name: 'timed session short', ref: '§10.1 #7', args: { entry: { id: LIFT, target: TT, sets: [{ sec: 45, done: true }, { sec: 30, done: true }] } }, golden: { ok: false } },
          { name: 'no sets, judged against the fallback', ref: '§11', args: { entry: { id: LIFT, sets: [] }, fallback: T }, golden: { mode: 'reps', goal: 5, reps: [], weight: 0, low: 0, amrap: 0, ok: false } },
          { name: 'null entry and fallback', ref: '§11', args: { entry: null, fallback: null }, golden: { mode: 'reps', goal: 0, reps: [], weight: 0, low: 0, amrap: 0, ok: false } },
          { name: 'cardio is read the reps way (goal 0)', args: { entry: { id: CARDIO, sets: [{ min: 20, speed: 9, done: true }] } } },
          { name: 'legacy entry judged against the fallback', args: { entry: { id: LIFT, sets: [set(60, 5), set(60, 5), set(60, 5)] }, fallback: { id: LIFT, sets: 3, reps: 5 } }, golden: { ok: true } },
        ],
      },
      sessionsFor: {
        call: (mod, a) => mod.progression.sessionsFor(prepare(mod, a.state), a.exId, a.fallback),
        vectors: [
          {
            name: 'only workouts where the exercise was logged',
            ref: '§10.11',
            args: {
              exId: LIFT,
              state: {
                unit: 'kg',
                workouts: [
                  { d: '2026-01-01', entries: [{ id: LIFT, target: { sets: 1, reps: 5 }, sets: [set(60, 5)] }] },
                  { d: '2026-01-02', entries: [{ id: LIFT, target: { sets: 1, reps: 5 }, sets: [set(60, 0, false)] }] },
                  { d: '2026-01-03', entries: [{ id: 'other', target: {}, sets: [set(20, 5)] }] },
                ],
              },
            },
          },
          { name: 'legacy entry without target', ref: '§10.11', args: { exId: LIFT, state: { unit: 'kg', workouts: [{ d: '2026-01-01', entries: [{ id: LIFT, sets: [set(60, 5)] }] }] } } },
          { name: 'legacy entries judged against the fallback', args: { exId: LIFT, fallback: { id: LIFT, sets: 3, reps: 5 }, state: legacy([[60, 5, 5, 5], [60, 5, 4, 5]]) } },
        ],
      },
      stallCount: {
        call: (mod, a) => mod.progression.stallCount(a.sessions),
        vectors: [[[true, true], 0], [[true, false], 1], [[false, false, false], 3], [[false, true, false], 1], [[], 0]]
          .map(([oks, n]) => ({ name: JSON.stringify(oks), ref: '§10.2', args: { sessions: oks.map(ok => ({ ok })) }, golden: n })),
      },
      doubleStallCount: {
        fixOnly: 'engine-Q1',
        note: 'Walk back from the last session; session i is a stall iff !ok && (i == 0 || sessions[i-1].weight != weight || low <= sessions[i-1].low).',
        call: (mod, a) => mod.progression.doubleStallCount(a.sessions),
        vectors: [
          { name: 'climbing inside the range is progress', rows: [[40, 10, 9, 9], [40, 11, 10, 10], [40, 11, 11, 11]], golden: 0 },
          { name: 'flat for three sessions', rows: times(3, [40, 9, 9, 9]), golden: 3 },
          { name: 'regression counts back to the first session', rows: [[40, 10, 10, 10], [40, 9, 9, 9]], golden: 2 },
          { name: 'improvement stops the count', rows: [[40, 8, 8, 8], [40, 10, 10, 10], [40, 10, 10, 10]], golden: 1 },
          { name: 'a weight change is not progress', rows: [[40, 9, 9, 9], [42.5, 8, 8, 8], [42.5, 8, 8, 8]], golden: 3 },
          { name: 'a hit ends the count', rows: [[40, 9, 9, 9], [40, 12, 12, 12]], golden: 0 },
          { name: 'no sessions', rows: [], golden: 0 },
        ].map(({ name, rows, golden }) => ({ name, args: { sessions: sessionsOf(rows, 12) }, golden })),
      },
      policyFor: {
        call: (mod, a) => mod.progression.policyFor(a.cfg, a.routine, a.mode),
        vectors: [
          [{ id: LIFT }, null, 'reps', 'linear'],
          [{ id: LIFT, mode: 'time' }, null, 'time', 'off'],
          [{ id: CARDIO }, null, 'cardio', 'off'],
          [{ id: LIFT }, { prog: 'greyskull' }, 'reps', 'greyskull'],
          [{ id: LIFT, prog: 'double' }, { prog: 'greyskull' }, 'reps', 'double'],
          [{ id: LIFT, mode: 'time', prog: 'greyskull' }, null, 'time', 'off'],
          [{ id: CARDIO, prog: 'linear' }, null, 'cardio', 'off'],
          [{ id: LIFT, mode: 'time' }, { prog: 'time' }, 'time', 'time'],
          [{ id: LIFT }, { prog: 'time' }, js('undefined'), 'off'],
          [{ id: CARDIO }, { prog: 'linear' }, js('undefined'), 'off'],
          [{ id: LIFT, prog: 'vibes' }, { prog: 'double' }, 'reps', 'off'],
        ].map(([cfg, routine, mode, out], i) => ({ name: `#${i + 1} ${JSON.stringify(cfg)} ${JSON.stringify(routine)} → ${out}`, ref: i < 7 ? '§10.3' : undefined, args: { cfg, routine, mode }, golden: out })),
      },
      defaultIncrement: {
        call: (mod, a) => { prepare(mod, a); return mod.progression.defaultIncrement(a.exId, a.unit) },
        vectors: [[LIFT, 'kg', 2.5, '§10.4'], [HEAVY, 'kg', 5, '§10.4'], [LIFT, 'lb', 5, '§10.4'], [HEAVY, 'lb', 10, '§10.4'], ['nope', 'kg', 2.5, '§10.4'],
          ['0007', 'kg', 5], ['1368', 'lb', 10], [BENCH, 'stone', 2.5], ['cx-legs', 'kg', 5]]
          .map(([exId, unit, out, ref]) => ({ name: `${exId} ${unit}`, ref, args: { exId, unit, ...(exId === 'cx-legs' ? { customEx: [CUSTOM_LEGS] } : {}) }, golden: out })),
      },
      nextPrescription: {
        call: (mod, a) => mod.progression.nextPrescription(prepare(mod, a.state), a.cfg, a.routine),
        vectors: [
          // §10.5 linear
          np('linear: nothing logged yet', { unit: 'kg', workouts: [] }, linear, { spec: { ref: '§10.5 #1', golden: { kind: 'first', weight: js('undefined') } } }),
          np('linear: clean session adds the increment', hist(LIFT, [[60, 5, 5, 5]]), linear, { spec: { ref: '§10.5 #2', golden: { kind: 'up', weight: 62.5, why: ['Every rep last time — {0} {1} more.', 2.5, 'kg'] } } }),
          np('linear: one miss holds', hist(LIFT, [[60, 5, 5, 3]]), linear, { spec: { ref: '§10.5 #3', golden: { kind: 'hold', weight: 60, why: ['Missed reps last time — same weight again ({0} of {1} to go).', 2, 3] } } }),
          np('linear: unchecked last set holds', hist(LIFT, [[60, 5, 5, null]]), linear, { spec: { ref: '§10.5 #4', golden: { kind: 'hold', weight: 60 } } }),
          np('linear: two misses hold', hist(LIFT, [[60, 5, 5, 3], [60, 5, 5, 3]]), linear, { spec: { ref: '§11', golden: { kind: 'hold', why: ['Missed reps last time — same weight again ({0} of {1} to go).', 1, 3] } } }),
          np('linear: three misses deload', hist(LIFT, [[60, 5, 5, 3], [60, 5, 4, 4], [60, 5, 5, 4]]), linear, { spec: { ref: '§10.5 #5', golden: { kind: 'deload', weight: 55 } } }),
          np('linear: a good session clears the stall', hist(LIFT, [[60, 5, 5, 3], [60, 5, 5, 5], [60, 5, 5, 3]]), linear, { spec: { ref: '§10.5 #6', golden: { kind: 'hold' } } }),
          np('linear: never below one increment', hist(LIFT, times(3, [2.5, 1, 1, 1])), linear, { spec: { ref: '§10.5 #7', golden: { kind: 'deload', weight: 2.5 } } }),
          np('linear: a deload is always lighter', hist(LIFT, times(3, [5, 1, 1, 1])), linear, { spec: { ref: '§10.5 #8 / §11', golden: { kind: 'deload', weight: 2.5, why: ['Missed reps {0} sessions running — reset to {1} {2} and work back up.', 3, 2.5, 'kg'] } } }),
          np('linear: heavy body part takes 5', hist(HEAVY, [[100, 5, 5, 5]]), { id: HEAVY, sets: 3, reps: 5, prog: 'linear' }, { spec: { ref: '§10.5 #9', golden: { weight: 105 } } }),
          np('linear: per-exercise increment', hist(LIFT, [[60, 5, 5, 5]]), { ...linear, inc: 1 }, { spec: { ref: '§10.5 #10', golden: { weight: 61 } } }),
          np('linear: pounds', { ...hist(LIFT, [[135, 5, 5, 5]]), unit: 'lb' }, linear, { spec: { ref: '§10.5 #11', golden: { weight: 140 } } }),
          np('linear: off-grid weight snaps onto the grid', hist(LIFT, [[61, 5, 5, 5]]), linear, { spec: { ref: '§11', golden: { kind: 'up', weight: 62.5 } } }),
          np('linear: routine default applies', hist(LIFT, [[60, 5, 5, 5]]), { id: LIFT, sets: 3, reps: 5 }, { routine: { id: 'r1', prog: 'greyskull' }, spec: { golden: { policy: 'greyskull', kind: 'up' } } }),
          // §10.6 bodyweight
          np('bodyweight: never deloads', bw([[0, 10, 10, 8], [0, 10, 10, 9], [0, 10, 10, 8]]), bodyweight, { spec: { ref: '§10.6 #1', golden: { kind: 'hold', weight: 0, reps: 10, why: ['Bodyweight — same target again until every set is clean.'] } } }),
          np('bodyweight: progresses in reps', bw([[0, 10, 10, 10]]), bodyweight, { spec: { ref: '§10.6 #2', golden: { kind: 'up', weight: 0, reps: 11, why: ['Bodyweight — every rep last time, so go for {0} this time.', 11] } } }),
          ...['linear', 'greyskull', 'double'].map(prog =>
            np(`bodyweight: ${prog} holds too`, bw(times(3, [0, 10, 10, 4])), { ...bodyweight, prog }, { spec: { ref: '§10.6 #3', golden: { weight: 0, kind: 'hold' } } })),
          np('bodyweight: load goes up once weighted', hist(LIFT, [[10, 10, 10, 10]], { sets: 3, reps: 10 }), bodyweight, { spec: { ref: '§10.6 #4', golden: { kind: 'up', weight: 12.5 } } }),
          np('bodyweight: no goal anywhere', hist(LIFT, [[0, 10, 10, 10]], { sets: 3 }), { id: LIFT, sets: 3, weight: 0, prog: 'linear' }, { spec: { golden: { kind: 'hold', weight: 0, reps: js('undefined') } } }),
          // §10.7 greyskull
          np('greyskull: final set makes the target', hist(LIFT, [[60, 5, 5, 5]]), greyskull, { spec: { ref: '§10.7 #1', golden: { kind: 'up', weight: 62.5 } } }),
          np('greyskull: doubled reps double the jump', hist(LIFT, [[60, 5, 5, 10]]), greyskull, { spec: { ref: '§10.7 #2', golden: { kind: 'up', weight: 65, why: ['Last set hit {0} reps — twice the target, so take a double jump of {1} {2}.', 10, 5, 'kg'] } } }),
          np('greyskull: first failure resets', hist(LIFT, [[60, 5, 5, 3]]), greyskull, { spec: { ref: '§10.7 #3', golden: { kind: 'deload', weight: 55, why: ['Missed reps — reset to {0} {1} and work back up.', 55, 'kg'] } } }),
          np('greyskull: resets from the reduced weight', hist(LIFT, [[60, 5, 5, 3], [55, 5, 5, 2]]), greyskull, { spec: { ref: '§10.7 #4', golden: { kind: 'deload', weight: 50 } } }),
          // §10.8 double
          np('double: top of the range adds weight', dbl([[40, 12, 12, 12]]), double, { spec: { ref: '§10.8 #1 / §11', golden: { kind: 'up', weight: 42.5, reps: 8, why: ['Top of the rep range in every set — {0} {1} more, back to {2} reps.', 2.5, 'kg', 8] } } }),
          np('double: inside the range aims one higher', dbl([[40, 10, 9, 9]]), double, { spec: { ref: '§10.8 #2 / §11', golden: { kind: 'hold', weight: 40, reps: 10, why: ['Same weight — aim for {0} reps this time.', 10] } } }),
          np('double: never above the top', dbl([[40, 12, 12, 11]]), double, { spec: { ref: '§10.8 #3', golden: { kind: 'hold', weight: 40, reps: 12 } } }),
          np('double: flat for three sessions deloads', dbl(times(3, [40, 9, 9, 9])), double, { spec: { ref: '§10.8 #4 / §11', golden: { kind: 'deload', reps: 8, weight: 35, why: ['Stalled {0} sessions — deload to {1} {2}.', 3, 35, 'kg'] } } }),
          np('double: bottom defaults to top − 2', dbl([[40, 12, 12, 12]]), { id: LIFT, sets: 3, reps: 12, weight: 40, prog: 'double' }, { spec: { ref: '§11', golden: { kind: 'up', weight: 42.5, reps: 10 } } }),
          np('double: an unchecked set aims at the bottom', dbl([[40, 11, 11, null]]), double, { spec: { ref: '§11', golden: { kind: 'hold', weight: 40, reps: 8 } } }),
          np('double: climbing inside the range is not a stall', dbl([[40, 10, 9, 9], [40, 11, 10, 10], [40, 11, 11, 11]]), double, { spec: { ref: '§11 (amended)', fix: 'engine-Q1', golden: { kind: 'hold', weight: 40, reps: 12 } } }),
          np('double: regression after progress still deloads after three', dbl([[40, 10, 10, 10], [40, 9, 9, 9], [40, 9, 9, 9]]), double, { spec: { golden: { kind: 'deload', weight: 35 } } }),
          // §10.9 time
          np('time: full holds add time', timeHist([[45, 45]]), timed, { spec: { ref: '§10.9 #1 / §11', golden: { kind: 'up', sec: 50, weight: js('undefined'), why: ['Held every set for the full time — target up by {0}s.', 5] } } }),
          np('time: a short hold repeats the target', timeHist([[45, 38]]), timed, { spec: { ref: '§10.9 #2 / §11', golden: { kind: 'hold', sec: 45, why: ['Last time came up short — same target again.'] } } }),
          np('time: three short sessions back off', timeHist([[45, 30], [45, 32], [45, 31]]), timed, { spec: { ref: '§10.9 #3 / §11', golden: { kind: 'deload', sec: 40, why: ['Short {0} sessions in a row — back off to {1}s and build up again.', 3, 40] } } }),
          np('time: reps history is ignored', hist(LIFT, [[60, 5, 5, 5]]), timed, { spec: { ref: '§10.9 #4', golden: { kind: 'first' } } }),
          np('time: inc 10 up', timeHist([[45, 45]]), { ...timed, inc: 10 }, { spec: { ref: '§11', golden: { kind: 'up', sec: 55 } } }),
          np('time: inc 10 deload', timeHist([[45, 30], [45, 32], [45, 31]]), { ...timed, inc: 10 }, { spec: { ref: '§11', golden: { kind: 'deload', sec: 40 } } }),
          np('time: the deload step follows inc', timeHist([[45, 30], [45, 32], [45, 31]]), { ...timed, inc: 15 }, { spec: { ref: 'contract §2.3', fix: 'engine-Q2', golden: { kind: 'deload', sec: 30 } } }),
          np('time: no policy anywhere is off', timeHist([[45, 45]]), { id: LIFT, mode: 'time', sets: 2, sec: 45 }, { routine: { id: 'r1' }, spec: { ref: '§11', golden: { policy: 'off', kind: 'off' } } }),
          np('time: routine policy time applies', timeHist([[45, 45]]), { id: LIFT, mode: 'time', sets: 2, sec: 45 }, { routine: { id: 'r1', prog: 'time' }, spec: { golden: { policy: 'time', kind: 'up', sec: 50 } } }),
          // §10.10 off
          np('off: no opinion', hist(LIFT, [[60, 5, 5, 5]]), { id: LIFT, sets: 3, reps: 5, prog: 'off' }, { spec: { ref: '§10.10', golden: { kind: 'off', weight: js('undefined') } } }),
          np('off: cardio always', { unit: 'kg', workouts: [] }, { id: CARDIO, sets: 1, min: 20 }, { spec: { ref: '§10.10', golden: { kind: 'off' } } }),
          // §10.12 legacy
          np('legacy: judged against the plan', legacy([[60, 5, 5, 5]]), linear, { spec: { ref: '§10.12', golden: { kind: 'up', weight: 62.5 } } }),
          np('legacy: long clean history', legacy(times(11, [60, 5, 5, 5])), linear, { spec: { ref: '§10.12', golden: { kind: 'up' } } }),
          np('legacy: a genuine miss', legacy([[60, 5, 5, 2]]), linear, { spec: { ref: '§10.12', golden: { kind: 'hold' } } }),
          np('legacy: extra reps are a hit', legacy([[60, 5, 6, 5]]), linear, { spec: { ref: '§10.12', golden: { weight: 62.5 } } }),
          np('legacy: short reps hold', legacy([[60, 5, 4, 5]]), linear, { spec: { ref: '§10.12', golden: { kind: 'hold' } } }),
          np('legacy: a changed plan target never triggers the new baseline', legacy([[60, 5, 5, 5]]), { ...linear, reps: 8 }, { spec: { golden: { kind: 'hold', weight: 60 } } }),
          // critic-G3: a changed plan target starts a new baseline
          ...['linear', 'greyskull', 'off'].map(prog =>
            np(`target changed: ${prog}`, hist(LIFT, [[60, 5, 5, 5]]), { ...linear, reps: 8, prog },
              { spec: prog === 'off' ? { golden: { kind: 'off' } } : { fix: 'critic-G3', golden: { policy: prog, kind: 'first', why: ['Plan target changed — this session sets the new baseline.'] } } })),
          np('target changed: double top moved', dbl([[40, 12, 12, 12]]), { ...double, reps: 10 }, { spec: { fix: 'critic-G3', golden: { kind: 'first' } } }),
          np('target changed: bodyweight', bw([[0, 10, 10, 10]]), { ...bodyweight, reps: 12 }, { spec: { fix: 'critic-G3', golden: { kind: 'first' } } }),
          np('target changed: time seconds', timeHist([[45, 45]]), { ...timed, sec: 60 }, { spec: { fix: 'critic-G3', golden: { policy: 'time', kind: 'first', why: ['Plan target changed — this session sets the new baseline.'] } } }),
          np('target without reps never triggers', hist(LIFT, [[60, 5, 5, 5]], { sets: 3 }), linear, { spec: { golden: { kind: 'hold', weight: 60 } } }),
          np('target reps as a string never triggers', hist(LIFT, [[60, 8, 8, 8]], { sets: 3, reps: '5' }), { ...linear, reps: 8 }, { spec: { golden: { kind: 'up' } } }),
          np('only the last session counts', {
            unit: 'kg',
            workouts: [
              { d: '2026-01-01', entries: [{ id: LIFT, target: { sets: 3, reps: 5 }, sets: [set(60, 5), set(60, 5), set(60, 5)] }] },
              { d: '2026-01-02', entries: [{ id: LIFT, target: { sets: 3, reps: 8 }, sets: [set(60, 8), set(60, 8), set(60, 8)] }] },
            ],
          }, { ...linear, reps: 8 }, { spec: { golden: { kind: 'up', weight: 62.5 } } }),
          np('the last session in another mode does not count', {
            unit: 'kg',
            workouts: [
              { d: '2026-01-01', entries: [{ id: LIFT, target: { sets: 3, reps: 5 }, sets: [set(60, 5), set(60, 5), set(60, 5)] }] },
              { d: '2026-01-02', entries: [{ id: LIFT, target: { sets: 1, sec: 30, mode: 'time' }, sets: [{ sec: 30, w: 0, done: true }] }] },
            ],
          }, linear, { spec: { golden: { kind: 'up', weight: 62.5 } } }),
        ],
      },
    },
  }
}

/** Sessions of a double-progression history, as readSession reports them. */
function sessionsOf(rows, reps) {
  return rows.map(([w, ...r]) => {
    const low = Math.min(...r)
    return { ok: r.every(x => x >= reps), weight: w, low }
  })
}

/* ================================================================== onerm.json */

export function onermFile() {
  const bench = (d, start, sets) => ({ d, start, entries: [{ id: 'bench', sets }] })
  const S = {
    workouts: [
      bench('2026-01-01', 1, [set(80, 5)]),
      { d: '2026-01-08', start: 2, entries: [{ id: 'squat', sets: [set(100, 5)] }] },
      bench('2026-01-15', 3, [set(90, 5), set(90, 3, false)]),
      bench('2026-01-22', 4, [set(85, 5)]),
      { d: '2026-01-29', start: 5, entries: [{ id: 'run', sets: [{ min: 30, speed: 10, done: true }] }] },
    ],
  }
  const table = []
  const golden = {
    epley: [100, 106.7, 110, 113.3, 116.7, 120, 123.3, 126.7, 130, 133.3, 136.7, 140],
    brzycki: [100, 102.9, 105.9, 109.1, 112.5, 116.1, 120, 124.1, 128.6, 133.3, 138.5, 144],
    lombardi: [100, 107.2, 111.6, 114.9, 117.5, 119.6, 121.5, 123.1, 124.6, 125.9, 127.1, 128.2],
  }
  for (const formula of Object.keys(golden)) {
    golden[formula].forEach((out, i) => table.push({ name: `100 × ${i + 1} ${formula}`, ref: '§11', args: { w: 100, r: i + 1, formula }, golden: out }))
  }
  const e = (w, r, out, ref = '§10.14') => ({ name: `${JSON.stringify(w)} × ${JSON.stringify(r)}`, ref, args: { w, r }, golden: out })
  return {
    about: 'frontend/src/lib/onerm.js (engine.md §5, §10.14–§10.16, §11).',
    constants: null,
    groups: {
      estimate1RM: {
        call: (mod, a) => mod.onerm.estimate1RM(a.w, a.r, a.formula),
        vectors: [
          e(100, 1, 100), e(62.5, 1, 62.5), e(100, 5, 116.7), e(100, 10, 133.3), e(80, 8, 101.3), e(60, 3, 66), e(101.25, 7, 124.9),
          e(100, 3, 110), e(100, 12, 140), e(100, 13, null), e(60, 30, null),
          e(0, 5, null), e(-100, 5, null), e(100, 0, null), e(100, -3, null), e(js('undefined'), 5, null), e(100, js('undefined'), null),
          e(js('NaN'), 5, null), e(js('Infinity'), 5, null), e('', '', null), e('100', '5', 116.7), e(null, 5, null),
          e(100, 2.5, 110, '§11'), e(100, 12.4, null, '§11'), e(100, 12.5, null, '§11'), e(100, 0.5, null, '§11'), e(100, 1.2, 103.3, '§11'),
          { name: 'brzycki', ref: '§10.14', args: { w: 100, r: 5, formula: 'brzycki' }, golden: 112.5 },
          { name: 'lombardi', ref: '§10.14', args: { w: 100, r: 5, formula: 'lombardi' }, golden: 117.5 },
          { name: 'unknown formula falls back to epley', ref: '§10.14', args: { w: 100, r: 5, formula: 'nope' }, golden: 116.7 },
          ...table,
        ],
      },
      bestSetOf: {
        call: (mod, a) => mod.onerm.bestSetOf(a.entry),
        vectors: [
          { name: 'highest estimate, not heaviest set', ref: '§10.15', args: { entry: { id: 'x', sets: [set(100, 5), set(110, 3), set(120, 1)] } }, golden: { est: 121, w: 110, r: 3 } },
          { name: 'undone sets ignored', ref: '§10.15', args: { entry: { id: 'x', sets: [set(100, 5), set(200, 5, false)] } }, golden: { est: 116.7, w: 100, r: 5 } },
          { name: 'topW ignored', ref: '§10.15', args: { entry: { id: 'x', topW: 200, sets: [set(100, 5)] } }, golden: { est: 116.7, w: 100, r: 5 } },
          { name: 'cardio', ref: '§10.15', args: { entry: { id: 'c', sets: [{ min: 20, speed: 9, done: true }] } }, golden: null },
          { name: 'timed bodyweight', ref: '§10.15', args: { entry: { id: 'p', sets: [{ sec: 60, w: 0, done: true }] } }, golden: null },
          { name: 'timed weighted', ref: '§10.15', args: { entry: { id: 'p', sets: [{ sec: 60, w: 20, done: true }] } }, golden: null },
          { name: 'null entry', ref: '§10.15', args: { entry: null }, golden: null },
          { name: 'no sets', ref: '§10.15', args: { entry: { sets: [] } }, golden: null },
          { name: 'ties keep the first set', args: { entry: { id: 'x', sets: [set(100, 5), set(100, 5)] } }, golden: { est: 116.7, w: 100, r: 5 } },
          { name: 'fractional reps are rounded in the result', args: { entry: { id: 'x', sets: [set('100', '2.5')] } }, golden: { est: 110, w: 100, r: 3 } },
        ],
      },
      e1rmSeries: {
        call: (mod, a) => mod.onerm.e1rmSeries(a.state, a.exId),
        vectors: [
          { name: 'one point per workout with an estimate', ref: '§10.16', args: { state: S, exId: 'bench' } },
          { name: 'cardio has no series', ref: '§10.16', args: { state: S, exId: 'run' }, golden: [] },
        ],
      },
      best1RM: {
        call: (mod, a) => mod.onerm.best1RM(a.state, a.exId),
        vectors: [
          { name: 'all-time best with its set', ref: '§10.16', args: { state: S, exId: 'bench' }, golden: { est: 105, w: 90, r: 5, d: '2026-01-15', t: 3 } },
          { name: 'cardio', ref: '§10.16', args: { state: S, exId: 'run' }, golden: null },
          { name: 'unknown exercise', ref: '§10.16', args: { state: S, exId: 'nope' }, golden: null },
          { name: 'no workouts', ref: '§10.16', args: { state: { workouts: [] }, exId: 'bench' }, golden: null },
          { name: 'empty state', ref: '§10.16', args: { state: {}, exId: 'bench' }, golden: null },
          {
            name: 'equal maxima keep the earliest',
            args: { state: { workouts: [bench('2026-01-01', 1, [set(90, 5)]), bench('2026-01-08', 2, [set(90, 5)])] }, exId: 'bench' },
            golden: { est: 105, w: 90, r: 5, d: '2026-01-01', t: 1 },
          },
        ],
      },
      is1RMRecord: {
        call: (mod, a) => mod.onerm.is1RMRecord(a.state, a.exId, a.entry),
        vectors: [
          { name: 'beats every previous estimate', ref: '§10.16', args: { state: S, exId: 'bench', entry: { id: 'bench', sets: [set(95, 5)] } }, golden: { est: 110.8, w: 95, r: 5, prev: 105 } },
          { name: 'equal is not a record', ref: '§10.16', args: { state: S, exId: 'bench', entry: { id: 'bench', sets: [set(90, 5)] } }, golden: null },
          { name: 'below', ref: '§10.16', args: { state: S, exId: 'bench', entry: { id: 'bench', sets: [set(80, 5)] } }, golden: null },
          { name: 'first estimate ever', ref: '§10.16', args: { state: S, exId: 'deadlift', entry: { id: 'deadlift', sets: [set(140, 3)] } }, golden: { est: 154, w: 140, r: 3, prev: 0 } },
          { name: 'timed entry', ref: '§10.16', args: { state: S, exId: 'plank', entry: { id: 'plank', sets: [{ sec: 90, done: true }] } }, golden: null },
          { name: 'unfinished entry', ref: '§10.16', args: { state: S, exId: 'bench', entry: { id: 'bench', sets: [set(200, 5, false)] } }, golden: null },
        ],
      },
    },
  }
}

/* ================================================================== effort.json */

export function effortFile(clock) {
  // effort.test.js `W(n, sets)`: one workout n days before now (local calendar), 0025 at 60×8.
  const W = (n, sets) => {
    const d = new Date(clock.now)
    d.setDate(d.getDate() - n)
    const iso = d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0')
    return { id: 'w' + n, d: iso, start: +d, entries: [{ id: BENCH, sets: sets.map(s => ({ w: 60, r: 8, done: true, ...s })) }] }
  }
  const S = (...workouts) => ({ workouts })
  const st = S(W(2, [{ rir: 1 }, { rir: 3 }, { rir: 2 }]), W(4, [{ rir: 0 }, { rpe: 6 }, {}]), W(40, [{ rir: 5 }, { rir: 5 }]))
  const dateOnly = (d, sets) => ({ id: 'd' + d, d, entries: [{ id: BENCH, sets: sets.map(s => ({ w: 60, r: 8, done: true, ...s })) }] })
  // now is 2026-09-30 10:00 Madrid: 3 days back is 2026-09-27 10:00. A date-only workout on the
  // 27th is at local noon (inside); the original read it as UTC midnight (outside).
  const edge = S(dateOnly('2026-09-27', [{ rir: 1 }, { rir: 2 }]), dateOnly('2026-09-26', [{ rir: 4 }]))
  const summary = (name, state, days, extra = {}) => ({ name, args: { state, days }, ...extra })

  return {
    about: 'frontend/src/lib/effort.js (engine.md §6, §10.17, §11) with engine-Q7 windows.',
    clock,
    constants: null,
    groups: {
      rirOf: {
        call: (mod, a) => mod.effort.rirOf(a.set),
        vectors: [[{ rir: 2 }, 2], [{ rpe: 8 }, 2], [{ rpe: 9.5 }, 0.5], [{ rir: 0 }, 0], [{ rpe: 10 }, 0], [{}, null], [{ rir: null }, null], [null, null], [{ rir: 3, rpe: 9 }, 3]]
          .map(([s, out]) => ({ name: JSON.stringify(s), ref: '§10.17', args: { set: s }, golden: out })),
      },
      toScale: {
        call: (mod, a) => mod.effort.toScale(a.kind, a.rir),
        vectors: [['rir', 2, 2], ['rpe', 2, 8], ['rpe', 0, 10], ['rir', null, null], ['rpe', 10 - 7.5, 7.5], ['rpe', 20 / 7, 7.1], ['rir', 20 / 7, 2.9]]
          .map(([kind, rir, out]) => ({ name: `${kind} ${rir}`, ref: '§10.17', args: { kind, rir }, golden: out })),
      },
      displayScale: {
        call: (mod, a) => mod.effort.displayScale(a.state),
        vectors: [
          { name: 'profile rpe', args: { state: { effort: 'rpe', workouts: [] } }, golden: 'rpe' },
          { name: 'profile rir', args: { state: { effort: 'rir', workouts: [] } }, golden: 'rir' },
          { name: 'unrated profile, RPE history', args: { state: { effort: 'none', ...S(W(3, [{ rpe: 8 }, { rpe: 9 }])) } }, golden: 'rpe' },
          { name: 'unrated profile, RIR history', args: { state: { effort: 'none', ...S(W(3, [{ rir: 2 }])) } }, golden: 'rir' },
          { name: 'unrated profile, no history', args: { state: { effort: 'none', workouts: [] } }, golden: 'rir' },
        ].map(v => ({ ...v, ref: '§10.17' })),
      },
      avgRir: {
        call: (mod, a) => mod.effort.avgRir(a.sets),
        vectors: [[[{ rir: 1 }, { rir: 3 }], 2], [[{ rir: 1 }, {}, { rpe: 7 }], 2], [[{}, { rir: null }], null], [[], null], [null, null]]
          .map(([sets, out]) => ({ name: JSON.stringify(sets), ref: '§10.17', args: { sets }, golden: out })),
      },
      effortSummary: {
        call: (mod, a) => mod.effort.effortSummary(a.state, a.days),
        vectors: [
          summary('all time', st, 0, { ref: '§10.17 / §11', golden: { done: 8, rated: 7, hard: 4, avg: 2.857142857142857, hardPct: 0.5714285714285714 } }),
          summary('one rating is not an average', S(W(2, [{ rir: 4 }, {}, {}, {}, {}, {}])), 0, { ref: '§10.17', golden: { rated: 1, avg: null } }),
          summary('MIN_RATED − 1', S(W(2, times(4, { rir: 2 }))), 0, { ref: '§10.17', golden: { avg: null } }),
          summary('MIN_RATED', S(W(2, times(5, { rir: 2 }))), 0, { ref: '§10.17', golden: { avg: 2 } }),
          summary('7-day window', st, 7, { ref: '§10.17 / §11', golden: { done: 6, rated: 5, hard: 4, avg: 2, hardPct: 0.8 } }),
          summary('3-day window', st, 3, { ref: '§10.17', golden: { rated: 3 } }),
          summary('no training', { workouts: [] }, 30, { ref: '§10.17', golden: { done: 0, rated: 0, hard: 0, avg: null, hardPct: null } }),
          summary('a date-only workout sits at local noon', edge, 3, { fix: 'engine-Q7', golden: { done: 2, rated: 2 } }),
        ],
      },
      hasEffort: {
        call: (mod, a) => mod.effort.hasEffort(a.state),
        vectors: [
          { name: 'RIR 0', args: { state: S(W(2, [{ rir: 0 }])) }, golden: true },
          { name: 'RPE', args: { state: S(W(2, [{ rpe: 8 }])) }, golden: true },
          { name: 'nothing rated', args: { state: S(W(2, [{}, { rir: null }])) }, golden: false },
          { name: 'no workouts', args: { state: { workouts: [] } }, golden: false },
          { name: 'rated but unfinished', args: { state: S(W(2, [{ rir: 2, done: false }])) }, golden: false },
        ].map(v => ({ ...v, ref: '§10.17' })),
      },
      effortWeeks: {
        call: (mod, a) => mod.effort.effortWeeks(a.state, a.days),
        vectors: [
          { name: 'one week', ref: '§10.17', args: { state: S(W(1, [{ rir: 1 }, { rir: 3 }, {}])), days: 0 }, golden: [{ rir: 2, n: 2, sets: 3, t: mondayNoon(clock, 1) }] },
          { name: 'a single rated set is dropped', ref: '§10.17', args: { state: S(W(1, [{ rir: 1 }])), days: 0 }, golden: [] },
          { name: 'oldest first', ref: '§10.17', args: { state: S(W(2, [{ rir: 1 }, { rir: 1 }]), W(30, [{ rir: 3 }, { rir: 3 }])), days: 0 } },
          { name: 'windowed with a date-only workout', args: { state: edge, days: 3 }, fix: 'engine-Q7' },
        ],
      },
      effortHistogram: {
        call: (mod, a) => mod.effort.effortHistogram(a.state, a.days),
        vectors: [
          { name: 'bins and tail', ref: '§10.17', args: { state: S(W(2, [{ rir: 0 }, { rir: 1.5 }, { rir: 4 }, { rir: 7 }])), days: 0 } },
          { name: 'nothing rated', ref: '§10.17', args: { state: S(W(2, [{}])), days: 0 } },
          { name: 'fixture st', ref: '§11', args: { state: st, days: 0 } },
        ],
      },
      isHardSet: {
        call: (mod, a) => mod.effort.isHardSet(a.set),
        vectors: [[{ rir: 3 }, true], [{ rir: 3.5 }, false], [{ rpe: 10 }, true], [{}, false]]
          .map(([s, out]) => ({ name: JSON.stringify(s), ref: '§10.17', args: { set: s }, golden: out })),
      },
    },
  }
}

/** Local noon of the Monday of the week `daysBack` days before now (what effortWeeks reports as `t`). */
function mondayNoon(clock, daysBack) {
  const d = new Date(clock.now)
  d.setDate(d.getDate() - daysBack)
  d.setDate(d.getDate() - ((d.getDay() + 6) % 7))
  d.setHours(12, 0, 0, 0)
  return +d
}

/* ================================================================== muscles.json */

export function musclesFile() {
  const withCustom = { customEx: [CUSTOM_LEGS] }
  const load = { chest: 12, triceps: 4.8, deltoids: 4.8, abs: 1, quadriceps: 0.1 }
  const workouts = [
    { d: '2026-09-28', entries: [
      { id: BENCH, sets: [{ w: 60, r: 8, rir: 2, done: true }, { w: 60, r: 8, rir: 4, done: true }, { w: 60, r: 8, done: false }] },
      { id: SQUAT, sets: [{ w: 100, r: 5, rpe: 9, done: true }] },
    ] },
    { d: '2026-09-29', entries: [{ id: 'cx-legs', sets: [{ w: 50, r: 10, done: true }, { w: 50, r: 10, done: true }] }] },
  ]
  return {
    about: 'frontend/src/lib/muscles.js (engine.md §7).',
    constants: null,
    groups: {
      musclesOf: {
        call: (mod, a) => { prepare(mod, a); return mod.muscles.musclesOf(mod.exercises.EXIDX[a.exId]) },
        vectors: [
          { name: 'bench press', ref: '§7.2', args: { exId: BENCH }, golden: { chest: 1, triceps: 0.4, deltoids: 0.4 } },
          { name: 'barbell full squat', ref: '§7.2', args: { exId: SQUAT }, golden: { gluteal: 1, quadriceps: 0.4, hamstring: 0.4, calves: 0.4, abs: 0.4 } },
          { name: '3/4 sit-up', args: { exId: LIFT } },
          { name: 'cardio exercise', args: { exId: CARDIO } },
          { name: 'custom exercise falls back to its body part', ref: '§7.2', args: { exId: 'cx-legs', ...withCustom }, golden: { quadriceps: 0.4, hamstring: 0.35, gluteal: 0.25 } },
          { name: 'unknown id', args: { exId: 'nope' }, golden: {} },
        ],
      },
      loadOf: {
        call: (mod, a) => { prepare(mod, a); return mod.muscles.loadOf(a.items) },
        vectors: [
          { name: 'effective sets per muscle', ref: '§7.3', args: { items: [{ id: BENCH, sets: 4 }, { id: LIFT, sets: 3 }] }, golden: { chest: 4, triceps: 1.6, deltoids: 1.6, abs: 3, 'hip-flexors': 1.2000000000000002, 'lower-back': 1.2000000000000002 } },
          { name: 'zero sets and unknown ids add nothing', args: { items: [{ id: BENCH, sets: 0 }, { id: 'nope', sets: 3 }, { id: 'cx-legs', sets: 2 }], ...withCustom } },
        ],
      },
      loadOfWorkouts: {
        note: '`hardOnly` passes isHardSet as the set filter.',
        call: (mod, a) => { prepare(mod, a); return mod.muscles.loadOfWorkouts(a.workouts, a.hardOnly ? mod.effort.isHardSet : undefined) },
        vectors: [
          { name: 'done sets', args: { workouts, ...withCustom } },
          { name: 'hard sets only', args: { workouts, hardOnly: true, ...withCustom } },
        ],
      },
      loadOfRoutine: {
        call: (mod, a) => mod.muscles.loadOfRoutine(a.routine),
        vectors: [{ name: 'planned sets, missing sets count 1', args: { routine: { id: 'r1', ex: [{ id: BENCH, sets: 3 }, { id: SQUAT }] } } }],
      },
      levelsOf: {
        call: (mod, a) => mod.muscles.levelsOf(a.load),
        vectors: [
          { name: 'relative to the hardest-worked muscle', ref: '§7.4', args: { load }, golden: { chest: 4, triceps: 2, deltoids: 2, abs: 1, quadriceps: 1, calves: 0 } },
          { name: 'nothing trained', args: { load: {} } },
        ],
      },
      rankOf: {
        call: (mod, a) => mod.muscles.rankOf(a.load),
        vectors: [
          { name: 'worked by load, ties in body order; missed in body order', ref: '§7.5', args: { load } },
          { name: 'nothing trained', args: { load: {} } },
        ],
      },
    },
  }
}

/* ================================================================== dates.json */

export function datesFile(clock) {
  const wk = [
    ['2025-12-29', '2026-1'], ['2026-01-01', '2026-1'], ['2026-12-31', '2026-53'], ['2027-01-01', '2026-53'], ['2027-01-03', '2026-53'],
    ['2027-01-04', '2027-1'], ['2020-12-31', '2020-53'], ['2021-01-03', '2020-53'], ['2024-12-30', '2025-1'],
  ]
  const extra = ['2026-09-30', '2026-03-29', '2026-10-25', '2021-01-04', '2015-12-31', '2016-01-03', '2008-12-29', '2010-01-03', '2026-06-15']
  const days = ds => ({ workouts: ds.map(d => ({ d, entries: [] })) })
  return {
    about: 'format.js weekKey, history.js streakWeeks (engine.md §2.17, §3), format helpers without locale, and workout order (engine-Q6/Q7).',
    clock,
    groups: {
      weekKey: {
        call: (mod, a) => mod.format.weekKey(a.date),
        vectors: [...wk.map(([date, out]) => ({ name: date, ref: '§3', args: { date }, golden: out })), ...extra.map(date => ({ name: date, args: { date } }))],
      },
      streakWeeks: {
        call: (mod, a) => mod.history.streakWeeks(a.state),
        vectors: [
          { name: 'no workouts', args: { state: days([]) }, golden: 0 },
          { name: 'this week and the two before', ref: '§2.17', args: { state: days(['2026-09-29', '2026-09-22', '2026-09-15']) }, golden: 3 },
          { name: 'an empty current week does not break it', ref: '§2.17', args: { state: days(['2026-09-22', '2026-09-15']) }, golden: 2 },
          { name: 'a gap stops the count', ref: '§2.17', args: { state: days(['2026-09-29', '2026-09-22', '2026-09-08']) }, golden: 2 },
          { name: 'only old workouts', args: { state: days(['2026-08-01']) }, golden: 0 },
          { name: 'across the new year (now Sunday 2027-01-03)', now: Date.UTC(2027, 0, 3, 11), args: { state: days(['2026-12-28', '2026-12-21', '2026-12-07']) }, golden: 2 },
        ],
      },
      fmtSec: {
        scope: 'app',
        call: (mod, a) => mod.history.fmtSec(a.sec),
        vectors: [[0, '0:00'], [9, '0:09'], [45, '0:45'], [60, '1:00'], [90, '1:30'], [605, '10:05'], [-5, '0:00'], [js('undefined'), '0:00'], [null, '0:00'], [js('NaN'), '0:00'], [44.6, '0:45']]
          .map(([sec, out]) => ({ name: JSON.stringify(sec), ref: '§10.18', args: { sec }, golden: out })),
      },
      fmtDur: {
        scope: 'app',
        call: (mod, a) => mod.format.fmtDur(a.ms),
        vectors: [0, 59999, 60000, 3599999, 3600000, 5400000, 7260000].map(ms => ({ name: String(ms), args: { ms } })),
      },
      durPart: {
        scope: 'app',
        call: (mod, a) => mod.format.durPart(a.ms),
        vectors: [0, 59999, 60000, 4500000].map(ms => ({ name: String(ms), args: { ms } })),
      },
    },
  }
}

/** Groups with no counterpart in the original code: expected values follow the contract. */
export function sortWorkoutsGroup(clock) {
  const at = (d, hh, mm = 0) => {
    const t = new Date(d + 'T00:00:00')
    t.setHours(hh, mm, 0, 0)
    return +t
  }
  const w = (id, d, start) => ({ id, d, ...(start !== undefined ? { start } : {}), entries: [] })
  const input = [
    w('a', '2026-03-02', at('2026-03-02', 18)),
    w('b', '2026-03-01', at('2026-03-01', 9)),
    w('c', '2026-03-02'),
    w('d', '2026-03-02', at('2026-03-02', 8)),
    w('e', '2026-02-27', at('2026-02-27', 20)),
    w('f', '2026-03-03', at('2026-03-03', 7)),
    w('g', '2026-03-03', at('2026-03-03', 7)),
    w('h', '2026-02-28', at('2026-03-05', 7)),
    w('i', '2026-03-02', at('2026-03-02', 12, 30)),
  ]
  return {
    scope: 'shared',
    fix: ['engine-Q6', 'engine-Q7'],
    note: 'Stable sort by (d, start) ascending; a workout without `start` sits at local noon of `d` in clock.tz.',
    vectors: [
      { name: 'date first, then start; date-only at local noon; ties keep input order', args: { workouts: input, tz: clock.tz }, expected: ['e', 'h', 'b', 'd', 'c', 'i', 'a', 'f', 'g'] },
      { name: 'already sorted input is unchanged', args: { workouts: [w('x', '2026-01-01', at('2026-01-01', 9)), w('y', '2026-01-02')], tz: clock.tz }, expected: ['x', 'y'] },
    ],
  }
}

/** engine.md §8.3 (lives in Heatmap.jsx, not a module): levels by quartiles of minutes per day. */
export function heatmapGroup() {
  const days = mins => mins.map(min => ({ min }))
  return {
    scope: 'app',
    note: 'Given the minutes of every trained day, t1/t2/t3 are quartiles of the positive ones; `levels` maps each probe (minutes, or null for no workout) to 0..4.',
    vectors: [
      { name: 'eight days', ref: '§11', args: { days: days([10, 20, 30, 40, 50, 60, 70, 80]), probes: [25, 30, 55, 70, 0, null] }, expected: { t1: 30, t2: 50, t3: 70, levels: [1, 2, 3, 4, 1, 0] } },
      { name: 'a single day', ref: '§11', args: { days: days([45]), probes: [45] }, expected: { t1: 45, t2: 45, t3: 45, levels: [4] } },
    ],
  }
}

/** Reference for heatmapGroup (engine.md §8.3), used to check the hand-written values. */
export function heatmapReference(dayMinutes, probes) {
  const mins = dayMinutes.filter(v => v > 0).sort((a, b) => a - b)
  const q = p => (mins.length ? mins[Math.min(mins.length - 1, Math.floor(p * mins.length))] : 0)
  const [t1, t2, t3] = [q(0.25), q(0.5), q(0.75)]
  const level = m => (m == null ? 0 : !m ? 1 : m >= t3 ? 4 : m >= t2 ? 3 : m >= t1 ? 2 : 1)
  return { t1, t2, t3, levels: probes.map(level) }
}

/** coach-B3 (coach.md §7.5 `superset` apply, app side): unique tag per link, cleanupSg afterwards. */
export function linkSupersetGroup() {
  return {
    scope: 'app',
    fix: 'coach-B3',
    note: 'Apply `superset` changes {link: true, with} to routine `ex`, one per [exId, with] pair in `links`, in order. `expected.ids` is the order afterwards; `expected.sg` gives each position a letter shared by exactly the positions that must share one tag, or null for no tag. Tags are fresh ("sg" + uid()), never equal to a tag already in the routine.',
    vectors: [
      {
        name: 'the partner moves next to the exercise',
        args: { ex: [{ id: '0001' }, { id: '0007' }, { id: '0009' }], links: [['0001', '0009']] },
        expected: { ids: ['0001', '0009', '0007'], sg: ['A', 'A', null] },
      },
      {
        name: 'two links in one change set get two tags',
        args: { ex: [{ id: '1' }, { id: '2' }, { id: '3' }, { id: '4' }], links: [['1', '2'], ['3', '4']] },
        expected: { ids: ['1', '2', '3', '4'], sg: ['A', 'A', 'B', 'B'] },
      },
      {
        name: 'the previous partner loses its orphaned tag',
        args: { ex: [{ id: '1', sg: 'old' }, { id: '2', sg: 'old' }, { id: '3' }], links: [['2', '3']] },
        expected: { ids: ['1', '2', '3'], sg: [null, 'A', 'A'] },
      },
    ],
  }
}

/** Reference for linkSupersetGroup: coach.md §7.5 `superset` link with coach-B3 applied. */
export function linkSupersetReference(ex, links, cleanupSg) {
  const list = ex.map(e => ({ ...e }))
  let serial = 0
  for (const [exId, partnerId] of links) {
    const j = list.findIndex(e => e.id === partnerId)
    const [partner] = list.splice(j, 1)
    const at = list.findIndex(e => e.id === exId)
    list.splice(at + 1, 0, partner)
    const tag = 'sg' + (++serial)
    list[at].sg = tag
    list[at + 1].sg = tag
    cleanupSg(list)
  }
  const letters = new Map()
  const sg = list.map(e => {
    if (!e.sg) return null
    if (!letters.has(e.sg)) letters.set(e.sg, String.fromCharCode(65 + letters.size))
    return letters.get(e.sg)
  })
  return { ids: list.map(e => e.id), sg }
}
