import { parseJsonObject, type JsonObject } from '../lib/json'
import { SEQ } from './seq'

export const DOC_KEYS = ['settings', 'plan', 'schedule', 'athlete', 'coach'] as const
export type DocKey = (typeof DOC_KEYS)[number]

export function isDocKey(value: unknown): value is DocKey {
  return typeof value === 'string' && (DOC_KEYS as readonly string[]).includes(value)
}

/** A doc as stored, or its defaults with `seq: 0, updatedAt: 0` when it was never written. */
export interface DocState {
  key: DocKey
  data: JsonObject
  updatedAt: number
  seq: number
}

export type Docs = Record<DocKey, DocState>

/** Default doc contents (contract §2.1). Each call returns fresh objects. */
export function defaultDocData(key: DocKey): JsonObject {
  switch (key) {
    case 'settings':
      return {
        unit: 'kg', restSec: 90, sound: true, keepAwake: true, theme: 'dark', accent: 'lime', body: 'male',
        gifSize: 'full', effort: null, targetW: null, lang: 'es', reminder: { on: false, time: '08:00', tz: null },
      }
    case 'plan':
      return { routines: [], week: {}, customEx: [] }
    case 'schedule':
      return { dayPlan: {} }
    case 'athlete':
      return {
        goal: null, experience: null, daysPerWeek: 3, preferredDays: [1, 3, 5], sessionMin: 45, equipment: [],
        limitations: '', likes: '', dislikes: '', notes: '', savedAt: null, updatedBy: null,
      }
    case 'coach':
      return { log: [], snapshots: [], lastReview: null }
  }
}

export interface DocRow {
  key: DocKey
  data: string
  updated_at: number
  seq: number
}

export const DOC_COLUMNS = 'key, data, updated_at, seq'

export function toDocState(row: DocRow): DocState {
  return { key: row.key, data: parseJsonObject(row.data), updatedAt: row.updated_at, seq: row.seq }
}

function missingDoc(key: DocKey): DocState {
  return { key, data: defaultDocData(key), updatedAt: 0, seq: 0 }
}

/** Every doc, defaults filled in for the ones never written. */
export async function getDocs(db: D1Database): Promise<Docs> {
  const { results } = await db.prepare(`SELECT ${DOC_COLUMNS} FROM docs`).all<DocRow>()
  return docsFromRows(results)
}

export function docsFromRows(rows: readonly DocRow[]): Docs {
  const docs = Object.fromEntries(DOC_KEYS.map(key => [key, missingDoc(key)])) as Docs
  for (const row of rows) if (isDocKey(row.key)) docs[row.key] = toDocState(row)
  return docs
}

export async function getDoc(db: D1Database, key: DocKey): Promise<DocState> {
  const row = await db.prepare(`SELECT ${DOC_COLUMNS} FROM docs WHERE key = ?`).bind(key).first<DocRow>()
  return row ? toDocState(row) : missingDoc(key)
}

export function selectDocs(db: D1Database, keys: readonly DocKey[]): D1PreparedStatement {
  return db.prepare(`SELECT ${DOC_COLUMNS} FROM docs WHERE key IN (SELECT value FROM json_each(?))`).bind(JSON.stringify(keys))
}

export interface DocWrite {
  key: DocKey
  data: JsonObject
  updatedAt: number
}

export interface DocCasWrite extends DocWrite {
  /** The `seq` of the version the write was derived from; 0 for a doc never written. */
  baseSeq: number
}

/**
 * Compare-and-swap write (contract §3.2): applies only when the stored doc's `seq` equals
 * `baseSeq`, or the doc does not exist and `baseSeq` is 0. `meta.changes` is 0 when it did not
 * apply. Must run after `bumpSeq` in the same batch.
 */
export function docCasStatement(db: D1Database, write: DocCasWrite): D1PreparedStatement {
  return db
    .prepare(
      `INSERT INTO docs (key, data, updated_at, seq)
       SELECT ?1, ?2, ?3, ${SEQ}
       WHERE ?4 = 0 OR EXISTS (SELECT 1 FROM docs WHERE key = ?1)
       ON CONFLICT(key) DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at, seq = excluded.seq
       WHERE docs.seq = ?4`,
    )
    .bind(write.key, JSON.stringify(write.data), write.updatedAt, write.baseSeq)
}

/** Unconditional write (import, reset, or after guards). Must run after `bumpSeq` in the same batch. */
export function docPutStatement(db: D1Database, write: DocWrite): D1PreparedStatement {
  return db
    .prepare(
      `INSERT INTO docs (key, data, updated_at, seq) VALUES (?1, ?2, ?3, ${SEQ})
       ON CONFLICT(key) DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at, seq = excluded.seq`,
    )
    .bind(write.key, JSON.stringify(write.data), write.updatedAt)
}

/** Guard condition (for `guard()`): true when the doc's current version is not `baseSeq`. */
export function docChangedCondition(key: DocKey, baseSeq: number): [string, ...unknown[]] {
  return ['coalesce((SELECT seq FROM docs WHERE key = ?), 0) IS NOT ?', key, baseSeq]
}
