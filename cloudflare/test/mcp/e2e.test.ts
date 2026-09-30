import { describe, expect, it } from 'vitest'
import { Catalog } from '../../src/catalog/library'
import { planHash } from '../../src/coach'
import type { JsonObject } from '../../src/lib/json'
import { api } from '../helpers'
import { freshOwner } from './client'

const PLAN = {
  routines: [
    {
      id: 'r1', name: 'Torso', emoji: '💪', prog: 'linear',
      ex: [{ id: '0025', sets: 3, mode: 'reps', reps: 8 }, { id: '0334', sets: 3, mode: 'reps', reps: 12 }],
    },
  ],
  week: { '1': 'r1', '4': 'r1' },
  customEx: [],
}

const hashOf = (plan: typeof PLAN) => planHash(plan, Catalog.forPlan(plan))

describe('Claude proposes, the owner decides in the app, Claude sees the outcome', () => {
  it('runs propose_changes → resolve → get_overview → revert', async () => {
    const { client, device, today } = await freshOwner()
    const sync = (body: JsonObject) => api('/api/sync', { token: device, body })

    // The app creates the plan.
    const pushed = await sync({ since: 0, docs: [{ key: 'plan', data: PLAN, baseSeq: 0, updatedAt: Date.now() }] })
    expect(pushed.body.conflicts).toEqual([])

    // Claude reads it and proposes two changes, misreading one current value.
    const before = await client.ok('get_overview')
    expect(before.planHash).toBe(hashOf(PLAN))
    const proposed = await client.ok('propose_changes', {
      summary: 'Una serie más de press y más repeticiones en elevaciones.',
      evidence: { from: today, to: today, sessions: 0 },
      changes: [
        { id: 'c1', type: 'sets', target: { routineId: 'r1', exId: '0025' }, before: 5, after: 4, why: 'RIR alto en todas las series.' },
        { id: 'c2', type: 'reps', target: { routineId: 'r1', exId: '0334' }, after: 15, why: 'Las 12 repeticiones salen fáciles.' },
      ],
    })

    // The app pulls the proposal, with the server's before values and fingerprint.
    const pulled = await api('/api/sync?since=0', { token: device })
    const proposal = pulled.body.proposals.find((p: { id: string }) => p.id === proposed.proposalId)
    expect(proposal).toEqual(expect.objectContaining({ kind: 'changes', status: 'pending', planHash: hashOf(PLAN), unit: 'kg' }))
    expect(proposal.changes.map((c: { before: unknown }) => c.before)).toEqual([3, 12])
    const planDoc = pulled.body.docs.find((d: { key: string }) => d.key === 'plan')

    // The owner accepts c1 and declines c2; the app commits plan + coach log atomically.
    const now = Date.now()
    const applied = structuredClone(PLAN)
    applied.routines[0]!.ex[0]!.sets = 4
    const [c1, c2] = proposal.changes
    const coach = {
      log: [{
        id: 'l1', kind: 'review', at: now, proposalId: proposal.id, summary: proposal.summary, evidence: proposal.evidence, notes: [],
        decisions: [{ ...c1, status: 'accepted' }, { id: c2.id, type: c2.type, why: c2.why, status: 'rejected' }],
      }],
      snapshots: [{ at: now, proposalId: proposal.id, label: 'Antes de los cambios del Coach', routines: PLAN.routines, week: PLAN.week }],
      lastReview: { at: now },
    }
    const resolved = await api(`/api/proposals/${proposal.id}/resolve`, {
      token: device,
      body: {
        outcome: 'applied', accepted: ['c1'], rejected: ['c2'], stale: [],
        docs: [{ key: 'plan', data: applied, baseSeq: planDoc.seq }, { key: 'coach', data: coach, baseSeq: 0 }],
      },
    })
    expect(resolved.status).toBe(200)

    // Claude sees the new plan and the owner's decision; the declined change is remembered once.
    const after = await client.ok('get_overview')
    expect(after.plan.routines[0].exercises[0]).toEqual(expect.objectContaining({ id: '0025', sets: 4 }))
    expect(after.planHash).toBe(hashOf(applied))
    expect(after.planHash).not.toBe(before.planHash)
    expect(after.pendingProposals).toEqual([])
    expect(after.recentDecisions).toEqual([
      expect.objectContaining({ id: proposal.id, kind: 'changes', outcome: 'applied', accepted: ['sets'], rejected: ['reps'], stale: [], reverted: false }),
    ])
    expect(after.previouslyDeclined).toEqual([{ type: 'reps', why: 'Las 12 repeticiones salen fáciles.', d: today }])

    // The next review starts where this one ended.
    const review = await client.ok('get_training_review')
    expect(review.window).toEqual(expect.objectContaining({ basis: 'since-last-review', from: today, lastReview: today }))

    // The owner undoes it in the app.
    const docs = (resolved.body.docs as { key: string; seq: number }[])
    const seqOf = (key: string) => docs.find(d => d.key === key)!.seq
    const reverted = await api(`/api/proposals/${proposal.id}/revert`, {
      token: device,
      body: {
        docs: [
          { key: 'plan', data: PLAN, baseSeq: seqOf('plan') },
          { key: 'coach', data: { ...coach, snapshots: [], log: [...coach.log, { id: 'l2', kind: 'revert', at: Date.now(), proposalId: proposal.id, summary: 'Deshecho.' }] }, baseSeq: seqOf('coach') },
        ],
      },
    })
    expect(reverted.status).toBe(200)

    const final = await client.ok('get_overview')
    expect(final.planHash).toBe(hashOf(PLAN))
    expect(final.recentDecisions[0]).toEqual(expect.objectContaining({ id: proposal.id, reverted: true }))

    // A fresh proposal reads the restored plan.
    const again = await client.ok('propose_changes', {
      summary: 'Otra vez.', changes: [{ id: 'c1', type: 'sets', target: { routineId: 'r1', exId: '0025' }, after: 4, why: 'Mismo motivo.' }],
    })
    expect(again.changes[0].before).toBe(3)
    expect(again.corrections).toEqual([])
  })
})
