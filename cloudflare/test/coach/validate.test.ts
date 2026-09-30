import { describe, expect, it } from 'vitest'
import fixture from '../../../docs/flutter-cloudflare/fixtures/validate.json'
import { CHANGE_TYPES, validatePlan, validateReview, type ReviewPlan } from '../../src/coach'
import { decode, type FixtureFile } from '../engine/fixtures'

/** validate.json: every vector of coach.md §6.4 and more, as the original validator answers them. */
const file = fixture as unknown as FixtureFile & { plan: ReviewPlan }

describe('validate.json (original dialect)', () => {
  it('has the closed list of change types', () => {
    expect(CHANGE_TYPES).toEqual(file.constants!.CHANGE_TYPES)
  })

  describe('validatePlan', () => {
    for (const v of file.groups.validatePlan!.vectors) {
      it(v.name, () => {
        const { data, ctx } = decode(v.args)
        expect(validatePlan(data, ctx)).toEqual(decode(v.expected))
      })
    }
  })

  describe('validateReview', () => {
    for (const v of file.groups.validateReview!.vectors) {
      it(v.name, () => {
        expect(validateReview(decode(v.args).data, file.plan)).toEqual(decode(v.expected))
      })
    }
  })
})
