#!/usr/bin/env node
// Regenerates the derived fixture files from the original openGym code:
//
//   node docs/flutter-cloudflare/fixtures/tools/generate.mjs
//
// engine/*.json, plan-hash.json, current-value.json and validate.json are written here.
// validate-port.json is maintained by hand (the port rules have no original to run).

import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { loadVariants, pinClock } from './harness.mjs'
import { buildGroup } from './derive.mjs'
import { writeFixture } from './json.mjs'
import {
  datesFile, effortFile, heatmapGroup, heatmapReference, historyFile, linkSupersetGroup, linkSupersetReference,
  musclesFile, onermFile, progressionFile, sortWorkoutsGroup,
} from './engine.mjs'
import { currentValueFile, planHashFile, validateFile } from './coach.mjs'

const FIXTURES = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')

/** Wednesday 2026-09-30 10:00 in Madrid. Every clock-dependent vector is relative to it. */
const CLOCK = { now: Date.UTC(2026, 8, 30, 8, 0, 0), tz: 'Europe/Madrid', today: '2026-09-30' }

const setNow = pinClock(CLOCK)
const { variants, validate, payload, cleanup } = await loadVariants()

try {
  const { original } = variants
  const build = file => {
    const out = { ...file, groups: {} }
    for (const [name, group] of Object.entries(file.groups)) out.groups[name] = buildGroup(variants, group, { setNow, clock: file.clock })
    return out
  }

  const history = build(historyFile(CLOCK))
  history.groups.linkSuperset = checked(linkSupersetGroup(), v => linkSupersetReference(v.args.ex, v.args.links, original.history.cleanupSg))
  history.constants = { EFFORT: original.history.EFFORT }

  const progression = build(progressionFile())
  const p = original.progression
  progression.constants = { POLICIES: p.POLICIES, POLICIES_FOR: p.POLICIES_FOR, DELOAD_AFTER: p.DELOAD_AFTER, DEFAULT_SEC_INCREMENT: p.DEFAULT_SEC_INCREMENT }

  const onerm = build(onermFile())
  onerm.constants = { REP_CAP: original.onerm.REP_CAP, DEFAULT_FORMULA: original.onerm.DEFAULT_FORMULA, FORMULAS: Object.keys(original.onerm.FORMULAS) }

  const effort = build(effortFile(CLOCK))
  effort.constants = { HARD_RIR: original.effort.HARD_RIR, MIN_RATED: original.effort.MIN_RATED, BUCKETS: original.effort.BUCKETS }

  const muscles = build(musclesFile())
  muscles.constants = { MUSCLES: original.muscles.MUSCLES }

  const dates = build(datesFile(CLOCK))
  dates.groups.sortWorkouts = sortWorkoutsGroup(CLOCK)

  const stats = {
    about: 'Stats-screen logic that lives in UI files (engine.md §8).',
    groups: { heatmap: checked(heatmapGroup(), v => heatmapReference(v.args.days.map(d => d.min), v.args.probes)) },
  }

  const files = { history, progression, onerm, effort, muscles, dates, stats }
  for (const [name, content] of Object.entries(files)) writeFixture(path.join(FIXTURES, 'engine', name + '.json'), content)

  writeFixture(path.join(FIXTURES, 'plan-hash.json'), planHashFile({ payload, coach: original.coach, exercises: original.exercises }))
  writeFixture(path.join(FIXTURES, 'current-value.json'), currentValueFile({ coach: original.coach }))
  writeFixture(path.join(FIXTURES, 'validate.json'), validateFile({ validate }))
  console.log('fixtures written to', FIXTURES)
} finally {
  cleanup()
}

/** Hand-written groups are checked against a small reference before they are written. */
function checked(group, reference) {
  for (const v of group.vectors) {
    const actual = JSON.stringify(reference(v))
    if (actual !== JSON.stringify(v.expected)) throw new Error(`${v.name}: reference gives ${actual}`)
  }
  return group
}
