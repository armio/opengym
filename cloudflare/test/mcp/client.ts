/**
 * Test helpers for the MCP server: an authenticated JSON-RPC client over the real /mcp route, and
 * seeding for the rows test/helpers.ts does not cover.
 */
import { env } from 'cloudflare:workers'
import { bumpSeq, SEQ } from '../../src/db'
import type { JsonObject } from '../../src/lib/json'
import { localDate } from '../../src/lib/time'
import { addDays } from '../../src/engine'
import { getAccessToken, loginDevice, mcpCall, resetDatabase } from '../helpers'

export const OWNER_TZ = 'Europe/Madrid'

export interface ToolCall<T = any> {
  isError: boolean
  text: string
  data: T
}

export class McpClient {
  private nextId = 1

  constructor(readonly token: string) {}

  static async connect(): Promise<McpClient> {
    return new McpClient(await getAccessToken())
  }

  /** One JSON-RPC request; throws on HTTP or JSON-RPC errors. */
  async request<T = any>(method: string, params: JsonObject = {}): Promise<T> {
    const { status, message } = await mcpCall(this.token, method, params, this.nextId++)
    if (status !== 200) throw new Error(`${method}: HTTP ${status}`)
    if (message.error) throw new Error(`${method}: ${JSON.stringify(message.error)}`)
    return message.result as T
  }

  async call<T = any>(name: string, args: JsonObject = {}): Promise<ToolCall<T>> {
    const result = await this.request('tools/call', { name, arguments: args })
    const text = result.content?.find((c: { type: string }) => c.type === 'text')?.text ?? ''
    return { isError: result.isError ?? false, text, data: result.structuredContent }
  }

  /** Calls a tool that must succeed and returns its structured result. */
  async ok<T = any>(name: string, args: JsonObject = {}): Promise<T> {
    const result = await this.call<T>(name, args)
    if (result.isError) throw new Error(`${name} failed: ${result.text}`)
    return result.data
  }
}

/**
 * A fresh database, a device logged in from the owner's zone (which fixes "today" for the MCP
 * tools) and an MCP client.
 */
export async function freshOwner(): Promise<{ client: McpClient; device: string; today: string }> {
  await resetDatabase()
  const { token } = await loginDevice('Móvil', { 'X-Timezone': OWNER_TZ })
  return { client: await McpClient.connect(), device: token, today: localDate(Date.now(), OWNER_TZ) }
}

/** `today` shifted by `days`. */
export const daysFrom = (today: string, days: number) => addDays(today, days)

export async function seedExWeights(weights: Record<string, { w: number; d: string }>): Promise<void> {
  await env.DB.batch([
    bumpSeq(env.DB),
    ...Object.entries(weights).map(([id, { w, d }]) =>
      env.DB.prepare(`INSERT INTO ex_weights (ex_id, w, d, deleted, updated_at, seq) VALUES (?, ?, ?, 0, ?, ${SEQ})`).bind(id, w, d, Date.now()),
    ),
  ])
}

/** Uses up `count` slots of an MCP write limit, as if the calls happened a second ago. */
export async function fillLimit(kind: string, count: number): Promise<void> {
  const at = Date.now() - 1000
  await env.DB.batch(Array.from({ length: count }, () => env.DB.prepare('INSERT INTO limits_log (kind, at) VALUES (?, ?)').bind(kind, at)))
}

/** A reps-mode entry with its target, one set per `reps` value, all at `w`. */
export function repsEntry(id: string, w: number, reps: number[], target: JsonObject = {}, extra: JsonObject = {}): JsonObject {
  return {
    id,
    topW: w,
    target: { id, sets: reps.length, mode: 'reps', reps: 8, ...target },
    sets: reps.map(r => ({ w, r, done: true, ...extra })),
  }
}

/** A finished workout on `d` starting at 18:00 UTC. */
export function workout(id: string, d: string, entries: JsonObject[], minutes = 60, extra: JsonObject = {}): JsonObject {
  const start = Date.parse(`${d}T18:00:00Z`)
  return { id, d, start, end: start + minutes * 60_000, routineId: 'r1', name: 'Torso', entries, prs: [], ...extra }
}
