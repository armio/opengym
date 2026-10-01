import { env } from 'cloudflare:workers'
import { beforeEach, describe, expect, it } from 'vitest'
import { listRecoveryDays } from '../src/db'
import { addDays } from '../src/engine'
import { api, loginDevice, resetDatabase } from './helpers'

let token: string
const today = new Date().toISOString().slice(0, 10)

beforeEach(async () => {
  await resetDatabase()
  token = (await loginDevice('iPhone')).token
})

const upload = (body: unknown) => api('/api/recovery', { token, body })

describe('POST /api/recovery', () => {
  it('stores each day, rounding the metrics and ignoring unknown keys', async () => {
    const result = await upload({
      days: [
        { d: addDays(today, -1), rhr: 54.26, hrv: 61.04, sleepMin: 431.6, inBedMin: 470, steps: 9000 },
        { d: today, rhr: 55, hrv: null },
      ],
    })
    expect(result.status).toBe(200)
    expect(result.body).toEqual({ ok: true, stored: 2, deleted: 0 })
    expect(await listRecoveryDays(env.DB)).toEqual([
      { d: addDays(today, -1), rhr: 54.3, hrv: 61, sleepMin: 432, inBedMin: 470 },
      { d: today, rhr: 55, hrv: null, sleepMin: null, inBedMin: null },
    ])
  })

  it('replaces a day whole, and deletes a day with no metric left', async () => {
    await upload({ days: [{ d: today, rhr: 55, hrv: 60, sleepMin: 420 }, { d: addDays(today, -1), rhr: 56 }] })
    const result = await upload({ days: [{ d: today, hrv: 58 }, { d: addDays(today, -1) }, { d: addDays(today, -2) }] })
    expect(result.body).toEqual({ ok: true, stored: 1, deleted: 1 })
    expect(await listRecoveryDays(env.DB)).toEqual([{ d: today, rhr: null, hrv: 58, sleepMin: null, inBedMin: null }])
  })

  it('accepts an empty upload', async () => {
    expect((await upload({ days: [] })).body).toEqual({ ok: true, stored: 0, deleted: 0 })
  })

  it.each([
    [{}, 'Envía { "days": [...] }.'],
    [{ days: {} }, 'Envía { "days": [...] }.'],
    [{ days: [{ rhr: 50 }] }, 'Cada día necesita una fecha d en formato YYYY-MM-DD.'],
    [{ days: [{ d: '2026-02-30' }] }, 'Cada día necesita una fecha d en formato YYYY-MM-DD.'],
    [{ days: [{ d: addDays(today, 3) }] }, `${addDays(today, 3)}: fecha fuera de rango.`],
    [{ days: [{ d: addDays(today, -401) }] }, `${addDays(today, -401)}: fecha fuera de rango.`],
    [{ days: [{ d: today }, { d: today }] }, `${today}: fecha repetida.`],
    [{ days: [{ d: today, rhr: 300 }] }, `${today}: rhr debe ser un número entre 20 y 250.`],
    [{ days: [{ d: today, hrv: '60' }] }, `${today}: hrv debe ser un número entre 1 y 500.`],
    [{ days: [{ d: today, sleepMin: -5 }] }, `${today}: sleepMin debe ser un número entre 0 y 1440.`],
    [{ days: [{ d: today, inBedMin: 1441 }] }, `${today}: inBedMin debe ser un número entre 0 y 1440.`],
  ])('refuses %j', async (body, error) => {
    const result = await upload(body)
    expect(result.status).toBe(400)
    expect(result.body.error).toBe(error)
    expect(await listRecoveryDays(env.DB)).toEqual([])
  })

  it('refuses more than 400 days at once', async () => {
    const days = Array.from({ length: 401 }, (_, i) => ({ d: addDays(today, -i) }))
    expect((await upload({ days })).status).toBe(400)
  })

  it('needs a device token', async () => {
    expect((await api('/api/recovery', { body: { days: [] } })).status).toBe(401)
    expect((await api('/api/recovery/clear', { body: {} })).status).toBe(401)
  })
})

describe('POST /api/recovery/clear', () => {
  it('deletes every day', async () => {
    await upload({ days: [{ d: today, rhr: 55 }, { d: addDays(today, -1), rhr: 56 }] })
    expect((await api('/api/recovery/clear', { token, body: {} })).body).toEqual({ ok: true, deleted: 2 })
    expect(await listRecoveryDays(env.DB)).toEqual([])
  })
})

describe('POST /api/reset', () => {
  it('also deletes the recovery days', async () => {
    await upload({ days: [{ d: today, rhr: 55 }] })
    expect((await api('/api/reset', { token, body: { confirm: 'RESET' } })).status).toBe(200)
    expect(await listRecoveryDays(env.DB)).toEqual([])
  })
})
