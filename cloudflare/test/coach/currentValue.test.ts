import { describe, expect, it } from 'vitest'
import fixture from '../../../docs/flutter-cloudflare/fixtures/current-value.json'
import { currentValue, type Change, type ChangeablePlan } from '../../src/coach'
import { decode } from '../engine/fixtures'

const file = fixture as unknown as { plan: ChangeablePlan; vectors: { name: string; change: Change; expected: unknown }[] }

describe('current-value.json', () => {
  for (const v of file.vectors) {
    it(v.name, () => {
      expect(currentValue(file.plan, v.change)).toEqual(decode(v.expected))
    })
  }
})
