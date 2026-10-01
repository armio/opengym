import { describe, expect, it } from 'vitest'
import fixture from '../../../docs/flutter-cloudflare/fixtures/plan-hash.json'
import { Catalog } from '../../src/catalog/library'
import { canonString, canonicalPlan, hashPlan, planHash, type HashablePlan } from '../../src/coach'

interface HashVector {
  name: string
  plan: HashablePlan & Record<string, unknown>
  canonical: unknown
  canon: string
  hash: string
}

const vectors = (fixture as unknown as { vectors: HashVector[] }).vectors

describe('plan-hash.json', () => {
  for (const v of vectors) {
    it(v.name, () => {
      const catalog = Catalog.forPlan(v.plan)
      const canonical = canonicalPlan(v.plan, catalog)
      expect(canonical).toEqual(v.canonical)
      expect(canonString(canonical)).toBe(v.canon)
      expect(hashPlan(canonical)).toBe(v.hash)
      expect(planHash(v.plan, catalog)).toBe(v.hash)
    })
  }

  it('ignores everything outside routines and week', () => {
    const plan = vectors[0]!.plan
    const catalog = Catalog.forPlan(plan)
    expect(planHash({ ...plan, theme: 'light' } as HashablePlan, catalog)).toBe(vectors[0]!.hash)
  })
})
