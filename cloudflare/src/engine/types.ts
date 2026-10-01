/**
 * The JSON shapes the engine reads (contract §2, specs/data-model.md §1.4–§1.5). Every field is
 * optional where the original tolerates its absence: workouts come from many app versions and
 * imports, and the engine reads them as defensively as the original did.
 */

export type Mode = 'reps' | 'time' | 'cardio'

export type Policy = 'off' | 'linear' | 'greyskull' | 'double' | 'time'

/** One logged set; which fields exist depends on the logging mode (engine.md §1.4). */
export interface SetLog {
  readonly done?: boolean
  readonly w?: number
  readonly r?: number
  readonly sec?: number
  readonly min?: number
  readonly speed?: number
  readonly rir?: number | null
  readonly rpe?: number | null
}

/** A routine exercise config (`cfg`). A workout entry stores a copy as its `target`. */
export interface ExerciseConfig {
  readonly id?: string
  readonly mode?: string
  readonly sets?: number
  readonly reps?: number
  readonly sec?: number
  readonly min?: number
  readonly speed?: number
  readonly weight?: number
  readonly prog?: string
  readonly inc?: number
  readonly repsMin?: number
  readonly sg?: string
}

/** A routine exercise as it sits in the plan: always names its exercise. */
export interface PlannedExercise extends ExerciseConfig {
  readonly id: string
}

export interface Routine {
  readonly id: string
  readonly name?: string
  readonly prog?: string
  readonly ex?: readonly PlannedExercise[]
}

export interface WorkoutEntry {
  readonly id: string
  readonly sets: readonly SetLog[]
  readonly topW?: number | null
  readonly target?: ExerciseConfig | null
}

export interface Workout {
  readonly id?: string
  /** Local date the session started, 'YYYY-MM-DD'. */
  readonly d: string
  /** Epoch ms; absent on some imports, which then count as local noon of `d` (engine-Q7). */
  readonly start?: number | null
  readonly end?: number | null
  readonly entries: readonly WorkoutEntry[]
}

/** `ex_weights` row / original `exWeights[id]`: the confirmed working weight. */
export interface WorkingWeight {
  readonly w: number
  readonly d?: string
}

/** What the engine needs to know about an exercise. `Catalog` from src/catalog satisfies it. */
export interface ExerciseInfo {
  readonly bodyPart: string
  readonly target: string
  readonly secondary: readonly string[]
}

export interface ExerciseIndex {
  get(id: string): ExerciseInfo | undefined
}

/** Workouts in (d, start) order — see `sortWorkouts`. */
export interface WorkoutLog {
  readonly workouts?: readonly Workout[]
}

/**
 * The original's state `S`, reduced to what the progression engine reads, plus the exercise
 * index the original kept in a global.
 */
export interface TrainingState extends WorkoutLog {
  readonly catalog: ExerciseIndex
  /** settings.unit; anything but 'lb' counts as kg. */
  readonly unit?: string
  readonly exWeights?: Readonly<Record<string, WorkingWeight | undefined>>
}

/** The instant and IANA zone every clock-dependent function works against. */
export interface Clock {
  readonly now: number
  readonly tz: string
}
