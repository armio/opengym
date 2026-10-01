import { describe, expect, it } from 'vitest'
import fixture from '../../../docs/flutter-cloudflare/fixtures/engine/effort.json'
import {
  BUCKETS, HARD_RIR, MIN_RATED, avgRir, displayScale, effortHistogram, effortSummary, effortWeeks, hasEffort, isHardSet, rirOf, toScale,
} from '../../src/engine'
import { runFixture, type FixtureFile } from './fixtures'

const file = fixture as unknown as FixtureFile

runFixture('effort.json', file, {
  rirOf: a => rirOf(a.set),
  toScale: a => toScale(a.kind, a.rir),
  displayScale: a => displayScale(a.state),
  avgRir: a => avgRir(a.sets),
  effortSummary: (a, clock) => effortSummary(a.state, a.days, clock),
  hasEffort: a => hasEffort(a.state),
  effortWeeks: (a, clock) => effortWeeks(a.state, a.days, clock),
  effortHistogram: (a, clock) => effortHistogram(a.state, a.days, clock),
  isHardSet: a => isHardSet(a.set),
})

describe('effort constants', () => {
  it('match the original', () => {
    expect({ HARD_RIR, MIN_RATED, BUCKETS }).toEqual(file.constants)
  })
})
