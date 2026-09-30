import { LIBRARY_BY_ID } from '../catalog/library'
import type { JsonObject } from '../lib/json'
import { POLICIES, type Mode, type Policy } from '../engine'

/**
 * Port of api/coach/validate.js (coach.md §6): the gate between Claude's output and the plan.
 * With the `ORIGINAL` dialect it reproduces the original byte for byte (normalisation and error
 * strings). The port (contract §5.3) passes another `Dialect`: a catalogue with the owner's
 * custom exercises, explicit modes, grapheme-safe emoji and extra checks (see ./portRules).
 *
 * Errors are collected, not thrown one at a time: Claude gets the whole list back.
 */

export const CHANGE_TYPES = [
  'add-exercise', 'remove-exercise', 'swap-exercise',
  'sets', 'reps', 'repsMin', 'sec', 'cardio',
  'reorder', 'superset',
  'routine-prog', 'exercise-prog', 'inc',
  'add-routine', 'remove-routine', 'rename-routine',
  'week',
] as const

export type ChangeType = (typeof CHANGE_TYPES)[number]

const MODES: readonly string[] = ['reps', 'time', 'cardio']
const MAX_CHANGES = 25
const MAX_ROUTINES = 7
const MAX_EX_PER_ROUTINE = 20
const NEEDS_EXERCISE: readonly string[] = ['remove-exercise', 'swap-exercise', 'sets', 'reps', 'repsMin', 'sec', 'cardio', 'exercise-prog', 'inc', 'superset']

const isStr = (v: unknown): v is string => typeof v === 'string' && v.trim().length > 0
const isNum = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v)
const isInt = (v: unknown, lo: number, hi: number): v is number => Number.isInteger(v) && (v as number) >= lo && (v as number) <= hi
const clampStr = (v: unknown, n: number) => String(v == null ? '' : v).slice(0, n)
const isPolicy = (v: unknown): v is Policy => (POLICIES as readonly unknown[]).includes(v)
const isMode = (v: unknown): v is Mode => MODES.includes(v as string)
/** Property access on untrusted JSON: anything that is not an object reads as empty. */
const obj = (v: unknown): JsonObject => (v !== null && typeof v === 'object' ? (v as JsonObject) : {})

/* ================================================================== dialects */

/** What validation needs to know about exercise ids. */
export interface ExerciseLookup {
  has(id: string): boolean
  name(id: string): string | null
  bodyPart(id: string): string | undefined
}

/** Extra checks the port runs on items the original rules accepted; each returns error messages. */
export interface PlanChecks {
  routine?(raw: JsonObject, where: string): string[]
  exercise?(clean: CleanExercise, raw: JsonObject, where: string, bodyPart: string | undefined): string[]
  bundle?(bundle: Pick<PlanBundle, 'week' | 'routines' | 'customEx'>): string[]
}

export interface ChangeChecks {
  change?(change: Change, raw: JsonObject, where: string, routine: ReviewRoutine | undefined): string[]
}

export interface Dialect {
  readonly exercises: ExerciseLookup
  /** coach-Q1: a missing mode follows the body part and every exercise states its mode. */
  readonly explicitModes: boolean
  /** coach-B5: added cardio exercises keep their `min`/`speed`. */
  readonly keepCardioFields: boolean
  /** coach-Q18: how emoji fields are clamped. */
  clampEmoji(value: string): string
  readonly plan?: PlanChecks
  readonly changes?: ChangeChecks
}

/** The built-in library, as the original's `libraryHas` / `libraryName`. */
export const LIBRARY_LOOKUP: ExerciseLookup = {
  has: id => LIBRARY_BY_ID.has(id),
  name: id => LIBRARY_BY_ID.get(id)?.n ?? null,
  bodyPart: id => LIBRARY_BY_ID.get(id)?.bp,
}

export const ORIGINAL: Dialect = {
  exercises: LIBRARY_LOOKUP,
  explicitModes: false,
  keepCardioFields: false,
  clampEmoji: value => value.slice(0, 8),
}

function defaultMode(dialect: Dialect, bodyPart: string | undefined): Mode {
  return dialect.explicitModes && bodyPart === 'cardio' ? 'cardio' : 'reps'
}

export type Result<T> = ({ ok: true } & T) | { ok: false; errors: string[] }

const fail = (errors: string[]): { ok: false; errors: string[] } => ({ ok: false, errors })

/* ================================================================== created plans */

export interface CleanExercise {
  id: string
  sets: number
  mode?: Mode
  reps?: number
  sec?: number
  min?: number
  speed?: number
  weight?: number
  prog?: Policy
  inc?: number
  repsMin?: number
  sg?: string
  why?: string
}

export interface BundleRoutine {
  id: string
  name: string
  emoji: string
  prog?: Policy
  why?: string
  ex: CleanExercise[]
}

export interface BundleCustomExercise {
  id: string
  n: string
  bp: string
  desc?: string
}

export interface PlanBundle {
  opengym_plan: 1
  name: string
  summary: string
  basedOn: string
  week: Record<string, string>
  routines: BundleRoutine[]
  customEx: BundleCustomExercise[]
}

export interface PlanContext {
  /** Proposed weights are capped at these (FR-20). */
  readonly workingWeights?: readonly { readonly id: string; readonly best: number }[]
  /** Enforced when an integer 1..7 and the week is non-empty (FR-17). */
  readonly daysPerWeek?: unknown
}

function cleanExercise(e: JsonObject, mode: Mode, dialect: Dialect): CleanExercise {
  const clean: CleanExercise = { id: e.id as string, sets: isInt(e.sets, 1, 10) ? e.sets : 3 }
  if (mode === 'cardio') {
    if (dialect.explicitModes) clean.mode = 'cardio'
    clean.min = isInt(e.min, 1, 180) ? e.min : 20
    clean.speed = isNum(e.speed) && e.speed > 0 ? e.speed : 8
  } else if (mode === 'time') {
    clean.mode = 'time'
    clean.sec = isInt(e.sec, 5, 3600) ? e.sec : 45
    if (isNum(e.weight) && e.weight > 0) clean.weight = e.weight
  } else {
    clean.mode = 'reps'
    clean.reps = isInt(e.reps, 1, 100) ? e.reps : 10
    if (isNum(e.weight) && e.weight > 0) clean.weight = e.weight
  }
  return clean
}

/** Validates a creation bundle into what the app's `mergePlan` consumes unchanged. */
export function validatePlan(data: unknown, ctx: PlanContext = {}, dialect: Dialect = ORIGINAL): Result<{ bundle: PlanBundle }> {
  const errors: string[] = []
  if (!data || typeof data !== 'object') return fail(['the answer was not an object'])
  const input = data as JsonObject
  if (input.nochange) return fail(['a plan was requested but the answer said "no change"'])
  if (!Array.isArray(input.routines) || !input.routines.length) errors.push('routines must be a non-empty array')

  const customEx: BundleCustomExercise[] = (Array.isArray(input.customEx) ? input.customEx : [])
    .map(obj)
    .filter(c => isStr(c.id) && isStr(c.n))
    .slice(0, 20)
    .map(c => ({ id: clampStr(c.id, 40), n: clampStr(c.n, 60), bp: clampStr(c.bp || 'waist', 30), ...(c.desc ? { desc: clampStr(c.desc, 400) } : {}) }))
  const proposed = new Map(customEx.map(c => [c.id, c]))

  const routines: BundleRoutine[] = []
  ;(Array.isArray(input.routines) ? input.routines : []).slice(0, MAX_ROUTINES).forEach((value: unknown, ri) => {
    if (!value || typeof value !== 'object') {
      errors.push(`routines[${ri}] is not an object`)
      return
    }
    const r = value as JsonObject
    if (!isStr(r.name)) errors.push(`routines[${ri}].name is required`)
    if (r.prog != null && !isPolicy(r.prog)) errors.push(`routines[${ri}].prog "${r.prog}" is not one of ${POLICIES.join(', ')}`)
    errors.push(...(dialect.plan?.routine?.(r, `routines[${ri}]`) ?? []))

    const ex: CleanExercise[] = []
    ;(Array.isArray(r.ex) ? r.ex : []).slice(0, MAX_EX_PER_ROUTINE).forEach((item: unknown, ei) => {
      const where = `routines[${ri}].ex[${ei}]`
      const e = obj(item)
      if (!item || !isStr(e.id)) {
        errors.push(`${where}.id is required`)
        return
      }
      if (!dialect.exercises.has(e.id) && !proposed.has(e.id)) {
        errors.push(`${where}.id "${e.id}" is not in the exercise library and is not one of your own customEx entries — use an id from the library provided in the payload`)
        return
      }
      const bodyPart = proposed.get(e.id)?.bp ?? dialect.exercises.bodyPart(e.id)
      const clean = cleanExercise(e, isMode(e.mode) ? e.mode : defaultMode(dialect, bodyPart), dialect)
      if (e.prog != null) {
        if (!isPolicy(e.prog)) errors.push(`${where}.prog "${e.prog}" is not one of ${POLICIES.join(', ')}`)
        else clean.prog = e.prog
      }
      if (isNum(e.inc) && e.inc > 0) clean.inc = e.inc
      if (isInt(e.repsMin, 1, 100)) clean.repsMin = e.repsMin
      if (isStr(e.sg)) clean.sg = clampStr(e.sg, 20)
      if (isStr(e.why)) clean.why = clampStr(e.why, 400)
      errors.push(...(dialect.plan?.exercise?.(clean, e, where, bodyPart) ?? []))
      ex.push(clean)
    })
    if (!ex.length) errors.push(`routines[${ri}] has no valid exercises`)
    routines.push({
      id: isStr(r.id) ? clampStr(r.id, 40) : 'r' + ri,
      name: clampStr(r.name || 'Routine', 40),
      emoji: dialect.clampEmoji(String(r.emoji || '🏋️')),
      ...(isPolicy(r.prog) ? { prog: r.prog } : {}),
      ...(isStr(r.why) ? { why: clampStr(r.why, 400) } : {}),
      ex,
    })
  })

  // The week may only point at routines this bundle defines.
  const known = new Set(routines.map(r => r.id))
  const week: Record<string, string> = {}
  for (const [d, rid] of Object.entries((input.week || {}) as object)) {
    const day = +d
    if (!isInt(day, 0, 6)) {
      errors.push(`week key "${d}" is not a weekday number 0-6`)
      continue
    }
    if (!known.has(rid)) {
      errors.push(`week[${d}] points at "${rid}", which is not one of the routines in this plan`)
      continue
    }
    week[day] = rid
  }

  // FR-20: never start someone above what they have actually lifted.
  const caps = new Map((ctx.workingWeights ?? []).map(w => [w.id, w.best]))
  for (const r of routines) {
    for (const e of r.ex) {
      const cap = caps.get(e.id)
      if (cap != null && e.weight !== undefined && e.weight > cap) e.weight = cap
    }
  }

  // FR-17: honour the number of training days asked for.
  const want = ctx.daysPerWeek
  const days = Object.keys(week).length
  if (isInt(want, 1, 7) && days && days !== want) errors.push(`the week schedules ${days} days but ${want} were asked for`)

  errors.push(...(dialect.plan?.bundle?.({ week, routines, customEx }) ?? []))

  if (errors.length) return fail(errors)
  return {
    ok: true,
    bundle: {
      opengym_plan: 1,
      name: clampStr(input.name || 'Coach plan', 40),
      summary: clampStr(input.summary || '', 1200),
      basedOn: clampStr(input.basedOn || '', 400),
      week,
      routines,
      customEx,
    },
  }
}

/* ================================================================== review change sets */

export interface ReviewRoutine {
  readonly id: string
  readonly name?: string
  readonly ex?: readonly { readonly id: string }[]
}

/** The plan the changes are validated against: the current plan doc. */
export interface ReviewPlan {
  readonly routines?: readonly ReviewRoutine[]
}

export interface ChangeTarget {
  routineId?: string
  exId?: string
  weekday?: number
}

export interface Change {
  id: string
  type: ChangeType
  target: ChangeTarget
  why: string
  before: unknown
  after: unknown
}

export interface ReviewProposal {
  summary: string
  evidence: { from: unknown; to: unknown; sessions: number | null }
  changes: Change[]
  notes: string[]
}

export type ReviewResult = Result<{ nochange: true; reading: string }> | { ok: true; proposal: ReviewProposal }

/** Validates and normalises one change's `after` by type; returns the error when it is unusable. */
function normaliseAfter(c: JsonObject, out: Change, where: string, routine: ReviewRoutine | undefined, plan: ReadonlyMap<string, ReviewRoutine>, dialect: Dialect): string | undefined {
  const { exercises } = dialect
  const target = obj(c.target)
  const inRoutine = (id: unknown) => (routine?.ex ?? []).some(e => e.id === id)
  const modeFor = (e: JsonObject) => (isMode(e.mode) ? e.mode : defaultMode(dialect, exercises.bodyPart(e.id as string)))
  switch (out.type) {
    case 'add-exercise': {
      const a = obj(c.after)
      if (!isStr(a.id) || !exercises.has(a.id)) return `${where}.after.id must be an exercise id from the library`
      const mode = modeFor(a)
      out.after = {
        id: a.id, name: exercises.name(a.id),
        sets: isInt(a.sets, 1, 10) ? a.sets : 3,
        mode,
        ...(isInt(a.reps, 1, 100) ? { reps: a.reps } : {}),
        ...(isInt(a.sec, 5, 3600) ? { sec: a.sec } : {}),
        ...(dialect.keepCardioFields && mode === 'cardio' ? cardioFields(a) : {}),
        ...(isNum(a.weight) && a.weight > 0 ? { weight: a.weight } : {}),
        ...(isPolicy(a.prog) ? { prog: a.prog } : {}),
        ...(isInt(a.position, 0, MAX_EX_PER_ROUTINE) ? { position: a.position } : {}),
      }
      return
    }
    case 'swap-exercise': {
      const a = obj(c.after)
      if (!isStr(a.id) || !exercises.has(a.id)) return `${where}.after.id must be an exercise id from the library`
      if (a.id === target.exId) return `${where} swaps an exercise for itself`
      out.after = {
        id: a.id, name: exercises.name(a.id),
        ...(isInt(a.sets, 1, 10) ? { sets: a.sets } : {}),
        ...(isInt(a.reps, 1, 100) ? { reps: a.reps } : {}),
        ...(isNum(a.weight) && a.weight > 0 ? { weight: a.weight } : {}),
      }
      return
    }
    case 'remove-exercise':
    case 'remove-routine':
      out.after = null
      return
    case 'sets':
      return isInt(c.after, 1, 10) ? undefined : `${where}.after must be a whole number of sets (1-10)`
    case 'reps':
      return isInt(c.after, 1, 100) ? undefined : `${where}.after must be a whole number of reps (1-100)`
    case 'repsMin':
      return isInt(c.after, 1, 100) ? undefined : `${where}.after must be a whole number (1-100)`
    case 'sec':
      return isInt(c.after, 5, 3600) ? undefined : `${where}.after must be seconds (5-3600)`
    case 'cardio': {
      const a = obj(c.after)
      if (!isInt(a.min, 1, 180) && !isNum(a.speed)) return `${where}.after must carry min and/or speed`
      out.after = cardioFields(a)
      return
    }
    case 'inc':
      return isNum(c.after) && c.after > 0 ? undefined : `${where}.after must be a positive increment`
    case 'routine-prog':
    case 'exercise-prog':
      return isPolicy(c.after) ? undefined : `${where}.after must be one of ${POLICIES.join(', ')}`
    case 'reorder': {
      if (!Array.isArray(c.after)) return `${where}.after must be an array of exercise ids in the new order`
      const have = (routine?.ex ?? []).map(e => e.id)
      if (c.after.length !== have.length || c.after.some(id => !have.includes(id))) {
        return `${where}.after must list exactly the ${have.length} exercise ids already in "${routine?.name}", reordered`
      }
      out.after = c.after
      return
    }
    case 'superset': {
      const a = obj(c.after)
      if (a.link && !isStr(a.with)) return `${where}.after.with is required when linking a superset`
      if (a.link && !inRoutine(a.with)) return `${where}.after.with "${a.with}" is not in routine "${routine?.name}"`
      out.after = { link: !!a.link, ...(a.link ? { with: a.with } : {}) }
      return
    }
    case 'add-routine': {
      const a = obj(c.after)
      if (!isStr(a.name)) return `${where}.after.name is required`
      const ex = usableRoutineExercises(a, exercises)
      if (!ex.length) return `${where}.after.ex must list at least one exercise from the library`
      out.after = {
        name: clampStr(a.name, 40), emoji: dialect.clampEmoji(String(a.emoji || '🏋️')),
        ...(isPolicy(a.prog) ? { prog: a.prog } : {}),
        ex: ex.map(({ exercise: e }) => {
          const mode = modeFor(e)
          return {
            id: e.id, name: exercises.name(e.id as string),
            sets: isInt(e.sets, 1, 10) ? e.sets : 3,
            mode,
            ...(isInt(e.reps, 1, 100) ? { reps: e.reps } : {}),
            ...(isInt(e.sec, 5, 3600) ? { sec: e.sec } : {}),
            ...(dialect.keepCardioFields && mode === 'cardio' ? cardioFields(e) : {}),
          }
        }),
      }
      return
    }
    case 'rename-routine':
      if (!isStr(c.after)) return `${where}.after must be the new routine name`
      out.after = clampStr(c.after, 40)
      return
    case 'week':
      if (!isInt(target.weekday, 0, 6)) return `${where}.target.weekday must be 0-6`
      // null or 'rest' clears the day; anything else must be a routine that exists.
      if (c.after != null && c.after !== 'rest' && !plan.has(c.after as string)) return `${where}.after must be a routine id from the plan, "rest", or null`
      out.after = c.after ?? null
      return
  }
}

/**
 * The entries of an `add-routine` change's `after.ex` that are kept (unusable ones are dropped
 * silently, at most 20), with their positions in the list as sent.
 */
export function usableRoutineExercises(after: unknown, exercises: ExerciseLookup): { index: number; exercise: JsonObject }[] {
  const list: unknown[] = Array.isArray(obj(after).ex) ? (obj(after).ex as unknown[]) : []
  return list
    .flatMap((item, index) => (item && isStr(obj(item).id) && exercises.has(obj(item).id as string) ? [{ index, exercise: obj(item) }] : []))
    .slice(0, MAX_EX_PER_ROUTINE)
}

function cardioFields(a: JsonObject): { min?: number; speed?: number } {
  return { ...(isInt(a.min, 1, 180) ? { min: a.min } : {}), ...(isNum(a.speed) && a.speed > 0 ? { speed: a.speed } : {}) }
}

/**
 * Validates a review answer against the current plan: every target must resolve, every change
 * type is on the closed list, and one bad change fails the whole set.
 */
export function validateReview(data: unknown, plan: ReviewPlan | null | undefined, dialect: Dialect = ORIGINAL): ReviewResult {
  if (!data || typeof data !== 'object') return fail(['the answer was not an object'])
  const input = data as JsonObject
  if (input.nochange) return { ok: true, nochange: true, reading: clampStr(input.reading || input.summary || '', 1200) }
  const errors: string[] = []
  const routines = new Map((plan?.routines ?? []).map(r => [r.id, r]))
  const changes: Change[] = []
  if (!Array.isArray(input.changes)) return fail(['changes must be an array (or set "nochange": true with a "reading")'])

  input.changes.slice(0, MAX_CHANGES).forEach((value: unknown, i) => {
    const where = `changes[${i}]`
    if (!value || typeof value !== 'object') {
      errors.push(`${where} is not an object`)
      return
    }
    const c = value as JsonObject
    if (!(CHANGE_TYPES as readonly unknown[]).includes(c.type)) {
      errors.push(`${where}.type "${c.type}" is not allowed — use one of: ${CHANGE_TYPES.join(', ')}`)
      return
    }
    const type = c.type as ChangeType
    if (!isStr(c.why)) {
      errors.push(`${where}.why is required — every change must cite the evidence behind it`)
      return
    }
    const target = obj(c.target)
    const routine = target.routineId ? routines.get(target.routineId as string) : undefined

    // Everything but add-routine and week names a routine that exists; anything touching an
    // exercise names one that is in it.
    if (type !== 'add-routine' && type !== 'week' && !routine) {
      errors.push(`${where}.target.routineId "${target.routineId}" is not one of the routines in the plan`)
      return
    }
    if (NEEDS_EXERCISE.includes(type)) {
      if (!target.exId) {
        errors.push(`${where}.target.exId is required for type "${type}"`)
        return
      }
      if (!(routine?.ex ?? []).some(e => e.id === target.exId)) {
        errors.push(`${where}.target.exId "${target.exId}" is not in routine "${routine?.name}"`)
        return
      }
    }

    const out: Change = {
      id: isStr(c.id) ? clampStr(c.id, 40) : 'c' + i,
      type,
      target: {
        ...(target.routineId ? { routineId: target.routineId as string } : {}),
        ...(target.exId ? { exId: target.exId as string } : {}),
        ...(isInt(target.weekday, 0, 6) ? { weekday: target.weekday } : {}),
      },
      why: clampStr(c.why, 600),
      before: c.before ?? null,
      after: c.after ?? null,
    }
    const problem = normaliseAfter(c, out, where, routine, routines, dialect)
    if (problem) {
      errors.push(problem)
      return
    }
    const extra = dialect.changes?.change?.(out, c, where, routine) ?? []
    if (extra.length) {
      errors.push(...extra)
      return
    }
    changes.push(out)
  })

  if (errors.length) return fail(errors)
  // An empty change list and "no change" are the same outcome.
  if (!changes.length) return { ok: true, nochange: true, reading: clampStr(input.summary || input.reading || '', 1200) }
  const evidence = obj(input.evidence)
  return {
    ok: true,
    proposal: {
      summary: clampStr(input.summary || '', 1200),
      evidence: {
        from: evidence.from || null,
        to: evidence.to || null,
        sessions: isInt(evidence.sessions, 0, 10000) ? evidence.sessions : null,
      },
      changes,
      notes: (Array.isArray(input.notes) ? input.notes : []).filter(isStr).slice(0, 6).map(n => clampStr(n, 600)),
    },
  }
}

