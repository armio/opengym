import { modeOf, type ExerciseIndex, type Mode } from '../engine'

/**
 * Plan fingerprint (coach.md §7.1, contract §5.4), identical in the app. A proposal stores the
 * hash of the plan it was made against; the app compares it with the live plan.
 */

/** The plan doc fields the fingerprint reads. Values are read as loosely as the original did. */
export interface HashablePlan {
  readonly routines?: readonly { readonly id?: unknown; readonly name?: unknown; readonly prog?: unknown; readonly ex?: readonly Record<string, unknown>[] }[]
  readonly week?: Readonly<Record<string, unknown>>
}

/**
 * One exercise, mode-aware, every absent value written out as 0 or '' so that "no weight" and
 * "0 kg" cannot hash apart. Values pass through as stored: hashPlan joins them the way
 * JavaScript prints them.
 */
export interface CanonicalExercise {
  id: unknown
  mode: Mode
  sets: unknown
  reps: unknown
  sec: unknown
  min: unknown
  speed: unknown
  weight: unknown
  prog: unknown
  inc: unknown
  repsMin: unknown
  sg: unknown
}

export interface CanonicalPlan {
  routines: { id: unknown; name: unknown; prog: unknown; ex: CanonicalExercise[] }[]
  week: Record<string, unknown>
}

const WEEKDAYS = [1, 2, 3, 4, 5, 6, 0]

/** `catalog` resolves modes by body part: the library plus the plan's custom exercises. */
export function canonicalPlan(plan: HashablePlan, catalog: ExerciseIndex): CanonicalPlan {
  return {
    routines: (plan.routines || []).map(r => ({
      id: r.id,
      name: r.name || '',
      prog: r.prog || '',
      ex: (r.ex || []).map(e => {
        const mode = modeOf(catalog, e)
        return {
          id: e.id,
          mode,
          sets: e.sets || 0,
          reps: mode === 'reps' ? e.reps || 0 : 0,
          sec: mode === 'time' ? e.sec || 0 : 0,
          min: mode === 'cardio' ? e.min || 0 : 0,
          speed: mode === 'cardio' ? e.speed || 0 : 0,
          weight: mode === 'cardio' ? 0 : e.weight || 0,
          prog: e.prog || '',
          inc: e.inc || 0,
          repsMin: e.repsMin || 0,
          sg: e.sg || '',
        }
      }),
    })),
    week: Object.fromEntries(WEEKDAYS.filter(d => plan.week?.[d]).map(d => [d, plan.week![d]])),
  }
}

/** The exact string the hash iterates over (UTF-16 code units). */
export function canonString(plan: CanonicalPlan): string {
  return JSON.stringify({
    routines: plan.routines.map(r => [r.id, r.name, r.prog, r.ex.map(e =>
      [e.id, e.mode, e.sets, e.reps, e.sec, e.min, e.speed, e.weight, e.prog, e.inc, e.repsMin, e.sg].join(':'))]),
    week: Object.keys(plan.week).sort().map(k => k + '=' + plan.week[k]),
  })
}

const hex8 = (n: number) => n.toString(16).padStart(8, '0')

/** Two 32-bit FNV-1a-style lanes over the canonical string, as 16 lowercase hex digits. */
export function hashPlan(plan: CanonicalPlan): string {
  const canon = canonString(plan)
  let h1 = 0x811c9dc5
  let h2 = 0x01000193
  for (let i = 0; i < canon.length; i++) {
    const c = canon.charCodeAt(i)
    h1 = Math.imul(h1 ^ c, 0x01000193) >>> 0
    h2 = Math.imul(h2 ^ ((c << 3) | (i & 7)), 0x85ebca6b) >>> 0
  }
  return hex8(h1) + hex8(h2)
}

export function planHash(plan: HashablePlan, catalog: ExerciseIndex): string {
  return hashPlan(canonicalPlan(plan, catalog))
}
