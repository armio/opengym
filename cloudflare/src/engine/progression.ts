import { modeOf } from './history'
import type { ExerciseConfig, ExerciseIndex, Mode, PlannedExercise, Policy, Routine, TrainingState, WorkoutEntry } from './types'

/**
 * Port of frontend/src/lib/progression.js (engine.md §4) with engine-Q1 (double-progression
 * stalls), engine-Q2 (timed deload step) and critic-G3 (a changed plan target starts a new
 * baseline). Everything is derived from history on demand; nothing is stored.
 */

export const POLICIES: readonly Policy[] = ['off', 'linear', 'greyskull', 'double', 'time']

export const POLICIES_FOR: Readonly<Record<Mode, readonly Policy[]>> = {
  reps: ['off', 'linear', 'greyskull', 'double'],
  time: ['off', 'time'],
  cardio: ['off'],
}

/** Consecutive missed sessions before a deload. */
export const DELOAD_AFTER: Readonly<Record<Exclude<Policy, 'off'>, number>> = { linear: 3, greyskull: 1, double: 3, time: 3 }

export const DEFAULT_SEC_INCREMENT = 5

const DELOAD_FACTOR = 0.9

/** Body parts that take the bigger jump ('hips' and 'glutes' never occur; kept for parity). */
const HEAVY_BODY_PARTS = new Set(['upper legs', 'lower legs', 'back', 'hips', 'glutes'])

/** The `why` templates: English i18n keys of the original, mapped to display text by the app. */
export const WHY = {
  first: 'Nothing logged yet — this session sets the baseline.',
  targetChanged: 'Plan target changed — this session sets the new baseline.',
  timeUp: 'Held every set for the full time — target up by {0}s.',
  timeDeload: 'Short {0} sessions in a row — back off to {1}s and build up again.',
  timeHold: 'Last time came up short — same target again.',
  bodyweightUp: 'Bodyweight — every rep last time, so go for {0} this time.',
  bodyweightHold: 'Bodyweight — same target again until every set is clean.',
  doubleUp: 'Top of the rep range in every set — {0} {1} more, back to {2} reps.',
  doubleDeload: 'Stalled {0} sessions — deload to {1} {2}.',
  doubleHold: 'Same weight — aim for {0} reps this time.',
  greyskullDoubleJump: 'Last set hit {0} reps — twice the target, so take a double jump of {1} {2}.',
  up: 'Every rep last time — {0} {1} more.',
  deloadRunning: 'Missed reps {0} sessions running — reset to {1} {2} and work back up.',
  deloadOnce: 'Missed reps — reset to {0} {1} and work back up.',
  hold: 'Missed reps last time — same weight again ({0} of {1} to go).',
} as const

export type Why = readonly [template: string, ...args: (number | string)[]]

export type PrescriptionKind = 'first' | 'up' | 'hold' | 'deload' | 'off'

/** A field the policy has no opinion on is absent; the caller keeps what the plan says. */
export interface Prescription {
  readonly policy: Policy
  readonly kind: PrescriptionKind
  readonly weight?: number
  readonly reps?: number
  readonly sec?: number
  readonly why?: Why
}

/** Fills a `why` template with its arguments ("Every rep last time — 2.5 kg more."). */
export function formatWhy(why: Why): string {
  const [template, ...args] = why
  return args.reduce<string>((text, arg, i) => text.replaceAll('{' + i + '}', String(arg)), template)
}

export function defaultIncrement(catalog: ExerciseIndex, exId: string, unit: string | undefined): number {
  const bodyPart = catalog.get(exId)?.bodyPart
  const heavy = bodyPart !== undefined && HEAVY_BODY_PARTS.has(bodyPart)
  if (unit === 'lb') return heavy ? 10 : 5
  return heavy ? 5 : 2.5
}

/**
 * The policy in force: the exercise's own, else the routine's, else the mode's default. A
 * policy not valid for the mode is 'off' — the lookup does not fall back a level.
 */
export function policyFor(
  catalog: ExerciseIndex,
  cfg: ExerciseConfig | null | undefined,
  routine: Pick<Routine, 'prog'> | null | undefined,
  mode?: Mode,
): Policy {
  const m = mode || modeOf(catalog, cfg ?? {})
  const pick = cfg?.prog || routine?.prog || (m === 'reps' ? 'linear' : 'off')
  return (POLICIES_FOR[m] as readonly string[]).includes(pick) ? (pick as Policy) : 'off'
}

const round1 = (v: number) => Math.round(v * 10) / 10

/** The nearest loadable multiple of `step`. */
function snap(v: number, step: number): number {
  if (!(step > 0)) return round1(v)
  return round1(Math.round(v / step) * step)
}

/** About 10 % lighter, on the grid, strictly lighter than `cur`, never below one step. */
function deloadTo(cur: number, step: number): number {
  let next = snap(cur * DELOAD_FACTOR, step)
  if (next >= cur) next = snap(cur - step, step)
  return Math.max(step, next)
}

const maxOf = (values: readonly number[]) => values.reduce((m, v) => Math.max(m, v), 0)

export interface RepsSession {
  readonly mode: 'reps' | 'cardio'
  readonly goal: number
  readonly reps: number[]
  /** Heaviest done set; 0 means bodyweight. */
  readonly weight: number
  /** Worst set (an unchecked set counts 0). */
  readonly low: number
  /** Final set: Greyskull's AMRAP. */
  readonly amrap: number
  readonly ok: boolean
}

export interface TimeSession {
  readonly mode: 'time'
  readonly goal: number
  readonly held: number[]
  readonly weight: number
  readonly best: number
  readonly ok: boolean
}

export type Session = RepsSession | TimeSession

export type DatedSession = Session & { readonly d: string }

/**
 * Reduces one logged entry to what the policies judge. An entry without its own target (older
 * workouts, imports) is judged against `fallback`, the exercise's current plan. A hit needs every
 * prescribed set checked off at or above the goal.
 */
export function readSession(catalog: ExerciseIndex, entry: WorkoutEntry | null | undefined, fallback?: ExerciseConfig | null): Session {
  const target: ExerciseConfig = entry?.target || fallback || {}
  const mode = modeOf(catalog, { ...target, id: entry?.id })
  const sets = entry?.sets ?? []
  const planned = target.sets || sets.length
  const enough = sets.length >= planned
  const weight = maxOf(sets.filter(s => s.done).map(s => s.w || 0))

  if (mode === 'time') {
    const goal = target.sec || 0
    const held = sets.map(s => (s.done ? s.sec || 0 : 0))
    return { mode, goal, held, weight, best: maxOf(held), ok: goal > 0 && enough && held.length > 0 && held.every(h => h >= goal) }
  }
  const goal = target.reps || 0
  const reps = sets.map(s => (s.done ? s.r || 0 : 0))
  return {
    mode,
    goal,
    reps,
    weight,
    low: reps.length ? Math.min(...reps) : 0,
    amrap: reps.length ? reps[reps.length - 1]! : 0,
    ok: goal > 0 && enough && reps.length > 0 && reps.every(r => r >= goal),
  }
}

/** Every session of one exercise with a done set, oldest first (workouts in (d, start) order). */
export function sessionsFor(S: TrainingState, exId: string, fallback?: ExerciseConfig | null): DatedSession[] {
  const out: DatedSession[] = []
  for (const workout of S.workouts ?? []) {
    const entry = workout.entries.find(e => e.id === exId)
    if (entry && entry.sets.some(s => s.done)) out.push({ d: workout.d, ...readSession(S.catalog, entry, fallback) })
  }
  return out
}

/** Consecutive misses counting back from the most recent session. */
export function stallCount(sessions: readonly { readonly ok: boolean }[]): number {
  let n = 0
  for (let i = sessions.length - 1; i >= 0; i--) {
    if (sessions[i]!.ok) break
    n++
  }
  return n
}

/**
 * engine-Q1: double progression climbs through a rep range at one weight, so a missed session
 * only counts as a stall when its worst set did not improve on the session before at the same
 * weight.
 */
export function doubleStallCount(sessions: readonly { readonly ok: boolean; readonly weight: number; readonly low: number }[]): number {
  let n = 0
  for (let i = sessions.length - 1; i >= 0; i--) {
    const s = sessions[i]!
    const prev = sessions[i - 1]
    const stalled = !s.ok && (prev === undefined || prev.weight !== s.weight || s.low <= prev.low)
    if (!stalled) break
    n++
  }
  return n
}

/**
 * Consecutive missed sessions as the policy counts them: double progression only counts misses
 * that did not improve (engine-Q1); cardio is never judged, so it never stalls.
 */
export function stallsFor(policy: Policy, mode: Mode, sessions: readonly Session[]): number {
  if (mode === 'cardio') return 0
  if (policy === 'double' && mode === 'reps') return doubleStallCount(sessions as readonly RepsSession[])
  return stallCount(sessions)
}

/**
 * critic-G3: the plan's rep (or hold) target differs from the one the last session was
 * prescribed. A session read against the plan itself (no stored target) has the plan's goal,
 * so it never trips this; neither does a target without the field.
 */
function planTargetChanged(last: Session, cfg: ExerciseConfig): boolean {
  const planned = last.mode === 'time' ? cfg.sec : cfg.reps
  return typeof last.goal === 'number' && last.goal > 0 && last.goal !== planned
}

/** The next prescription for one routine exercise (engine.md §4.8). */
export function nextPrescription(S: TrainingState, cfg: PlannedExercise, routine?: Pick<Routine, 'prog'> | null): Prescription {
  const mode = modeOf(S.catalog, cfg)
  const policy = policyFor(S.catalog, cfg, routine, mode)
  const unit = S.unit || 'kg'
  const inc = (cfg.inc ?? 0) > 0 ? cfg.inc! : mode === 'time' ? DEFAULT_SEC_INCREMENT : defaultIncrement(S.catalog, cfg.id, unit)
  if (policy === 'off') return { policy, kind: 'off' }

  const sessions = sessionsFor(S, cfg.id, cfg).filter(s => s.mode === mode)
  const last = sessions[sessions.length - 1]
  if (!last) return { policy, kind: 'first', why: [WHY.first] }
  if (planTargetChanged(last, cfg)) return { policy, kind: 'first', why: [WHY.targetChanged] }

  const deloadAt = DELOAD_AFTER[policy]
  const stalls = stallsFor(policy, mode, sessions)

  if (last.mode === 'time') {
    if (last.ok) {
      const sec = (last.goal || cfg.sec || 0) + inc
      return { policy, kind: 'up', sec, why: [WHY.timeUp, inc] }
    }
    if (stalls >= deloadAt) {
      const sec = deloadTo(last.goal || cfg.sec || 0, inc)   // engine-Q2: the step is the increment
      return { policy, kind: 'deload', sec, why: [WHY.timeDeload, stalls, sec] }
    }
    return { policy, kind: 'hold', sec: last.goal || cfg.sec, why: [WHY.timeHold] }
  }

  const w = last.weight

  // Bodyweight work progresses in reps under every policy and never deloads.
  if (w <= 0) {
    const goal = last.goal || cfg.reps || 0
    if (last.ok && goal > 0) return { policy, kind: 'up', weight: 0, reps: goal + 1, why: [WHY.bodyweightUp, goal + 1] }
    return { policy, kind: 'hold', weight: 0, reps: goal || undefined, why: [WHY.bodyweightHold] }
  }

  if (policy === 'double') {
    const top = cfg.reps || last.goal || 10
    const bottom = Math.min(cfg.repsMin || Math.max(1, top - 2), top)
    if (last.ok) return { policy, kind: 'up', weight: snap(w + inc, inc), reps: bottom, why: [WHY.doubleUp, inc, unit, bottom] }
    if (stalls >= deloadAt) {
      const dw = deloadTo(w, inc)
      return { policy, kind: 'deload', weight: dw, reps: bottom, why: [WHY.doubleDeload, stalls, dw, unit] }
    }
    const aim = Math.min(top, Math.max(bottom, last.low + 1))
    return { policy, kind: 'hold', weight: w, reps: aim, why: [WHY.doubleHold, aim] }
  }

  // linear and greyskull
  if (last.ok) {
    const doubleJump = policy === 'greyskull' && last.goal > 0 && last.amrap >= last.goal * 2
    const step = doubleJump ? inc * 2 : inc
    return {
      policy,
      kind: 'up',
      weight: snap(w + step, inc),
      why: doubleJump ? [WHY.greyskullDoubleJump, last.amrap, step, unit] : [WHY.up, step, unit],
    }
  }
  if (stalls >= deloadAt) {
    const dw = deloadTo(w, inc)
    return { policy, kind: 'deload', weight: dw, why: stalls > 1 ? [WHY.deloadRunning, stalls, dw, unit] : [WHY.deloadOnce, dw, unit] }
  }
  return { policy, kind: 'hold', weight: w, why: [WHY.hold, deloadAt - stalls, deloadAt] }
}
