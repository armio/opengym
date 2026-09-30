import { describe, expect, it } from 'vitest'
import fixture from '../../../docs/flutter-cloudflare/fixtures/validate-port.json'
import { Catalog, customExercisesOf } from '../../src/catalog/library'
import { clampEmoji, validateChangesProposal, validatePlanProposal, type ChangeablePlan, type PortContext } from '../../src/coach'

interface ContextJson {
  customEx: unknown[]
  athlete: PortContext['athlete']
  workingWeights: { id: string; best: number }[]
}

interface PortVector {
  name: string
  rules?: string[]
  args: { input?: unknown; context?: ContextJson; value?: string }
  expected: any
}

const file = fixture as unknown as {
  context: ContextJson
  plan: ChangeablePlan & Record<string, unknown>
  groups: Record<'validatePlanProposal' | 'validateChangesProposal' | 'clampEmoji', { vectors: PortVector[] }>
}

function contextOf(json: ContextJson = file.context): PortContext {
  return { catalog: new Catalog(customExercisesOf({ customEx: json.customEx })), athlete: json.athlete, workingWeights: json.workingWeights }
}

const label = (v: PortVector) => v.name + (v.rules?.length ? ` [${v.rules.join(', ')}]` : '')

describe('validate-port.json', () => {
  describe('validatePlanProposal', () => {
    for (const v of file.groups.validatePlanProposal.vectors) {
      it(label(v), () => {
        expect(validatePlanProposal(v.args.input, contextOf(v.args.context))).toMatchObject(v.expected)
      })
    }
  })

  describe('validateChangesProposal', () => {
    for (const v of file.groups.validateChangesProposal.vectors) {
      it(label(v), () => {
        expect(validateChangesProposal(v.args.input, file.plan, contextOf(v.args.context))).toMatchObject(v.expected)
      })
    }
  })

  describe('clampEmoji', () => {
    for (const v of file.groups.clampEmoji.vectors) {
      it(v.name, () => {
        expect(clampEmoji(v.args.value!)).toBe(v.expected)
      })
    }
  })
})
