import type { Catalog } from '../../catalog/library'
import { planHash } from '../../coach'
import { formatWhy, modeOf, policyFor, type Mode, type PlannedExercise, type Policy, type Prescription } from '../../engine'
import { routineById, type Plan, type PlanRoutine } from '../owner'
import { MONDAY_FIRST, WEEKDAY_NAMES, type WeekdayName } from './format'

/** The plan as Claude reads it: exercise names, explicit modes and the policy actually in force. */

export interface ExerciseView {
  id: string
  name: string | null
  custom?: true
  mode: Mode
  sets: unknown
  reps?: unknown
  sec?: unknown
  min?: unknown
  speed?: unknown
  weight?: unknown
  /** The policy the progression engine applies (the exercise's, else the routine's, else the mode default). */
  policy: Policy
  /** The exercise's own `prog`, when set: what an `exercise-prog` change compares against. */
  prog?: string
  inc?: unknown
  repsMin?: unknown
  sg?: unknown
}

export interface RoutineView {
  id: string
  name: string
  emoji: unknown
  prog?: string
  exercises: ExerciseView[]
}

export interface WeekDayView {
  weekday: number
  routineId: string
  /** null when the schedule points at a routine that no longer exists (the app treats it as rest). */
  routine: string | null
}

export interface PlanView {
  routines: RoutineView[]
  /** Monday first; null = rest day. */
  week: Record<WeekdayName, WeekDayView | null>
}

const present = (value: unknown) => value !== undefined && value !== null && value !== ''

export function exerciseView(cfg: PlannedExercise, routine: Pick<PlanRoutine, 'prog'>, catalog: Catalog): ExerciseView {
  const mode = modeOf(catalog, cfg)
  const exercise = catalog.get(cfg.id)
  const fields = mode === 'cardio' ? (['min', 'speed'] as const) : mode === 'time' ? (['sec', 'weight'] as const) : (['reps', 'weight'] as const)
  const view: ExerciseView = { id: cfg.id, name: exercise?.name ?? null, mode, sets: cfg.sets ?? null, policy: policyFor(catalog, cfg, routine, mode) }
  if (exercise?.custom) view.custom = true
  for (const field of fields) if (present(cfg[field])) view[field] = cfg[field]
  if (typeof cfg.prog === 'string' && cfg.prog) view.prog = cfg.prog
  for (const field of ['inc', 'repsMin', 'sg'] as const) if (present(cfg[field])) view[field] = cfg[field]
  return view
}

export function routineView(routine: PlanRoutine, catalog: Catalog): RoutineView {
  return {
    id: routine.id,
    name: routine.name ?? '',
    emoji: routine.emoji ?? null,
    ...(routine.prog ? { prog: routine.prog } : {}),
    exercises: routine.ex.map(cfg => exerciseView(cfg, routine, catalog)),
  }
}

export function weekView(plan: Plan): PlanView['week'] {
  const week = {} as PlanView['week']
  for (const day of MONDAY_FIRST) {
    const routineId = plan.week[day]
    week[WEEKDAY_NAMES[day]] = routineId ? { weekday: day, routineId, routine: routineById(plan, routineId)?.name ?? null } : null
  }
  return week
}

export function planView(plan: Plan, catalog: Catalog): PlanView {
  return { routines: plan.routines.map(routine => routineView(routine, catalog)), week: weekView(plan) }
}

/** Where an exercise sits in the plan (the last routine wins, as the original Coach payload read it). */
export function planConfigs(plan: Plan): Map<string, { cfg: PlannedExercise; routine: PlanRoutine }> {
  const configs = new Map<string, { cfg: PlannedExercise; routine: PlanRoutine }>()
  for (const routine of plan.routines) for (const cfg of routine.ex) configs.set(cfg.id, { cfg, routine })
  return configs
}

/** The plan fingerprint stored with proposals (contract §5.4). */
export function currentPlanHash(plan: Plan, catalog: Catalog): string {
  const routines = plan.routines.map(routine => ({ ...routine, ex: routine.ex.map(cfg => ({ ...cfg })) }))
  return planHash({ routines, week: plan.week }, catalog)
}

export interface PrescriptionView {
  policy: Policy
  /** first: sets a baseline · up · hold · deload · off: the engine does not prescribe. */
  kind: Prescription['kind']
  weight?: number
  reps?: number
  sec?: number
  /** The engine's reason, in English. */
  why?: string
}

/** What the progression engine will prefill next session. */
export function prescriptionView({ policy, kind, weight, reps, sec, why }: Prescription): PrescriptionView {
  return {
    policy,
    kind,
    ...(weight !== undefined ? { weight } : {}),
    ...(reps !== undefined ? { reps } : {}),
    ...(sec !== undefined ? { sec } : {}),
    ...(why ? { why: formatWhy(why) } : {}),
  }
}
