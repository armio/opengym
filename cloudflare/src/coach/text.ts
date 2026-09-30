const segmenter = new Intl.Segmenter(undefined, { granularity: 'grapheme' })

/**
 * The first `max` grapheme clusters of `value` (coach-Q18). The original sliced UTF-16 units,
 * which can split a ZWJ emoji sequence or a surrogate pair; ASCII text clamps exactly as before.
 */
export function clampGraphemes(value: string, max: number): string {
  let out = ''
  let count = 0
  for (const { segment } of segmenter.segment(value)) {
    if (count++ === max) break
    out += segment
  }
  return out
}
