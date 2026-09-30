import type { ProposalDTO } from '../../db'
import { addDays, effortOf, heaviestDoneSets, streakWeeks } from '../../engine'
import type { JsonObject } from '../../lib/json'
import type { Owner, Training } from '../owner'
import { athleteView } from '../views/athlete'
import { localDateTimeOrNull } from '../views/format'
import { currentPlanHash, planView } from '../views/plan'
import { effectiveStatus, previouslyDeclined, recentDecisions } from '../views/proposals'
import { loadRecords, workoutSummary } from '../views/workouts'
import { changeOver, goalWeight, type WeighIn } from './bodyweight'

/** `get_overview` (contract §5.2): the one call Claude makes first. */

export const RECENT_WORKOUTS = 5

export interface OverviewInput {
  owner: Owner
  training: Training
  /** Every body-weight reading, in date order. */
  bodyweight: readonly WeighIn[]
  /** Every proposal, newest first. */
  proposals: readonly ProposalDTO[]
}

export function metaOf(owner: Owner): JsonObject {
  return {
    unit: owner.unit,
    lang: typeof owner.settings.lang === 'string' ? owner.settings.lang : 'es',
    effortScale: effortOf(owner.settings),
    today: owner.today,
    tz: owner.clock.tz,
  }
}

/** The heaviest done set (reps-mode entries, all history) next to the confirmed working weight. */
function workingWeights(owner: Owner, training: Training): JsonObject[] {
  const best = heaviestDoneSets(training)
  const ids = new Set([...best.keys(), ...Object.keys(training.workingWeights)])
  return [...ids]
    .map(id => ({
      id,
      name: owner.catalog.get(id)?.name ?? null,
      best: best.get(id) ?? null,
      workingWeight: training.workingWeights[id]?.w ?? null,
    }))
    .sort((a, b) => (a.name ?? a.id).localeCompare(b.name ?? b.id))
}

function stats(owner: Owner, training: Training): JsonObject {
  const { workouts } = training
  const since = addDays(owner.today, -30)
  return {
    workoutsTotal: workouts.length,
    last30Days: workouts.filter(w => w.d > since && w.d <= owner.today).length,
    firstWorkout: workouts[0]?.d ?? null,
    lastWorkout: workouts.at(-1)?.d ?? null,
    streakWeeks: streakWeeks(training, owner.clock),
  }
}

/** Short pointers for the situations where Claude should act differently. */
function hints(owner: Owner, training: Training, pending: number): string[] {
  const out: string[] = []
  if (owner.athlete.savedAt == null) {
    out.push('The athlete profile was never saved: ask the owner for goal, experience, days per week, session length, equipment and limitations, then save them with update_athlete_profile.')
  }
  if (!owner.plan.routines.length) out.push('There is no plan yet: design one and send it with propose_plan.')
  if (!training.workouts.length) out.push('No workouts are logged yet, so there is no history to review.')
  if (pending) out.push(`${pending} proposal(s) are waiting for the owner in the app's Coach tab. A new proposal of the same kind replaces the pending one.`)
  return out
}

export function buildOverview({ owner, training, bodyweight, proposals }: OverviewInput): JsonObject {
  const { catalog, clock } = owner
  const records = loadRecords(catalog, training.workouts)
  const pending = proposals.filter(p => effectiveStatus(p, clock.now) === 'pending')
  return {
    meta: metaOf(owner),
    athlete: athleteView(owner.athlete, clock.tz),
    plan: planView(owner.plan, catalog),
    planHash: currentPlanHash(owner.plan, catalog),
    stats: stats(owner, training),
    recentWorkouts: training.workouts.slice(-RECENT_WORKOUTS).reverse().map(w => workoutSummary(w, catalog, records)),
    bodyweight: { latest: bodyweight.at(-1) ?? null, goal: goalWeight(owner), change4w: changeOver(bodyweight, 28) },
    workingWeights: workingWeights(owner, training),
    pendingProposals: pending.map(p => ({ id: p.id, kind: p.kind, summary: p.summary, createdAt: localDateTimeOrNull(p.createdAt, clock.tz) })),
    recentDecisions: recentDecisions(proposals, clock),
    previouslyDeclined: previouslyDeclined(proposals, owner.coach, clock),
    hints: hints(owner, training, pending.length),
  }
}
