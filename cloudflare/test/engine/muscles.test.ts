import { describe, expect, it } from 'vitest'
import fixture from '../../../docs/flutter-cloudflare/fixtures/engine/muscles.json'
import { MUSCLES, isHardSet, levelsOf, loadOf, loadOfRoutine, loadOfWorkouts, musclesOf, rankOf, setsByBodyPart } from '../../src/engine'
import { Catalog } from '../../src/catalog/library'
import { catalogFor, runFixture, type FixtureFile } from './fixtures'

const file = fixture as unknown as FixtureFile

runFixture('muscles.json', file, {
  musclesOf: a => musclesOf(catalogFor(a).get(a.exId)),
  loadOf: a => loadOf(catalogFor(a), a.items),
  loadOfWorkouts: a => loadOfWorkouts(catalogFor(a), a.workouts, a.hardOnly ? isHardSet : undefined),
  loadOfRoutine: a => loadOfRoutine(catalogFor(a), a.routine),
  levelsOf: a => levelsOf(a.load),
  rankOf: a => rankOf(a.load),
})

describe('muscles constants', () => {
  it('match the original', () => {
    expect({ MUSCLES }).toEqual(file.constants)
  })
})

describe('setsByBodyPart', () => {
  const catalog = new Catalog([{ id: 'cx1', n: 'sled push', bp: 'upper legs', desc: '', tg: '', eq: 'custom', custom: true }])
  const workouts = [
    { d: '2026-09-28', entries: [
      { id: '0025', sets: [{ w: 60, r: 8, rir: 2, done: true }, { w: 60, r: 8, rir: 4, done: true }, { w: 60, r: 8, done: false }] },
      { id: 'cx1', sets: [{ w: 50, r: 10, done: true }] },
      { id: 'unknown', sets: [{ w: 1, r: 1, done: true }] },
      { id: '0043', sets: [{ w: 100, r: 5, done: false }] },
    ] },
    { d: '2026-09-29', entries: [{ id: '0025', sets: [{ w: 60, r: 8, rpe: 9, done: true }] }] },
  ]

  it('counts done sets per body part, customs included, unknown ids skipped', () => {
    expect(setsByBodyPart(catalog, workouts)).toEqual({ chest: 3, 'upper legs': 1 })
  })

  it('narrows to hard sets', () => {
    expect(setsByBodyPart(catalog, workouts, isHardSet)).toEqual({ chest: 2 })
  })
})
