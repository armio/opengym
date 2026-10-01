// Vectors for plan-hash.json, current-value.json and validate.json, computed by the original
// server code (api/coach/payload.js canonicalPlan, api/coach/validate.js) and the original
// client code (frontend/src/lib/coach.js hashPlan, currentValue).

import { encode } from './json.mjs'

/* ------------------------------------------------------------------ plan-hash.json */

/** coach.test.js `state()`, reduced to the plan doc (routines, week, customEx). */
const baseRoutines = () => [{
  id: 'r1', name: 'Full body A', emoji: '💪', prog: 'linear',
  ex: [
    { id: '0001', sets: 3, reps: 10, mode: 'reps', weight: 20, prog: 'linear' },
    { id: '0007', sets: 3, sec: 45, mode: 'time' },
    { id: '0009', sets: 3, reps: 12, mode: 'reps' },
  ],
}, { id: 'r2', name: 'Full body B', ex: [{ id: '0002', sets: 4, reps: 6, mode: 'reps' }] }]
const basePlan = (over = {}) => ({ routines: baseRoutines(), week: { 1: 'r1', 3: 'r2', 5: 'r1' }, customEx: [], ...over })
const tiny = (over = {}) => ({ routines: [{ id: 'r1', name: 'A', ex: [{ id: '0001', sets: 3, reps: 10, ...over }] }], week: { 1: 'r1' } })

/** The exact string hashPlan feeds to its loop (coach.md §7.1). */
function canonString(plan) {
  return JSON.stringify({
    routines: (plan?.routines || []).map(r => [r.id, r.name, r.prog, (r.ex || []).map(e =>
      [e.id, e.mode, e.sets, e.reps, e.sec, e.min, e.speed, e.weight, e.prog, e.inc, e.repsMin, e.sg].join(':'))]),
    week: Object.keys(plan?.week || {}).sort().map(k => k + '=' + plan.week[k]),
  })
}

export function planHashFile({ payload, coach, exercises }) {
  const specs = [
    { name: 'coach.test state()', ref: 'coach.md §7.1', plan: basePlan(), hash: 'f784c8ca82c205eb',
      canon: '{"routines":[["r1","Full body A","linear",["0001:reps:3:10:0:0:0:20:linear:0:0:","0007:time:3:0:45:0:0:0::0:0:","0009:reps:3:12:0:0:0:0::0:0:"]],["r2","Full body B","",["0002:reps:4:6:0:0:0:0::0:0:"]]],"week":["1=r1","3=r2","5=r1"]}' },
    { name: 'state({ week: {} })', ref: 'coach.md §7.1', plan: basePlan({ week: {} }), hash: 'd619a67e9451fd3f',
      canon: '{"routines":[["r1","Full body A","linear",["0001:reps:3:10:0:0:0:20:linear:0:0:","0007:time:3:0:45:0:0:0::0:0:","0009:reps:3:12:0:0:0:0::0:0:"]],["r2","Full body B","",["0002:reps:4:6:0:0:0:0::0:0:"]]],"week":[]}' },
    { name: 'state({ routines: [] })', ref: 'coach.md §7.1', plan: basePlan({ routines: [] }), hash: '14115d860381e569',
      canon: '{"routines":[],"week":["1=r1","3=r2","5=r1"]}' },
    { name: 'no plan at all', ref: 'coach.md §7.1', plan: {}, hash: '76c7079ae0cff7e9', canon: '{"routines":[],"week":[]}' },
    { name: 'one exercise', ref: 'coach.md §7.1', plan: tiny(), hash: '05bc4c803f5a9a39', canon: '{"routines":[["r1","A","",["0001:reps:3:10:0:0:0:0::0:0:"]]],"week":["1=r1"]}' },
    { name: 'one exercise, weight 0 ≡ no weight', ref: 'coach.md §7.1', plan: tiny({ weight: 0 }), hash: '05bc4c803f5a9a39' },
    { name: 'one exercise, sets 4', ref: 'coach.md §7.1', plan: tiny({ sets: 4 }), hash: '0ee50bfd7ee8f6a1', canon: '{"routines":[["r1","A","",["0001:reps:4:10:0:0:0:0::0:0:"]]],"week":["1=r1"]}' },
    {
      name: 'non-ASCII name, decimals, superset, cardio, Sunday', ref: 'coach.md §7.1',
      plan: {
        routines: [{ id: 'r1', name: 'Ä ü', prog: 'double', ex: [
          { id: '0001', sets: 3, reps: 10, weight: 22.5, inc: 2.5, repsMin: 8, sg: 'a' },
          { id: 'x', mode: 'cardio', sets: 1, min: 20, speed: 8.5 },
        ] }],
        week: { 0: 'r1', 6: 'r1' },
      },
      hash: 'a7c56f988c93f498',
      canon: '{"routines":[["r1","Ä ü","double",["0001:reps:3:10:0:0:0:22.5::2.5:8:a","x:cardio:1:0:0:20:8.5:0::0:0:"]]],"week":["0=r1","6=r1"]}',
    },
    {
      name: 'custom exercise without mode takes its body part',
      plan: {
        routines: [{ id: 'r1', name: 'Cardio', ex: [{ id: 'cx-run', sets: 1, min: 25, speed: 9, weight: 5 }, { id: '3220', sets: 1, min: 10, speed: 6 }] }],
        week: { 2: 'r1' },
        customEx: [{ id: 'cx-run', n: 'sled run', bp: 'cardio', desc: '', tg: '', eq: 'custom', custom: true }],
      },
    },
    {
      name: 'week ignores non-weekday keys and empty values',
      plan: { routines: tiny().routines, week: { 1: 'r1', 2: '', 7: 'r1', x: 'r1', 6: null } },
    },
    {
      name: 'JSON escapes and UTF-16 code units',
      plan: { routines: [{ id: 'r"1', name: 'Día "A"\\\n\t\u0001 💪', prog: 'linear', ex: [{ id: '0001', sets: 3, reps: 10, sg: 'ß' }] }], week: { 4: 'r"1' } },
    },
    {
      name: 'numbers join the way JavaScript prints them',
      plan: { routines: [{ id: 'r1', name: 'N', ex: [
        { id: '0001', sets: 3, reps: 10, weight: 1e21, inc: 0.1 + 0.2 },
        { id: '0025', sets: '4', reps: 8, weight: 1.5e-7, inc: 100, repsMin: -1 },
        { id: '0007', mode: 'time', sec: 30.5, sets: 2, weight: 12.75, reps: 99 },
      ] }], week: { 3: 'r1' } },
    },
    {
      name: 'mode wins over body part; cardio drops weight',
      plan: { routines: [{ id: 'r1', name: 'M', prog: 'off', ex: [
        { id: '3220', mode: 'reps', sets: 3, reps: 12, weight: 10 },
        { id: '0001', mode: 'cardio', sets: 1, min: 15, speed: 7, weight: 10, reps: 5 },
        { id: '0001', mode: 'bogus', sets: 2, sec: 40, reps: 6 },
      ] }], week: {} },
    },
  ]

  const vectors = specs.map(spec => {
    const canonical = payload.canonicalPlan(spec.plan)
    const canon = canonString(canonical)
    const hash = coach.hashPlan(canonical)
    if (spec.hash && hash !== spec.hash) throw new Error(`${spec.name}: hash ${hash}, spec says ${spec.hash}`)
    if (spec.canon && canon !== spec.canon) throw new Error(`${spec.name}: canon ${canon}, spec says ${spec.canon}`)
    exercises.registerCustom(spec.plan.customEx || [])
    if (coach.planHash(spec.plan) !== hash) throw new Error(`${spec.name}: client and server disagree`)
    return { name: spec.name, ...(spec.ref ? { ref: spec.ref } : {}), plan: spec.plan, canonical, canon, hash }
  })
  return {
    about: 'canonicalPlan + hashPlan (coach.md §7.1, contract §5.4). `plan` is the plan doc; `canonical` is canonicalPlan(plan); `canon` is the string hashPlan iterates over (UTF-16 code units); `hash` is the result. modeOf resolves ids through the library and plan.customEx.',
    vectors: encode(vectors),
  }
}

/* ------------------------------------------------------------------ current-value.json */

export function currentValueFile({ coach }) {
  const plan = basePlan()
  plan.routines[0].ex[0].repsMin = 8
  plan.routines[0].ex[0].inc = 2.5
  const change = over => ({ id: 'c1', type: 'sets', target: { routineId: 'r1', exId: '0001' }, before: 3, after: 4, why: 'x', ...over })
  const cases = [
    ['sets', change()],
    ['reps', change({ type: 'reps' })],
    ['repsMin', change({ type: 'repsMin' })],
    ['repsMin unset', change({ type: 'repsMin', target: { routineId: 'r1', exId: '0009' } })],
    ['sec', change({ type: 'sec', target: { routineId: 'r1', exId: '0007' } })],
    ['sec unset on a reps exercise', change({ type: 'sec' })],
    ['inc', change({ type: 'inc' })],
    ['inc unset', change({ type: 'inc', target: { routineId: 'r2', exId: '0002' } })],
    ['exercise-prog', change({ type: 'exercise-prog' })],
    ['exercise-prog unset', change({ type: 'exercise-prog', target: { routineId: 'r1', exId: '0007' } })],
    ['routine-prog', change({ type: 'routine-prog', target: { routineId: 'r1' } })],
    ['routine-prog unset', change({ type: 'routine-prog', target: { routineId: 'r2' } })],
    ['rename-routine', change({ type: 'rename-routine', target: { routineId: 'r2' } })],
    ['week, planned day', change({ type: 'week', target: { weekday: 1 } })],
    ['week, rest day', change({ type: 'week', target: { weekday: 6 } })],
    ['sets on a missing exercise', change({ target: { routineId: 'r1', exId: 'ghost' } })],
    ['sets on a missing routine', change({ target: { routineId: 'ghost', exId: '0001' } })],
    ...['add-exercise', 'remove-exercise', 'swap-exercise', 'cardio', 'reorder', 'superset', 'add-routine', 'remove-routine']
      .map(type => [`${type} is structural`, change({ type })]),
  ]
  return {
    about: 'currentValue(plan, change) (coach.md §7.2): the plan value a scalar change is about; `{"$js":"undefined"}` for structural types.',
    plan,
    vectors: cases.map(([name, c]) => ({ name, change: c, expected: encode(coach.currentValue(plan, c)) })),
  }
}

/* ------------------------------------------------------------------ validate.json */

const PLAN = {
  routines: [{ id: 'r1', name: 'Full body A', ex: [{ id: '0001', sets: 3, reps: 10 }, { id: '0007', sets: 3, sec: 45 }] },
    { id: 'r2', name: 'Full body B', ex: [{ id: '0009', sets: 3, reps: 8 }] }],
  week: { 1: 'r1', 3: 'r2' },
}
const change = over => ({ id: 'c1', type: 'sets', target: { routineId: 'r1', exId: '0001' }, before: 3, after: 4, why: 'stalled twice', ...over })
const review = changes => ({ coach_contract: 1, summary: 's', changes })
const oneEx = (ex, over = {}) => ({ routines: [{ id: 'r1', name: 'A', ex: [ex] }], ...over })

function planVectors() {
  const many = n => Array.from({ length: n }, (_, i) => ({ id: 'r' + i, name: 'R' + i, ex: [{ id: '0001' }] }))
  return [
    // §6.4
    { name: 'unknown exercise id is rejected', ref: '§6.4', data: { routines: [{ name: 'A', ex: [{ id: '0001', sets: 3, reps: 10 }, { id: 'not-a-real-id', sets: 3, reps: 10 }] }] } },
    { name: 'custom exercise defined in the answer', ref: '§6.4', data: { routines: [{ name: 'A', ex: [{ id: 'cx1', sets: 3, reps: 10 }] }], customEx: [{ id: 'cx1', n: 'Sandbag carry', bp: 'back' }] } },
    { name: 'week points at an unknown routine', ref: '§6.4', data: { routines: [{ id: 'r1', name: 'A', ex: [{ id: '0001', sets: 3, reps: 10 }] }], week: { 1: 'ghost' } } },
    { name: 'weight capped at the best', ref: '§6.4', data: oneEx({ id: '0001', sets: 3, reps: 10, weight: 100 }), ctx: { workingWeights: [{ id: '0001', best: 40 }] } },
    { name: 'days per week enforced', ref: '§6.4', data: { routines: [{ id: 'r1', name: 'A', ex: [{ id: '0001', sets: 3, reps: 10 }] }], week: { 1: 'r1', 2: 'r1', 3: 'r1', 4: 'r1' } }, ctx: { daysPerWeek: 3 } },
    { name: 'unknown routine policy', ref: '§6.4', data: { routines: [{ name: 'A', prog: 'vibes', ex: [{ id: '0001', sets: 3, reps: 10 }] }] } },
    // P1–P3
    { name: 'P1 null', data: null },
    { name: 'P1 string', data: 'plan' },
    { name: 'P1 array is an object without routines', data: [] },
    { name: 'P2 nochange', data: { nochange: true, routines: [{ name: 'A', ex: [{ id: '0001' }] }] } },
    { name: 'P3 empty routines', data: { routines: [] } },
    { name: 'P3 missing routines', data: {} },
    // P4 customEx
    {
      name: 'P4 customEx normalised, invalid dropped, clamped',
      data: {
        routines: [{ name: 'A', ex: [{ id: 'cx1' }, { id: 'cx2' }] }],
        customEx: [null, { id: 'cx0' }, { id: ' ', n: 'blank id' }, { id: 'cx1', n: 'N'.repeat(70), desc: 'D'.repeat(410) }, { id: 'cx2', n: 'Two', bp: 'B'.repeat(35), desc: '' }],
      },
    },
    { name: 'P4 at most 20 customEx', data: { routines: [{ name: 'A', ex: [{ id: 'c20' }] }], customEx: Array.from({ length: 21 }, (_, i) => ({ id: 'c' + i, n: 'n' + i })) } },
    // P5–P9
    { name: 'P5 only the first 7 routines', data: { routines: many(8), week: { 0: 'r7' } } },
    { name: 'P6 routine not an object', data: { routines: [null, 'x', { name: 'A', ex: [{ id: '0001' }] }] } },
    { name: 'P7 routine name required', data: { routines: [{ ex: [{ id: '0001' }] }, { name: '  ', ex: [{ id: '0001' }] }] } },
    { name: 'P9 only the first 20 exercises', data: { routines: [{ name: 'A', ex: [...Array.from({ length: 20 }, () => ({ id: '0001' })), { id: 'nope' }] }] } },
    // P10–P14
    { name: 'P10 exercise id required', data: { routines: [{ name: 'A', ex: [null, {}, { id: '' }, { id: 7 }, { id: '0001' }] }] } },
    { name: 'P12 numbers defaulted per mode', data: { routines: [{ name: 'A', ex: [
      { id: '0001', sets: 0, reps: '8', weight: -5 },
      { id: '0001', mode: 'time', sets: 11, sec: 4, weight: 12.5 },
      { id: '3220', mode: 'cardio', sets: 2.5, min: 181, speed: -1, weight: 9 },
      { id: '3220', min: 30, speed: 10 },
      { id: '0001', mode: 'time', sec: 3600, weight: Infinity },
      { id: '0001', reps: 100, sets: 10, weight: 0.5, inc: 0, repsMin: 101, sg: ' ', why: ' ' },
    ] }] } },
    { name: 'P13 exercise policy', data: { routines: [{ name: 'A', ex: [{ id: '0001', prog: 'vibes' }, { id: '0001', prog: 'double', inc: 1.25, repsMin: 6, sg: 'abcdefghijklmnopqrstuvwxyz', why: 'W'.repeat(401) }] }] } },
    { name: 'P14 no valid exercises', data: { routines: [{ name: 'A', ex: [] }, { name: 'B' }, { name: 'C', ex: [{ id: 'nope' }] }] } },
    // P15–P18
    { name: 'P15 week keys', data: { routines: [{ id: 'r1', name: 'A', ex: [{ id: '0001' }] }], week: { x: 'r1', 7: 'r1', '-1': 'r1', 1.5: 'r1', 2: 'r1' } } },
    { name: 'P16 week values', data: { routines: [{ id: 'r1', name: 'A', ex: [{ id: '0001' }] }], week: { 1: null, 2: 'r1' } } },
    { name: 'P17 cap only above the best, per id', data: { routines: [{ name: 'A', ex: [{ id: '0001', weight: 30 }, { id: '0025', weight: 90 }, { id: '0007', mode: 'time', weight: 50 }] }] }, ctx: { workingWeights: [{ id: '0001', best: 40 }, { id: '0025', best: 80 }, { id: '0007', best: 20 }] } },
    { name: 'P18 skipped for an empty week', data: oneEx({ id: '0001' }), ctx: { daysPerWeek: 3 } },
    { name: 'P18 skipped for a daysPerWeek outside 1..7', data: oneEx({ id: '0001' }, { week: { 1: 'r1' } }), ctx: { daysPerWeek: 0 } },
    { name: 'P18 matching count', data: oneEx({ id: '0001' }, { week: { 1: 'r1', 4: 'r1' } }), ctx: { daysPerWeek: 2 } },
    // normalisation of a valid bundle
    {
      name: 'full bundle normalisation',
      data: {
        coach_contract: 1, opengym_plan: 1, name: 'Plan '.repeat(10), summary: 'S', basedOn: 'no history yet',
        week: { 1: 'up', 4: 'r1' },
        routines: [
          { id: 'up', name: 'Upper', emoji: '💪', prog: 'linear', why: 'Balanced.', ex: [{ id: '0025', sets: 4, mode: 'reps', reps: 6, weight: 60, prog: 'double', inc: 2.5, repsMin: 4, sg: 'a', why: 'Main lift.' }, { id: '0001', sets: 3, reps: 15, sg: 'a' }] },
          { name: 'Conditioning', emoji: '👨‍👩‍👧‍👦 extra', ex: [{ id: '3220', mode: 'cardio', min: 20, speed: 8.5 }, { id: '0007', mode: 'time', sec: 60 }] },
        ],
        customEx: [],
      },
      ctx: { daysPerWeek: 2 },
    },
    { name: 'defaults: name, emoji, summary', data: { routines: [{ name: 'A', emoji: '', ex: [{ id: '0001' }] }] } },
  ]
}

function reviewVectors() {
  const good = {
    'add-exercise': change({ type: 'add-exercise', target: { routineId: 'r1' }, after: { id: '0009', sets: 3, reps: 10 } }),
    'remove-exercise': change({ type: 'remove-exercise' }),
    'swap-exercise': change({ type: 'swap-exercise', after: { id: '0009' } }),
    sets: change({ type: 'sets', after: 4 }),
    reps: change({ type: 'reps', after: 12 }),
    repsMin: change({ type: 'repsMin', after: 8 }),
    sec: change({ type: 'sec', target: { routineId: 'r1', exId: '0007' }, after: 60 }),
    cardio: change({ type: 'cardio', after: { min: 25, speed: 9 } }),
    reorder: change({ type: 'reorder', target: { routineId: 'r1' }, after: ['0007', '0001'] }),
    superset: change({ type: 'superset', after: { link: true, with: '0007' } }),
    'routine-prog': change({ type: 'routine-prog', target: { routineId: 'r1' }, after: 'double' }),
    'exercise-prog': change({ type: 'exercise-prog', after: 'greyskull' }),
    inc: change({ type: 'inc', after: 2.5 }),
    'add-routine': change({ type: 'add-routine', target: {}, after: { name: 'C', ex: [{ id: '0001', sets: 3, reps: 10 }] } }),
    'remove-routine': change({ type: 'remove-routine', target: { routineId: 'r2' } }),
    'rename-routine': change({ type: 'rename-routine', target: { routineId: 'r1' }, after: 'Upper' }),
    week: change({ type: 'week', target: { weekday: 2 }, after: 'r1' }),
  }
  const r = (name, changes, extra = {}) => ({ name, data: review(changes), ...extra })
  return [
    // §6.4
    r('invented change type', [change({ type: 'delete-all-workouts' })], { ref: '§6.4' }),
    r('target routine unknown', [change({ target: { routineId: 'ghost', exId: '0001' } })], { ref: '§6.4' }),
    r('exercise not in that routine', [change({ target: { routineId: 'r1', exId: '9999' } })], { ref: '§6.4' }),
    r('right exercise, wrong routine', [change({ target: { routineId: 'r2', exId: '0001' } })], { ref: '§6.4' }),
    r('why required', [change({ why: '' })], { ref: '§6.4' }),
    r('sets must be an integer', [change({ type: 'sets', after: 'four' })], { ref: '§6.4' }),
    r('sets above 10', [change({ type: 'sets', after: 99 })], { ref: '§6.4' }),
    r('reps 0', [change({ type: 'reps', after: 0 })], { ref: '§6.4' }),
    r('exercise-prog linear', [change({ type: 'exercise-prog', after: 'linear' })], { ref: '§6.4' }),
    r('exercise-prog vibes', [change({ type: 'exercise-prog', after: 'vibes' })], { ref: '§6.4' }),
    r('inc negative', [change({ type: 'inc', after: -5 })], { ref: '§6.4' }),
    r('add-exercise with a library id gets its name', [change({ type: 'add-exercise', target: { routineId: 'r1' }, after: { id: '0009', sets: 3, reps: 12 } })], { ref: '§6.4' }),
    r('add-exercise with a made-up id', [change({ type: 'add-exercise', target: { routineId: 'r1' }, after: { id: 'made-up' } })], { ref: '§6.4' }),
    r('reorder permutation', [change({ type: 'reorder', target: { routineId: 'r1' }, after: ['0007', '0001'] })], { ref: '§6.4' }),
    r('reorder dropping one', [change({ type: 'reorder', target: { routineId: 'r1' }, after: ['0007'] })], { ref: '§6.4' }),
    r('reorder smuggling one in', [change({ type: 'reorder', target: { routineId: 'r1' }, after: ['0007', '0009'] })], { ref: '§6.4' }),
    r('week to an existing routine', [change({ type: 'week', target: { weekday: 6 }, after: 'r2' })], { ref: '§6.4' }),
    r('week to rest', [change({ type: 'week', target: { weekday: 6 }, after: 'rest' })], { ref: '§6.4' }),
    r('week to null', [change({ type: 'week', target: { weekday: 6 }, after: null })], { ref: '§6.4' }),
    r('week weekday 9', [change({ type: 'week', target: { weekday: 9 }, after: 'r1' })], { ref: '§6.4' }),
    r('week to an unknown routine', [change({ type: 'week', target: { weekday: 6 }, after: 'ghost' })], { ref: '§6.4' }),
    { name: 'nochange with a reading', ref: '§6.4', data: { nochange: true, reading: 'Plan is working.' } },
    r('empty change list is nochange', [], { ref: '§6.4' }),
    { name: 'notes survive with a change', ref: '§6.4', data: { summary: 's', changes: [change()], notes: ['Body weight is flat — eat more.'] } },
    r('one bad change fails the set', [change(), change({ id: 'c2', type: 'not-a-type' })], { ref: '§6.4' }),
    ...Object.entries(good).map(([type, c]) => r(`well-formed ${type}`, [c], { ref: '§6.4' })),
    // R1–R3
    { name: 'R1 null', data: null },
    { name: 'R2 nochange falls back to summary', data: { nochange: 1, summary: 'S'.repeat(1300) } },
    { name: 'R2 nochange without text', data: { nochange: true } },
    { name: 'R3 changes missing', data: { summary: 's' } },
    { name: 'R3 changes not an array', data: { changes: {} } },
    // R4–R10
    r('R4 only the first 25 changes', Array.from({ length: 26 }, (_, i) => change({ id: 'c' + i, ...(i === 25 ? { type: 'bogus' } : {}) }))),
    r('R5 change not an object', [null, 'x', change()]),
    r('R6 type missing', [change({ type: undefined })]),
    r('R7 why blank', [change({ why: '   ' }), change({ why: 7 })]),
    r('R8 routineId missing', [change({ target: {} }), change({ target: undefined, type: 'rename-routine', after: 'X' })]),
    r('R9 exId missing', ['remove-exercise', 'swap-exercise', 'sets', 'reps', 'repsMin', 'sec', 'cardio', 'exercise-prog', 'inc', 'superset'].map(type => change({ type, target: { routineId: 'r1' } }))),
    // per-type checks
    r('R11 add-exercise without after', [change({ type: 'add-exercise', target: { routineId: 'r1' }, after: null })]),
    r('R11 add-exercise normalisation', [change({ type: 'add-exercise', target: { routineId: 'r1', exId: '0001', weekday: 3 }, after: { id: '3220', sets: 0, mode: 'cardio', reps: 8, sec: 4, weight: 50, prog: 'vibes', position: 21, min: 30, speed: 9 } }),
      change({ id: 'c2', type: 'add-exercise', target: { routineId: 'r2' }, after: { id: '0001', mode: 'bogus', sec: 60, weight: -1, prog: 'double', position: 0 } })]),
    r('R12 swap to an unknown id', [change({ type: 'swap-exercise', after: { id: 'nope' } })]),
    r('R12 swap normalisation', [change({ type: 'swap-exercise', after: { id: '0025', sets: 5, reps: 101, weight: 70, mode: 'time' } })]),
    r('R13 swap for itself', [change({ type: 'swap-exercise', after: { id: '0001' } })]),
    r('R14–R17 ranges', [change({ type: 'sets', after: 0 }), change({ type: 'reps', after: 100 }), change({ type: 'repsMin', after: 101 }), change({ type: 'sec', target: { routineId: 'r1', exId: '0007' }, after: 4 }), change({ type: 'sec', target: { routineId: 'r1', exId: '0007' }, after: 3600 })]),
    r('R18 cardio', [change({ type: 'cardio', after: {} }), change({ type: 'cardio', after: { speed: 9.5 } }), change({ type: 'cardio', after: { min: 200, speed: 7 } }), change({ type: 'cardio', after: { speed: -1 } }), change({ type: 'cardio', after: null })]),
    r('R19 inc', [change({ type: 'inc', after: 0 }), change({ type: 'inc', after: '2.5' }), change({ type: 'inc', after: 1.25 })]),
    r('R20 policies', [change({ type: 'routine-prog', target: { routineId: 'r1' }, after: 'time' }), change({ type: 'routine-prog', target: { routineId: 'r1' }, after: null })]),
    r('R21 reorder not an array', [change({ type: 'reorder', target: { routineId: 'r1' }, after: '0007,0001' })]),
    r('R22 reorder with a duplicate passes (coach-Q7 in the original)', [change({ type: 'reorder', target: { routineId: 'r1' }, after: ['0001', '0001'] })]),
    r('R23 superset link without partner', [change({ type: 'superset', after: { link: true } })]),
    r('R24 superset partner not in routine', [change({ type: 'superset', after: { link: true, with: '0009' } })]),
    r('R24 superset with itself passes (coach-Q8 in the original)', [change({ type: 'superset', after: { link: true, with: '0001' } })]),
    r('superset unlink', [change({ type: 'superset', after: { link: false, with: '0007' } }), change({ type: 'superset', after: null })]),
    r('R25 add-routine name required', [change({ type: 'add-routine', target: {}, after: { ex: [{ id: '0001' }] } })]),
    r('R26 add-routine needs a library exercise', [change({ type: 'add-routine', target: {}, after: { name: 'C', ex: [{ id: 'nope' }, null] } })]),
    r('R26 add-routine normalisation', [change({ type: 'add-routine', target: { routineId: 'ghost' }, after: {
      name: 'N'.repeat(45), emoji: '🏋️‍♀️🏋️‍♀️', prog: 'time',
      ex: [{ id: 'nope' }, { id: '0001', sets: 12, mode: 'time', sec: 30, reps: 5 }, { id: '3220', mode: 'cardio', min: 30, speed: 9 }, ...Array.from({ length: 20 }, () => ({ id: '0025' }))],
    } })]),
    r('R27 rename to blank', [change({ type: 'rename-routine', target: { routineId: 'r1' }, after: '  ' })]),
    r('R27 rename clamped', [change({ type: 'rename-routine', target: { routineId: 'r1' }, after: 'R'.repeat(50) })]),
    r('R28 weekday missing', [change({ type: 'week', target: {}, after: 'r1' })]),
    r('R28 weekday as a string', [change({ type: 'week', target: { weekday: '2' }, after: 'r1' })]),
    r('R29 week to undefined', [change({ type: 'week', target: { weekday: 0 }, after: undefined })]),
    r('remove types force after null', [change({ type: 'remove-exercise', after: { id: 'x' } }), change({ id: 'c2', type: 'remove-routine', target: { routineId: 'r2' }, after: 'x' })]),
    // envelope normalisation
    {
      name: 'envelope normalisation',
      data: {
        summary: 'S'.repeat(1300),
        evidence: { from: '2026-07-01', to: '', sessions: 10001 },
        changes: [
          { type: 'sets', target: { routineId: 'r1', exId: '0001', weekday: 7 }, after: 4, why: 'W'.repeat(700) },
          { id: 'I'.repeat(45), type: 'reps', target: { routineId: 'r1', exId: '0001' }, before: 10, after: 12, why: 'y' },
          { id: ' ', type: 'week', target: { weekday: 0, routineId: 'ghost' }, before: undefined, after: 'rest', why: 'z' },
        ],
        notes: ['n1', ' ', 7, 'N'.repeat(610), 'n4', 'n5', 'n6', 'n7'],
      },
    },
    { name: 'evidence missing', data: { changes: [change()] } },
    { name: 'evidence sessions valid', data: { evidence: { from: 1, to: '2026-09-30', sessions: 0 }, changes: [change()] } },
  ]
}

export function validateFile({ validate }) {
  const planGroup = planVectors().map(v => ({
    name: v.name, ...(v.ref ? { ref: v.ref } : {}),
    args: encode({ data: v.data, ...(v.ctx ? { ctx: v.ctx } : {}) }),
    expected: encode(validate.validatePlan(v.data, v.ctx)),
  }))
  const reviewGroup = reviewVectors().map(v => ({
    name: v.name, ...(v.ref ? { ref: v.ref } : {}),
    args: encode({ data: v.data }),
    expected: encode(validate.validateReview(v.data, PLAN)),
  }))
  return {
    about: 'validatePlan(data, ctx) and validateReview(data, plan) exactly as api/coach/validate.js (coach.md §6). Every expected value is the original\'s full result. validateReview vectors all use `plan`.',
    constants: { CHANGE_TYPES: validate.CHANGE_TYPES },
    plan: PLAN,
    groups: {
      validatePlan: { vectors: planGroup },
      validateReview: { vectors: reviewGroup },
    },
  }
}
