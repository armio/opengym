import type { BodyweightEntry } from '../../db'
import { addDays, weekKey } from '../../engine'
import type { Owner, Unit } from '../owner'
import { mondayDate, round } from '../views/format'

/** Body-weight readings: the series, weekly averages and changes over 4 and 12 weeks. */

export interface WeighIn {
  d: string
  w: number
}

export interface WeeklyAverage {
  /** ISO week, e.g. '2026-40'. */
  week: string
  /** Its Monday. */
  from: string
  avg: number
  n: number
}

export function goalWeight(owner: Owner): number | null {
  const goal = owner.settings.targetW
  return typeof goal === 'number' && Number.isFinite(goal) && goal > 0 ? goal : null
}

export const toWeighIns = (entries: readonly BodyweightEntry[]): WeighIn[] =>
  entries.filter(e => typeof e.w === 'number' && Number.isFinite(e.w)).map(e => ({ d: e.d, w: e.w }))

/**
 * The latest reading minus the last one at least `days` days before it; null without such a
 * reading. `entries` are in date order.
 */
export function changeOver(entries: readonly WeighIn[], days: number): number | null {
  const latest = entries.at(-1)
  if (!latest) return null
  const cutoff = addDays(latest.d, -days)
  const base = entries.findLast(entry => entry.d <= cutoff)
  return base ? round(latest.w - base.w) : null
}

export function weeklyAverages(entries: readonly WeighIn[]): WeeklyAverage[] {
  const weeks = new Map<string, WeeklyAverage & { sum: number }>()
  for (const entry of entries) {
    const key = weekKey(entry.d)
    const week = weeks.get(key) ?? { week: key, from: mondayDate(entry.d), avg: 0, n: 0, sum: 0 }
    week.sum += entry.w
    week.n++
    weeks.set(key, week)
  }
  return [...weeks.values()].sort((a, b) => (a.from < b.from ? -1 : 1)).map(({ week, from, n, sum }) => ({ week, from, avg: round(sum / n), n }))
}

export interface BodyWeightReport {
  unit: Unit
  goal: number | null
  from: string
  to: string
  latest: WeighIn | null
  change4w: number | null
  change12w: number | null
  entries: WeighIn[]
  weeklyAvg: WeeklyAverage[]
}

/** Default range: the 12 weeks up to `to` (or today). */
export const BODYWEIGHT_DEFAULT_DAYS = 84

/** `get_body_weight`: `all` is every reading in date order; the changes always use all of them. */
export function buildBodyWeight(owner: Owner, all: readonly WeighIn[], range: { from?: string; to?: string }): BodyWeightReport {
  const to = range.to ?? owner.today
  const from = range.from ?? addDays(to, -BODYWEIGHT_DEFAULT_DAYS)
  const entries = all.filter(entry => entry.d >= from && entry.d <= to)
  return {
    unit: owner.unit,
    goal: goalWeight(owner),
    from,
    to,
    latest: all.at(-1) ?? null,
    change4w: changeOver(all, 28),
    change12w: changeOver(all, 84),
    entries,
    weeklyAvg: weeklyAverages(entries),
  }
}
