import { env } from 'cloudflare:workers'
import { beforeEach, describe, expect, it } from 'vitest'
import { createProposal, getCounters, getDoc, getProposal, listProposals, PROPOSAL_RATE_LIMIT, ProposalRateLimitError } from '../src/db'
import { api, loginDevice, resetDatabase, seedDoc } from './helpers'

let token: string

beforeEach(async () => {
  await resetDatabase()
  token = (await loginDevice()).token
})

const changesBody = { evidence: null, changes: [{ id: 'c1', type: 'sets' }, { id: 'c2', type: 'reps' }], notes: [] }

async function seedPlanAndCoach() {
  const planSeq = await seedDoc('plan', { routines: [{ id: 'r1', name: 'Empuje', emoji: 'barbell', ex: [] }], week: {}, customEx: [] })
  const coachSeq = await seedDoc('coach', { log: [], snapshots: [], lastReview: null })
  return { planSeq, coachSeq }
}

describe('createProposal', () => {
  it('stores a pending proposal with its unit, expiry and body in the DTO', async () => {
    await seedDoc('settings', { unit: 'lb' })
    const now = Date.now()
    const proposal = await createProposal(env.DB, { kind: 'changes', summary: 'Más series', body: changesBody, planHash: 'f784c8ca82c205eb' }, now)
    expect(proposal).toEqual({
      id: expect.stringMatching(/^p[0-9a-f]{16}$/),
      kind: 'changes',
      status: 'pending',
      createdAt: now,
      expiresAt: now + 14 * 86_400_000,
      planHash: 'f784c8ca82c205eb',
      unit: 'lb',
      iteration: 1,
      summary: 'Más series',
      resolution: null,
      resolvedAt: null,
      revertedAt: null,
      seq: (await getCounters(env.DB)).seq,
      ...changesBody,
    })
  })

  it('supersedes pending proposals of the same kind only; nochange supersedes nothing', async () => {
    const plan = await createProposal(env.DB, { kind: 'plan', summary: 'A', body: { bundle: {} } })
    const changes = await createProposal(env.DB, { kind: 'changes', summary: 'B', body: changesBody })
    const note = await createProposal(env.DB, { kind: 'nochange', summary: 'C', body: { reading: 'Bien.' } })
    const plan2 = await createProposal(env.DB, { kind: 'plan', summary: 'D', body: { bundle: {} }, iteration: 2 })
    const status = async (id: string) => (await getProposal(env.DB, id))?.status
    expect(await status(plan.id)).toBe('superseded')
    expect(await status(changes.id)).toBe('pending')
    expect(await status(note.id)).toBe('pending')
    expect(plan2.iteration).toBe(2)
    expect((await listProposals(env.DB, { status: 'pending' })).map(p => p.id)).toEqual([plan2.id, note.id, changes.id])
  })

  it('refuses the 31st proposal in 24 hours without writing anything', async () => {
    const now = Date.now()
    await env.DB.batch(
      Array.from({ length: PROPOSAL_RATE_LIMIT.max }, () => env.DB.prepare("INSERT INTO limits_log (kind, at) VALUES ('propose', ?)").bind(now - 1000)),
    )
    const before = await getCounters(env.DB)
    await expect(createProposal(env.DB, { kind: 'nochange', summary: 'x', body: { reading: 'x' } }, now)).rejects.toBeInstanceOf(ProposalRateLimitError)
    expect(await getCounters(env.DB)).toEqual(before)
    expect(await listProposals(env.DB)).toEqual([])
  })
})

describe('POST /api/proposals/:id/resolve', () => {
  it('applies a proposal atomically with its doc writes', async () => {
    const { planSeq, coachSeq } = await seedPlanAndCoach()
    const proposal = await createProposal(env.DB, { kind: 'changes', summary: 'Más series', body: changesBody })
    const newPlan = { routines: [{ id: 'r1', name: 'Empuje', emoji: 'barbell', ex: [{ id: '0025', sets: 4 }] }], week: {}, customEx: [] }
    const newCoach = { log: [{ kind: 'review', outcome: 'applied' }], snapshots: [{ at: 1 }], lastReview: { at: 1 } }
    const result = await api(`/api/proposals/${proposal.id}/resolve`, {
      token,
      body: {
        outcome: 'applied',
        accepted: ['c1'],
        rejected: ['c2'],
        stale: [],
        docs: [
          { key: 'plan', data: newPlan, baseSeq: planSeq },
          { key: 'coach', data: newCoach, baseSeq: coachSeq },
        ],
      },
    })
    expect(result.status).toBe(200)
    const seq = (await getCounters(env.DB)).seq
    expect(result.body.proposal).toEqual(
      expect.objectContaining({
        status: 'applied',
        resolution: { outcome: 'applied', accepted: ['c1'], rejected: ['c2'], stale: [] },
        resolvedAt: expect.any(Number),
        seq,
      }),
    )
    expect(result.body.docs).toEqual(
      expect.arrayContaining([
        { key: 'plan', data: newPlan, updatedAt: expect.any(Number), seq },
        { key: 'coach', data: newCoach, updatedAt: expect.any(Number), seq },
      ]),
    )
    expect((await getDoc(env.DB, 'plan')).data).toEqual(newPlan)
  })

  it('dismisses with a coach-only write and answers an identical retry with the stored state', async () => {
    const { coachSeq } = await seedPlanAndCoach()
    const proposal = await createProposal(env.DB, { kind: 'changes', summary: 'x', body: changesBody })
    const body = {
      outcome: 'dismissed',
      accepted: [],
      rejected: ['c1', 'c2'],
      stale: [],
      docs: [{ key: 'coach', data: { log: [{ outcome: 'dismissed' }], snapshots: [], lastReview: { at: 2 } }, baseSeq: coachSeq }],
    }
    const first = await api(`/api/proposals/${proposal.id}/resolve`, { token, body })
    expect(first.status).toBe(200)
    const seqAfter = (await getCounters(env.DB)).seq
    // The retry's baseSeq is stale now, but the proposal already carries this exact resolution.
    const retry = await api(`/api/proposals/${proposal.id}/resolve`, { token, body: { ...body, rejected: ['c2', 'c1'] } })
    expect(retry.status).toBe(200)
    expect(retry.body.proposal).toEqual(first.body.proposal)
    expect(retry.body.docs).toEqual(first.body.docs)
    expect((await getCounters(env.DB)).seq).toBe(seqAfter)
  })

  it('answers 409 with the proposal when it was resolved differently', async () => {
    await seedPlanAndCoach()
    const proposal = await createProposal(env.DB, { kind: 'changes', summary: 'x', body: changesBody })
    await api(`/api/proposals/${proposal.id}/resolve`, { token, body: { outcome: 'dismissed', rejected: ['c1', 'c2'] } })
    const other = await api(`/api/proposals/${proposal.id}/resolve`, { token, body: { outcome: 'applied', accepted: ['c1'], rejected: ['c2'] } })
    expect(other.status).toBe(409)
    expect(other.body).toEqual({ error: expect.any(String), proposal: expect.objectContaining({ id: proposal.id, status: 'dismissed' }) })
  })

  it('answers 409 without partial writes when a doc changed since the draft', async () => {
    const { planSeq, coachSeq } = await seedPlanAndCoach()
    const proposal = await createProposal(env.DB, { kind: 'changes', summary: 'x', body: changesBody })
    const movedPlanSeq = await seedDoc('plan', { routines: [], week: { '1': 'r9' }, customEx: [] })
    const before = await getCounters(env.DB)
    const result = await api(`/api/proposals/${proposal.id}/resolve`, {
      token,
      body: {
        outcome: 'applied',
        accepted: ['c1'],
        docs: [
          { key: 'coach', data: { log: ['should not be written'] }, baseSeq: coachSeq },
          { key: 'plan', data: { routines: ['should not be written'] }, baseSeq: planSeq },
        ],
      },
    })
    expect(result.status).toBe(409)
    expect(result.body.proposal).toEqual(expect.objectContaining({ id: proposal.id, status: 'pending' }))
    expect(await getCounters(env.DB)).toEqual(before)
    expect((await getDoc(env.DB, 'coach')).seq).toBe(coachSeq)
    expect((await getDoc(env.DB, 'plan')).seq).toBe(movedPlanSeq)
    expect((await getProposal(env.DB, proposal.id))?.status).toBe('pending')
  })

  it('refuses a proposal past its expiry even before the cron flipped it, and expires it', async () => {
    const created = Date.now() - 15 * 24 * 3600 * 1000
    const proposal = await createProposal(env.DB, { kind: 'nochange', summary: 'Vieja', body: { reading: 'x' } }, created)
    const result = await api(`/api/proposals/${proposal.id}/resolve`, { token, body: { outcome: 'dismissed', accepted: [], rejected: [], stale: [], docs: [] } })
    expect(result.status).toBe(409)
    expect(result.body.proposal.status).toBe('expired')
    expect((await getProposal(env.DB, proposal.id))?.status).toBe('expired')
  })

  it('validates the request', async () => {
    const proposal = await createProposal(env.DB, { kind: 'plan', summary: 'x', body: { bundle: {} } })
    const url = `/api/proposals/${proposal.id}/resolve`
    expect((await api(url, { token, body: { outcome: 'maybe' } })).status).toBe(400)
    expect((await api(url, { token, body: { outcome: 'applied', accepted: [1] } })).status).toBe(400)
    expect((await api(url, { token, body: { outcome: 'applied', docs: [{ key: 'settings', data: {}, baseSeq: 0 }] } })).status).toBe(400)
    expect((await api(url, { token, body: { outcome: 'applied', docs: [{ key: 'plan', data: [], baseSeq: 0 }] } })).status).toBe(400)
    expect((await api('/api/proposals/pmissing/resolve', { token, body: { outcome: 'dismissed' } })).status).toBe(404)
  })

  it('records the schedule choice of a plan proposal', async () => {
    const { planSeq } = await seedPlanAndCoach()
    const proposal = await createProposal(env.DB, { kind: 'plan', summary: 'Plan nuevo', body: { bundle: { routines: [] } } })
    const result = await api(`/api/proposals/${proposal.id}/resolve`, {
      token,
      body: { outcome: 'applied', accepted: ['plan'], schedule: false, docs: [{ key: 'plan', data: { routines: [], week: {}, customEx: [] }, baseSeq: planSeq }] },
    })
    expect(result.body.proposal.resolution).toEqual({ outcome: 'applied', accepted: ['plan'], rejected: [], stale: [], schedule: false })
  })
})

describe('POST /api/proposals/:id/revert', () => {
  async function appliedProposal() {
    const { planSeq, coachSeq } = await seedPlanAndCoach()
    const proposal = await createProposal(env.DB, { kind: 'changes', summary: 'x', body: changesBody })
    const applied = await api(`/api/proposals/${proposal.id}/resolve`, {
      token,
      body: {
        outcome: 'applied',
        accepted: ['c1', 'c2'],
        docs: [
          { key: 'plan', data: { routines: [], week: {}, customEx: [] }, baseSeq: planSeq },
          { key: 'coach', data: { log: [], snapshots: [{ at: 1 }], lastReview: null }, baseSeq: coachSeq },
        ],
      },
    })
    const docs = Object.fromEntries(applied.body.docs.map((d: any) => [d.key, d.seq]))
    return { proposal, docs }
  }

  it('restores the docs and sets revertedAt atomically; a retry answers with the stored state', async () => {
    const { proposal, docs } = await appliedProposal()
    const body = {
      docs: [
        { key: 'plan', data: { routines: [{ id: 'r1', name: 'Empuje', emoji: 'barbell', ex: [] }], week: {}, customEx: [] }, baseSeq: docs.plan },
        { key: 'coach', data: { log: [{ kind: 'revert', snapshotAt: 1 }], snapshots: [], lastReview: null }, baseSeq: docs.coach },
      ],
    }
    const reverted = await api(`/api/proposals/${proposal.id}/revert`, { token, body })
    expect(reverted.status).toBe(200)
    expect(reverted.body.proposal).toEqual(expect.objectContaining({ status: 'applied', revertedAt: expect.any(Number) }))
    expect((await getDoc(env.DB, 'plan')).data.routines).toHaveLength(1)

    const retry = await api(`/api/proposals/${proposal.id}/revert`, { token, body })
    expect(retry.status).toBe(200)
    expect(retry.body.proposal.revertedAt).toBe(reverted.body.proposal.revertedAt)
  })

  it('requires an applied proposal and unchanged docs', async () => {
    const pending = await createProposal(env.DB, { kind: 'nochange', summary: 'x', body: { reading: 'x' } })
    expect((await api(`/api/proposals/${pending.id}/revert`, { token, body: { docs: [] } })).status).toBe(409)

    const { proposal, docs } = await appliedProposal()
    await seedDoc('coach', { log: ['changed elsewhere'], snapshots: [], lastReview: null })
    const result = await api(`/api/proposals/${proposal.id}/revert`, {
      token,
      body: { docs: [{ key: 'plan', data: { routines: [] }, baseSeq: docs.plan }, { key: 'coach', data: { log: [] }, baseSeq: docs.coach }] },
    })
    expect(result.status).toBe(409)
    expect(result.body.proposal.revertedAt).toBeNull()
  })
})
