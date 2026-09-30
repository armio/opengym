import { beforeEach, describe, expect, it } from 'vitest'
import { seedBodyweight, seedDoc, seedWorkouts } from '../helpers'
import { daysFrom, freshOwner, McpClient, repsEntry, seedExWeights, workout } from './client'

let client: McpClient
let T: (days: number) => string

beforeEach(async () => {
  const owner = await freshOwner()
  client = owner.client
  T = days => daysFrom(owner.today, days)
  await seedDoc('settings', { unit: 'kg', effort: 'rir', targetW: 75 })
  await seedDoc('plan', { routines: [{ id: 'r1', name: 'Torso', emoji: '💪', ex: [{ id: '0025', sets: 3, mode: 'reps', reps: 8 }] }], week: { '1': 'r1' }, customEx: [] })
  await seedWorkouts([
    workout('w1', T(-9), [repsEntry('0025', 70, [8, 8, 8], {}, { rir: 2 })]),
    workout('w2', T(-5), [{ ...repsEntry('0025', 72.5, [8, 8, 8]), sets: [{ w: 72.5, r: 8, done: true }, { w: 72.5, r: 8, done: true }, { w: 72.5, r: 8, done: true }, { w: 72.5, r: 8, done: false }] }], 45, { rating: 'right' }),
    workout('w3', T(-2), [repsEntry('0025', 75, [8, 8, 7], {}, { rir: 1 }), repsEntry('0043', 100, [5, 5, 5])], 80),
  ])
  await seedExWeights({ '0025': { w: 75, d: T(-2) } })
})

describe('get_exercise_history', () => {
  it('lists the sessions oldest first with records, working weight and the next prescription', async () => {
    const history = await client.ok('get_exercise_history', { exerciseId: '0025' })
    expect(history.unit).toBe('kg')
    expect(history.exercise).toEqual({ id: '0025', name: 'barbell bench press', bodyPart: 'chest', target: 'pectorals', equipment: 'barbell', custom: false, mode: 'reps' })
    expect(history.totalSessions).toBe(3)
    expect(history.sessions).toEqual([
      { d: T(-9), workoutId: 'w1', mode: 'reps', sets: [{ w: 70, r: 8, rir: 2 }, { w: 70, r: 8, rir: 2 }, { w: 70, r: 8, rir: 2 }], topSet: { w: 70, r: 8 }, e1rm: 88.7, volume: 1680, avgRir: 2 },
      {
        d: T(-5), workoutId: 'w2', mode: 'reps',
        sets: [{ w: 72.5, r: 8 }, { w: 72.5, r: 8 }, { w: 72.5, r: 8 }, { w: 72.5, r: 8, done: false }],
        topSet: { w: 72.5, r: 8 }, e1rm: 91.8, volume: 1740, avgRir: null,
      },
      { d: T(-2), workoutId: 'w3', mode: 'reps', sets: [{ w: 75, r: 8, rir: 1 }, { w: 75, r: 8, rir: 1 }, { w: 75, r: 7, rir: 1 }], topSet: { w: 75, r: 8 }, e1rm: 95, volume: 1725, avgRir: 1 },
    ])
    expect(history.best).toEqual({ e1rm: { value: 95, w: 75, r: 8, d: T(-2) }, weight: 75 })
    expect(history.workingWeight).toEqual({ w: 75, d: T(-2) })
    // w2's unchecked set reads as 0 reps and w3 missed a rep: two stalls, so linear holds the weight.
    const next = { policy: 'linear', kind: 'hold', weight: 75, why: 'Missed reps last time — same weight again (1 of 3 to go).' }
    expect(history.inPlan).toEqual([{ routineId: 'r1', routine: 'Torso', config: { id: '0025', name: 'barbell bench press', mode: 'reps', sets: 3, reps: 8, policy: 'linear' }, next }])
    expect(history.nextPrescription).toEqual(next)

    const lastTwo = await client.ok('get_exercise_history', { exerciseId: '0025', limit: 2 })
    expect(lastTwo.sessions.map((s: { workoutId: string }) => s.workoutId)).toEqual(['w2', 'w3'])
    expect(lastTwo.totalSessions).toBe(3)
  })

  it('works for an exercise outside the plan and rejects unknown ids', async () => {
    const squat = await client.ok('get_exercise_history', { exerciseId: '0043' })
    expect(squat).toEqual(expect.objectContaining({ totalSessions: 1, inPlan: [], nextPrescription: null, workingWeight: null }))
    const neverDone = await client.ok('get_exercise_history', { exerciseId: '0032' })
    expect(neverDone).toEqual(expect.objectContaining({ totalSessions: 0, sessions: [], best: { e1rm: null, weight: null } }))
    expect((await client.call('get_exercise_history', { exerciseId: 'nope' })).isError).toBe(true)
  })
})

describe('list_workouts', () => {
  it('lists workouts newest first, summarised or in full', async () => {
    const all = await client.ok('list_workouts')
    expect(all.unit).toBe('kg')
    expect(all.hasMore).toBe(false)
    expect(all.workouts.map((w: { id: string }) => w.id)).toEqual(['w3', 'w2', 'w1'])
    expect(all.workouts[0]).toEqual({
      id: 'w3', d: T(-2), name: 'Torso', routineId: 'r1', minutes: 80, setsDone: 6, volume: 3225,
      exercises: [
        { id: '0025', name: 'barbell bench press', setsDone: 3, top: { w: 75, r: 8 } },
        { id: '0043', name: 'barbell full squat', setsDone: 3, top: { w: 100, r: 5 } },
      ],
    })

    const page = await client.ok('list_workouts', { limit: 2 })
    expect(page.workouts.map((w: { id: string }) => w.id)).toEqual(['w3', 'w2'])
    expect(page.hasMore).toBe(true)

    const detailed = await client.ok('list_workouts', { from: T(-5), to: T(-5), detail: true })
    expect(detailed.workouts).toEqual([
      expect.objectContaining({ id: 'w2', rating: 'right', minutes: 45, entries: [expect.objectContaining({ id: '0025', mode: 'reps', target: { sets: 3, reps: 8 } })] }),
    ])
    expect(detailed.workouts[0].entries[0].sets).toHaveLength(4)

    expect((await client.call('list_workouts', { from: T(-1), to: T(-5) })).isError).toBe(true)
  })
})

describe('get_body_weight', () => {
  it('reports the last 12 weeks by default with weekly averages and 4/12-week changes', async () => {
    await seedBodyweight([
      { d: T(-100), w: 82 }, { d: T(-90), w: 81.5 }, { d: T(-40), w: 80.5 }, { d: T(-30), w: 80 }, { d: T(-10), w: 79.2 }, { d: T(-3), w: 79 },
    ])
    const report = await client.ok('get_body_weight')
    expect(report).toEqual(expect.objectContaining({
      unit: 'kg', goal: 75, from: T(-84), to: T(0), latest: { d: T(-3), w: 79 },
      // 79 − 80.5 (the last reading at least 28 days before) and 79 − 81.5 (84 days).
      change4w: -1.5, change12w: -2.5,
    }))
    expect(report.entries).toEqual([{ d: T(-40), w: 80.5 }, { d: T(-30), w: 80 }, { d: T(-10), w: 79.2 }, { d: T(-3), w: 79 }])
    expect(report.weeklyAvg.reduce((n: number, week: { n: number }) => n + week.n, 0)).toBe(4)
    expect(report.weeklyAvg[0]).toEqual({ week: expect.stringMatching(/^\d{4}-\d{1,2}$/), from: expect.any(String), avg: 80.5, n: 1 })

    const older = await client.ok('get_body_weight', { from: T(-100), to: T(-90) })
    expect(older.entries).toEqual([{ d: T(-100), w: 82 }, { d: T(-90), w: 81.5 }])
    expect(older.change4w).toBe(-1.5)
  })
})
