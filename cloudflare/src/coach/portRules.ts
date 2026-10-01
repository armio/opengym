import type { Catalog } from '../catalog/library'
import { POLICIES, POLICIES_FOR, modeOf, type Mode, type Routine } from '../engine'
import type { JsonObject } from '../lib/json'
import { fillBefore, type ChangeablePlan } from './currentValue'
import { clampGraphemes } from './text'
import {
  usableRoutineExercises, validatePlan, validateReview,
  type Change, type Dialect, type ExerciseLookup, type PlanBundle, type Result, type ReviewProposal,
} from './validate'

/**
 * The port rules of contract §5.3 on top of the original validators. `propose_plan` and
 * `propose_changes` call `validatePlanProposal` / `validateChangesProposal`; each rule is also
 * exported on its own. Messages name fields the way the original's do (`routines[i].ex[j]`,
 * `changes[i]`).
 */

const REPS_POLICIES: readonly string[] = POLICIES_FOR.reps

/** Contract §5.3: an emoji or icon key keeps at most 8 grapheme clusters (coach-Q18). */
export const clampEmoji = (value: string): string => clampGraphemes(value, 8)

/** coach-Q2: a plan has to train at least one day. */
export function checkTrainingDays(week: Readonly<Record<string, string>>): string[] {
  return Object.keys(week).length ? [] : ['the plan needs at least one training day in "week"']
}

/** critic-G4: `mode === 'cardio'` exactly when the body part is cardio. `where` names the exercise. */
export function checkExerciseMode(where: string, mode: Mode | undefined, bodyPart: string | undefined): string[] {
  const cardio = bodyPart === 'cardio'
  if (mode === 'cardio' && !cardio) return [`${where}.mode "cardio" is only for cardio exercises`]
  if (mode !== 'cardio' && cardio) return [`${where} is a cardio exercise and must use mode "cardio"`]
  return []
}

/** coach-Q13 / critic-G5: an exercise policy must suit its mode. `field` names the policy value. */
export function checkPolicyForMode(field: string, prog: unknown, mode: Mode): string[] {
  if (typeof prog !== 'string' || (POLICIES_FOR[mode] as readonly string[]).includes(prog)) return []
  return [`${field} "${prog}" is not allowed for mode "${mode}"`]
}

/**
 * coach-Q13 / critic-G5: a routine-level policy applies to its reps exercises, so it must be a
 * reps policy. Values the original already rejects are left to its message.
 */
export function checkRoutinePolicy(field: string, prog: unknown): string[] {
  if (!(POLICIES as readonly unknown[]).includes(prog) || REPS_POLICIES.includes(prog as string)) return []
  return [`${field} must be one of ${REPS_POLICIES.join(', ')}`]
}

/** coach-Q7: a reorder lists every exercise exactly once. */
export function checkReorder(where: string, order: readonly unknown[], routine: Routine | undefined): string[] {
  if (new Set(order).size === order.length) return []
  const n = routine?.ex?.length ?? 0
  return [`${where}.after must list exactly the ${n} exercise ids already in "${routine?.name}", reordered`]
}

/** coach-Q8: a superset links two different exercises. */
export function checkSupersetPartner(where: string, exId: string | undefined, after: unknown): string[] {
  const link = after as { link?: boolean; with?: string } | null
  return link?.link && link.with === exId ? [`${where}.after.with must be a different exercise than target.exId`] : []
}

/** coach-Q12: adding or swapping in an exercise the routine already has would duplicate it. */
export function checkNotInRoutine(where: string, id: string, routine: Routine | undefined): string[] {
  return (routine?.ex ?? []).some(e => e.id === id) ? [`${where}.after.id "${id}" is already in routine "${routine?.name}"`] : []
}

/** critic-G4: a swap keeps the old logging mode, so it cannot cross between cardio and the rest. */
export function checkSwapMode(where: string, current: Mode, newBodyPart: string | undefined): string[] {
  return (current === 'cardio') !== (newBodyPart === 'cardio') ? [`${where} swaps between cardio and non-cardio — use remove-exercise and add-exercise`] : []
}

/** Everything the port rules read besides the proposal itself. */
export interface PortContext {
  /** The library plus the owner's custom exercises (`Catalog.forPlan(planDoc)`). */
  readonly catalog: Catalog
  /** The athlete doc: `daysPerWeek` counts once `savedAt` is set; `equipment` ([] = everything) drives warnings. */
  readonly athlete: { readonly daysPerWeek?: unknown; readonly savedAt?: unknown; readonly equipment?: unknown }
  /** The heaviest load handled per exercise; proposed weights are capped at it (FR-20, coach-Q17). */
  readonly workingWeights?: readonly { readonly id: string; readonly best: number }[]
}

function lookupOf(catalog: Catalog): ExerciseLookup {
  return { has: id => catalog.has(id), name: id => catalog.get(id)?.name ?? null, bodyPart: id => catalog.bodyPartOf(id) }
}

/** Exercises whose equipment the athlete did not list (coach-Q3): a warning, never an error. */
export function equipmentWarnings(ids: Iterable<string>, catalog: Catalog, equipment: unknown): string[] {
  const owned = Array.isArray(equipment) ? equipment.map(e => String(e).toLowerCase()) : []
  if (!owned.length) return []
  const warnings: string[] = []
  for (const id of new Set(ids)) {
    const exercise = catalog.get(id)
    if (!exercise || exercise.custom || owned.includes(exercise.equipment.toLowerCase())) continue
    warnings.push(`"${exercise.name}" (${id}) needs ${exercise.equipment}, which is not in the athlete's equipment (${owned.join(', ')})`)
  }
  return warnings
}

/* ================================================================== plans */

export type PlanProposalResult = Result<{ bundle: PlanBundle; warnings: string[] }>

/**
 * A plan may define new custom exercises, but not re-define existing ones. Accepting a plan maps a
 * proposed custom onto an owner's exercise with the same name (case-insensitive) and body part
 * (`mergePlan`), after the server has capped weights under the proposal's own id; re-using an id
 * would likewise alias an existing exercise. Either way a starting weight would slip past the
 * working-weight cap (coach-Q17), so both are rejected with the id to use instead.
 */
function checkProposedCustoms(input: unknown, catalog: Catalog): string[] {
  const proposed = (input as { customEx?: unknown } | null)?.customEx
  if (!Array.isArray(proposed)) return []
  const owned = catalog.exercises.filter(exercise => exercise.custom)
  const errors: string[] = []
  proposed.forEach((raw, i) => {
    if (!raw || typeof raw !== 'object') return
    const { id, n, bp } = raw as { id?: unknown; n?: unknown; bp?: unknown }
    if (typeof id === 'string' && catalog.has(id)) {
      errors.push(`customEx[${i}].id "${id}" is already an exercise — reference it from the routine instead of redefining it`)
      return
    }
    if (typeof n !== 'string') return
    const name = n.trim().toLowerCase()
    const same = owned.find(exercise => exercise.name.trim().toLowerCase() === name && exercise.bodyPart === bp)
    if (same) errors.push(`customEx[${i}] "${n}" already exists as the owner's exercise "${same.id}" — use that id instead`)
  })
  return errors
}

/** `propose_plan`: the original rules plus contract §5.3, against the owner's catalogue and profile. */
export function validatePlanProposal(input: unknown, context: PortContext): PlanProposalResult {
  const dialect: Dialect = {
    exercises: lookupOf(context.catalog),
    explicitModes: true,
    keepCardioFields: true,
    clampEmoji,
    plan: {
      routine: (raw, where) => checkRoutinePolicy(`${where}.prog`, raw.prog),
      exercise: (clean, _raw, where, bodyPart) => [
        ...checkExerciseMode(where, clean.mode, bodyPart),
        ...checkPolicyForMode(`${where}.prog`, clean.prog, clean.mode ?? 'reps'),
      ],
      bundle: bundle => checkTrainingDays(bundle.week),
    },
  }
  const { athlete } = context
  const redefined = checkProposedCustoms(input, context.catalog)
  if (redefined.length) return { ok: false, errors: redefined }
  const result = validatePlan(input, {
    workingWeights: context.workingWeights ?? [],
    daysPerWeek: athlete.savedAt != null ? athlete.daysPerWeek : undefined,
  }, dialect)
  if (!result.ok) return result
  const ids = result.bundle.routines.flatMap(r => r.ex.map(e => e.id))
  return { ok: true, bundle: result.bundle, warnings: equipmentWarnings(ids, context.catalog, athlete.equipment) }
}

/* ================================================================== change sets */

export type ChangesProposalResult =
  | { ok: false; errors: string[] }
  | { ok: true; nochange: true; reading: string }
  | { ok: true; proposal: ReviewProposal; warnings: string[] }

/** Weights on added or swapped-in exercises capped at the working weight (coach-Q17). */
function capWeights(changes: readonly Change[], caps: ReadonlyMap<string, number>): Change[] {
  return changes.map(change => {
    if (change.type !== 'add-exercise' && change.type !== 'swap-exercise') return change
    const after = change.after as { id: string; weight?: number }
    const cap = caps.get(after.id)
    return cap != null && after.weight !== undefined && after.weight > cap ? { ...change, after: { ...after, weight: cap } } : change
  })
}

function addedExerciseIds(changes: readonly Change[]): string[] {
  return changes.flatMap(change => {
    if (change.type === 'add-exercise' || change.type === 'swap-exercise') return [(change.after as { id: string }).id]
    if (change.type === 'add-routine') return (change.after as { ex: { id: string }[] }).ex.map(e => e.id)
    return []
  })
}

/**
 * `propose_changes`: the original rules plus contract §5.3, against the current plan. On
 * success every change's `before` is the plan's actual current value.
 */
export function validateChangesProposal(input: unknown, plan: ChangeablePlan, context: PortContext): ChangesProposalResult {
  const { catalog } = context
  const lookup = lookupOf(catalog)
  const routines = new Map((plan.routines ?? []).map(r => [r.id, r]))
  const seenIds = new Map<string, string>()

  const checkChange = (change: Change, raw: JsonObject, where: string): string[] => {
    const errors: string[] = []
    const previous = seenIds.get(change.id)
    if (previous) errors.push(`${where}.id "${change.id}" is already used by ${previous}`)
    else seenIds.set(change.id, where)

    const routine = change.target.routineId ? routines.get(change.target.routineId) : undefined
    const current = routine?.ex?.find(e => e.id === change.target.exId)
    const after = change.after as { id: string; mode: Mode; prog?: unknown }
    switch (change.type) {
      case 'add-exercise':
        errors.push(...checkNotInRoutine(where, after.id, routine))
        errors.push(...checkExerciseMode(`${where}.after`, after.mode, catalog.bodyPartOf(after.id)))
        errors.push(...checkPolicyForMode(`${where}.after.prog`, after.prog, after.mode))
        break
      case 'swap-exercise':
        errors.push(...checkNotInRoutine(where, after.id, routine))
        errors.push(...checkSwapMode(where, modeOf(catalog, current), catalog.bodyPartOf(after.id)))
        break
      case 'exercise-prog':
        errors.push(...checkPolicyForMode(`${where}.after`, change.after, modeOf(catalog, current)))
        break
      case 'routine-prog':
        errors.push(...checkRoutinePolicy(`${where}.after`, change.after))
        break
      case 'reorder':
        errors.push(...checkReorder(where, change.after as unknown[], routine))
        break
      case 'superset':
        errors.push(...checkSupersetPartner(where, change.target.exId, change.after))
        break
      case 'add-routine':
        errors.push(...checkRoutinePolicy(`${where}.after.prog`, after.prog))
        errors.push(...addedRoutineModes(where, change, raw, lookup))
        break
    }
    return errors
  }

  const dialect: Dialect = { exercises: lookup, explicitModes: true, keepCardioFields: true, clampEmoji, changes: { change: checkChange } }
  const result = validateReview(input, plan, dialect)
  if (!result.ok || 'nochange' in result) return result
  const caps = new Map((context.workingWeights ?? []).map(w => [w.id, w.best]))
  const changes = fillBefore(plan, capWeights(result.proposal.changes, caps))
  return {
    ok: true,
    proposal: { ...result.proposal, changes },
    warnings: equipmentWarnings(addedExerciseIds(changes), catalog, context.athlete.equipment),
  }
}

/** The mode rule for a new routine's exercises, indexed as Claude sent them. */
function addedRoutineModes(where: string, change: Change, raw: JsonObject, lookup: ExerciseLookup): string[] {
  const added = (change.after as { ex: { id: string; mode: Mode }[] }).ex
  return usableRoutineExercises(raw.after, lookup).flatMap(({ index }, k) =>
    checkExerciseMode(`${where}.after.ex[${index}]`, added[k]!.mode, lookup.bodyPart(added[k]!.id)))
}
