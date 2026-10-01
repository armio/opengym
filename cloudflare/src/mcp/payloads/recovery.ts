import type { RecoveryDay } from '../../db'
import { addDays } from '../../engine'
import { round } from '../views/format'

/**
 * Recovery from Apple Health (contract §8): resting heart rate, HRV and sleep per day, the last
 * 7 days against the 28 before them, and plain-language signals when they differ clearly.
 */

export const RECOVERY_DEFAULT_DAYS = 28
export const RECOVERY_MAX_DAYS = 400
export const RECENT_DAYS = 7
export const BASELINE_DAYS = 28

/** Days a comparison needs on each side before it says anything. */
const MIN_RECENT = 3
const MIN_BASELINE = 10

/** Sleep below this many minutes is a short night. */
export const SHORT_NIGHT_MIN = 360

export interface Stat {
  mean: number | null
  sd: number | null
  n: number
}

export interface RecoveryWindow {
  from: string
  to: string
  rhr: Stat
  hrv: Stat
  sleepMin: Stat
}

export interface RecoveryComparison {
  /** The 7 days up to the reference date. */
  recent: RecoveryWindow & { shortNights: number }
  /** The 28 days before them. */
  baseline: RecoveryWindow
  /** True when both sides have enough days of at least one metric to compare. */
  comparable: boolean
  signals: string[]
}

function stat(values: readonly number[], decimals = 1): Stat {
  const n = values.length
  if (n === 0) return { mean: null, sd: null, n }
  const mean = values.reduce((sum, v) => sum + v, 0) / n
  const sd = n > 1 ? Math.sqrt(values.reduce((sum, v) => sum + (v - mean) ** 2, 0) / (n - 1)) : null
  return { mean: round(mean, decimals), sd: sd === null ? null : round(sd, decimals), n }
}

const valuesOf = (days: readonly RecoveryDay[], key: 'rhr' | 'hrv' | 'sleepMin') =>
  days.map(day => day[key]).filter((v): v is number => typeof v === 'number')

function windowOf(days: readonly RecoveryDay[], from: string, to: string): RecoveryWindow {
  const inside = days.filter(day => day.d >= from && day.d <= to)
  return { from, to, rhr: stat(valuesOf(inside, 'rhr')), hrv: stat(valuesOf(inside, 'hrv')), sleepMin: stat(valuesOf(inside, 'sleepMin'), 0) }
}

const enough = (recent: Stat, baseline: Stat) => recent.n >= MIN_RECENT && baseline.n >= MIN_BASELINE

const hours = (minutes: number) => round(minutes / 60, 1)

/** Compares the 7 days ending `to` with the 28 days before them. `days` may hold any range. */
export function compareRecovery(days: readonly RecoveryDay[], to: string): RecoveryComparison {
  const recentFrom = addDays(to, -(RECENT_DAYS - 1))
  const baselineTo = addDays(recentFrom, -1)
  const recentWindow = windowOf(days, recentFrom, to)
  const shortNights = valuesOf(days.filter(day => day.d >= recentFrom && day.d <= to), 'sleepMin').filter(v => v < SHORT_NIGHT_MIN).length
  const recent = { ...recentWindow, shortNights }
  const baseline = windowOf(days, addDays(baselineTo, -(BASELINE_DAYS - 1)), baselineTo)
  const signals: string[] = []

  if (enough(recent.hrv, baseline.hrv) && baseline.hrv.sd !== null) {
    const [r, b, sd] = [recent.hrv.mean!, baseline.hrv.mean!, baseline.hrv.sd]
    const pct = Math.round(((r - b) / b) * 100)
    if (r < b - sd) signals.push(`HRV is down: the 7-day mean is ${r} ms against a 28-day baseline of ${b} ± ${sd} ms (${pct}%).`)
    else if (r > b + sd) signals.push(`HRV is up: the 7-day mean is ${r} ms against a 28-day baseline of ${b} ± ${sd} ms (+${pct}%).`)
  }
  if (enough(recent.rhr, baseline.rhr)) {
    const [r, b] = [recent.rhr.mean!, baseline.rhr.mean!]
    const margin = Math.max(baseline.rhr.sd ?? 0, 2)
    if (r > b + margin) signals.push(`Resting heart rate is up: the 7-day mean is ${r} bpm against a 28-day baseline of ${b} bpm (+${round(r - b)}).`)
  }
  if (recent.sleepMin.n >= MIN_RECENT) {
    const r = recent.sleepMin.mean!
    if (r < SHORT_NIGHT_MIN) {
      signals.push(`Short sleep: ${hours(r)} h a night on average over the last ${recent.sleepMin.n} nights (${shortNights} under 6 h).`)
    } else if (baseline.sleepMin.n >= MIN_BASELINE && r < baseline.sleepMin.mean! - 45) {
      signals.push(`Less sleep than usual: ${hours(r)} h a night over the last ${recent.sleepMin.n} nights against ${hours(baseline.sleepMin.mean!)} h in the 28 days before.`)
    }
  }

  const comparable = enough(recent.hrv, baseline.hrv) || enough(recent.rhr, baseline.rhr) || enough(recent.sleepMin, baseline.sleepMin)
  return { recent, baseline, comparable, signals }
}

/** The most recent day with any metric, on or before `to`. */
export const latestRecoveryDay = (days: readonly RecoveryDay[], to: string): RecoveryDay | null =>
  days.findLast(day => day.d <= to) ?? null

/** First date `get_overview` and `get_recovery` must load to compare up to `to`. */
export const comparisonStart = (to: string): string => addDays(to, -(RECENT_DAYS + BASELINE_DAYS - 1))

export interface RecoveryReport {
  source: 'Apple Health'
  from: string
  to: string
  latest: RecoveryDay | null
  comparison: RecoveryComparison
  days: RecoveryDay[]
}

/** `get_recovery`: `days` covers at least min(from, comparisonStart(to)) … to. */
export function buildRecovery(days: readonly RecoveryDay[], from: string, to: string): RecoveryReport {
  return {
    source: 'Apple Health',
    from,
    to,
    latest: latestRecoveryDay(days, to),
    comparison: compareRecovery(days, to),
    days: days.filter(day => day.d >= from && day.d <= to),
  }
}

/** The compact block `get_overview` carries; null when the owner never shared recovery data. */
export function recoverySummary(days: readonly RecoveryDay[], today: string): { latest: RecoveryDay | null } & RecoveryComparison | null {
  if (days.length === 0) return null
  return { latest: latestRecoveryDay(days, today), ...compareRecovery(days, today) }
}
