import { describe, expect, it } from 'vitest'
import fixture from '../../../docs/flutter-cloudflare/fixtures/engine/history.json'
import {
  EFFORT, bestWeightFor, effectiveRoutine, effectiveRoutineId, effortOf, entryModeOf, heaviestDoneSets, lastEntryFor, modeOf, setsDone, workoutVolume,
} from '../../src/engine'
import { Catalog } from '../../src/catalog/library'
import { catalogFor, runFixture, trainingState, type FixtureFile } from './fixtures'

const file = fixture as unknown as FixtureFile

runFixture('history.json', file, {
  modeOf: a => modeOf(catalogFor(a), a.cfg),
  effortOf: a => effortOf(a.settings),
  lastEntryFor: a => lastEntryFor(trainingState(a), a.exId),
  bestWeightFor: a => bestWeightFor(trainingState(a), a.exId),
  effectiveRoutineId: a => effectiveRoutineId(a.plan, a.date),
  effectiveRoutine: a => effectiveRoutine(a.plan, a.date),
  workoutVolume: a => workoutVolume(a.workout),
  setsDone: a => setsDone(a.workout),
})

describe('history constants', () => {
  it('match the original', () => {
    expect(EFFORT).toEqual(file.constants!.EFFORT)
  })
})

describe('entryModeOf', () => {
  const catalog = new Catalog()
  it('reads the stored target, falling back to the body part', () => {
    expect(entryModeOf(catalog, { id: '0001', sets: [], target: { mode: 'time' } })).toBe('time')
    expect(entryModeOf(catalog, { id: '3220', sets: [], target: null })).toBe('cardio')
    expect(entryModeOf(catalog, { id: '3220', sets: [], target: { id: 'ignored', mode: 'reps' } })).toBe('reps')
  })
})

describe('heaviestDoneSets', () => {
  it('takes done sets of reps-mode entries only, and ignores topW', () => {
    const S = {
      catalog: new Catalog(),
      workouts: [
        { d: '2026-01-01', entries: [
          { id: '0025', topW: 100, sets: [{ w: 60, r: 5, done: true }, { w: 90, r: 5, done: false }] },
          { id: '0001', target: { mode: 'time' }, sets: [{ sec: 60, w: 20, done: true }] },
          { id: '3220', sets: [{ min: 20, speed: 9, done: true }] },
        ] },
        { d: '2026-01-08', entries: [{ id: '0025', sets: [{ w: 70, r: 3, done: true }] }, { id: '0043', sets: [{ w: 0, r: 10, done: true }] }] },
      ],
    }
    expect(heaviestDoneSets(S)).toEqual(new Map([['0025', 70]]))
    expect(bestWeightFor(S, '0025')).toBe(100)
  })
})
