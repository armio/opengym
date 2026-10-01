import { describe, expect, it } from 'vitest'
import fixture from '../../../docs/flutter-cloudflare/fixtures/engine/progression.json'
import {
  DEFAULT_SEC_INCREMENT, DELOAD_AFTER, POLICIES, POLICIES_FOR, WHY, defaultIncrement, doubleStallCount, formatWhy, nextPrescription, policyFor,
  readSession, sessionsFor, stallCount, stallsFor,
} from '../../src/engine'
import { Catalog } from '../../src/catalog/library'
import { catalogFor, runFixture, trainingState, type FixtureFile } from './fixtures'

const file = fixture as unknown as FixtureFile

runFixture('progression.json', file, {
  readSession: a => readSession(catalogFor(a), a.entry, a.fallback),
  sessionsFor: a => sessionsFor(trainingState(a), a.exId, a.fallback),
  stallCount: a => stallCount(a.sessions),
  doubleStallCount: a => doubleStallCount(a.sessions),
  policyFor: a => policyFor(catalogFor(a), a.cfg, a.routine, a.mode),
  defaultIncrement: a => defaultIncrement(catalogFor(a), a.exId, a.unit),
  nextPrescription: a => nextPrescription(trainingState(a), a.cfg, a.routine),
})

describe('progression constants', () => {
  it('match the original', () => {
    expect({ POLICIES, POLICIES_FOR, DELOAD_AFTER, DEFAULT_SEC_INCREMENT }).toEqual(file.constants)
  })
})

describe('why templates', () => {
  it('cover every template the fixtures expect', () => {
    const templates = new Set<string>(Object.values(WHY))
    const expected = file.groups.nextPrescription!.vectors
      .map(v => (v.expected as { why?: string[] }).why?.[0])
      .filter((t): t is string => t !== undefined)
    expect(expected.filter(t => !templates.has(t))).toEqual([])
  })

  it('format with their arguments', () => {
    expect(formatWhy([WHY.up, 2.5, 'kg'])).toBe('Every rep last time — 2.5 kg more.')
    expect(formatWhy([WHY.doubleUp, 2.5, 'kg', 8])).toBe('Top of the rep range in every set — 2.5 kg more, back to 8 reps.')
    expect(formatWhy([WHY.first])).toBe(WHY.first)
  })
})

describe('nextPrescription with a custom exercise', () => {
  it('takes the heavy increment from the custom body part', () => {
    const catalog = new Catalog([{ id: 'cx1', n: 'sled push', bp: 'upper legs', desc: '', tg: '', eq: 'custom', custom: true }])
    const S = {
      catalog,
      unit: 'kg',
      workouts: [{ d: '2026-01-01', entries: [{ id: 'cx1', target: { sets: 1, reps: 5 }, sets: [{ w: 100, r: 5, done: true }] }] }],
    }
    expect(nextPrescription(S, { id: 'cx1', sets: 1, reps: 5 })).toMatchObject({ policy: 'linear', kind: 'up', weight: 105 })
  })
})

describe('stallsFor', () => {
  const climbing = [
    { mode: 'reps' as const, goal: 12, reps: [10, 9, 9], weight: 40, low: 9, amrap: 9, ok: false },
    { mode: 'reps' as const, goal: 12, reps: [11, 10, 10], weight: 40, low: 10, amrap: 10, ok: false },
  ]

  it('counts the way the policy judges', () => {
    expect(stallsFor('double', 'reps', climbing)).toBe(0)
    expect(stallsFor('linear', 'reps', climbing)).toBe(2)
    expect(stallsFor('off', 'reps', climbing)).toBe(2)
  })

  it('never stalls cardio', () => {
    expect(stallsFor('off', 'cardio', [{ ...climbing[0]!, mode: 'cardio' }])).toBe(0)
  })
})
