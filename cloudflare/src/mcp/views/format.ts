import { addDays, weekdayOf } from '../../engine'

/** Small formatting helpers shared by the payload builders. */

/** Weekday names by JavaScript day number: 0 = Sunday … 6 = Saturday. */
export const WEEKDAY_NAMES = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'] as const

export type WeekdayName = (typeof WEEKDAY_NAMES)[number]

/** The order days are listed in: Monday first, as the app shows the week. */
export const MONDAY_FIRST = [1, 2, 3, 4, 5, 6, 0] as const

export const weekdayName = (iso: string): WeekdayName => WEEKDAY_NAMES[weekdayOf(iso)]!

export function round(value: number, decimals = 1): number {
  const factor = 10 ** decimals
  return Math.round(value * factor) / factor
}

export const roundOrNull = (value: number | null | undefined, decimals = 1): number | null =>
  value == null || !Number.isFinite(value) ? null : round(value, decimals)

/** 'YYYY-MM-DD HH:MM' in the owner's zone: how timestamps appear in tool results. */
export function localDateTime(epochMs: number, timeZone: string): string {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone,
    hourCycle: 'h23',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  }).formatToParts(new Date(epochMs))
  const part = (type: Intl.DateTimeFormatPartTypes) => parts.find(p => p.type === type)?.value ?? ''
  return `${part('year').padStart(4, '0')}-${part('month')}-${part('day')} ${part('hour')}:${part('minute')}`
}

export const localDateTimeOrNull = (epochMs: unknown, timeZone: string): string | null =>
  typeof epochMs === 'number' && Number.isFinite(epochMs) && epochMs > 0 ? localDateTime(epochMs, timeZone) : null

/** The middle value; for an even count the upper one (as the original Coach payload did). */
export function upperMedian(values: readonly number[]): number | null {
  if (!values.length) return null
  const sorted = [...values].sort((a, b) => a - b)
  return sorted[Math.floor(sorted.length / 2)]!
}

/** Every date from `from` to `to`, inclusive. */
export function datesBetween(from: string, to: string): string[] {
  const dates: string[] = []
  for (let d = from; d <= to; d = addDays(d, 1)) dates.push(d)
  return dates
}

/** The Monday of the ISO week containing `iso`. */
export const mondayDate = (iso: string): string => addDays(iso, -((weekdayOf(iso) + 6) % 7))
