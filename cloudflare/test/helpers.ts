/**
 * Reusable test helpers for the Worker: HTTP calls against the real entrypoint, device login,
 * database seeding, a realistic openGym backup, and the full OAuth flow for /mcp tests.
 */
import { applyD1Migrations, reset } from 'cloudflare:test'
import { env, exports } from 'cloudflare:workers'
import { bumpSeq, docPutStatement, getCounters, SEQ, type DocKey } from '../src/db'
import type { JsonObject } from '../src/lib/json'

/** Must match the bindings in vitest.config.ts. */
export const ORIGIN = 'https://opengym.test'
export const PASSWORD = 'correct horse battery staple'
export const APP_ORIGIN = 'https://app.opengym.test'
export const CLAUDE_CALLBACK = 'https://claude.ai/api/mcp/auth_callback'

/** Empties D1 and KV and re-applies the migrations (storage is shared by the tests of one file). */
export async function resetDatabase(): Promise<void> {
  await reset()
  await applyD1Migrations(env.DB, env.TEST_MIGRATIONS)
}

/** Sends a request to the Worker's default export, with the Host header a real request carries. */
export function fetchWorker(input: string, init?: RequestInit): Promise<Response> {
  const url = new URL(input, ORIGIN)
  const headers = new Headers(init?.headers)
  if (!headers.has('Host')) headers.set('Host', url.host)
  return exports.default.fetch(new Request(url, { ...init, headers }))
}

export interface ApiOptions {
  method?: 'GET' | 'POST' | 'OPTIONS'
  token?: string
  body?: unknown
  headers?: Record<string, string>
}

export interface ApiResult<T = any> {
  status: number
  body: T
  headers: Headers
}

/** Calls /api/* with a JSON body and optional device token; parses the JSON response. */
export async function api<T = any>(path: string, options: ApiOptions = {}): Promise<ApiResult<T>> {
  const headers = new Headers(options.headers)
  if (options.token) headers.set('Authorization', `Bearer ${options.token}`)
  let body: string | undefined
  if (options.body !== undefined) {
    body = JSON.stringify(options.body)
    if (!headers.has('Content-Type')) headers.set('Content-Type', 'application/json')
  }
  const method = options.method ?? (options.body !== undefined ? 'POST' : 'GET')
  const response = await fetchWorker(path, { method, headers, body })
  const text = await response.text()
  return { status: response.status, body: text ? JSON.parse(text) : null, headers: response.headers }
}

export interface LoggedInDevice {
  token: string
  deviceId: string
}

/** Logs a device in with the owner password. */
export async function loginDevice(deviceName = 'Test device', headers: Record<string, string> = {}): Promise<LoggedInDevice> {
  const result = await api<LoggedInDevice>('/api/auth/login', { body: { password: PASSWORD, deviceName }, headers })
  if (result.status !== 200) throw new Error(`login failed: ${result.status} ${JSON.stringify(result.body)}`)
  return result.body
}

/** Writes a doc directly (new seq), bypassing compare-and-swap. Returns the doc's seq. */
export async function seedDoc(key: DocKey, data: JsonObject, updatedAt = Date.now()): Promise<number> {
  await env.DB.batch([bumpSeq(env.DB), docPutStatement(env.DB, { key, data, updatedAt })])
  return (await getCounters(env.DB)).seq
}

/** Inserts finished workouts directly, one seq for all of them. */
export async function seedWorkouts(workouts: readonly JsonObject[], updatedAt = Date.now()): Promise<number> {
  await env.DB.batch([
    bumpSeq(env.DB),
    ...workouts.map(w =>
      env.DB.prepare(
        `INSERT INTO workouts (id, d, start, routine_id, data, deleted, updated_at, seq) VALUES (?, ?, ?, ?, ?, 0, ?, ${SEQ})`,
      ).bind(w.id, w.d, w.start ?? null, w.routineId ?? null, JSON.stringify(w), updatedAt),
    ),
  ])
  return (await getCounters(env.DB)).seq
}

/** Inserts body-weight entries directly, one seq for all of them. */
export async function seedBodyweight(entries: readonly { d: string; w: number; t?: number }[], updatedAt = Date.now()): Promise<number> {
  await env.DB.batch([
    bumpSeq(env.DB),
    ...entries.map(b =>
      env.DB.prepare(`INSERT INTO bodyweight (d, w, t, deleted, updated_at, seq) VALUES (?, ?, ?, 0, ?, ${SEQ})`).bind(b.d, b.w, b.t ?? null, updatedAt),
    ),
  ])
  return (await getCounters(env.DB)).seq
}

/** A workout in the shape the port writes (targets carry `id` and `mode`). */
export function sampleWorkout(id: string, d: string, overrides: JsonObject = {}): JsonObject {
  const start = Date.parse(`${d}T18:07:00Z`)
  return {
    id,
    d,
    start,
    end: start + 57 * 60_000,
    routineId: 'r-push',
    name: 'Empuje',
    bw: 78.7,
    entries: [
      {
        id: '0025',
        topW: 75,
        target: { id: '0025', sets: 3, mode: 'reps', reps: 8, weight: 72.5 },
        sets: [
          { w: 75, r: 8, done: true, rir: 2 },
          { w: 75, r: 8, done: true, rir: 1 },
          { w: 75, r: 7, done: true, rir: 0 },
        ],
      },
    ],
    prs: [],
    vol: 1725,
    ...overrides,
  }
}

/**
 * A realistic openGym backup `S` (specs/data-model.md §1.11), with the quirks an importer must
 * handle: targets without `id`/`mode`, a workout without `start`, a plan-file custom exercise
 * without `tg`/`eq`/`custom`, and a coach namespace with consent and cadence.
 */
export function sampleOpenGymState(): JsonObject {
  return {
    unit: 'kg', restSec: 90, sound: true, keepAwake: true, lang: 'en',
    theme: 'dark', accent: 'lime', body: 'male', gifSize: 'full',
    effort: 'rir', showRir: true, targetW: 77,
    reminder: { on: true, time: '07:30', tz: 'America/Puerto_Rico' },
    futureSetting: { kept: true },
    bodyweight: [
      { d: '2026-09-21', w: 79.2, t: 1790000000000 },
      { d: '2026-09-28', w: 78.7, t: 1790580600000 },
    ],
    routines: [
      {
        id: 'muo979oo50vo1', name: 'Push Day', emoji: 'barbell', prog: 'linear',
        ex: [
          { id: '0025', sets: 4, mode: 'reps', reps: 8, weight: 60, inc: 2.5 },
          { id: '0334', sets: 3, mode: 'reps', reps: 12, weight: 10, sg: 'sgmuo9a1b2c3d' },
          { id: '0241', sets: 3, mode: 'reps', reps: 12, weight: 25, sg: 'sgmuo9a1b2c3d' },
          { id: '0001', sets: 3, mode: 'time', sec: 45, weight: 0, prog: 'time' },
          { id: 'cmuo9zz12abc', sets: 3, mode: 'reps', reps: 10, weight: 0, prog: 'double', repsMin: 8 },
          { id: '0685', sets: 1, min: 20, speed: 8 },
        ],
      },
      { id: 'muo979oohb54d', name: 'Pull Day', emoji: 'pullup', ex: [{ id: '2330', sets: 4, reps: 10, weight: 0 }] },
    ],
    week: { '1': 'muo979oo50vo1', '3': 'muo979oohb54d' },
    dayPlan: { '2026-09-30': 'muo979oo50vo1', '2026-10-02': 'rest' },
    exWeights: { '0025': { w: 75, d: '2026-09-28' }, '0251': { w: 0, d: '2026-09-21' } },
    workouts: [
      {
        id: 'muo979osyicjp', d: '2026-09-28', start: 1790618820000, end: 1790622240000,
        routineId: 'muo979oo50vo1', name: 'Push Day', bw: 78.7,
        entries: [
          {
            id: '0025', topW: 75,
            target: { id: '0025', sets: 4, mode: 'reps', reps: 8, weight: 60 },
            sets: [{ w: 75, r: 8, done: true, rir: 3 }, { w: 75, r: 7, done: true, rir: 0.5 }, { w: 75, r: 8, done: false }],
          },
          { id: '0001', topW: null, target: { sets: 3, sec: 45, weight: 0 }, sets: [{ sec: 38, w: 0, done: true }] },
          { id: '0685', topW: null, target: { sets: 1, min: 20, speed: 8 }, sets: [{ min: 20, speed: 8, done: true }] },
          { id: 'kx2plan0cust', topW: null, target: { sets: 3, reps: 10 }, sets: [{ w: 0, r: 10, done: true }] },
        ],
        prs: ['0025'], vol: 1125, rating: 'right', note: 'Felt strong',
      },
      {
        id: 'iwmuo1imported', d: '2026-09-21', end: 1790000000000, routineId: null, name: 'Imported',
        entries: [{ id: '0025', sets: [{ w: 72.5, r: 8, done: true }], topW: 72.5 }],
        prs: [], vol: 580,
      },
    ],
    active: { id: 'activeone', d: '2026-09-30', start: 1790700000000, routineId: null, name: 'Freestyle', bw: null, cur: 0, entries: [] },
    customEx: [
      { id: 'cmuo9zz12abc', n: 'Nordic curl', bp: 'upper legs', desc: '', tg: '', eq: 'custom', custom: true },
      { id: 'kx2plan0cust', n: 'Sled sprint', bp: 'cardio', desc: 'Outdoor sled' },
    ],
    coach: {
      consent: { agreedAt: '2026-09-01T10:00:00.000Z', version: 1 },
      profile: {
        goal: 'strength', experience: 'regular', daysPerWeek: 3, preferredDays: [1, 3, 5], sessionMin: 60,
        equipment: ['barbell', 'dumbbell'], limitations: 'Left shoulder', likes: '', dislikes: '', notes: '',
      },
      cadence: { weekly: { day: 0, time: '18:00' } },
      lastReview: { at: 1790500000000 },
      log: [{ at: 1790500000000, kind: 'review', outcome: 'applied', accepted: 1, rejected: 0 }],
      snapshots: [],
    },
    _ts: 1790622241000,
  }
}

// --- OAuth + MCP -----------------------------------------------------------------------------

function base64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

export async function pkcePair(): Promise<{ verifier: string; challenge: string }> {
  const verifier = base64url(crypto.getRandomValues(new Uint8Array(32)))
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier)))
  return { verifier, challenge: base64url(digest) }
}

/** Registers a public client through dynamic client registration. */
export async function registerClient(redirectUris: string[] = [CLAUDE_CALLBACK]): Promise<Response> {
  return fetchWorker('/register', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      client_name: 'Claude',
      redirect_uris: redirectUris,
      token_endpoint_auth_method: 'none',
      grant_types: ['authorization_code', 'refresh_token'],
      response_types: ['code'],
    }),
  })
}

export interface AuthorizeSession {
  clientId: string
  verifier: string
  state: string
  authorizeUrl: string
}

export async function startAuthorization(clientId?: string): Promise<AuthorizeSession> {
  const id = clientId ?? ((await (await registerClient()).json()) as { client_id: string }).client_id
  const { verifier, challenge } = await pkcePair()
  const state = crypto.randomUUID()
  const params = new URLSearchParams({
    response_type: 'code',
    client_id: id,
    redirect_uri: CLAUDE_CALLBACK,
    scope: 'mcp',
    state,
    code_challenge: challenge,
    code_challenge_method: 'S256',
    resource: `${ORIGIN}/mcp`,
  })
  return { clientId: id, verifier, state, authorizeUrl: `${ORIGIN}/authorize?${params}` }
}

/** The consent handle and the browser-binding cookie of a rendered consent page. */
export async function consentForm(page: Response): Promise<{ handle: string; cookie: string }> {
  const html = await page.text()
  const handle = /name="handle" value="([^"]+)"/.exec(html)?.[1]
  const cookie = (page.headers.get('Set-Cookie') ?? '').split(';')[0]!
  if (!handle || !cookie) throw new Error('consent page without handle or cookie')
  return { handle, cookie }
}

export function submitConsent(authorizeUrl: string, form: Record<string, string>, cookie: string): Promise<Response> {
  return fetchWorker(authorizeUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded', Cookie: cookie },
    body: new URLSearchParams(form).toString(),
    redirect: 'manual',
  })
}

export async function exchangeCode(session: AuthorizeSession, code: string): Promise<Response> {
  return fetchWorker('/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'authorization_code',
      code,
      redirect_uri: CLAUDE_CALLBACK,
      client_id: session.clientId,
      code_verifier: session.verifier,
      resource: `${ORIGIN}/mcp`,
    }).toString(),
  })
}

/** Runs the whole consent flow (register, authorize, approve, token) and returns an MCP access token. */
export async function getAccessToken(): Promise<string> {
  const session = await startAuthorization()
  const { handle, cookie } = await consentForm(await fetchWorker(session.authorizeUrl))
  const approved = await submitConsent(session.authorizeUrl, { handle, password: PASSWORD, decision: 'approve' }, cookie)
  const code = new URL(approved.headers.get('Location') ?? '').searchParams.get('code')
  if (!code) throw new Error(`no authorization code: ${approved.status}`)
  const tokens = (await (await exchangeCode(session, code)).json()) as { access_token?: string }
  if (!tokens.access_token) throw new Error('token exchange failed')
  return tokens.access_token
}

export const MCP_PROTOCOL_VERSION = '2025-06-18'

/**
 * Sends one JSON-RPC request to /mcp (the stateless 2025 lane) and returns the HTTP status and the
 * parsed JSON-RPC message, whether it came back as JSON or as a server-sent event.
 */
export async function mcpCall(token: string | null, method: string, params: JsonObject = {}, id = 1): Promise<{ status: number; message: any; headers: Headers }> {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    Accept: 'application/json, text/event-stream',
    'MCP-Protocol-Version': MCP_PROTOCOL_VERSION,
  }
  if (token) headers.Authorization = `Bearer ${token}`
  const response = await fetchWorker('/mcp', { method: 'POST', headers, body: JSON.stringify({ jsonrpc: '2.0', id, method, params }) })
  const text = await response.text()
  let message: unknown = null
  if (text) {
    const data = text
      .split('\n')
      .filter(line => line.startsWith('data:'))
      .map(line => line.slice(5).trim())
    message = JSON.parse(data.length > 0 ? data.join('') : text)
  }
  return { status: response.status, message, headers: response.headers }
}

/** `initialize` params for the 2025 lane. */
export const MCP_INITIALIZE = {
  protocolVersion: MCP_PROTOCOL_VERSION,
  capabilities: {},
  clientInfo: { name: 'opengym-tests', version: '1.0.0' },
}
