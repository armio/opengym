import { describe, expect, it } from 'vitest'
import { Catalog, customExercisesOf } from '../../src/catalog/library'
import type { Clock, TrainingState, Workout } from '../../src/engine'

/**
 * Runs the shared fixture files of docs/flutter-cloudflare/fixtures (format: fixtures/README.md)
 * against the TypeScript implementation. Groups with scope "app" belong to the Flutter engine
 * only; every "shared" group must have a runner here.
 */

export interface Vector {
  readonly name: string
  readonly ref?: string
  readonly args: Record<string, unknown>
  readonly expected: unknown
  readonly now?: number
  readonly fix?: string | readonly string[]
}

export interface Group {
  readonly scope: 'shared' | 'app'
  readonly vectors: readonly Vector[]
}

export interface FixtureFile {
  readonly clock?: { readonly now: number; readonly tz: string; readonly today: string }
  readonly constants?: Record<string, unknown>
  readonly groups: Record<string, Group>
}

export type Args = Record<string, any>

export type Runner = (args: Args, clock: Clock) => unknown

const MARKERS: Record<string, unknown> = { undefined, NaN, Infinity, '-Infinity': -Infinity }

/** Turns {"$js": "undefined" | "NaN" | "Infinity" | "-Infinity"} markers into values. */
export function decode(value: unknown): any {
  if (Array.isArray(value)) return value.map(decode)
  if (value !== null && typeof value === 'object') {
    const entries = Object.entries(value)
    if (entries.length === 1 && entries[0]![0] === '$js') {
      const name = entries[0]![1] as string
      if (!(name in MARKERS)) throw new Error('unknown marker ' + name)
      return MARKERS[name]
    }
    return Object.fromEntries(entries.map(([k, v]) => [k, decode(v)]))
  }
  return value
}

/** The catalogue a vector sees: the library plus its `customEx` (top level or in `state`). */
export function catalogFor(args: Args): Catalog {
  return new Catalog(customExercisesOf({ customEx: args.customEx ?? args.state?.customEx ?? [] }))
}

/** A fixture state `S` as the engine's TrainingState. */
export function trainingState(args: Args): TrainingState {
  const state = args.state ?? {}
  return { ...state, workouts: (state.workouts ?? []) as Workout[], catalog: catalogFor(args) }
}

export function runFixture(title: string, file: FixtureFile, runners: Record<string, Runner>): void {
  describe(title, () => {
    it('has a runner for every shared group', () => {
      const shared = Object.entries(file.groups).filter(([, g]) => g.scope === 'shared').map(([name]) => name)
      expect(shared.filter(name => !runners[name])).toEqual([])
    })
    for (const [name, group] of Object.entries(file.groups)) {
      const run = runners[name]
      if (group.scope !== 'shared' || !run) continue
      describe(name, () => {
        for (const vector of group.vectors) {
          const label = vector.name + (vector.fix ? ` [${[vector.fix].flat().join(', ')}]` : '')
          it(label, () => {
            const clock = { now: vector.now ?? file.clock?.now ?? 0, tz: file.clock?.tz ?? 'UTC' }
            expect(run(decode(vector.args), clock)).toEqual(decode(vector.expected))
          })
        }
      })
    }
  })
}
