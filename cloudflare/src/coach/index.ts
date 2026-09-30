/**
 * Server side of the Coach: the validators that gate Claude's proposals (contract §5.3), the plan
 * fingerprint (§5.4) and the current values stored as each change's `before`. Applying proposals
 * happens in the app.
 */
export {
  CHANGE_TYPES, LIBRARY_LOOKUP, ORIGINAL, usableRoutineExercises, validatePlan, validateReview,
  type BundleCustomExercise, type BundleRoutine, type Change, type ChangeChecks, type ChangeTarget, type ChangeType, type CleanExercise,
  type Dialect, type ExerciseLookup, type PlanBundle, type PlanChecks, type PlanContext, type Result, type ReviewPlan, type ReviewProposal,
  type ReviewResult, type ReviewRoutine,
} from './validate'
export {
  checkExerciseMode, checkNotInRoutine, checkPolicyForMode, checkReorder, checkRoutinePolicy, checkSupersetPartner, checkSwapMode,
  checkTrainingDays, clampEmoji, equipmentWarnings, validateChangesProposal, validatePlanProposal,
  type ChangesProposalResult, type PlanProposalResult, type PortContext,
} from './portRules'
export { canonString, canonicalPlan, hashPlan, planHash, type CanonicalExercise, type CanonicalPlan, type HashablePlan } from './planHash'
export { beforeOf, currentValue, fillBefore, type ChangeablePlan } from './currentValue'
export { clampGraphemes } from './text'
