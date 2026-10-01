#!/usr/bin/env node
// End-to-end smoke test of a running openGym Worker, driven the way the app and Claude drive it.
//
//   node scripts/smoke.mjs --origin http://localhost:8787 --password '<OWNER_PASSWORD>' [--write]
//
// Read-only by default, so it is safe against production:
//   1. /api/health, device login, a pull-only sync, logout (the device is revoked again);
//   2. the MCP OAuth flow as a Claude Code-style client (dynamic registration with a loopback
//      redirect, PKCE, the consent page with the owner password, code → token exchange);
//   3. MCP initialize, tools/list, prompts/list, and the read tools get_overview and
//      search_exercises.
// With --write (local development only) it also proposes a plan through MCP, accepts it the way
// the app does (POST /api/proposals/:id/resolve with the plan and coach docs) and checks that
// get_overview reports the new plan.

import { createHash, randomBytes } from 'node:crypto'

const args = Object.fromEntries(
  process.argv.slice(2).reduce((pairs, arg, i, all) => {
    if (arg.startsWith('--')) pairs.push([arg.slice(2), all[i + 1]?.startsWith('--') || all[i + 1] === undefined ? true : all[i + 1]])
    return pairs
  }, []),
)
const ORIGIN = String(args.origin ?? 'http://localhost:8787').replace(/\/$/, '')
const PASSWORD = args.password
const WRITE = args.write === true
if (!PASSWORD || PASSWORD === true) {
  console.error('usage: node scripts/smoke.mjs --origin <url> --password <OWNER_PASSWORD> [--write]')
  process.exit(2)
}

let failures = 0
const ok = (label, detail = '') => console.log(`  ✓ ${label}${detail ? ` — ${detail}` : ''}`)
const fail = (label, detail) => { failures++; console.log(`  ✗ ${label} — ${detail}`) }
const check = (cond, label, detail) => (cond ? ok(label, typeof detail === 'string' ? detail : '') : fail(label, JSON.stringify(detail)))

async function json(res) {
  const text = await res.text()
  try { return JSON.parse(text) } catch { return { raw: text.slice(0, 300) } }
}

// ── 1. App API ─────────────────────────────────────────────────────────────────────────────────
console.log(`openGym smoke test against ${ORIGIN}${WRITE ? ' (with writes)' : ''}\n\nApp API`)
const health = await fetch(`${ORIGIN}/api/health`)
check(health.ok, 'GET /api/health', await json(health))

const tz = Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC'
const appHeaders = token => ({ 'content-type': 'application/json', 'x-timezone': tz, authorization: `Bearer ${token}` })
const login = await fetch(`${ORIGIN}/api/auth/login`, {
  method: 'POST',
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ password: PASSWORD, deviceName: 'smoke test' }),
})
const loginBody = await json(login)
check(login.ok && loginBody.token, 'POST /api/auth/login', login.ok ? 'device token issued' : loginBody)
const device = loginBody.token
if (!device) process.exit(1)

const pull = await json(await fetch(`${ORIGIN}/api/sync?since=0`, { headers: appHeaders(device) }))
check(typeof pull.seq === 'number' && typeof pull.epoch === 'number', 'GET /api/sync?since=0',
  `seq ${pull.seq}, ${pull.docs?.length ?? 0} docs, ${pull.workouts?.length ?? 0} workouts, ${pull.proposals?.length ?? 0} proposals`)

// ── 2. OAuth as a Claude client ────────────────────────────────────────────────────────────────
console.log('\nOAuth (Claude connector flow)')
const challenge = await fetch(`${ORIGIN}/mcp`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' })
const wwwAuth = challenge.headers.get('www-authenticate') ?? ''
check(challenge.status === 401 && wwwAuth.includes('resource_metadata'), 'POST /mcp without a token → 401 challenge', wwwAuth.slice(0, 120))

const resourceMeta = await json(await fetch(`${ORIGIN}/.well-known/oauth-protected-resource/mcp`))
check(resourceMeta.resource === `${ORIGIN}/mcp`, 'protected resource metadata', resourceMeta.resource)
const asMeta = await json(await fetch(`${ORIGIN}/.well-known/oauth-authorization-server`))
check(asMeta.issuer === ORIGIN && asMeta.registration_endpoint, 'authorization server metadata', asMeta.issuer)

const redirectUri = 'http://localhost:33418/callback'
const reg = await fetch(asMeta.registration_endpoint, {
  method: 'POST',
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ client_name: 'openGym smoke test', redirect_uris: [redirectUri], token_endpoint_auth_method: 'none', grant_types: ['authorization_code', 'refresh_token'], response_types: ['code'] }),
})
const client = await json(reg)
check(reg.status === 201 && client.client_id, 'dynamic client registration (loopback redirect)', client.client_id ? '' : client)

const foreign = await fetch(asMeta.registration_endpoint, {
  method: 'POST',
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ client_name: 'not claude', redirect_uris: ['https://evil.example/cb'], token_endpoint_auth_method: 'none' }),
})
check(foreign.status >= 400, 'registration with a foreign redirect is refused', `HTTP ${foreign.status}`)

const verifier = randomBytes(32).toString('base64url')
const codeChallenge = createHash('sha256').update(verifier).digest('base64url')
const state = randomBytes(8).toString('hex')
const authorizeUrl = `${asMeta.authorization_endpoint}?${new URLSearchParams({
  response_type: 'code', client_id: client.client_id, redirect_uri: redirectUri, scope: 'mcp', state,
  code_challenge: codeChallenge, code_challenge_method: 'S256', resource: `${ORIGIN}/mcp`,
})}`
const page = await fetch(authorizeUrl, { redirect: 'manual' })
const html = await page.text()
const handle = /name="handle" value="([^"]+)"/.exec(html)?.[1]
const cookies = (page.headers.getSetCookie?.() ?? []).map(c => c.split(';')[0]).join('; ')
check(page.status === 200 && handle, 'GET /authorize renders the consent page', `frame-ancestors ${/frame-ancestors 'none'/.test(page.headers.get('content-security-policy') ?? '') ? 'none' : 'MISSING'}`)

const consent = await fetch(authorizeUrl, {
  method: 'POST',
  redirect: 'manual',
  headers: { 'content-type': 'application/x-www-form-urlencoded', cookie: cookies, origin: ORIGIN },
  body: new URLSearchParams({ handle, password: PASSWORD, decision: 'approve' }),
})
const location = consent.headers.get('location') ?? ''
const code = location.startsWith(redirectUri) ? new URL(location).searchParams.get('code') : null
check(consent.status === 302 && code && new URL(location).searchParams.get('state') === state, 'POST /authorize with the owner password → code', location.slice(0, 60))

const tokenRes = await fetch(asMeta.token_endpoint, {
  method: 'POST',
  headers: { 'content-type': 'application/x-www-form-urlencoded' },
  body: new URLSearchParams({ grant_type: 'authorization_code', code, redirect_uri: redirectUri, client_id: client.client_id, code_verifier: verifier, resource: `${ORIGIN}/mcp` }),
})
const tokens = await json(tokenRes)
check(tokenRes.ok && tokens.access_token && tokens.refresh_token, 'code → access + refresh token (PKCE)', tokens.access_token ? `expires_in ${tokens.expires_in}` : tokens)
const access = tokens.access_token
if (!access) process.exit(1)

// ── 3. MCP ─────────────────────────────────────────────────────────────────────────────────────
console.log('\nMCP')
let rpcId = 0
async function mcp(method, params = {}) {
  const res = await fetch(`${ORIGIN}/mcp`, {
    method: 'POST',
    headers: { authorization: `Bearer ${access}`, 'content-type': 'application/json', accept: 'application/json, text/event-stream', 'mcp-protocol-version': '2025-06-18' },
    body: JSON.stringify({ jsonrpc: '2.0', id: ++rpcId, method, params }),
  })
  const text = await res.text()
  const payload = res.headers.get('content-type')?.includes('text/event-stream')
    ? text.split('\n').filter(l => l.startsWith('data:')).map(l => JSON.parse(l.slice(5))).find(m => m.id === rpcId)
    : JSON.parse(text)
  if (payload?.error) throw new Error(`${method}: ${JSON.stringify(payload.error)}`)
  return payload.result
}
const tool = async (name, args = {}) => {
  const result = await mcp('tools/call', { name, arguments: args })
  return { isError: result.isError === true, data: result.structuredContent ?? JSON.parse(result.content?.[0]?.text ?? '{}'), text: result.content?.[0]?.text }
}

const init = await mcp('initialize', { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'smoke', version: '1' } })
check(init.serverInfo?.name === 'opengym' && init.instructions, 'initialize', `${init.serverInfo?.name} ${init.serverInfo?.version}, protocol ${init.protocolVersion}`)
const { tools } = await mcp('tools/list')
const names = tools.map(t => t.name)
const expected = ['get_overview', 'get_training_review', 'get_exercise_history', 'list_workouts', 'get_body_weight', 'search_exercises', 'get_exercise', 'list_proposals', 'get_proposal', 'update_athlete_profile', 'propose_plan', 'propose_changes', 'report_no_change']
check(expected.every(n => names.includes(n)), 'tools/list', `${names.length} tools`)
const { prompts } = await mcp('prompts/list')
check(prompts?.length >= 3, 'prompts/list', prompts?.map(p => p.name).join(', '))

const overview = await tool('get_overview')
check(!overview.isError && overview.data.meta, 'get_overview', `unit ${overview.data.meta?.unit}, ${overview.data.plan?.routines?.length ?? 0} routines, ${overview.data.stats?.workoutsTotal ?? 0} workouts`)
const search = await tool('search_exercises', { query: 'bench press', limit: 5 })
const bench = search.data.exercises?.[0]
check(!search.isError && bench, 'search_exercises "bench press"', bench ? `${bench.id} ${bench.name}` : search.text)
const pecho = await tool('search_exercises', { query: 'pecho', limit: 3 })
check(!pecho.isError && pecho.data.exercises?.length, 'search_exercises "pecho" (Spanish label)', pecho.data.exercises?.map(e => e.name).join(', '))

// ── 4. Writes (local only) ─────────────────────────────────────────────────────────────────────
if (WRITE) {
  console.log('\nPropose → accept (as the app)')
  const squat = (await tool('search_exercises', { query: 'barbell full squat', limit: 1 })).data.exercises[0]
  const row = (await tool('search_exercises', { query: 'barbell bent over row', limit: 1 })).data.exercises[0]
  // A saved athlete profile fixes how many training days a plan must schedule.
  const athlete = overview.data.athlete ?? {}
  const days = athlete.savedAt != null && Number.isInteger(athlete.daysPerWeek) ? athlete.daysPerWeek : 2
  const week = Object.fromEntries([1, 3, 5, 2, 4, 6, 0].slice(0, days).map(d => [d, 'r1']))
  const proposed = await tool('propose_plan', {
    name: `Fuerza ${days} días`, summary: 'Sesiones de cuerpo completo para empezar.', basedOn: 'sin historial',
    week,
    routines: [{ id: 'r1', name: 'Cuerpo completo', emoji: 'barbell', prog: 'linear', why: 'Básicos compuestos.', ex: [
      { id: squat.id, sets: 3, mode: 'reps', reps: 5, why: 'Base de pierna.' },
      { id: bench.id, sets: 3, mode: 'reps', reps: 5, why: 'Empuje horizontal.' },
      { id: row.id, sets: 3, mode: 'reps', reps: 8, why: 'Tirón horizontal.' },
    ] }],
  })
  check(!proposed.isError && proposed.data.proposalId, 'propose_plan', proposed.data?.proposalId ?? proposed.text)
  if (proposed.isError) process.exit(1)

  const synced = await json(await fetch(`${ORIGIN}/api/sync?since=0`, { headers: appHeaders(device) }))
  const proposal = synced.proposals?.find(p => p.id === proposed.data.proposalId)
  check(proposal?.status === 'pending' && proposal.bundle, 'the app sees the pending proposal', proposal?.summary)
  const docOf = key => synced.docs.find(d => d.key === key) ?? { data: key === 'plan' ? { routines: [], week: {}, customEx: [] } : { log: [], snapshots: [], lastReview: null }, seq: 0 }
  const planDoc = docOf('plan'), coachDoc = docOf('coach')
  const rid = `r${Date.now().toString(36)}`
  const newPlan = {
    ...planDoc.data,
    routines: [...(planDoc.data.routines ?? []), { ...proposal.bundle.routines[0], id: rid, ex: proposal.bundle.routines[0].ex.map(({ why, name, ...e }) => e), why: undefined }],
    week: Object.fromEntries(Object.keys(week).map(d => [d, rid])),
  }
  const newCoach = { ...coachDoc.data, log: [...(coachDoc.data.log ?? []), { id: `l${Date.now()}`, kind: 'create', at: Date.now(), proposalId: proposal.id, summary: proposal.summary, routines: 1, iteration: 1 }] }
  const resolve = await fetch(`${ORIGIN}/api/proposals/${proposal.id}/resolve`, {
    method: 'POST', headers: appHeaders(device),
    body: JSON.stringify({ outcome: 'applied', accepted: ['plan'], rejected: [], stale: [], schedule: true,
      docs: [{ key: 'plan', data: newPlan, baseSeq: planDoc.seq }, { key: 'coach', data: newCoach, baseSeq: coachDoc.seq }] }),
  })
  check(resolve.ok, 'POST /api/proposals/:id/resolve (applied, plan + coach docs)', `HTTP ${resolve.status}`)
  const after = await tool('get_overview')
  check(after.data.plan?.routines?.some(r => r.id === rid) && after.data.recentDecisions?.length, 'get_overview reflects the accepted plan', `${after.data.plan?.routines?.length} routines`)
}

await fetch(`${ORIGIN}/api/auth/logout`, { method: 'POST', headers: appHeaders(device), body: '{}' })
console.log(`\n${failures ? `${failures} check(s) failed` : 'All checks passed'}`)
process.exit(failures ? 1 : 0)
