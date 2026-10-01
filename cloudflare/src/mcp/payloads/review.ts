import type { ProposalDTO } from '../../db'
import {
  addDays, avgRir, best1RM, e1rmSeries, effectiveRoutine, effortOf, effortSummary, lastEntryFor, loadOfWorkouts, modeOf, nextPrescription,
  policyFor, rankOf, sessionsFor, setsByBodyPart, stallsFor, weekKey, type Mode, type MuscleLoad, type Policy,
} from '../../engine'
import type { JsonObject } from '../../lib/json'
import { localDate } from '../../lib/time'
import type { LoggedWorkout, Owner, Training } from '../owner'
import { datesBetween, mondayDate, round, roundOrNull, upperMedian, weekdayName } from '../views/format'
import { planConfigs, prescriptionView, type PrescriptionView } from '../views/plan'
import { doneSets, durationMinutes, loadRecords, workoutDetail } from '../views/workouts'
import { goalWeight, weeklyAverages, type WeighIn } from './bodyweight'

/**
 * `get_training_review` (contract §5.2): the logged training of a window, and what the shared
 * engine reads into it. Exercise stalls and prescriptions use all history, as the app does.
 */

export const REVIEW_DEFAULT_WEEKS = 12
/** The longest window a review may cover (the `weeks` maximum, and the earliest `since`). */
export const REVIEW_MAX_WEEKS = 52
export const REVIEW_MAX_SESSIONS = 60

export interface ReviewRequest {
  since?: string
  weeks?: number
}

export type WindowBasis = 'since' | 'weeks' | 'since-last-review' | 'last-12-weeks'

export interface WindowBounds {
  from: string
  to: string
  basis: WindowBasis
  /** Local date the owner last accepted or dismissed a review, if ever. */
  lastReview: string | null
}

/** When the owner last decided on a review: applied or dismissed `changes`/`nochange` proposals. */
export function lastReviewAt(proposals: readonly ProposalDTO[]): number | null {
  const times = proposals
    .filter(p => (p.kind === 'changes' || p.kind === 'nochange') && (p.status === 'applied' || p.status === 'dismissed') && p.resolvedAt)
    .map(p => p.resolvedAt!)
  return times.length ? Math.max(...times) : null
}

/**
 * The window: `since` or the last `weeks` when asked; otherwise since the last review, but never
 * more than 12 weeks back (FR-22 with coach-B1 fixed).
 */
export function windowBounds(owner: Owner, proposals: readonly ProposalDTO[], request: ReviewRequest): WindowBounds {
  const to = owner.today
  const reviewedAt = lastReviewAt(proposals)
  const lastReview = reviewedAt ? localDate(reviewedAt, owner.clock.tz) : null
  // Never more than a year: every day in the window is walked for adherence (the tool rejects
  // older dates; this keeps the builder bounded for any other caller).
  const earliest = addDays(to, -7 * REVIEW_MAX_WEEKS)
  if (request.since) return { from: request.since < earliest ? earliest : request.since, to, basis: 'since', lastReview }
  if (request.weeks) return { from: addDays(to, -7 * request.weeks), to, basis: 'weeks', lastReview }
  const cutoff = addDays(to, -7 * REVIEW_DEFAULT_WEEKS)
  if (lastReview && lastReview > cutoff) return { from: lastReview, to, basis: 'since-last-review', lastReview }
  return { from: cutoff, to, basis: 'last-12-weeks', lastReview }
}

/* ------------------------------------------------------------------ exercises */

/** Best estimated 1RM ever, and the first and last estimates inside the window. */
function e1rmView(training: Training, id: string, from: string, to: string): JsonObject | null {
  const best = best1RM(training, id)
  if (!best) return null
  const inWindow = e1rmSeries(training, id).filter(p => p.d >= from && p.d <= to)
  const first = inWindow[0]
  const last = inWindow.at(-1)
  return {
    best: { value: best.est, w: best.w, r: best.r, d: best.d },
    windowFirst: first ? { d: first.d, value: first.y } : null,
    windowLast: last ? { d: last.d, value: last.y } : null,
    change: first && last ? round(last.y - first.y) : null,
  }
}

/** Every exercise logged with a done set, in order of first appearance. */
function loggedExerciseIds(workouts: readonly LoggedWorkout[]): string[] {
  const ids = new Set<string>()
  for (const workout of workouts) for (const entry of workout.entries) if (entry.sets.some(s => s.done)) ids.add(entry.id)
  return [...ids]
}

export interface ExerciseAggregate {
  id: string
  name: string | null
  mode: Mode
  inPlan: boolean
  policy: Policy
  /** Sessions in this mode over all history. */
  sessions: number
  sessionsInWindow: number
  lastSession: string
  lastOk: boolean
  /** Consecutive missed sessions as the engine counts them for this policy. */
  stalls: number
  /** Set when the last session had no rep/time target to judge (old or imported data). */
  noTarget?: true
  /** The engine's next prescription (plan exercises only). */
  next?: PrescriptionView
  e1rm?: JsonObject | null
  /** Average RIR of the window's done sets (0 = failure); null when none was rated. */
  avgRir: number | null
  workingWeight: number | null
}

/**
 * Per exercise, over all history in the mode it is (or was last) trained in: the engine's
 * policy-aware stall count (cardio never stalls), the next prescription for plan exercises,
 * e1RM and effort. Listed when it stalled or has at least 3 sessions; most stalls first.
 */
function exerciseAggregates(owner: Owner, training: Training, window: readonly LoggedWorkout[], from: string, to: string): ExerciseAggregate[] {
  const { catalog } = owner
  const configs = planConfigs(owner.plan)
  const out: ExerciseAggregate[] = []
  for (const id of loggedExerciseIds(training.workouts)) {
    const planned = configs.get(id)
    const lastTarget = lastEntryFor(training, id)?.target ?? null
    const mode: Mode = planned ? modeOf(catalog, planned.cfg) : modeOf(catalog, { ...(lastTarget ?? {}), id })
    const sessions = sessionsFor(training, id, planned?.cfg).filter(s => s.mode === mode)
    const last = sessions.at(-1)
    if (!last) continue
    const policy = policyFor(catalog, planned?.cfg ?? lastTarget, planned?.routine, mode)
    // Without a rep or time target (old or imported sessions of an exercise not in the plan)
    // there is nothing to miss, so nothing to count as a stall.
    const hasTarget = last.goal > 0
    const stalls = hasTarget ? stallsFor(policy, mode, sessions) : 0
    if (stalls === 0 && sessions.length < 3) continue
    const windowSets = window.flatMap(w => w.entries.filter(e => e.id === id).flatMap(doneSets))
    out.push({
      id,
      name: catalog.get(id)?.name ?? null,
      mode,
      inPlan: Boolean(planned),
      policy,
      sessions: sessions.length,
      sessionsInWindow: sessions.filter(s => s.d >= from && s.d <= to).length,
      lastSession: last.d,
      lastOk: last.ok,
      stalls,
      ...(hasTarget ? {} : { noTarget: true as const }),
      ...(planned ? { next: prescriptionView(nextPrescription(training, planned.cfg, planned.routine)) } : {}),
      ...(mode === 'reps' ? { e1rm: e1rmView(training, id, from, to) } : {}),
      avgRir: roundOrNull(avgRir(windowSets)),
      workingWeight: training.workingWeights[id]?.w ?? null,
    })
  }
  return out.sort((a, b) => b.stalls - a.stalls || b.sessions - a.sessions || (a.name ?? a.id).localeCompare(b.name ?? b.id))
}

/* ------------------------------------------------------------------ adherence */

interface AdherenceWeek {
  week: string
  from: string
  planned: number
  trained: number
  sessions: number
}

/**
 * Planned against trained under the current plan and schedule (coach-Q6): a date is planned
 * when its effective routine exists; a planned date without a workout is missed (today only
 * once it is over). Reschedules inside the window split into moved and rest days.
 */
function adherence(owner: Owner, window: readonly LoggedWorkout[], from: string, to: string): JsonObject {
  const { plan, dayPlan, today } = owner
  const schedule = { routines: plan.routines, week: plan.week, dayPlan }
  const sessionsOn = new Map<string, number>()
  for (const workout of window) sessionsOn.set(workout.d, (sessionsOn.get(workout.d) ?? 0) + 1)

  const weeks = new Map<string, AdherenceWeek>()
  const missedDays: JsonObject[] = []
  let plannedDays = 0
  for (const d of datesBetween(from, to)) {
    const routine = effectiveRoutine(schedule, d)
    const sessions = sessionsOn.get(d) ?? 0
    const key = weekKey(d)
    const week = weeks.get(key) ?? { week: key, from: mondayDate(d), planned: 0, trained: 0, sessions: 0 }
    weeks.set(key, week)
    if (routine) {
      week.planned++
      plannedDays++
    }
    if (sessions) week.trained++
    week.sessions += sessions
    if (routine && !sessions && d < today) missedDays.push({ d, weekday: weekdayName(d), routineId: routine.id, routine: routine.name ?? null })
  }

  const reschedules = Object.entries(dayPlan).filter(([d]) => d >= from && d <= to).sort(([a], [b]) => (a < b ? -1 : 1))
  return {
    plannedPerWeek: Object.keys(plan.week).length,
    plannedDays,
    trainedDays: sessionsOn.size,
    sessions: window.length,
    missedDays,
    weeks: [...weeks.values()],
    reschedules: {
      moved: reschedules
        .filter(([, value]) => value !== 'rest')
        .map(([d, routineId]) => ({ d, routineId, routine: plan.routines.find(r => r.id === routineId)?.name ?? null })),
      rest: reschedules.filter(([, value]) => value === 'rest').map(([d]) => d),
    },
  }
}

/* ------------------------------------------------------------------ the payload */

function roundLoad(load: MuscleLoad): Record<string, number> {
  return Object.fromEntries(Object.entries(load).map(([muscle, sets]) => [muscle, round(sets ?? 0)]))
}

export interface ReviewInput {
  owner: Owner
  training: Training
  /** Every body-weight reading, in date order. */
  bodyweight: readonly WeighIn[]
  proposals: readonly ProposalDTO[]
  request: ReviewRequest
}

export function buildTrainingReview({ owner, training, bodyweight, proposals, request }: ReviewInput): JsonObject {
  const { catalog, clock } = owner
  const bounds = windowBounds(owner, proposals, request)
  const inRange = training.workouts.filter(w => w.d >= bounds.from && w.d <= bounds.to)
  const truncated = inRange.length > REVIEW_MAX_SESSIONS
  const window = inRange.slice(-REVIEW_MAX_SESSIONS)
  // A truncated window starts at its oldest session, so every number below describes the same days.
  const from = truncated ? window[0]!.d : bounds.from
  const { to } = bounds
  const records = loadRecords(catalog, training.workouts)
  const effort = effortSummary({ workouts: window }, 0, clock)
  const muscles = loadOfWorkouts(catalog, window)
  const entries = bodyweight.filter(b => b.d >= from && b.d <= to)
  return {
    unit: owner.unit,
    today: owner.today,
    effortScale: effortOf(owner.settings),
    window: {
      from,
      to,
      basis: bounds.basis,
      lastReview: bounds.lastReview,
      sessions: window.length,
      truncated,
      workouts: window.map(w => workoutDetail(w, catalog, records)),
    },
    aggregates: {
      exercises: exerciseAggregates(owner, training, window, from, to),
      adherence: adherence(owner, window, from, to),
      setsByBodyPart: setsByBodyPart(catalog, window),
      setsByMuscle: roundLoad(muscles),
      untrainedMuscles: rankOf(muscles).missed,
      medianSessionMin: upperMedian(window.map(durationMinutes).filter((m): m is number => m !== null)),
      hardSetShare: roundOrNull(effort.hardPct, 2),
      effort: { doneSets: effort.done, ratedSets: effort.rated, hardSets: effort.hard, avgRir: roundOrNull(effort.avg) },
    },
    bodyweight: { goal: goalWeight(owner), entries, weeklyAvg: weeklyAverages(entries) },
  }
}
