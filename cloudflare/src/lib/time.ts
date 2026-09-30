export const MINUTE_MS = 60_000
export const HOUR_MS = 60 * MINUTE_MS
export const DAY_MS = 24 * HOUR_MS

const ISO_DATE = /^(\d{4})-(\d{2})-(\d{2})$/

/** A real calendar date written as 'YYYY-MM-DD'. */
export function isIsoDate(value: unknown): value is string {
  if (typeof value !== 'string') return false
  const match = ISO_DATE.exec(value)
  if (!match) return false
  const [year, month, day] = [Number(match[1]), Number(match[2]), Number(match[3])]
  const date = new Date(Date.UTC(year, month - 1, day))
  return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day
}

export function isValidTimeZone(value: unknown): value is string {
  if (typeof value !== 'string' || value.length === 0 || value.length > 64) return false
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: value })
    return true
  } catch {
    return false
  }
}

interface ZonedParts {
  year: number
  month: number
  day: number
  hour: number
  minute: number
  second: number
}

function zonedParts(epochMs: number, timeZone: string): ZonedParts {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone,
    hourCycle: 'h23',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  }).formatToParts(new Date(epochMs))
  const get = (type: Intl.DateTimeFormatPartTypes) => Number(parts.find(part => part.type === type)?.value)
  return { year: get('year'), month: get('month'), day: get('day'), hour: get('hour'), minute: get('minute'), second: get('second') }
}

const pad = (n: number, width = 2) => String(n).padStart(width, '0')

/** The calendar date ('YYYY-MM-DD') of an instant in a time zone. */
export function localDate(epochMs: number, timeZone: string): string {
  const { year, month, day } = zonedParts(epochMs, timeZone)
  return `${pad(year, 4)}-${pad(month)}-${pad(day)}`
}

/** Offset of `timeZone` from UTC at an instant, in milliseconds (positive east of Greenwich). */
function zoneOffsetMs(epochMs: number, timeZone: string): number {
  const p = zonedParts(epochMs, timeZone)
  const asUtc = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second)
  return asUtc - Math.floor(epochMs / 1000) * 1000
}

/** Epoch ms of a wall-clock time on a date in a time zone. */
export function zonedTimeToEpoch(isoDate: string, hour: number, minute: number, timeZone: string): number {
  const [year, month, day] = isoDate.split('-').map(Number) as [number, number, number]
  const wallAsUtc = Date.UTC(year, month - 1, day, hour, minute)
  // Two passes settle the offset across a DST change between the guess and the answer.
  let epoch = wallAsUtc - zoneOffsetMs(wallAsUtc, timeZone)
  epoch = wallAsUtc - zoneOffsetMs(epoch, timeZone)
  return epoch
}

/** Local noon of a date: the time assumed for a workout that has only a date (engine-Q7). */
export function localNoon(isoDate: string, timeZone: string): number {
  return zonedTimeToEpoch(isoDate, 12, 0, timeZone)
}
