import { defaultDocData } from '../../db'
import type { JsonObject } from '../../lib/json'
import { localDateTimeOrNull } from './format'

/** The Coach intake profile (contract §2.1) as Claude reads and writes it. */

export const GOALS = ['strength', 'muscle', 'general', 'fatloss', 'endurance'] as const
export const EXPERIENCE = ['new', 'returning', 'regular'] as const

/** The fields Claude may change; `savedAt` and `updatedBy` are stamped by the server. */
export const ATHLETE_FIELDS = [
  'goal', 'experience', 'daysPerWeek', 'preferredDays', 'sessionMin', 'equipment', 'limitations', 'likes', 'dislikes', 'notes',
] as const

export type AthleteField = (typeof ATHLETE_FIELDS)[number]

/** The profile with defaults for missing fields; `savedAt` in the owner's zone (null = never saved). */
export function athleteView(athlete: JsonObject, tz: string): JsonObject {
  const defaults = defaultDocData('athlete')
  const view: JsonObject = {}
  for (const field of ATHLETE_FIELDS) view[field] = athlete[field] !== undefined ? athlete[field] : defaults[field]
  view.savedAt = localDateTimeOrNull(athlete.savedAt, tz)
  view.updatedBy = typeof athlete.updatedBy === 'string' ? athlete.updatedBy : null
  return view
}
