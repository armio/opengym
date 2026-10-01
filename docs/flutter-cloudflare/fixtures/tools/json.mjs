// JSON encoding for fixture files.
//
// JSON has no `undefined`, `NaN` or `±Infinity`, but a few original test vectors feed exactly
// those to the engine. They are written as marker objects {"$js": "undefined" | "NaN" |
// "Infinity" | "-Infinity"}. An object key whose value is `undefined` is simply absent.

import fs from 'node:fs'
import path from 'node:path'

const MARKERS = { undefined, NaN, Infinity, '-Infinity': -Infinity }

export const js = name => ({ $js: name })

function isMarker(v) {
  return v !== null && typeof v === 'object' && !Array.isArray(v) && Object.keys(v).length === 1 && typeof v.$js === 'string'
}

/** Marker objects → JavaScript values (to call the original code with). */
export function decode(v) {
  if (isMarker(v)) {
    if (!(v.$js in MARKERS)) throw new Error('unknown marker ' + v.$js)
    return MARKERS[v.$js]
  }
  if (Array.isArray(v)) return v.map(decode)
  if (v !== null && typeof v === 'object') return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, decode(x)]))
  return v
}

/** JavaScript values → JSON-safe values with markers (what the original code returned). */
export function encode(v) {
  if (v === undefined) return js('undefined')
  if (typeof v === 'number') {
    if (Number.isNaN(v)) return js('NaN')
    if (v === Infinity) return js('Infinity')
    if (v === -Infinity) return js('-Infinity')
    return Object.is(v, -0) ? 0 : v
  }
  if (Array.isArray(v)) return v.map(encode)
  if (v !== null && typeof v === 'object') {
    return Object.fromEntries(Object.entries(v).filter(([, x]) => x !== undefined).map(([k, x]) => [k, encode(x)]))
  }
  return v
}

/** Structural equality on encoded values (key order ignored). */
export function same(a, b) {
  return JSON.stringify(sortKeys(encode(a))) === JSON.stringify(sortKeys(encode(b)))
}

function sortKeys(v) {
  if (Array.isArray(v)) return v.map(sortKeys)
  if (v !== null && typeof v === 'object') return Object.fromEntries(Object.keys(v).sort().map(k => [k, sortKeys(v[k])]))
  return v
}

const WIDTH = 110

/**
 * Pretty JSON that keeps short arrays and objects on one line. `used` is how many characters
 * already sit on the current line before the value (its key).
 */
export function pretty(value, indent = '', used = 0) {
  const inline = JSON.stringify(value)
  if (inline === undefined) throw new Error('value is not JSON-serialisable')
  if (value === null || typeof value !== 'object' || indent.length + used + inline.length <= WIDTH) return inline
  const inner = indent + '  '
  if (Array.isArray(value)) {
    if (value.length === 0) return '[]'
    return '[\n' + value.map(x => inner + pretty(x, inner)).join(',\n') + '\n' + indent + ']'
  }
  const entries = Object.entries(value)
  if (entries.length === 0) return '{}'
  return '{\n' + entries.map(([k, x]) => {
    const key = JSON.stringify(k) + ': '
    return inner + key + pretty(x, inner, key.length)
  }).join(',\n') + '\n' + indent + '}'
}

export function writeFixture(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true })
  fs.writeFileSync(file, pretty(value) + '\n')
}
