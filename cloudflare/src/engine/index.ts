/**
 * The training engine shared with the app (contract §2.3): pure functions over the JSON shapes of
 * the plan doc and workout rows. Clock-dependent functions take a `Clock`; order-dependent ones
 * expect workouts in `(d, start)` order (`sortWorkouts`).
 */
export * from './types'
export { addDays, mondayOf, sortWorkouts, startOf, streakWeeks, weekKey, weekdayOf } from './dates'
export {
  EFFORT, bestWeightFor, effectiveRoutine, effectiveRoutineId, effortOf, entryModeOf, heaviestDoneSets, isCardio, lastEntryFor, modeOf, setsDone, workoutVolume,
  type EffortKind, type EffortSettings, type LastEntry, type PlanView,
} from './history'
export {
  DEFAULT_SEC_INCREMENT, DELOAD_AFTER, POLICIES, POLICIES_FOR, WHY, defaultIncrement, doubleStallCount, formatWhy, nextPrescription, policyFor,
  readSession, sessionsFor, stallCount, stallsFor,
  type DatedSession, type Prescription, type PrescriptionKind, type RepsSession, type Session, type TimeSession, type Why,
} from './progression'
export {
  DEFAULT_FORMULA, FORMULAS, REP_CAP, best1RM, bestSetOf, e1rmSeries, estimate1RM, is1RMRecord,
  type BestEstimate, type BestSet, type E1rmPoint, type Formula,
} from './onerm'
export {
  BUCKETS, HARD_RIR, MIN_RATED, avgRir, displayScale, effortHistogram, effortSummary, effortWeeks, hasEffort, isHardSet, rirOf, toScale,
  type EffortBin, type EffortSummary, type EffortWeek,
} from './effort'
export { MUSCLES, levelsOf, loadOf, loadOfRoutine, loadOfWorkouts, musclesOf, rankOf, setsByBodyPart, type Muscle, type MuscleLoad } from './muscles'
