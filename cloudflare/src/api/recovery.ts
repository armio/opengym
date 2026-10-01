import { clearRecovery, putRecoveryDays, type RecoveryDay } from '../db'
import { HttpError, jsonResponse, KIB, readJsonBody } from '../lib/http'
import { isPlainObject } from '../lib/json'
import { DAY_MS, isIsoDate } from '../lib/time'
import type { DeviceContext } from './context'

/** Days per upload: the app backfills 90 and then re-sends the last couple of weeks. */
export const MAX_RECOVERY_DAYS = 400

/** How far back an uploaded day may be. */
const MAX_AGE_DAYS = 400

/** Accepted range per metric; values outside it are refused, not clamped. */
const LIMITS = {
  rhr: { min: 20, max: 250, decimals: 1 },
  hrv: { min: 1, max: 500, decimals: 1 },
  sleepMin: { min: 0, max: 1440, decimals: 0 },
  inBedMin: { min: 0, max: 1440, decimals: 0 },
} as const

type Metric = keyof typeof LIMITS

const isoOf = (epochMs: number) => new Date(epochMs).toISOString().slice(0, 10)

function readMetric(raw: Record<string, unknown>, key: Metric, d: string): number | null {
  const value = raw[key]
  if (value === undefined || value === null) return null
  const { min, max, decimals } = LIMITS[key]
  if (typeof value !== 'number' || !Number.isFinite(value) || value < min || value > max) {
    throw new HttpError(400, `${d}: ${key} debe ser un número entre ${min} y ${max}.`)
  }
  const factor = 10 ** decimals
  return Math.round(value * factor) / factor
}

/** Parses `{ days: [{ d, rhr?, hrv?, sleepMin?, inBedMin? }] }`; unknown keys are ignored. */
export function parseRecoveryDays(body: unknown, now: number): RecoveryDay[] {
  if (!isPlainObject(body) || !Array.isArray(body.days)) throw new HttpError(400, 'Envía { "days": [...] }.')
  if (body.days.length > MAX_RECOVERY_DAYS) throw new HttpError(400, `Como mucho ${MAX_RECOVERY_DAYS} días por envío.`)
  // Dates are the owner's local dates: allow one day of time-zone slack on the future side.
  const latest = isoOf(now + DAY_MS)
  const earliest = isoOf(now - MAX_AGE_DAYS * DAY_MS)
  const seen = new Set<string>()
  return body.days.map(raw => {
    if (!isPlainObject(raw) || !isIsoDate(raw.d)) throw new HttpError(400, 'Cada día necesita una fecha d en formato YYYY-MM-DD.')
    const d = raw.d
    if (d > latest || d < earliest) throw new HttpError(400, `${d}: fecha fuera de rango.`)
    if (seen.has(d)) throw new HttpError(400, `${d}: fecha repetida.`)
    seen.add(d)
    return {
      d,
      rhr: readMetric(raw, 'rhr', d),
      hrv: readMetric(raw, 'hrv', d),
      sleepMin: readMetric(raw, 'sleepMin', d),
      inBedMin: readMetric(raw, 'inBedMin', d),
    }
  })
}

/**
 * `POST /api/recovery { days }`: replaces each day's metrics (a day with none left is deleted).
 * → `{ ok, stored, deleted }`.
 */
export async function uploadRecovery({ request, env, now }: DeviceContext): Promise<Response> {
  const days = parseRecoveryDays(await readJsonBody(request, 64 * KIB), now)
  return jsonResponse({ ok: true, ...(await putRecoveryDays(env.DB, days, now)) })
}

/** `POST /api/recovery/clear`: deletes every recovery day (sharing turned off). → `{ ok, deleted }`. */
export async function clearRecoveryDays({ env }: DeviceContext): Promise<Response> {
  return jsonResponse({ ok: true, deleted: await clearRecovery(env.DB) })
}
