#!/usr/bin/env node
// Builds the exercise catalogue shipped by the Flutter app and the Cloudflare Worker from the
// same source the React app uses (frontend/src/lib/exercises-data.js + the Spanish instruction
// pack and taxonomy labels), so the three never disagree on an exercise id.
//
//   node scripts/build-flutter-cloudflare-data.mjs          # write both files
//   node scripts/build-flutter-cloudflare-data.mjs --check  # fail if either is out of date
//
// app/assets/exercises.json       full records for the app (names, taxonomy, instructions en/es, media)
// cloudflare/src/catalog/library.json records for the MCP tools: {id, n, bp, tg, eq, sm} plus the Spanish
//                                  labels and instructions (bp_es, tg_es, eq_es, sm_es, st_es)
//
// Order is the dataset order (roughly alphabetical); ids are 4-digit strings, never numbers.

import { readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const load = async p => import(pathToFileURL(join(root, p)).href)
const { EXDB } = await load('frontend/src/lib/exercises-data.js')
const ES_INSTR = (await load('frontend/src/instr/es.js')).default
const ES_UI = (await load('frontend/src/locales/es.js')).default
const tr = s => (s && ES_UI[s]) || s || ''

const app = EXDB.map(e => ({
  id: e.id,
  name: e.n,
  bodyPart: e.bp,
  equipment: e.eq,
  target: e.tg,
  secondary: e.sm || [],
  instructions: e.st || [],
  instructions_es: ES_INSTR[e.id] || [],
  bodyPart_es: tr(e.bp),
  equipment_es: tr(e.eq),
  target_es: tr(e.tg),
  secondary_es: (e.sm || []).map(tr),
  img: e.img || null,
  gif: e.gif || null,
}))

const worker = EXDB.map(e => ({
  id: e.id, n: e.n, bp: e.bp, tg: e.tg, eq: e.eq, sm: e.sm || [],
  bp_es: tr(e.bp), tg_es: tr(e.tg), eq_es: tr(e.eq), sm_es: (e.sm || []).map(tr),
  st_es: ES_INSTR[e.id] || [],
}))

const ids = new Set(app.map(r => r.id))
if (ids.size !== app.length) throw new Error('duplicate exercise ids')
for (const r of app) if (!/^\d{4}$/.test(r.id)) throw new Error('bad exercise id ' + r.id)

const outputs = [
  ['app/assets/exercises.json', JSON.stringify(app) + '\n'],
  ['cloudflare/src/catalog/library.json', JSON.stringify(worker) + '\n'],
]
const check = process.argv.includes('--check')
let stale = 0
for (const [rel, content] of outputs) {
  const file = join(root, rel)
  if (check) {
    let cur = null
    try { cur = readFileSync(file, 'utf8') } catch { /* missing */ }
    if (cur !== content) { console.error(`${rel} is out of date — run node scripts/build-flutter-cloudflare-data.mjs`); stale++ }
  } else {
    writeFileSync(file, content)
    console.log(`wrote ${rel} (${app.length} exercises, ${content.length} bytes)`)
  }
}
if (stale) process.exit(1)
