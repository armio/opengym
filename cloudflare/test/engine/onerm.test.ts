import { describe, expect, it } from 'vitest'
import fixture from '../../../docs/flutter-cloudflare/fixtures/engine/onerm.json'
import { DEFAULT_FORMULA, FORMULAS, REP_CAP, best1RM, bestSetOf, e1rmSeries, estimate1RM, is1RMRecord } from '../../src/engine'
import { runFixture, type FixtureFile } from './fixtures'

const file = fixture as unknown as FixtureFile

runFixture('onerm.json', file, {
  estimate1RM: a => estimate1RM(a.w, a.r, a.formula),
  bestSetOf: a => bestSetOf(a.entry),
  e1rmSeries: a => e1rmSeries(a.state, a.exId),
  best1RM: a => best1RM(a.state, a.exId),
  is1RMRecord: a => is1RMRecord(a.state, a.exId, a.entry),
})

describe('onerm constants', () => {
  it('match the original', () => {
    expect({ REP_CAP, DEFAULT_FORMULA, FORMULAS: Object.keys(FORMULAS) }).toEqual(file.constants)
  })

  it('ignore inherited names when picking a formula', () => {
    expect(estimate1RM(100, 5, 'constructor')).toBe(116.7)
  })
})
