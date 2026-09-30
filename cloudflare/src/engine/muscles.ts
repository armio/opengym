import type { ExerciseIndex, ExerciseInfo, Routine, SetLog, Workout } from './types'

/**
 * Port of frontend/src/lib/muscles.js (engine.md §7): which muscles an exercise trains and how
 * much work each muscle got, in "effective sets" (weight is deliberately ignored).
 */

/** The 18 drawable muscles, head to toe. */
export const MUSCLES = [
  'trapezius', 'deltoids', 'chest', 'upper-back', 'serratus',
  'biceps', 'triceps', 'forearm',
  'abs', 'obliques', 'lower-back',
  'gluteal', 'quadriceps', 'hamstring', 'adductors', 'hip-flexors',
  'calves', 'tibialis',
] as const

export type Muscle = (typeof MUSCLES)[number]

/** Every `tg`/`sm` spelling in the dataset → muscle; null = not drawable. */
const ALIAS: ReadonlyMap<string, Muscle | null> = new Map<string, Muscle | null>([
  ['abs', 'abs'], ['pectorals', 'chest'], ['biceps', 'biceps'], ['glutes', 'gluteal'], ['delts', 'deltoids'],
  ['triceps', 'triceps'], ['upper back', 'upper-back'], ['lats', 'upper-back'], ['calves', 'calves'],
  ['quads', 'quadriceps'], ['forearms', 'forearm'], ['hamstrings', 'hamstring'], ['spine', 'lower-back'],
  ['traps', 'trapezius'], ['adductors', 'adductors'], ['serratus anterior', 'serratus'],
  ['abductors', 'gluteal'], ['levator scapulae', 'trapezius'], ['cardiovascular system', null],
  ['shoulders', 'deltoids'], ['deltoids', 'deltoids'], ['rear deltoids', 'deltoids'],
  ['rotator cuff', 'deltoids'], ['quadriceps', 'quadriceps'], ['core', 'abs'], ['abdominals', 'abs'],
  ['lower abs', 'abs'], ['chest', 'chest'], ['upper chest', 'chest'], ['hip flexors', 'hip-flexors'],
  ['obliques', 'obliques'], ['lower back', 'lower-back'], ['rhomboids', 'upper-back'],
  ['trapezius', 'trapezius'], ['back', 'upper-back'], ['latissimus dorsi', 'upper-back'],
  ['brachialis', 'biceps'], ['soleus', 'calves'], ['shins', 'tibialis'], ['wrists', 'forearm'],
  ['wrist flexors', 'forearm'], ['wrist extensors', 'forearm'], ['grip muscles', 'forearm'],
  ['groin', 'adductors'], ['inner thighs', 'adductors'],
  ['ankles', null], ['feet', null], ['hands', null], ['ankle stabilizers', null], ['sternocleidomastoid', null],
])

/** Custom exercises have no target muscles: they spread over their body part (weights sum to 1). */
const BY_BODY_PART: ReadonlyMap<string, Partial<Record<Muscle, number>>> = new Map([
  ['chest', { chest: 1 }],
  ['back', { 'upper-back': 0.75, 'lower-back': 0.25 }],
  ['shoulders', { deltoids: 1 }],
  ['upper arms', { biceps: 0.5, triceps: 0.5 }],
  ['lower arms', { forearm: 1 }],
  ['waist', { abs: 0.7, obliques: 0.3 }],
  ['upper legs', { quadriceps: 0.4, hamstring: 0.35, gluteal: 0.25 }],
  ['lower legs', { calves: 0.8, tibialis: 0.2 }],
  ['neck', { trapezius: 1 }],
  ['cardio', {}],
])

/** A secondary muscle counts this much against a primary. */
const SECONDARY = 0.4

export type MuscleLoad = Partial<Record<Muscle, number>>

/** Muscles one exercise trains, { muscle: 0…1 }: primary 1, secondaries 0.4, else by body part. */
export function musclesOf(exercise: ExerciseInfo | null | undefined): MuscleLoad {
  if (!exercise) return {}
  const out: MuscleLoad = {}
  const add = (name: unknown, weight: number) => {
    const muscle = ALIAS.get(String(name || '').toLowerCase().trim())
    if (muscle) out[muscle] = Math.max(out[muscle] || 0, weight)
  }
  add(exercise.target, 1)
  for (const name of exercise.secondary ?? []) add(name, SECONDARY)
  if (!Object.keys(out).length) Object.assign(out, BY_BODY_PART.get(exercise.bodyPart) ?? {})
  return out
}

/** Effective sets per muscle for `{id, sets}` items (items with no sets or unknown ids add nothing). */
export function loadOf(catalog: ExerciseIndex, items: readonly { readonly id: string; readonly sets: number }[]): MuscleLoad {
  const load: MuscleLoad = {}
  for (const { id, sets } of items) {
    if (!sets) continue
    const muscles = musclesOf(catalog.get(id))
    for (const [muscle, weight] of Object.entries(muscles) as [Muscle, number][]) load[muscle] = (load[muscle] || 0) + weight * sets
  }
  return load
}

/** Sets per muscle over finished workouts: done sets, optionally narrowed by `pick` (e.g. isHardSet). */
export function loadOfWorkouts(catalog: ExerciseIndex, workouts: readonly Pick<Workout, 'entries'>[], pick?: (s: SetLog) => boolean): MuscleLoad {
  return loadOf(catalog, workouts.flatMap(w => w.entries.map(e => ({ id: e.id, sets: e.sets.filter(s => s.done && (!pick || pick(s))).length }))))
}

/** Planned sets per muscle for one routine (a missing `sets` counts as 1). */
export function loadOfRoutine(catalog: ExerciseIndex, routine: Pick<Routine, 'ex'> | null | undefined): MuscleLoad {
  return loadOf(catalog, (routine?.ex ?? []).map(c => ({ id: c.id, sets: c.sets || 1 })))
}

/** Done sets per body part (library and custom exercises), optionally narrowed by `pick`. */
export function setsByBodyPart(catalog: ExerciseIndex, workouts: readonly Pick<Workout, 'entries'>[], pick?: (s: SetLog) => boolean): Record<string, number> {
  const out: Record<string, number> = {}
  for (const workout of workouts) {
    for (const entry of workout.entries) {
      const bodyPart = catalog.get(entry.id)?.bodyPart
      const sets = entry.sets.filter(s => s.done && (!pick || pick(s))).length
      if (bodyPart && sets) out[bodyPart] = (out[bodyPart] ?? 0) + sets
    }
  }
  return out
}

/** Shade 0–4 per muscle, relative to the hardest-worked muscle; any load is at least 1. */
export function levelsOf(load: MuscleLoad): Record<Muscle, number> {
  const max = MUSCLES.reduce((m, muscle) => Math.max(m, load[muscle] || 0), 0)
  const levels = {} as Record<Muscle, number>
  for (const muscle of MUSCLES) {
    const v = load[muscle] || 0
    levels[muscle] = !v ? 0 : max <= 0 ? 0 : Math.max(1, Math.min(4, Math.ceil((v / max) * 4)))
  }
  return levels
}

/** Worked muscles by load (ties in body order) and the untrained ones in body order. */
export function rankOf(load: MuscleLoad): { worked: Muscle[]; missed: Muscle[] } {
  const worked = MUSCLES.filter(m => (load[m] || 0) > 0).sort((a, b) => load[b]! - load[a]!)
  const missed = MUSCLES.filter(m => !((load[m] ?? 0) > 0))
  return { worked, missed }
}
