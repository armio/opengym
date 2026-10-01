import { beforeEach, describe, expect, it } from 'vitest'
import { api } from '../helpers'
import { daysFrom, freshOwner, McpClient } from './client'

let client: McpClient
let device: string
let today: string

beforeEach(async () => {
  ;({ client, device, today } = await freshOwner())
})

interface Day {
  d: string
  rhr?: number | null
  hrv?: number | null
  sleepMin?: number | null
  inBedMin?: number | null
}

async function share(days: Day[]): Promise<void> {
  const result = await api('/api/recovery', { token: device, body: { days } })
  if (result.status !== 200) throw new Error(JSON.stringify(result.body))
}

/** 35 days: a steady baseline, then the last 7 days as `recent` says (offset 0 = today). */
function block(recent: (offset: number) => Omit<Day, 'd'>): Day[] {
  return Array.from({ length: 35 }, (_, i) => {
    const offset = 34 - i
    const d = daysFrom(today, -offset)
    if (offset < 7) return { d, ...recent(offset) }
    // Baseline: HRV 58–62 ms, resting HR 54–56 bpm, 7–7.5 h of sleep.
    return { d, hrv: 58 + (offset % 5), rhr: 54 + (offset % 3), sleepMin: 420 + (offset % 4) * 10, inBedMin: 480 }
  })
}

describe('get_recovery', () => {
  it('says nothing when the owner shares no recovery data', async () => {
    const report = await client.ok('get_recovery')
    expect(report.source).toBe('Apple Health')
    expect(report.from).toBe(daysFrom(today, -27))
    expect(report.to).toBe(today)
    expect(report.latest).toBeNull()
    expect(report.days).toEqual([])
    expect(report.comparison.comparable).toBe(false)
    expect(report.comparison.signals).toEqual([])
  })

  it('flags HRV down, resting heart rate up and short sleep against the baseline', async () => {
    await share(block(() => ({ hrv: 44, rhr: 61, sleepMin: 320, inBedMin: 400 })))
    const report = await client.ok('get_recovery')
    expect(report.days).toHaveLength(28)
    expect(report.latest).toEqual({ d: today, rhr: 61, hrv: 44, sleepMin: 320, inBedMin: 400 })
    const { recent, baseline, comparable, signals } = report.comparison
    expect(comparable).toBe(true)
    expect(recent).toEqual(expect.objectContaining({ from: daysFrom(today, -6), to: today, shortNights: 7 }))
    expect(recent.hrv).toEqual({ mean: 44, sd: 0, n: 7 })
    expect(baseline.from).toBe(daysFrom(today, -34))
    expect(baseline.to).toBe(daysFrom(today, -7))
    expect(baseline.hrv.n).toBe(28)
    expect(baseline.hrv.mean).toBeCloseTo(60, 0)
    expect(signals).toHaveLength(3)
    expect(signals[0]).toMatch(/^HRV is down: the 7-day mean is 44 ms against a 28-day baseline of 60(\.\d)? ± \d/)
    expect(signals[1]).toMatch(/^Resting heart rate is up: the 7-day mean is 61 bpm/)
    expect(signals[2]).toBe('Short sleep: 5.3 h a night on average over the last 7 nights (7 under 6 h).')
  })

  it('stays quiet when the last week looks like the baseline', async () => {
    await share(block(offset => ({ hrv: 59 + (offset % 3), rhr: 55, sleepMin: 430 })))
    const { comparison } = await client.ok('get_recovery')
    expect(comparison.comparable).toBe(true)
    expect(comparison.signals).toEqual([])
  })

  it('notices sleep well below the usual even when it is above 6 hours', async () => {
    await share(block(() => ({ sleepMin: 370 })))
    const { comparison } = await client.ok('get_recovery')
    expect(comparison.signals).toEqual(['Less sleep than usual: 6.2 h a night over the last 7 nights against 7.3 h in the 28 days before.'])
  })

  it('needs a few days on each side before comparing', async () => {
    await share([{ d: today, hrv: 30, rhr: 70, sleepMin: 200 }, { d: daysFrom(today, -10), hrv: 60, rhr: 55, sleepMin: 450 }])
    const { comparison } = await client.ok('get_recovery')
    expect(comparison.comparable).toBe(false)
    expect(comparison.signals).toEqual([])
  })

  it('reads a chosen range and compares up to its end', async () => {
    await share(block(() => ({ hrv: 44 })))
    const report = await client.ok('get_recovery', { from: daysFrom(today, -20), to: daysFrom(today, -10) })
    expect(report.days.map((d: Day) => d.d)).toEqual(Array.from({ length: 11 }, (_, i) => daysFrom(today, -20 + i)))
    expect(report.latest.d).toBe(daysFrom(today, -10))
    expect(report.comparison.recent.to).toBe(daysFrom(today, -10))
    expect(report.comparison.signals).toEqual([])
  })

  it('refuses a backwards or oversized range', async () => {
    const backwards = await client.call('get_recovery', { from: today, to: daysFrom(today, -1) })
    expect(backwards.isError).toBe(true)
    expect(backwards.text).toContain('is after to')
    const huge = await client.call('get_recovery', { from: daysFrom(today, -400) })
    expect(huge.isError).toBe(true)
    expect(huge.text).toContain('at most 400 days')
  })
})

describe('get_overview recovery block', () => {
  it('is null without shared data', async () => {
    const overview = await client.ok('get_overview')
    expect(overview.recovery).toBeNull()
    expect(overview.hints.join(' ')).not.toContain('get_recovery')
  })

  it('summarises the comparison and points Claude at get_recovery when there are signals', async () => {
    await share(block(() => ({ hrv: 44, rhr: 61, sleepMin: 320 })))
    const overview = await client.ok('get_overview')
    expect(overview.recovery.latest).toEqual({ d: today, rhr: 61, hrv: 44, sleepMin: 320, inBedMin: null })
    expect(overview.recovery.signals).toHaveLength(3)
    expect(overview.recovery.recent.hrv.mean).toBe(44)
    expect(overview.hints.at(-1)).toBe('recovery has signals from Apple Health: read get_recovery before proposing harder work.')
  })
})
