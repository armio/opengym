// Turns vector specs into fixture vectors by running the reference implementations.
//
// A vector's `expected` value is what the fully fixed variant returns. When that differs from
// the untouched original, the vector records `original` and `fix`: the id(s) of every single
// fix whose variant alone changes the result. A spec may pin `golden` values (from the specs'
// tables); generation fails if the reference disagrees with them.

import { FIX_IDS } from './harness.mjs'
import { decode, encode, same } from './json.mjs'

/**
 * @param variants   loaded module variants (see harness.loadVariants)
 * @param group      { scope?, note?, fixOnly?, call(mod, args), sameInstance?(args, result), vectors: [...] }
 * @param setNow     re-pins the clock for vectors that carry their own `now`
 * @param clock      the file-level clock
 */
export function buildGroup(variants, group, { setNow, clock }) {
  return {
    scope: group.scope ?? 'shared',
    ...(group.note ? { note: group.note } : {}),
    ...(group.fixOnly ? { fix: group.fixOnly } : {}),
    vectors: group.vectors.map(spec => buildVector(variants, group, spec, { setNow, clock })),
  }
}

function buildVector(variants, group, spec, { setNow, clock }) {
  const now = spec.now ?? clock?.now
  const run = variantName => {
    if (now !== undefined) setNow(now)
    const args = decode(encode(spec.args))        // a fresh copy: some originals mutate
    const result = group.call(variants[variantName], args)
    return group.sameInstance ? { result, sameInstance: group.sameInstance(args, result) } : { result }
  }

  const fixed = run('fixed')
  const out = { name: spec.name, ...(spec.ref ? { ref: spec.ref } : {}), args: encode(spec.args) }
  if (spec.now !== undefined) out.now = spec.now
  out.expected = encode(fixed.result)
  if (group.sameInstance) out.sameInstance = fixed.sameInstance

  if (!group.fixOnly) {
    const original = run('original')
    const changedBy = FIX_IDS.filter(id => !same(run(id).result, original.result))
    if (same(fixed.result, original.result)) {
      if (changedBy.length) throw new Error(`${spec.name}: fixes ${changedBy} cancel out — write a separate vector per fix`)
    } else {
      if (!changedBy.length) throw new Error(`${spec.name}: the fixed result differs but no single fix explains it`)
      out.fix = changedBy.length === 1 ? changedBy[0] : changedBy
      out.original = encode(original.result)
    }
    // Every amendment is declared in the spec, so a fix never changes a vector by surprise.
    if (JSON.stringify(spec.fix) !== JSON.stringify(out.fix)) {
      throw new Error(`${spec.name}: declared fix ${spec.fix ?? 'none'}, reference says ${out.fix ?? 'none'}`)
    }
  }
  if ('golden' in spec) assertGolden(spec.name, out.expected, encode(spec.golden))
  return out
}

/** `golden` may be partial: object keys it lists must match; {"$js":"undefined"} means absent. */
function assertGolden(name, actual, golden) {
  const fail = () => { throw new Error(`${name}: expected ${JSON.stringify(golden)}, reference gave ${JSON.stringify(actual)}`) }
  if (golden !== null && typeof golden === 'object' && !Array.isArray(golden) && golden.$js === undefined) {
    if (actual === null || typeof actual !== 'object' || Array.isArray(actual)) fail()
    for (const [k, v] of Object.entries(golden)) {
      if (v !== null && typeof v === 'object' && v.$js === 'undefined') { if (k in actual) fail() }
      else if (!same(decode(actual[k]), decode(v))) fail()
    }
    return
  }
  if (!same(decode(actual), decode(golden))) fail()
}
