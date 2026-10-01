import type { BodyweightItem } from '../db/bodyweight'
import { isDocKey, type DocCasWrite } from '../db/docs'
import type { ExWeightItem } from '../db/exWeights'
import type { SyncPush } from '../db/sync'
import type { WorkoutItem } from '../db/workouts'
import { HttpError, KIB } from '../lib/http'
import { byteLength, isPlainObject, type JsonObject } from '../lib/json'
import { MAX_DOC_BYTES, MAX_WORKOUT_BYTES, ROW_ID } from '../lib/rules'
import { isIsoDate, MINUTE_MS } from '../lib/time'

/** Items per push (contract §3.2). */
export const SYNC_CAPS = { docs: 10, workouts: 100, bodyweight: 500, exWeights: 500 } as const
/** How far ahead of the server clock an `updatedAt` may be. */
const MAX_CLOCK_LEAD_MS = 10 * MINUTE_MS

export type RejectedKind = 'doc' | 'workout' | 'bodyweight' | 'exWeight'

export interface Rejected {
  kind: RejectedKind
  key: string
  error: string
}

/** A per-item validation failure: the item is skipped and reported, the rest apply. */
export class ItemError extends Error {}

const keyOf = (value: unknown): string => (typeof value === 'string' || typeof value === 'number' ? String(value).slice(0, 64) : '')

function nonNegativeInteger(value: unknown): value is number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0
}

/** `since` of a sync request; 0 when absent. */
export function parseSince(value: unknown): number {
  if (value === undefined || value === null || value === '') return 0
  const since = typeof value === 'string' && /^\d+$/.test(value) ? Number(value) : value
  if (!nonNegativeInteger(since)) throw new HttpError(400, '`since` debe ser un entero mayor o igual que 0.')
  return since
}

function updatedAtOf(item: JsonObject, now: number): number {
  const value = item.updatedAt
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value <= 0 || value > now + MAX_CLOCK_LEAD_MS) {
    throw new ItemError('updatedAt no válido')
  }
  return value
}

function deletedOf(item: JsonObject): boolean {
  if (item.deleted === undefined) return false
  if (typeof item.deleted !== 'boolean') throw new ItemError('deleted debe ser booleano')
  return item.deleted
}

function jsonObjectOf(value: unknown, maxBytes: number): JsonObject {
  if (!isPlainObject(value)) throw new ItemError('data debe ser un objeto JSON')
  if (byteLength(JSON.stringify(value)) > maxBytes) throw new ItemError(`data supera ${maxBytes / KIB} KiB`)
  return value
}

function optionalInteger(value: unknown, field: string): number | null {
  if (value === undefined || value === null) return null
  if (typeof value !== 'number' || !Number.isSafeInteger(value)) throw new ItemError(`${field} no válido`)
  return value
}

/** A doc write of a sync push or of a proposal resolve/revert; throws `ItemError` when invalid. */
export function parseDocWrite(item: unknown, now: number, options: { requireUpdatedAt: boolean }): DocCasWrite {
  if (!isPlainObject(item)) throw new ItemError('debe ser un objeto')
  if (!isDocKey(item.key)) throw new ItemError('clave de documento desconocida')
  if (!nonNegativeInteger(item.baseSeq)) throw new ItemError('baseSeq debe ser un entero mayor o igual que 0')
  const data = jsonObjectOf(item.data, MAX_DOC_BYTES)
  const updatedAt = options.requireUpdatedAt || item.updatedAt !== undefined ? updatedAtOf(item, now) : now
  return { key: item.key, data, baseSeq: item.baseSeq, updatedAt }
}

function parseWorkout(item: JsonObject, now: number): WorkoutItem {
  if (typeof item.id !== 'string' || !ROW_ID.test(item.id)) throw new ItemError('id no válido')
  if (!isIsoDate(item.d)) throw new ItemError('fecha no válida')
  const deleted = deletedOf(item)
  const updatedAt = updatedAtOf(item, now)
  const start = optionalInteger(item.start, 'start')
  if (item.routineId !== undefined && item.routineId !== null && typeof item.routineId !== 'string') {
    throw new ItemError('routineId no válido')
  }
  const routineId = typeof item.routineId === 'string' ? item.routineId : null
  if (deleted) return { id: item.id, d: item.d, start, routineId, data: null, deleted, updatedAt }
  const data = jsonObjectOf(item.data, MAX_WORKOUT_BYTES)
  if (data.id !== undefined && data.id !== item.id) throw new ItemError('data.id no coincide con id')
  return { id: item.id, d: item.d, start, routineId, data, deleted, updatedAt }
}

function parseBodyweight(item: JsonObject, now: number): BodyweightItem {
  if (!isIsoDate(item.d)) throw new ItemError('fecha no válida')
  const deleted = deletedOf(item)
  const updatedAt = updatedAtOf(item, now)
  if (deleted) return { d: item.d, w: null, t: null, deleted, updatedAt }
  if (typeof item.w !== 'number' || !Number.isFinite(item.w) || item.w <= 0) throw new ItemError('peso no válido')
  return { d: item.d, w: item.w, t: optionalInteger(item.t, 't'), deleted, updatedAt }
}

/**
 * Working weights may be 0: the weight-confirm sheet stores 0 for body-weight exercises
 * (data-model §1.8), so only negative or non-finite values are rejected.
 */
function parseExWeight(item: JsonObject, now: number): ExWeightItem {
  if (typeof item.id !== 'string' || !ROW_ID.test(item.id)) throw new ItemError('id no válido')
  const deleted = deletedOf(item)
  const updatedAt = updatedAtOf(item, now)
  if (deleted) return { id: item.id, w: null, d: null, deleted, updatedAt }
  if (typeof item.w !== 'number' || !Number.isFinite(item.w) || item.w < 0) throw new ItemError('peso no válido')
  if (!isIsoDate(item.d)) throw new ItemError('fecha no válida')
  return { id: item.id, w: item.w, d: item.d, deleted, updatedAt }
}

function listOf(body: JsonObject, field: keyof typeof SYNC_CAPS): unknown[] {
  const value = body[field]
  if (value === undefined) return []
  if (!Array.isArray(value)) throw new HttpError(400, `\`${field}\` debe ser una lista.`)
  if (value.length > SYNC_CAPS[field]) throw new HttpError(400, `Demasiados elementos en \`${field}\` (máximo ${SYNC_CAPS[field]} por petición).`)
  return value
}

/**
 * Validates each list with `parse`, collecting per-item failures in `rejected` and skipping
 * repeated keys (a second write to the same item in one request could never be ordered).
 */
function parseItems<T>(
  items: unknown[],
  kind: RejectedKind,
  keyField: string,
  parse: (item: JsonObject) => T,
  keyOfItem: (item: T) => string,
  rejected: Rejected[],
): T[] {
  const seen = new Set<string>()
  const accepted: T[] = []
  for (const raw of items) {
    const key = isPlainObject(raw) ? keyOf(raw[keyField]) : ''
    try {
      if (!isPlainObject(raw)) throw new ItemError('debe ser un objeto')
      const item = parse(raw)
      if (seen.has(keyOfItem(item))) throw new ItemError('repetido en la misma petición')
      seen.add(keyOfItem(item))
      accepted.push(item)
    } catch (error) {
      if (!(error instanceof ItemError)) throw error
      rejected.push({ kind, key, error: error.message })
    }
  }
  return accepted
}

export interface ParsedPush {
  push: SyncPush
  rejected: Rejected[]
}

/** Parses a `POST /api/sync` body: 400 for a malformed envelope, per-item rejections otherwise. */
export function parseSyncPush(body: unknown, now: number): ParsedPush {
  if (!isPlainObject(body)) throw new HttpError(400, 'El cuerpo debe ser un objeto JSON.')
  const since = parseSince(body.since)
  const rejected: Rejected[] = []
  const docs = parseItems(listOf(body, 'docs'), 'doc', 'key', item => parseDocWrite(item, now, { requireUpdatedAt: true }), d => d.key, rejected)
  const workouts = parseItems(listOf(body, 'workouts'), 'workout', 'id', item => parseWorkout(item, now), w => w.id, rejected)
  const bodyweight = parseItems(listOf(body, 'bodyweight'), 'bodyweight', 'd', item => parseBodyweight(item, now), b => b.d, rejected)
  const exWeights = parseItems(listOf(body, 'exWeights'), 'exWeight', 'id', item => parseExWeight(item, now), x => x.id, rejected)
  return { push: { since, docs, workouts, bodyweight, exWeights }, rejected }
}

