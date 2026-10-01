import type { PlannedExercise, Routine } from '../engine'
import type { Change } from './validate'

/** The plan doc fields a change can be about. */
export interface ChangeablePlan {
  readonly routines?: readonly Routine[]
  readonly week?: Readonly<Record<string, string | null | undefined>>
}

type ChangeRef = Pick<Change, 'type'> & { readonly target?: Change['target'] | null }

const findRoutine = (plan: ChangeablePlan, id: string | undefined) => (plan.routines ?? []).find(r => r.id === id) ?? null
const findExercise = (routine: Routine | null, id: string) => (routine?.ex ?? []).find(e => e.id === id) ?? null

/**
 * The plan's current value for what a scalar change is about (coach.md §7.2), null when unset;
 * undefined for structural changes, which have no single value. The app marks a change stale
 * when this differs from the change's `before`.
 */
export function currentValue(plan: ChangeablePlan, change: ChangeRef): unknown {
  const routine = findRoutine(plan, change.target?.routineId)
  const exercise = change.target?.exId ? findExercise(routine, change.target.exId) : null
  switch (change.type) {
    case 'sets': return exercise?.sets ?? null
    case 'reps': return exercise?.reps ?? null
    case 'repsMin': return exercise?.repsMin ?? null
    case 'sec': return exercise?.sec ?? null
    case 'inc': return exercise?.inc ?? null
    case 'exercise-prog': return exercise?.prog ?? null
    case 'routine-prog': return routine?.prog ?? null
    case 'rename-routine': return routine?.name ?? null
    case 'week': return plan.week?.[change.target?.weekday as number] ?? null
    default: return undefined
  }
}

/** The partner an exercise is currently supersetted with (the next one first), if any. */
function supersetPartner(exercises: readonly PlannedExercise[], index: number): string | undefined {
  const sg = exercises[index]?.sg
  if (!sg) return undefined
  return [exercises[index + 1], exercises[index - 1]].find(e => e?.sg === sg)?.id
}

/**
 * What the server stores as a change's `before` (contract §5.2 `propose_changes`): the actual
 * current value, never Claude's claim. Scalar changes take `currentValue`; structural ones get
 * the current state of what they touch where one exists, else null.
 */
export function beforeOf(plan: ChangeablePlan, change: ChangeRef): unknown {
  const scalar = currentValue(plan, change)
  if (scalar !== undefined) return scalar
  const routine = findRoutine(plan, change.target?.routineId)
  const exercises = routine?.ex ?? []
  const index = exercises.findIndex(e => e.id === change.target?.exId)
  const exercise = exercises[index]
  switch (change.type) {
    case 'swap-exercise':
      return exercise ? { id: exercise.id } : null
    case 'cardio':
      return exercise ? { ...(exercise.min != null ? { min: exercise.min } : {}), ...(exercise.speed != null ? { speed: exercise.speed } : {}) } : null
    case 'reorder':
      return routine ? exercises.map(e => e.id) : null
    case 'superset': {
      if (!exercise) return null
      const partner = supersetPartner(exercises, index)
      return partner ? { link: true, with: partner } : { link: false }
    }
    default:
      return null
  }
}

/** Changes with `before` overwritten by the server-side current value. */
export function fillBefore<C extends Change>(plan: ChangeablePlan, changes: readonly C[]): C[] {
  return changes.map(change => ({ ...change, before: beforeOf(plan, change) }))
}
