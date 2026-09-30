// Loads the ORIGINAL openGym engine modules (frontend/src/lib/*.js) under Node, once as they are
// and once per documented fix (contract §2.3), so every fixture vector can be computed by the
// reference implementation rather than typed in by hand.
//
// The modules are copied into a temporary directory with two stubs: i18n.js (the real one
// imports React and Vite globs) and the `import.meta.env` media bases in exercises.js. A fix is
// a literal source patch; every patch must match exactly once, so a change upstream fails loudly.

import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../..')
const LIB = path.join(REPO, 'frontend/src/lib')
const MODULES = ['history', 'progression', 'onerm', 'effort', 'muscles', 'format', 'exercises', 'exercises-data', 'coach', 'plan-share']

const I18N_STUB = `// Stub: English keys, en-GB numbers (the locale the original tests assume).
export const dateLocale = () => 'en-GB'
export const getLang = () => 'en'
export function t(s, ...args) {
  let v = s
  args.forEach((a, i) => { v = v.replaceAll('{' + i + '}', a) })
  return v
}
`

// engine-Q1: a double-progression session only counts as a stall when it did not improve on
// the one before it at the same weight.
const DOUBLE_STALL = `
export function doubleStallCount(sessions) {
  let n = 0
  for (let i = sessions.length - 1; i >= 0; i--) {
    const s = sessions[i]
    const prev = sessions[i - 1]
    const stalled = !s.ok && (i === 0 || prev.weight !== s.weight || s.low <= prev.low)
    if (!stalled) break
    n++
  }
  return n
}
`

// critic-G3, written as literally as the contract states it: the stored target of the last
// session in this mode, compared field by field with the plan.
const TARGET_CHANGED = `
function lastTargetOf(S, cfg, mode) {
  const workouts = S.workouts || []
  for (let i = workouts.length - 1; i >= 0; i--) {
    const entry = workouts[i].entries.find(e => e.id === cfg.id)
    if (entry && entry.sets.some(s => s.done) && readSession(entry, cfg).mode === mode) return entry.target || null
  }
  return null
}
function targetChanged(S, cfg, mode) {
  const target = lastTargetOf(S, cfg, mode)
  const key = mode === 'time' ? 'sec' : 'reps'
  return target != null && typeof target[key] === 'number' && target[key] > 0 && target[key] !== cfg[key]
}
`

const FIRST_LINE = "if (!last) return { policy, kind: 'first', why: ['Nothing logged yet — this session sets the baseline.'] }"

/** Source patches per fix id: [file, exact text, replacement]. */
export const PATCHES = {
  'engine-Q1': [
    ['progression.js', 'const stalls = stallCount(sessions)', "const stalls = policy === 'double' ? doubleStallCount(sessions) : stallCount(sessions)"],
    ['progression.js', '\n/**\n * The next prescription', DOUBLE_STALL + '\n/**\n * The next prescription'],
  ],
  'engine-Q2': [
    ['progression.js', 'const sec = deloadTo(last.goal || cfg.sec || 0, 5)', 'const sec = deloadTo(last.goal || cfg.sec || 0, inc > 0 ? inc : 5)'],
  ],
  'engine-Q5': [
    ['history.js', 'if (e.id === exId) {', "if (e.id === exId && modeOf({ ...(e.target ?? {}), id: e.id }) === 'reps') {"],
  ],
  'engine-Q7': [
    ['effort.js', '(w.start || new Date(w.d).getTime())', "(w.start || new Date(w.d + 'T12:00:00').getTime())"],
  ],
  'critic-G3': [
    ['progression.js', FIRST_LINE, FIRST_LINE + "\n  if (targetChanged(S, cfg, mode)) return { policy, kind: 'first', why: ['Plan target changed — this session sets the new baseline.'] }"],
    ['progression.js', '\n/**\n * The next prescription', TARGET_CHANGED + '\n/**\n * The next prescription'],
    ['history.js', '  const mode = modeOf(cfg)\n  const sets = []',
      "  const mode = modeOf(cfg)\n  const retarget = key => !!last && last.target != null && typeof last.target[key] === 'number' && last.target[key] > 0 && last.target[key] !== cfg[key]\n  const sets = []"],
    ['history.js', 'sets.push({ sec: carried ? carried.sec : (cfg.sec || 45),', "sets.push({ sec: retarget('sec') ? (cfg.sec || 45) : carried ? carried.sec : (cfg.sec || 45),"],
    ['history.js', 'sets.push({ w, r: usable ? usable.r : cfg.reps, done: false })', "sets.push({ w, r: retarget('reps') ? cfg.reps : usable ? usable.r : cfg.reps, done: false })"],
  ],
}

export const FIX_IDS = Object.keys(PATCHES)

function applyPatch(source, find, replacement, label) {
  const at = source.indexOf(find)
  if (at < 0 || source.indexOf(find, at + 1) >= 0) throw new Error(`patch ${label} must match exactly once: ${JSON.stringify(find)}`)
  return source.slice(0, at) + replacement + source.slice(at + find.length)
}

function writeVariant(root, name, fixIds) {
  const dir = path.join(root, name)
  fs.mkdirSync(dir, { recursive: true })
  const sources = {}
  for (const mod of MODULES) sources[mod + '.js'] = fs.readFileSync(path.join(LIB, mod + '.js'), 'utf8')
  sources['exercises.js'] = sources['exercises.js'].replaceAll('import.meta.env.VITE_IMG_BASE', 'undefined').replaceAll('import.meta.env.VITE_GIF_BASE', 'undefined')
  sources['i18n.js'] = I18N_STUB
  for (const id of fixIds) {
    for (const [file, find, replacement] of PATCHES[id]) sources[file] = applyPatch(sources[file], find, replacement, id)
  }
  for (const [file, text] of Object.entries(sources)) fs.writeFileSync(path.join(dir, file), text)
  return dir
}

async function importVariant(dir) {
  const load = mod => import(pathToFileURL(path.join(dir, mod + '.js')).href)
  const [history, progression, onerm, effort, muscles, format, exercises, coach] = await Promise.all(
    ['history', 'progression', 'onerm', 'effort', 'muscles', 'format', 'exercises', 'coach'].map(load))
  return { history, progression, onerm, effort, muscles, format, exercises, coach }
}

/**
 * Pins the process clock and zone. Must run before anything reads the clock; Node re-reads
 * `process.env.TZ` when it changes. Returns a setter to move the pinned instant.
 */
export function pinClock({ now, tz }) {
  process.env.TZ = tz
  let current = now
  const RealDate = Date
  class PinnedDate extends RealDate {
    constructor(...args) { if (args.length === 0) super(current); else super(...args) }
    static now() { return current }
  }
  globalThis.Date = PinnedDate
  return ms => { current = ms }
}

/**
 * Loads every variant: `original`, one per fix id, and `fixed` (all fixes). The server-side
 * coach modules (api/coach/validate.js, payload.js) are imported from the repository as is.
 */
export async function loadVariants() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'opengym-fixtures-'))
  const variants = { original: await importVariant(writeVariant(root, 'original', [])) }
  for (const id of FIX_IDS) variants[id] = await importVariant(writeVariant(root, id, [id]))
  variants.fixed = await importVariant(writeVariant(root, 'fixed', FIX_IDS))
  process.env.DATA_DIR = root   // payload.js only reads it lazily for pseudonyms, which are never built here
  const validate = await import(pathToFileURL(path.join(REPO, 'api/coach/validate.js')).href)
  const payload = await import(pathToFileURL(path.join(REPO, 'api/coach/payload.js')).href)
  return { variants, validate, payload, cleanup: () => fs.rmSync(root, { recursive: true, force: true }) }
}

export { REPO }
