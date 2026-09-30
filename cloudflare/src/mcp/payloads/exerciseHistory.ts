import { avgRir, best1RM, bestSetOf, entryModeOf, heaviestDoneSets, modeOf, nextPrescription } from '../../engine'
import type { JsonObject } from '../../lib/json'
import type { LoggedEntry, LoggedWorkout, Owner, Training } from '../owner'
import { round, roundOrNull } from '../views/format'
import { exerciseView, prescriptionView } from '../views/plan'
import { compactSet, doneSets, exerciseName, topSetOf } from '../views/workouts'

/** `get_exercise_history` (contract §5.2): one exercise's sessions, records and next prescription. */

export const HISTORY_DEFAULT_LIMIT = 20
export const HISTORY_MAX_LIMIT = 100

/** Σ w × r over done sets. */
const volumeOf = (entry: LoggedEntry) => round(doneSets(entry).reduce((sum, s) => sum + (s.w ?? 0) * (s.r ?? 0), 0))

/** Null when the id is neither in the catalogue nor in the logged history. */
export function buildExerciseHistory(owner: Owner, training: Training, exerciseId: string, limit = HISTORY_DEFAULT_LIMIT): JsonObject | null {
  const { catalog } = owner
  const logged: { workout: LoggedWorkout; entry: LoggedEntry }[] = []
  for (const workout of training.workouts) {
    // The engine reads an exercise's first entry of a session.
    const entry = workout.entries.find(e => e.id === exerciseId)
    if (entry && entry.sets.some(s => s.done)) logged.push({ workout, entry })
  }
  const exercise = catalog.get(exerciseId)
  if (!exercise && !logged.length) return null

  const placements = owner.plan.routines.flatMap(routine => routine.ex.filter(cfg => cfg.id === exerciseId).map(cfg => ({ routine, cfg })))
  const lastLogged = logged.at(-1)
  const mode = placements[0]
    ? modeOf(catalog, placements[0].cfg)
    : lastLogged
      ? entryModeOf(catalog, lastLogged.entry)
      : modeOf(catalog, { id: exerciseId })
  const best = best1RM(training, exerciseId)
  const workingWeight = training.workingWeights[exerciseId]
  const inPlan = placements.map(({ routine, cfg }) => ({
    routineId: routine.id,
    routine: routine.name ?? null,
    config: exerciseView(cfg, routine, catalog),
    next: prescriptionView(nextPrescription(training, cfg, routine)),
  }))

  return {
    unit: owner.unit,
    exercise: {
      id: exerciseId,
      name: exercise?.name ?? (lastLogged ? exerciseName(catalog, lastLogged.entry) : null),
      bodyPart: exercise?.bodyPart ?? null,
      target: exercise?.target || null,
      equipment: exercise?.equipment ?? null,
      custom: exercise?.custom ?? false,
      mode,
    },
    totalSessions: logged.length,
    sessions: logged.slice(-limit).map(({ workout, entry }) => {
      const entryMode = entryModeOf(catalog, entry)
      return {
        d: workout.d,
        workoutId: workout.id,
        mode: entryMode,
        sets: entry.sets.map(compactSet),
        topSet: topSetOf(entry, entryMode),
        e1rm: bestSetOf(entry)?.est ?? null,
        volume: volumeOf(entry),
        avgRir: roundOrNull(avgRir(doneSets(entry))),
      }
    }),
    best: {
      e1rm: best ? { value: best.est, w: best.w, r: best.r, d: best.d } : null,
      weight: heaviestDoneSets(training).get(exerciseId) ?? null,
    },
    workingWeight: workingWeight ? { w: workingWeight.w, d: workingWeight.d } : null,
    inPlan,
    nextPrescription: inPlan[0]?.next ?? null,
  }
}
