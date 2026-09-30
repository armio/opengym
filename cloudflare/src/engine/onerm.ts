import type { WorkoutEntry, WorkoutLog } from './types'

/**
 * Port of frontend/src/lib/onerm.js (engine.md §5): estimated one-rep max. Only reps-mode sets
 * carry both a weight and a rep count, so timed and cardio sets drop out on their own.
 */

/** Above this many reps an estimate says more about work capacity than maximal strength. */
export const REP_CAP = 12

export type Formula = 'epley' | 'brzycki' | 'lombardi'

export const FORMULAS: Readonly<Record<Formula, (w: number, r: number) => number>> = {
  epley: (w, r) => w * (1 + r / 30),
  brzycki: (w, r) => (w * 36) / (37 - r),
  lombardi: (w, r) => w * Math.pow(r, 0.1),
}

export const DEFAULT_FORMULA: Formula = 'epley'

function formulaOf(name: string): (w: number, r: number) => number {
  return Object.hasOwn(FORMULAS, name) ? FORMULAS[name as Formula] : FORMULAS[DEFAULT_FORMULA]
}

/**
 * Estimate from one set, to one decimal; null for anything it cannot honestly answer. A single
 * rep is the measurement itself. Inputs may be numeric strings (Number() semantics).
 */
export function estimate1RM(w: unknown, r: unknown, formula: string = DEFAULT_FORMULA): number | null {
  const weight = Number(w)
  const reps = Number(r)
  if (!Number.isFinite(weight) || !Number.isFinite(reps)) return null
  if (weight <= 0 || reps < 1) return null
  if (reps > REP_CAP) return null
  const est = reps === 1 ? weight : formulaOf(formula)(weight, Math.round(reps))
  if (!Number.isFinite(est) || est <= 0) return null
  return Math.round(est * 10) / 10
}

export interface BestSet {
  readonly est: number
  readonly w: number
  readonly r: number
}

/** The done set with the highest estimate (the first wins ties); `topW` has no reps and is ignored. */
export function bestSetOf(entry: Pick<WorkoutEntry, 'sets'> | null | undefined, formula: string = DEFAULT_FORMULA): BestSet | null {
  let best: BestSet | null = null
  for (const s of entry?.sets ?? []) {
    if (!s.done) continue
    const est = estimate1RM(s.w, s.r, formula)
    if (est !== null && (!best || est > best.est)) best = { est, w: Number(s.w), r: Math.round(Number(s.r)) }
  }
  return best
}

export interface E1rmPoint {
  /** The workout's `start`. */
  readonly t: number | null | undefined
  readonly d: string
  readonly y: number
  readonly w: number
  readonly r: number
}

/** One point per workout whose first entry of the exercise produced an estimate, in workout order. */
export function e1rmSeries(S: WorkoutLog, exId: string, formula: string = DEFAULT_FORMULA): E1rmPoint[] {
  const points: E1rmPoint[] = []
  for (const workout of S.workouts ?? []) {
    const entry = workout.entries.find(e => e.id === exId)
    if (!entry) continue
    const best = bestSetOf(entry, formula)
    if (best) points.push({ t: workout.start, d: workout.d, y: best.est, w: best.w, r: best.r })
  }
  return points
}

export interface BestEstimate extends BestSet {
  readonly d: string
  readonly t: number | null | undefined
}

/** All-time best estimate with the set and date behind it; the earliest wins ties. */
export function best1RM(S: WorkoutLog, exId: string, formula: string = DEFAULT_FORMULA): BestEstimate | null {
  let best: BestEstimate | null = null
  for (const p of e1rmSeries(S, exId, formula)) {
    if (!best || p.y > best.est) best = { est: p.y, w: p.w, r: p.r, d: p.d, t: p.t }
  }
  return best
}

/** Whether `entry` beats every estimate in `S` (which must not contain it yet). */
export function is1RMRecord(S: WorkoutLog, exId: string, entry: Pick<WorkoutEntry, 'sets'>, formula: string = DEFAULT_FORMULA): (BestSet & { readonly prev: number }) | null {
  const now = bestSetOf(entry, formula)
  if (!now) return null
  const prev = best1RM(S, exId, formula)
  return !prev || now.est > prev.est ? { ...now, prev: prev ? prev.est : 0 } : null
}
