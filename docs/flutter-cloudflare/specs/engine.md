# openGym → Flutter / Cloudflare: TRAINING LOGIC ENGINE porting spec

Source of truth: `frontend/src/lib/{progression,onerm,effort,history,format,muscles,sound}.js`
plus their `*.test.js` files, at commit `678bf5b`. The spec also covers the engine-level logic
that lives in UI files but belongs in a ported engine: PR detection at finish, the
`exWeights` update, heatmap buckets, stats windows and the session-build pipeline
(`sheets.jsx`, `components/Heatmap.jsx`, `views/Stats.jsx`, `views/Workout.jsx`,
`store/useUI.js`).

Every function below is a **pure function of the state object `S`**, with three exceptions:
some functions read the clock (`Date.now()`/`new Date()`), `cleanupSg` mutates its argument,
and the `sound.js` functions have side effects. Nothing in the engine writes back into a
finished workout. The engine derives each next prescription from history whenever it needs one.

I checked the spec against the reference implementation. I copied the modules into a harness,
stubbed only `i18n`, and all four original test files passed (53 + 21 + 23 + 40 `it` blocks).
Section 11 lists more golden values that I produced with the same harness.

---

## 0. Porting conventions (read first)

The JS code depends on several JavaScript semantics. A faithful Dart or TypeScript port has
to reproduce them.

| JS construct | Meaning | Port as |
|---|---|---|
| `a \|\| b` | returns `b` when `a` is falsy: `0`, `''`, `null`, `undefined`, `NaN`, `false` | helper `num orIf(num? a, num b) => (a == null \|\| a == 0 \|\| a.isNaN) ? b : a`. **A zero value falls through**, for example `cfg.reps \|\| last.goal \|\| 10` |
| `x != null` / `x == null` | true / false for both `null` **and** `undefined` (a missing key) | Dart `x != null` (a missing JSON key reads as null) |
| `x ?? y` | only null/undefined fall through, `0` does not | Dart `??` |
| `Math.round(x)` | rounds half **toward +∞**: `Math.round(2.5)=3`, `Math.round(-2.5)=-2` | Dart `round()` rounds half away from zero. Use `jsRound(x) = (x - x.floorToDouble() == 0.5) ? x.ceilToDouble() : x.roundToDouble()`. The two agree for positive values, which covers every real case here |
| `round1(v) = Math.round(v*10)/10` | round to one decimal | `jsRound(v*10)/10` |
| `Math.max(0, ...[])` | `0` (empty spread) | `[0, ...xs].reduce(max)` |
| `Math.max(0, ...[undefined])` | `NaN` | the port should treat missing as 0 and document any divergence (see §8.1) |
| `Math.min(...[])` | `Infinity`. It is never reached, because the code guards with `reps.length ?` | guard the same way |
| `Number(x)` | `Number('')=0`, `Number(null)=0`, `Number(undefined)=NaN`, `Number('100')=100` | helper `jsNumber(dynamic)` |
| `isFinite(x)` | false for NaN and ±Infinity | `x.isFinite` |
| Number → string in `why` args (i18n `t()` uses `String(n)`) | `55` → `"55"`, `62.5` → `"62.5"` | Dart `55.0.toString()` gives `"55.0"`, which is **wrong**. Use `fmtArg(n) = n == n.truncateToDouble() ? n.toInt().toString() : n.toString()` |
| `new Date('2026-01-01')` (date-only ISO) | **UTC** midnight | `DateTime.utc(y,m,d)` |
| `new Date('2026-01-01T12:00:00')` | **local** noon | `DateTime(y,m,d,12)` |
| `d.getDay()` | 0 = Sunday … 6 = Saturday | Dart `weekday % 7` (Dart uses Mon = 1 … Sun = 7) |

Dates `d` are always local calendar dates written as `'YYYY-MM-DD'` strings. Timestamps
(`start`, `end`, bodyweight `t`) are epoch milliseconds.

Clock-dependent functions include `streakWeeks`, the effort windows, `todayISO` and the
heatmap. **In the port, pass `now` in as a parameter** (`DateTime now`) so tests are
deterministic. The original tests build their fixtures relative to the real clock.

Recommended layout. The Cloudflare Worker needs a TS copy for the MCP tools, for example
"next prescription", "e1RM trend" and "muscle balance". Keep one TS implementation in the Worker
and a Dart port in the app, and pin both to the same JSON fixture files (the tables in §10 and
§11). The current repo already duplicates `readSession`/`stallCount`/`effortOf` in
`api/coach/payload.js`, and `coach.test.js` pins them against each other.

---

## 1. Data model the engine reads

### 1.1 State `S` (engine-relevant keys only; defaults from `store/useStore.js` `DEF`)

```jsonc
{
  "unit": "kg",              // "kg" | "lb". Weights are stored in the profile unit; the engine does no conversion
  "restSec": 90,             // rest timer length
  "sound": true,             // gates beep()
  "effort": null,            // null | "none" | "rir" | "rpe"   (null ⇒ fall back to legacy showRir)
  "showRir": false,          // LEGACY boolean, read only when effort is not a valid value
  "bodyweight": [ { "d": "2026-01-01", "w": 80.2, "t": 1767268800000 } ],   // kept sorted by d ascending
  "routines": [ Routine ],
  "week": { "1": "routineId", "3": "routineId" },   // key = JS weekday 0=Sun..6=Sat (string keys in JSON)
  "dayPlan": { "2026-01-05": "rest" | "routineId" }, // per-date override
  "exWeights": { "<exId>": { "w": 75, "d": "2026-01-01" } },  // confirmed "working weight" (a running max)
  "workouts": [ Workout ],   // chronological by APPEND order (finish order), not re-sorted
  "active": ActiveWorkout | null,
  "customEx": [ { "id": "c<uid>", "n": "name", "bp": "<bodypart>", "desc": "", "tg": "", "eq": "custom", "custom": true } ],
  "body": "male"             // body map geometry
}
```

### 1.2 Routine and routine exercise config (`cfg`)

```jsonc
Routine = { "id": "...", "name": "...", "emoji": "...", "prog": "linear"|"greyskull"|"double"|"time"|"off"|undefined, "ex": [ Cfg ] }

Cfg (reps)   = { "id": "0025", "sg": "a"?, "mode": "reps",  "sets": 3, "reps": 10, "weight": 60, "prog"?: Policy, "inc"?: number>0, "repsMin"?: int }
Cfg (time)   = { "id": "...",  "sg"?,      "mode": "time",  "sets": 3, "sec": 45,   "weight": 0,  "prog"?: Policy, "inc"?: seconds>0 }
Cfg (cardio) = { "id": "...",  "sg"?,                        "sets": 1, "min": 20,   "speed": 8 }   // cardio configs carry no `mode`
```

- `mode` may be missing (legacy). `modeOf` then derives it from the exercise body part.
- `sg` is the superset group id. Consecutive entries with the same `sg` form one unit.
- `prog` and `inc` are saved only when they differ from the inherited value. `repsMin` is saved
  only when the effective policy is `double`, clamped to `min(reps, max(1, round(repsMin) || max(1, reps-2)))`.
- Save-time clamps (ExConfig): `sets = max(1, round(sets) || (cardio?1:3))`; reps
  `max(1, round(reps) || 10)`; sec `max(1, round(sec) || 45)`; weight `max(0, weight || 0)`;
  min `max(1, round(min) || 20)`; speed `max(0, speed || 8)`.

### 1.3 Workout (finished) and entries

```jsonc
Workout = {
  "id": "...", "d": "2026-01-01", "start": 1767250000000, "end": 1767253600000,
  "routineId": "..." | null, "name": "Push A", "bw": 80.2 | null,
  "entries": [ Entry ],   // only entries with ≥1 done set are stored
  "prs": [ "<exId>", ... ],  // load PRs detected at finish (§8.1)
  "vol": 12345,             // workoutVolume(w) at finish
  "rating"?: ..., "note"?: ...
}
Entry = { "id": "<exId>", "sets": [ Set ], "topW": number | null, "target": Cfg-copy | null }
```

`target` is a copy of the routine exercise config used when the session was built (`{...cfg}`).
Workouts from before v1.2.2 have no `target` (it is `undefined`/`null`).

### 1.4 Set shapes per logging mode

| mode | shape | notes |
|---|---|---|
| `reps` | `{ w, r, done, rir?, rpe? }` | `w` is weight in the profile unit (0 = bodyweight), `r` is reps. At most one of `rir`/`rpe` is normally present; a cleared value is **deleted** (key dropped), not set to null |
| `time` | `{ sec, w, done }` | `w = 0` for bodyweight holds |
| `cardio` | `{ min, speed, done }` | speed in km/h |

`done: true` means the user checked the set off. Unchecked sets stay in the stored workout.
Only whole entries with no done set are dropped.

The active workout's entries also carry `plan` (the prescription object) and `asked` (the
top-weight sheet was shown).

### 1.5 Exercise catalogue record (`EXDB`, 1324 built-ins; `EXIDX[id]` also indexes custom ones)

```jsonc
{ "id": "0025", "n": "barbell bench press", "bp": "chest", "eq": "barbell",
  "tg": "pectorals", "mg": "...", "sm": ["triceps","shoulders"], "st": ["step", ...], "img": "...", "gif": "..." }
```

- `bp` (body part) is one of 10 values: `upper arms` 292, `upper legs` 227, `back` 203, `waist` 169,
  `chest` 163, `shoulders` 143, `lower legs` 59, `lower arms` 37, `cardio` 29, `neck` 2.
  Custom exercises choose from the same list (`BODYPARTS`, sorted).
- `isCardio(idOrEx)` is true when `(EXIDX[id] or ex).bp === 'cardio'`. An unknown id gives false.
- `tg` is the primary target (free text) and `sm` is the list of secondary muscles (free text).
  `mg` is **not used** by the engine.

---

## 2. `history.js` — modes, labels, set building, simple aggregates

### 2.1 `modeOf(cfg) → 'reps'|'time'|'cardio'`
```js
const m = cfg && cfg.mode
if (m === 'reps' || m === 'time' || m === 'cardio') return m
return isCardio(cfg && cfg.id) ? 'cardio' : 'reps'
```
An explicit valid `mode` always wins, even `reps` on a cardio exercise. An unknown or empty
mode falls back to the body part. `null`, `undefined` and `{}` all give `'reps'`.

`isTimed(cfg) = modeOf(cfg) === 'time'`.

### 2.2 `fmtSec(sec) → 'm:ss'`
`n = max(0, Math.round(Number(sec) || 0))`, result `floor(n/60) + ':' + pad2(n % 60)`.
Minutes are not padded and have no upper bound (`605 → '10:05'`).

### 2.3 Effort scales — `EFFORT`
```js
EFFORT = {
  rir: { f: 'rir', hd: 'RIR', step: 0.5, min: 0, max: 10 },
  rpe: { f: 'rpe', hd: 'RPE', step: 0.5, min: 6, max: 10 }
}
```
RIR (reps in reserve) and RPE are stored in **separate fields** on a set, and the app never
rewrites one into the other. Conversion is `RIR = 10 − RPE`.

### 2.4 `stepEffort(kind, cur, dir) → number|null` (one tap of the ± stepper)
```js
const e = EFFORT[kind]
if (!e) return cur ?? null                      // profile logs no effort: unchanged
if (cur == null) return dir < 0 ? null : e.min  // empty: '+' lands on the floor, '−' stays empty
const n = Math.round((cur + dir * e.step) * 100) / 100
if (dir < 0 && n < e.min) return null           // stepping below the floor clears the cell
return dir > 0 ? Math.min(e.max, n) : Math.max(e.min, n)
```
Only the ceiling is enforced on the way up. A value typed below the floor (for example RPE 3)
steps evenly (3 → 3.5). A null result means the caller **deletes the key**.

### 2.5 `capEffort(kind, v)`
Returns `v` unchanged when `v == null` or the kind is unknown. Otherwise it returns
`min(EFFORT[kind].max, v)`. The value is **not floored**, so typing "10" survives the "1" keystroke.

### 2.6 `effortOf(S) → 'none'|'rir'|'rpe'`
```js
const e = S && S.effort
return e === 'none' || EFFORT[e] ? e : (S && S.showRir ? 'rir' : 'none')
```
An explicit `'none'` beats the legacy `showRir` flag. A junk value (`'RIR'`, `'rpe10'`, `'f'`)
falls back to `showRir`.

### 2.7 `setLabel(id, s, cfg?) → string`
`mode = modeOf(cfg || { id })`. If `cfg` is passed without `id` and without `mode`, the mode
is `'reps'`. See open question Q4.
- cardio: `` `${s.min || 0} min @ ${fmtNum(s.speed || 0)} km/h` `` (`min` is not passed through `fmtNum`)
- time: `fmtSec(s.sec) + (s.w > 0 ? ' · ' + fmtNum(s.w) : '')` (no unit)
- reps: `` `${fmtNum(s.w || 0)}×${s.r || 0}` `` + effortTail. The `×` is U+00D7.
- effortTail: `k = s.rir != null ? 'rir' : s.rpe != null ? 'rpe' : null`, then `' (' + hd + ' ' + fmtNum(s[k]) + ')'` or `''`.
  RIR wins when a set carries both. Cardio and time labels never show effort.

### 2.8 `defaultConfig(id, mode?)`
`m = mode || modeOf({id})`
- cardio → `{ sets: 1, min: 20, speed: 8 }`
- time → `{ sets: 3, sec: 45, weight: 0, mode: 'time' }`
- reps → `{ sets: 3, reps: 10, weight: 0, mode: 'reps' }`

### 2.9 `exLine(cfg, unit) → string` (for example "3 × 10 · 60 kg")
`n = cfg.sets || 1`. `load = cfg.weight ? ' · ' + fmtNum(cfg.weight) + ' ' + unit : ''`.
- cardio: `` `${n} × ${cfg.min || 20} min @ ${fmtNum(cfg.speed || 8)} km/h` `` (no load)
- time: `` `${n} × ${fmtSec(cfg.sec || 45)}${load}` ``
- reps: `` `${n} × ${cfg.reps}${load}` `` (a missing `reps` prints "undefined", a JS quirk; the port should use `cfg.reps ?? ''`)

### 2.10 `cleanupSg(ex)` (mutates)
Deletes `sg` from any item whose immediate neighbours (i−1 or i+1) do not share its `sg`.
Example: `[{sg:a},{sg:b},{sg:b},{sg:c}] → [{},{sg:b},{sg:b},{}]`.

### 2.11 `lastEntryFor(S, exId) → { d, sets, target } | null` (the "last time" lookup)
The function scans `S.workouts` **from the end of the array backwards**. In each workout it
takes the **first** entry with `id === exId`. It returns on the first such entry that has
≥1 done set: `{ d: workout.d, sets: en.sets.filter(done), target: en.target || null }`.

### 2.12 `bestWeightFor(S, exId) → number` (the load "Best", used for PR detection)
Takes the max over **all** entries of `exId` in all workouts of `s.w` for done sets, and of
`e.topW`. Starts at 0. A missing `w` never wins. Timed sets with a `w` also count.

### 2.13 `effectiveRoutineId(S, iso)` / `effectiveRoutine(S, iso)`
```js
const ov = S.dayPlan[iso]
if (ov === 'rest') return null
if (ov && S.routines.some(r => r.id === ov)) return ov   // override to an existing routine
const wd = new Date(iso + 'T12:00:00').getDay()          // 0=Sun..6=Sat
return S.week[wd] || null                                 // the id may point to a deleted routine
```
`effectiveRoutine` returns the routine object or null (it also returns null when the id is stale).

### 2.14 `buildSets(S, cfg) → Set[]` (fresh sets for a new session, before the prescription is applied)
```js
const last = lastEntryFor(S, cfg.id)          // done sets only
const n = Math.max(1, cfg.sets || 1)
const mode = modeOf(cfg)
const prevAt = i => last ? (last.sets[i] || last.sets[last.sets.length - 1]) : null
```
- **cardio**: for each i, `{ min: prev ? prev.min : (cfg.min || 20), speed: prev ? prev.speed : (cfg.speed || 8), done: false }`
- **time**: `carried = prev && prev.sec > 0 ? prev : null` (a rep set is never used to seed a duration);
  `{ sec: carried ? carried.sec : (cfg.sec || 45), w: carried ? (carried.w || 0) : (cfg.weight || 0), done: false }`
- **reps**: `conf = S.exWeights[cfg.id]`; `usable = prev && prev.r > 0 ? prev : null` (a timed set has no `r`, so it is never used);
  `w = conf && conf.w > 0 ? conf.w : (usable ? usable.w : cfg.weight)`; `r = usable ? usable.r : cfg.reps`;
  gives `{ w, r, done: false }`.
  **The confirmed working weight `exWeights[id].w` beats last session's weights.** Last session's reps beat the plan's reps.
- When the plan now has more sets than last time, the extra positions reuse last time's **final** done set.

**Session-build pipeline** (in `beginWorkout`, and when an exercise is added mid-workout):
```js
plan  = nextPrescription(S, cfg, routine)
entry = { id: cfg.id, sg: cfg.sg, target: { ...cfg }, plan, sets: applyPrescription(buildSets(S, cfg), plan) }
active = { id: uid(), d: todayISO(), start: Date.now(), routineId, name: routine ? routine.name : 'Freestyle', bw, cur: 0, entries }
```

### 2.15 Aggregates
- `workoutVolume(w) = Σ over entries, Σ over done sets of (s.w || 0) * (s.r || 0)`. Timed sets (no `r`) and cardio sets add 0.
- `setsDone(w)` counts done sets across entries. `setsDoneActive(A)` does the same and returns 0 when `A` is null.
- `lastBW(S)` returns the last element of `S.bodyweight` (the array is sorted by `d`) or null.

### 2.16 Supersets
- `supersetUnits(items) → number[][]`: groups consecutive indices. Item i joins the previous unit when `i>0 && e.sg && prev.sg && e.sg === prev.sg`.
  Example: `[{},{sg:'a'},{sg:'a'},{sg:'b'},{sg:'a'},{}] → [[0],[1,2],[3],[4],[5]]`.
- `unitOf(units, idx)` returns the unit containing `idx`, or `[idx]`.

### 2.17 `streakWeeks(S) → int` (consecutive ISO weeks with at least one workout)
```js
if (!S.workouts.length) return 0
const weeks = new Set(S.workouts.map(w => weekKey(w.d)))
let streak = 0; const cur = new Date()
for (let i = 0; i < 520; i++) {
  if (weeks.has(weekKey(isoOf(cur)))) streak++
  else if (i > 0) break          // an empty CURRENT week doesn't break the streak (yet)
  cur.setDate(cur.getDate() - 7)
}
return streak
```
Capped at 520 weeks. A workout this week plus workouts in the 2 previous weeks gives 3.
No workout this week plus workouts in the last 2 weeks gives 2. A gap two weeks ago stops the count.

---

## 3. `format.js` — dates and number formatting

| export | spec |
|---|---|
| `todayISO()` | local date `YYYY-MM-DD` |
| `isoOf(d)` | local date of a Date as `YYYY-MM-DD` |
| `DAYN` | `['Sunday','Monday',…,'Saturday']` |
| `DAYS` | `['Su','Mo','Tu','We','Th','Fr','Sa']` |
| `MONTHS` | `['Jan',…,'Dec']` |
| `MONTHS_LONG` | `['January',…,'December']` |
| `fmtDate(iso, long)` | `new Date(iso+'T12:00:00').toLocaleDateString(locale, long ? {weekday:'short', day:'numeric', month:'short'} : {day:'numeric', month:'short'})`. en-GB gives `"1 Jan"` / `"Thu 1 Jan"` |
| `fmtDur(ms)` | `m = floor(ms/60000)`; `m >= 60 ? floor(m/60)+'h '+(m%60)+'m' : m+' min'` |
| `durPart(ms)` | `ms >= 60000 ? [fmtDur(ms)] : []`. An unknown or zero duration is left out |
| `fmtNum(n)` | `round1(n).toLocaleString(locale)`. Default locale **`en-GB`** (`1,234.6`); per UI language: en→en-GB, de→de-DE, es→es-ES, fr→fr-FR, it→it-IT, pt→pt-PT, pl→pl-PL, tr→tr-TR, ru→ru-RU, zh→zh-CN, ko→ko-KR, hi→hi-IN. Grouping on, at most 3 fraction digits (only 1 can occur after rounding). Dart: `NumberFormat('#,##0.###', locale)` |
| `fmtVol(v, unit)` | `fmtNum(v) + ' ' + unit`, always in the profile unit, never "t" |
| `exCount(n)` | `t(n===1 ? '{0} exercise' : '{0} exercises', n)` |
| `weekKey(iso)` | **ISO-8601 week** as `"<ISO-week-year>-<week>"`, **week not zero-padded**. Algorithm: local noon of the date → move to the Thursday of its Mon–Sun week → `week = 1 + round(((thu − jan4)/86400000 − 3 + ((jan4.getDay()+6)%7)) / 7)`, where `jan4` is Jan 4 of the Thursday's year |
| `localTZ()` | IANA tz or `'UTC'` |
| `uid()` | `Date.now().toString(36) + Math.random().toString(36).slice(2,7)` |
| `ACCENTS` | `{lime:'#30d158', sky:'#0a84ff', orange:'#ff9f0a', violet:'#bf5af2', pink:'#ff375f', red:'#ff453a', teal:'#40c8e0', gold:'#ffd60a'}` |

`weekKey` golden values from the reference run:

| date | weekKey |
|---|---|
| 2025-12-29 (Mon) | `2026-1` |
| 2026-01-01 | `2026-1` |
| 2026-12-31 | `2026-53` |
| 2027-01-01 | `2026-53` |
| 2027-01-03 (Sun) | `2026-53` |
| 2027-01-04 (Mon) | `2027-1` |
| 2020-12-31 | `2020-53` |
| 2021-01-03 | `2020-53` |
| 2024-12-30 | `2025-1` |

---

## 4. `progression.js` — automatic progression (Greyskull, linear, double, time)

### 4.1 Constants

```js
POLICIES     = ['off', 'linear', 'greyskull', 'double', 'time']
POLICIES_FOR = { reps: ['off','linear','greyskull','double'], time: ['off','time'], cardio: ['off'] }
DELOAD_AFTER = { linear: 3, greyskull: 1, double: 3, time: 3 }   // consecutive missed sessions before deload
DELOAD_FACTOR = 0.9        // private
HEAVY_BP = ['upper legs','lower legs','back','hips','glutes']    // private; 'hips','glutes' never occur as bp (dead)
DEFAULT_SEC_INCREMENT = 5
```
`POLICY_NAME` (i18n keys):
- off: `'No automatic progression'`
- linear: `'Linear progression'`
- greyskull: `'Greyskull LP'`
- double: `'Double progression'`
- time: `'Add time'`

`POLICY_DESC` (i18n keys, verbatim):
- off: `'Targets stay where you set them.'`
- linear: `'Hit every rep in every set and the weight goes up. Repeated misses trigger a deload.'`
- greyskull: `'Two straight sets plus a final set taken to failure. Beat the target on that set and the weight goes up — double if you double the reps. One failure resets 10 %.'`
- double: `'Work up through a rep range at the same weight. Reach the top of the range in every set and the weight goes up, reps back to the bottom.'`
- time: `'Hold every set for the full duration and the target goes up.'`

### 4.2 `defaultIncrement(exId, unit) → number`
```js
const ex = EXIDX[exId]; const heavy = ex && HEAVY_BP.includes(ex.bp)
if (unit === 'lb') return heavy ? 10 : 5
return heavy ? 5 : 2.5              // any unit other than 'lb' is treated as kg
```

| | kg | lb |
|---|---|---|
| heavy bp (upper legs, lower legs, back) | 5 | 10 |
| everything else, or an unknown id | 2.5 | 5 |

**Effective increment**: `inc = cfg.inc > 0 ? cfg.inc : (mode === 'time' ? 5 : defaultIncrement(cfg.id, S.unit || 'kg'))`.
In the config UI the increment stepper moves by 1.25 (weight) or 5 (seconds).

### 4.3 `policyFor(cfg, routine, mode?) → Policy`
```js
const m = mode || modeOf(cfg || {})
const allowed = POLICIES_FOR[m] || ['off']
const pick = (cfg && cfg.prog) || (routine && routine.prog) || (m === 'reps' ? 'linear' : 'off')
return allowed.includes(pick) ? pick : 'off'
```
The exercise override beats the routine default, which beats the mode default (`reps` → `linear`,
anything else → `off`). A policy that is invalid for the mode becomes `off`, and the lookup
does **not** fall back to the next level. For example, an exercise `prog:'greyskull'` on a timed
exercise gives `off` even when the routine says `time`.

### 4.4 Rounding helpers (private)
```js
const round1 = v => Math.round(v * 10) / 10
function snap(v, step) {                 // nearest loadable multiple of step
  if (!(step > 0)) return round1(v)
  return round1(Math.round(v / step) * step)
}
function deloadTo(cur, step) {           // ~10 % cut, guaranteed lighter, never below one step
  let next = snap(cur * DELOAD_FACTOR, step)
  if (next >= cur) next = snap(cur - step, step)
  return Math.max(step, next)
}
```
Worked examples with step 2.5:
- 60 → 54 → snaps to **55**
- 55 → 49.5 → **50**
- 40 → 36 → **35**
- 20 → 18 → **17.5**
- 5 → 4.5 → snaps to 5, which is not lighter, so 5 − 2.5 = **2.5**
- 2.5 → 2.25 → 2.5, not lighter, so 0, then max(2.5, 0) = **2.5**

With step 5 s, 45 s → 40.5 → **40**.

### 4.5 `readSession(entry, fallback?) → Session`
This reduces one logged entry to what the policies judge.
```js
const target  = (entry && entry.target) || fallback || {}   // legacy (targetless) entries judged against current plan
const mode    = modeOf({ ...target, id: entry && entry.id })
const sets    = (entry && entry.sets) || []
const planned = target.sets || sets.length
const enough  = sets.length >= planned                         // counts ALL sets, checked or not

// time mode
goal = target.sec || 0
held = sets.map(s => s.done ? (s.sec || 0) : 0)
→ { mode, goal, held,
    weight: Math.max(0, ...doneSets.map(s => s.w || 0)),
    best:   Math.max(0, ...held),
    ok:     goal > 0 && enough && held.length > 0 && held.every(h => h >= goal) }

// reps (and cardio, which is read the reps way but never used)
goal = target.reps || 0
reps = sets.map(s => s.done ? (s.r || 0) : 0)                  // unchecked set ⇒ 0 reps
→ { mode, goal, reps,
    weight: Math.max(0, ...doneSets.map(s => s.w || 0)),       // working weight from DONE sets only
    low:    reps.length ? Math.min(...reps) : 0,               // worst set (0 if any unchecked)
    amrap:  reps.length ? reps[reps.length - 1] : 0,           // final set (Greyskull AMRAP)
    ok:     goal > 0 && enough && reps.length > 0 && reps.every(r => r >= goal) }
```
A session is a **hit** only when every set, including the last, is checked and reached at least
`goal` reps (or seconds), with at least the prescribed number of sets. The following count as a
**miss**:
- short reps on any set
- any unchecked set
- fewer sets than `target.sets`
- `goal` = 0 or missing

### 4.6 `sessionsFor(S, exId, fallback?) → (Session & {d})[]`
The function walks the workouts in array order, oldest first. In each workout it takes the first
entry with `id === exId`, and only when that entry has ≥1 done set. It pushes
`{ d: w.d, ...readSession(entry, fallback) }`.

### 4.7 `stallCount(sessions) → int`
This counts consecutive `!ok` sessions, going back from the last one. `[]` gives 0.

### 4.8 `nextPrescription(S, cfg, routine?) → Prescription`

Return shape: `{ policy, kind, weight?, reps?, sec?, why? }`. The values are:
- `kind` ∈ `first | up | hold | deload | off`
- `why` = `[i18nTemplate, ...args]` (args are raw numbers or unit strings, substituted into `{0}`, `{1}`…)

A field the policy has no opinion on is **absent** (undefined).

```
mode   = modeOf(cfg)
policy = policyFor(cfg, routine, mode)
unit   = S.unit || 'kg'
inc    = cfg.inc > 0 ? cfg.inc : (mode === 'time' ? 5 : defaultIncrement(cfg.id, unit))
if policy == 'off'                         → { policy, kind: 'off' }
sessions = sessionsFor(S, cfg.id, cfg).filter(s => s.mode === mode)     // cfg is the legacy fallback
last = sessions.at(-1)
if !last → { policy, kind: 'first', why: ['Nothing logged yet — this session sets the baseline.'] }
stalls   = stallCount(sessions)            // over the mode-filtered list
deloadAt = DELOAD_AFTER[policy] || 3
```

**TIME mode** (policy is necessarily `time`):

| condition | result |
|---|---|
| `last.ok` | `kind:'up'`, `sec = (last.goal \|\| cfg.sec \|\| 0) + inc`, why `['Held every set for the full time — target up by {0}s.', inc]` |
| `stalls >= deloadAt` (3) | `kind:'deload'`, `sec = deloadTo(last.goal \|\| cfg.sec \|\| 0, 5)` (**step hard-coded to 5 s, not `inc`**), why `['Short {0} sessions in a row — back off to {1}s and build up again.', stalls, sec]` |
| otherwise | `kind:'hold'`, `sec = last.goal \|\| cfg.sec`, why `['Last time came up short — same target again.']` |

No `weight` is returned in time mode.

**REPS mode.** Let `w = last.weight`, the max weight of the last session's done sets.

1. **Bodyweight** (`w <= 0`, which applies to every policy and runs first):
   - `goal = last.goal || cfg.reps || 0`
   - If `last.ok && goal > 0`: `kind:'up'`, `weight: 0`, `reps: goal + 1`, why `['Bodyweight — every rep last time, so go for {0} this time.', goal+1]`
   - Otherwise: `kind:'hold'`, `weight: 0`, `reps: goal || undefined`, why `['Bodyweight — same target again until every set is clean.']`
   - A bodyweight exercise never gets a deload.
2. **Double progression** (`policy === 'double'`):
   - `top = cfg.reps || last.goal || 10`
   - `bottom = Math.min(cfg.repsMin || Math.max(1, top - 2), top)`
   - If `last.ok` (every set ≥ `last.goal`, and `last.goal` is `target.reps`, the top of the range):
     `kind:'up'`, `weight: snap(w + inc, inc)`, `reps: bottom`,
     why `['Top of the rep range in every set — {0} {1} more, back to {2} reps.', inc, unit, bottom]`
   - Else if `stalls >= 3`: `dw = deloadTo(w, inc)`, `kind:'deload'`, `weight: dw`, `reps: bottom`,
     why `['Stalled {0} sessions — deload to {1} {2}.', stalls, dw, unit]`
   - Otherwise: `aim = Math.min(top, Math.max(bottom, last.low + 1))`, `kind:'hold'`, `weight: w`, `reps: aim`,
     why `['Same weight — aim for {0} reps this time.', aim]`.
     An unchecked set makes `low = 0`, so `aim = bottom`.
3. **Linear and Greyskull**:
   - If `last.ok`:
     - `dbl = policy === 'greyskull' && last.goal > 0 && last.amrap >= last.goal * 2`
     - `step = dbl ? inc * 2 : inc`
     - Result: `kind:'up'`, `weight: snap(w + step, inc)`
     - why when `dbl`: `['Last set hit {0} reps — twice the target, so take a double jump of {1} {2}.', last.amrap, step, unit]`
     - why otherwise: `['Every rep last time — {0} {1} more.', step, unit]`
     - `reps` is not returned.
   - Else if `stalls >= deloadAt` (linear 3, greyskull **1**, so Greyskull deloads on the first miss and never holds):
     - `dw = deloadTo(w, inc)`, `kind:'deload'`, `weight: dw`
     - why when `stalls > 1`: `['Missed reps {0} sessions running — reset to {1} {2} and work back up.', stalls, dw, unit]`
     - why when `stalls == 1`: `['Missed reps — reset to {0} {1} and work back up.', dw, unit]`
   - Otherwise: `kind:'hold'`, `weight: w`, why `['Missed reps last time — same weight again ({0} of {1} to go).', deloadAt - stalls, deloadAt]`

Notes:
- `snap(w + inc, inc)` snaps to the grid of multiples of `inc`, so an off-grid weight moves onto the grid.
  For example, `61` with inc 2.5 gives 63.5, which snaps to **62.5**. The result is always > `w`.
- `unit` in the why args is the literal `S.unit` string (`'kg'`/`'lb'`).
- The UI shows the `why` line with an icon: `up` → arrowUp, `deload` → arrowDown with a warning style, anything else → lightbulb. Nothing is shown when kind is `off` or `why` is absent.

### 4.9 `applyPrescription(sets, p) → Set[]`
```js
if (!p || p.kind === 'off' || p.kind === 'first') return sets      // same reference
return sets.map(s => {
  if (s.done) return s
  const out = { ...s }
  if (p.weight != null) out.w = p.weight
  if (p.reps   != null) out.r = p.reps
  if (p.sec    != null) out.sec = p.sec
  return out
})
```

---

## 5. `onerm.js` — estimated one-rep max

```js
REP_CAP = 12
FORMULAS = {
  epley:    (w, r) => w * (1 + r / 30),        // default
  brzycki:  (w, r) => w * 36 / (37 - r),
  lombardi: (w, r) => w * Math.pow(r, 0.1)
}
DEFAULT_FORMULA = 'epley'
```

### 5.1 `estimate1RM(w, r, formula = 'epley') → number|null`
```js
const weight = Number(w), reps = Number(r)
if (!isFinite(weight) || !isFinite(reps)) return null
if (weight <= 0 || reps < 1) return null
if (reps > REP_CAP) return null                 // compared BEFORE rounding: 12.4 → null
const fn = FORMULAS[formula] || FORMULAS.epley  // unknown formula → epley
const est = reps === 1 ? weight : fn(weight, Math.round(reps))   // exactly 1 rep = measured, unchanged
if (!isFinite(est) || est <= 0) return null
return Math.round(est * 10) / 10
```
Input can be a numeric string. `''` and `null` become 0 and give null. `undefined` becomes NaN
and gives null. Fractional reps are rounded for the formula: 2.5 is treated as 3, so 100×2.5
gives 110. Reps of 1.2 are **not** exactly 1, so the result is `epley(100, 1)` = 103.3.

### 5.2 `bestSetOf(entry, formula) → { est, w, r } | null`
The function scans `entry.sets` and skips sets that are not done. The best set is the one with
the highest `estimate1RM(s.w, s.r)` (strictly greater wins, so the first one wins ties). It
returns `{ est, w: Number(s.w), r: Math.round(Number(s.r)) }`.
- `topW` is **ignored** because it has no rep count.
- Cardio and timed sets have no `r`, so they return null automatically.
- A null entry returns null.

### 5.3 `e1rmSeries(S, exId, formula) → { t, d, y, w, r }[]`
For each workout in array order, the function takes the first entry for `exId`. When
`bestSetOf` is non-null it pushes `{ t: w.start, d: w.d, y: best.est, w: best.w, r: best.r }`.

### 5.4 `best1RM(S, exId, formula) → { est, w, r, d, t } | null`
Returns the max `y` over `e1rmSeries`, where strictly greater wins so the earliest max is kept.
It is safe with `{}` (no `workouts`).

### 5.5 `is1RMRecord(S, exId, entry, formula) → { est, w, r, prev } | null`
`now = bestSetOf(entry)` and `prev = best1RM(S, exId)`, where `S` does **not** yet contain the
workout being finished. The function returns `{ ...now, prev: prev ? prev.est : 0 }` when
`!prev || now.est > prev.est` (strictly), and null otherwise. The first ever estimate counts
as a record with `prev = 0`.

---

## 6. `effort.js` — RIR/RPE statistics

All aggregation happens in **RIR**, and results are converted back for display. The reason
is that RIR has a real zero (failure) while RPE has a conventional floor.

```js
HARD_RIR  = 3      // RIR ≤ 3 ⇒ "hard set"
MIN_RATED = 5      // fewer rated sets than this ⇒ avg/hardPct are null (UI shows "—")
BUCKETS   = 4      // histogram bins 0,1,2,3 and a "4+" tail
```

| fn | spec |
|---|---|
| `rirOf(s)` | `!s ? null : s.rir != null ? s.rir : s.rpe != null ? 10 - s.rpe : null`. RIR wins when both exist. 0 is a valid rating |
| `toScale(kind, rir)` | `rir == null ? null : round1(kind === 'rpe' ? 10 - rir : rir)` |
| `displayScale(S)` | if `effortOf(S)` is `'rir'`/`'rpe'` it returns that. Otherwise it counts **all** done sets in all workouts (no window): `rir++` when `s.rir != null`, else `rpe++` when `s.rpe != null`. Returns `rpe > rir ? 'rpe' : 'rir'` |
| `scaleName(kind)` | `EFFORT[kind].hd` → `'RIR'`/`'RPE'` |
| `avgRir(sets)` | mean of the non-null `rirOf` values, or null when there are none. `null`/`[]` give null |
| `effortSummary(S, days)` | see below |
| `hasEffort(S)` | true when any done set has a non-null `rirOf`. It decides whether the Effort card exists |
| `effortWeeks(S, days)` | see below |
| `effortHistogram(S, days)` | see below |
| `isHardSet(s)` | `r = rirOf(s); r != null && r <= 3` |

The private helper `eachDoneSet(S, fn)` visits every `done` set, in workouts → entries → sets
order, with `(s, w, e)`.

**Window** `inWindow(w, days)` is `!days || (w.start || new Date(w.d).getTime()) > Date.now() - days*86400000`:
- `days = 0` (or falsy) means everything.
- The comparison is strict.
- When there is no `start`, `new Date(w.d)` parses as **UTC midnight**.

**`effortSummary(S, days) → { done, rated, hard, avg, hardPct }`**. The function visits every
done set inside the window:
1. `done++`
2. `r = rirOf(s)`; a null `r` skips the rest
3. `rated++`, `sum += r`, and `hard++` when `r <= 3`

Then `avg = rated >= 5 ? sum/rated : null` and `hardPct = rated >= 5 ? hard/rated : null`.

**`effortWeeks(S, days) → { t, rir, n, sets }[]`**
- Groups done sets in the window by `weekKey(w.d)`. For each week, `sets` counts all done sets
  and `n`/`sum` cover the rated ones.
- `t = mondayOf(w.d)`: the local-noon timestamp of that ISO week's Monday.
- Drops weeks with `n < 2`, sorts by `t` ascending and maps to `{ t, rir: sum/n, n, sets }`.

**`effortHistogram(S, days) → { rir, tail, n, pct }[5]`**
- For each rated done set in the window, the bin is `min(4, max(0, floor(r)))`.
- Output: `[{rir:0..4, tail: i===4, n, pct: rated ? n/rated : 0}]`.
- Display labels: RIR `0,1,2,3,4+`; RPE `10,9,8,7,≤ 6`. Bars with `rir <= 3` are highlighted.

**Stats windows used by callers**:
- Effort card: 30/90/365/0 days, default 90.
- Body-weight chart: 30/90/365/0, default 90.
- The Muscle-balance window is different (§8.4).

---

## 7. `muscles.js` — muscle credit, load and map levels

### 7.1 Constants
```js
MUSCLES = ['trapezius','deltoids','chest','upper-back','serratus','biceps','triceps','forearm',
           'abs','obliques','lower-back','gluteal','quadriceps','hamstring','adductors','hip-flexors',
           'calves','tibialis']                        // 18 drawable muscles, head-to-toe order
INERT   = ['head','hair','neck','hands','feet','knees','ankles']   // silhouette only
SECONDARY = 0.4
```
`MUSCLE_NAME` (the English display names, which are also the i18n keys):

| slug | name | slug | name |
|---|---|---|---|
| trapezius | Traps | abs | Abs |
| deltoids | Shoulders | obliques | Obliques |
| chest | Chest | lower-back | Lower back |
| upper-back | Upper back | gluteal | Glutes |
| serratus | Serratus | quadriceps | Quads |
| biceps | Biceps | hamstring | Hamstrings |
| triceps | Triceps | adductors | Adductors |
| forearm | Forearms | hip-flexors | Hip flexors |
| | | calves | Calves |
| | | tibialis | Shins |

`ALIAS` maps a free-text name (lower-cased, trimmed) to a slug, or to `null` when the name is
not drawable:

| name | slug | name | slug |
|---|---|---|---|
| abs | abs | shoulders | deltoids |
| pectorals | chest | deltoids | deltoids |
| biceps | biceps | rear deltoids | deltoids |
| glutes | gluteal | rotator cuff | deltoids |
| delts | deltoids | quadriceps | quadriceps |
| triceps | triceps | core | abs |
| upper back | upper-back | abdominals | abs |
| lats | upper-back | lower abs | abs |
| calves | calves | chest | chest |
| quads | quadriceps | upper chest | chest |
| forearms | forearm | hip flexors | hip-flexors |
| hamstrings | hamstring | obliques | obliques |
| spine | lower-back | lower back | lower-back |
| traps | trapezius | rhomboids | upper-back |
| adductors | adductors | trapezius | trapezius |
| serratus anterior | serratus | back | upper-back |
| abductors | gluteal | latissimus dorsi | upper-back |
| levator scapulae | trapezius | brachialis | biceps |
| cardiovascular system | **null** | soleus | calves |
| | | shins | tibialis |
| | | wrists | forearm |
| | | wrist flexors | forearm |
| | | wrist extensors | forearm |
| | | grip muscles | forearm |
| | | groin | adductors |
| | | inner thighs | adductors |
| | | ankles, feet, hands, ankle stabilizers, sternocleidomastoid | **null** |

Every `tg`/`sm` spelling in the 1324-exercise dataset appears in this table. Every built-in
exercise, including every cardio one, resolves to at least one muscle through `tg` or `sm`.

`BY_BODYPART` is the fallback for custom exercises, which have `tg: ''` and no `sm`. The
weights for each body part sum to 1:
```js
chest:        { chest: 1 }
back:         { 'upper-back': 0.75, 'lower-back': 0.25 }
shoulders:    { deltoids: 1 }
'upper arms': { biceps: 0.5, triceps: 0.5 }
'lower arms': { forearm: 1 }
waist:        { abs: 0.7, obliques: 0.3 }
'upper legs': { quadriceps: 0.4, hamstring: 0.35, gluteal: 0.25 }
'lower legs': { calves: 0.8, tibialis: 0.2 }
neck:         { trapezius: 1 }
cardio:       {}
```

### 7.2 `musclesOf(ex) → { slug: weight }`
```js
if (!ex) return {}
const out = {}
const add = (name, w) => { const slug = ALIAS[String(name || '').toLowerCase().trim()]; if (slug) out[slug] = Math.max(out[slug] || 0, w) }
add(ex.tg, 1)                               // primary counts 1.0
;(ex.sm || []).forEach(m => add(m, 0.4))    // each secondary counts 0.4; max() so a primary is never downgraded
if (!Object.keys(out).length) Object.assign(out, BY_BODYPART[ex.bp] || {})
return out
```
Examples:
- bench `0025` (tg pectorals, sm triceps, shoulders) → `{chest:1, triceps:0.4, deltoids:0.4}`
- barbell full squat `0043` (tg glutes; sm quadriceps, hamstrings, calves, core) → `{gluteal:1, quadriceps:0.4, hamstring:0.4, calves:0.4, abs:0.4}`
- custom `{bp:'upper legs', tg:''}` → `{quadriceps:0.4, hamstring:0.35, gluteal:0.25}`

### 7.3 Load ("effective sets")
- `loadOf(items: {id, sets:int}[])`: skips items with `!sets`. `m = musclesOf(EXIDX[id])`, and an unknown id gives `{}`.
  Then `load[slug] += m[slug] * sets`. The weight in kg is deliberately ignored.
- `loadOfWorkouts(workouts, pick?)`: each entry contributes `{ id, sets: count of sets with done && (!pick || pick(s)) }`.
  With `pick = isHardSet`, the map shows where the hard sets went.
- `loadOfRoutine(routine)`: `{ id: c.id, sets: c.sets || 1 }` for each routine exercise (planned load).
- `loadOfActive(active)`: counts the done sets so far.

Example: `loadOf([{id:'0025',sets:4},{id:'0001',sets:3}])` gives
`{chest:4, triceps:1.6, deltoids:1.6, abs:3, 'hip-flexors':1.2, 'lower-back':1.2}`, where the
last two are `1.2000000000000002` in float.

### 7.4 `levelsOf(load) → { slug: 0..4 }` for all 18 muscles
```js
const max = Math.max(0, ...MUSCLES.map(m => load[m] || 0))
lv[m] = !v ? 0 : max <= 0 ? 0 : Math.max(1, Math.min(4, Math.ceil(v / max * 4)))
```
Levels are relative to the hardest-worked muscle in the same load. Any non-zero load is at
least level 1. The same 0–4 shade classes are used by the heatmap.

Example: `{chest:12, triceps:4.8, deltoids:4.8, abs:1, quadriceps:0.1}` gives chest 4,
triceps 2, deltoids 2, abs 1, quadriceps 1, and 0 for the rest.

### 7.5 `rankOf(load) → { worked, missed }`
- `worked`: muscles with load > 0, sorted by load descending. The sort is stable, so ties keep body order.
- `missed`: the untrained muscles in body order.

The UI shows the top 4 worked muscles with bars and the sets rounded to 1 decimal, plus
"Not trained in this period" chips for the missed muscles.

---

## 8. Engine logic that currently lives in UI files (port it into the engine)

### 8.1 Finishing a workout: load PRs, e1RM PRs, stored record, `exWeights`
This is `doFinishWorkout` in `sheets.jsx`. Here `st` is the state **before** the workout is appended.
```js
prs = []; e1prs = []
for e of A.entries:
  mx = Math.max(0, ...e.sets.filter(done).map(s => s.w))       // NB: undefined w (cardio) ⇒ NaN ⇒ never a PR
  if (mx > 0 && mx > bestWeightFor(st, e.id)) prs.push(e.id)    // LOAD PR: heavier than any done set or topW ever
  rec = is1RMRecord(st, e.id, e)
  if (rec && !prs.includes(e.id)) e1prs.push({ id: e.id, ...rec })   // e1RM PR only when not already a load PR
w = { id: A.id, d: A.d, start: A.start, end: Date.now(), routineId: A.routineId, name: A.name, bw: A.bw,
      entries: A.entries.map(e => ({ id, sets: e.sets, topW: e.topW || null, target: e.target || null }))
                        .filter(e => e.sets.some(s => s.done)),
      prs }
w.vol = workoutVolume(w)
for e of w.entries:
  mx = Math.max(0, ...doneSets.map(x => x.w || 0), e.topW || 0)
  if (mx > 0 && (!exWeights[e.id] || mx > exWeights[e.id].w)) exWeights[e.id] = { w: mx, d: w.d }
S.workouts.push(w); S.active = null
```
Timed sets that carry a weight can produce a load PR. Unchecked sets are kept in the stored entry.

Other rules around finishing:
- **Top-weight confirmation.** After every set of a **reps** entry is checked, the app asks once
  per entry (`asked` flag). The default value is `max(maxDoneSetW, prevBest) || target.weight || 0`,
  where `prevBest = max(exWeights[id].w, bestWeightFor)`. On save:
  - `n = round1(v)`, which must be finite and ≥ 0
  - `entry.topW = n`
  - `exWeights[id] = { w: max(n, cur?.w || 0), d: today }` (the date is always refreshed)
- **Finish guards.** No sets done means a confirm dialog ("Finish anyway"). Some sets unchecked
  means "Finish early?" with the count.

### 8.2 "Best" shown during a workout
`best = cardio ? 0 : max(bestWeightFor(S,id), exWeights[id]?.w || 0)`. The workout screen and
the top-weight sheet use the same number.

### 8.3 Activity heatmap (last 12 months, shaded by minutes trained)
```js
agg[d] = { n: #workouts that day, vol: Σ w.vol, min: Σ max(0, round(((w.end || w.start) - w.start) / 60000)) }
mins = Object.values(agg).map(a => a.min).filter(v => v > 0).sort(asc)
q(p) = mins.length ? mins[Math.min(mins.length - 1, Math.floor(p * mins.length))] : 0
t1 = q(.25); t2 = q(.5); t3 = q(.75)
level(a) = !a ? 0 : !a.min ? 1 : a.min >= t3 ? 4 : a.min >= t2 ? 3 : a.min >= t1 ? 2 : 1
```
The thresholds are quartiles of the user's own positive-minute days. A workout day with 0
minutes (imported without a clock) is level 1.

The grid has 53 columns, one per Monday-to-Sunday week:
- `end` is the Monday of the current week (local noon) and `start = end − 52×7 days`.
- Column `wk` starts at `start + 7·wk` days and runs 7 rows, Monday first.
- Days after today get the `future` style.
- A month label appears on a column whose first day is day 1–7 of a month different from the
  last labelled month, but only when `wk < 51`.
- Cell title: `"<iso> · N workout(s) · M min · <vol unit>"`. Tapping a day opens that day's
  workout, or the calendar when the day has several.

### 8.4 Stats windows and metrics
- **Muscle balance** (`loadOfWorkouts` + `levelsOf` + `rankOf`):
  - window options: `7` = **same ISO week as today** (`weekKey(w.d) === weekKey(today)`, not rolling), `30`/`90` = rolling days by `w.start || new Date(w.d)`, `0` = all
  - default window: 7
  - "Hard" toggle: offered only when the window contains at least one done hard set; it uses `pick = isHardSet`
- **Exercise progress** (per exercise):
  - Which exercises appear: ids seen in any workout that exist in EXIDX, sorted by name.
  - Mode: taken from the most recent workout entry for the exercise, `modeOf({...(en.target||{}), id})`.
  - Metric per workout (first entry of the exercise): `max(0, done sets' metric, reps-mode ? topW||0 : 0)`, where the metric is `speed` for cardio, `sec` for time and `w` for reps. Only points > 0 are kept.
  - The best value is the max of the points. The list shows the last 5 sessions, newest first.
  - The e1RM toggle appears when `e1rmSeries` has ≥1 point.
  - Effort per session is `avgRir(done sets)`. The Effort toggle appears when ≥3 sessions are rated.
  - On the top-set curve, the dot fill is `1 − clamp(avgRir, 0, 4)/4`.
- **Tiles**:
  - total workouts
  - workouts this calendar month (`w.d.slice(0,7) === today.slice(0,7)`)
  - `streakWeeks`
  - body-weight Δ over 30 days: last minus first entry with `(b.t || Date(b.d)) > now − 30d`, shown when there are ≥2 entries
- **Home**:
  - workouts this ISO week
  - `plannedPerWeek` = number of truthy `S.week` keys
  - week strip dots: done if any workout on that date, else ovr if `dayPlan` has the date and a routine is effective, else plan if a routine is effective

### 8.5 In-workout steppers (UI constants that shape logged values)
- Each stepper tap computes `max(0, round2(cur + dir·step))`.
  - reps sets: weight step 2.5, reps step 1
  - time sets: sec step 5, weight step 2.5
  - cardio sets: min step 1, speed step 0.5
- The effort column (reps mode only, when `EFFORT[effortOf(S)]` exists) uses `stepEffort` and `capEffort`.
- A timed set has a work timer. It auto-completes at 0 with `sec = total`. An early finish logs `elapsed = max(1, total − left)`.

---

## 9. `sound.js` — beeps and haptics

`beep(enabled, freq = 880, dur = 0.18, when = 0)`. It does nothing when `enabled` is falsy. The
sound is a sine oscillator with this gain envelope, starting at `t0 = now + when`:
- 0.001 at t0
- exponential ramp to 0.35 by t0 + 0.02
- exponential ramp to 0.001 by t0 + dur

The oscillator stops at `t0 + dur + 0.05`. The audio context is created lazily and reused, and
errors are swallowed. `vibrate(pattern)` calls `navigator.vibrate` when available.

Event → sound map (the `enabled` flag is `S.sound`):

| event | beeps (freq Hz, dur s, when s) | vibrate |
|---|---|---|
| set checked off | (1040, 0.12) | 30 ms |
| rest countdown, each of the last 3 s | (660, 0.1) | – |
| rest over | (880,0.15,0), (880,0.15,0.25), (1320,0.4,0.5) | [200,100,200] |
| timed set: last 3 s | (660, 0.1) | – |
| timed set complete | same as "rest over" | [200,100,200] |
| timed set finished early | – | 30 ms |
| workout finished | (880,0.15,0), (1100,0.15,0.18), (1320,0.3,0.36) | – |

Rest timer:
- It starts after checking a set when the current unit (exercise or superset) is not complete and the checked exercise is the last in its unit. The length is `S.restSec`, default 90.
- It stops when the unit completes.
- `addRest(±sec)`: when the result would be ≤ 0, it stops the timer instead.
- Starting a work timer stops the rest timer.

Flutter: use a short tone asset or synthesis, plus `HapticFeedback` or the `vibration` package.

---

## 10. Test cases to port (transcribed from the `*.test.js` files)

### Fixture conventions
- Catalogue ids from the tests: **LIFT = `'0001'`** (3/4 sit-up, bp `waist`, so not heavy and not cardio), **HEAVY = `'1512'`** (bp `upper legs`), **CARDIO = `'3220'`** (bp `cardio`). A Dart test catalogue only needs these three records with the right `bp`.
- `hist(id, rows, target?)` builds `{ unit:'kg', workouts }`:
  - Workout `i` has `d = '2026-01-0'+(i+1)`.
  - Its single entry is `{ id, target: target || {sets:3, reps:5, weight: row[0]}, sets }`.
  - Each `row = [weight, r1, r2, …]` gives sets: `r === null` becomes `{w: weight, r: 0, done:false}`, otherwise `{w: weight, r, done:true}`.
- Absent / undefined in the expected column means the key is not present.

### 10.1 `readSession` (with `T = {sets:3, reps:5}`)
| # | entry | expected |
|---|---|---|
| 1 | `{id:LIFT, target:T, sets:[60×5✓, 60×5✓, 60×6✓]}` | `ok=true, weight=60, amrap=6, low=5` |
| 2 | sets `[60×5✓, 60×5✓, 60×3✓]` | `ok=false` |
| 3 | sets `[60×5✓, 60×5✓, {w:60,r:0,done:false}]` | `ok=false, weight=60` |
| 4 | sets `[60×5✓, 60×5✓]` (2 of 3) | `ok=false` |
| 5 | `target:{}`, sets `[60×5✓]` | `ok=false` |
| 6 | `target:{sets:2, sec:45, mode:'time'}`, sets `[{sec:45,w:0,done:true},{sec:50,w:0,done:true}]` | `mode='time', ok=true, best=50` |
| 7 | same target, sets `[{sec:45,done:true},{sec:30,done:true}]` | `ok=false` |

### 10.2 `stallCount`
| input `ok` list | expected |
|---|---|
| `[true, true]` | 0 |
| `[true, false]` | 1 |
| `[false, false, false]` | 3 |
| `[false, true, false]` | 1 |
| `[]` | 0 |

### 10.3 `policyFor`
| cfg | routine | mode | expected |
|---|---|---|---|
| `{id:LIFT}` | null | reps | `linear` |
| `{id:LIFT, mode:'time'}` | null | time | `off` |
| `{id:CARDIO}` | null | cardio | `off` |
| `{id:LIFT}` | `{prog:'greyskull'}` | reps | `greyskull` |
| `{id:LIFT, prog:'double'}` | `{prog:'greyskull'}` | reps | `double` |
| `{id:LIFT, mode:'time', prog:'greyskull'}` | null | time | `off` |
| `{id:CARDIO, prog:'linear'}` | null | cardio | `off` |
| — | — | — | `POLICIES_FOR.cardio` equals `['off']` |

### 10.4 `defaultIncrement`
| exId | unit | expected |
|---|---|---|
| LIFT | kg | 2.5 |
| HEAVY | kg | 5 |
| LIFT | lb | 5 |
| HEAVY | lb | 10 |
| `'nope'` | kg | 2.5 |

### 10.5 `nextPrescription`: linear (`cfg = {id:LIFT, sets:3, reps:5, weight:60, prog:'linear'}`)
| # | S | cfg override | expected |
|---|---|---|---|
| 1 | `{unit:'kg', workouts:[]}` | – | `kind='first'`, `weight` undefined |
| 2 | `hist(LIFT, [[60,5,5,5]])` | – | `kind='up'`, `weight=62.5` |
| 3 | `hist(LIFT, [[60,5,5,3]])` | – | `kind='hold'`, `weight=60` |
| 4 | `hist(LIFT, [[60,5,5,null]])` | – | `kind='hold'`, `weight=60` |
| 5 | `hist(LIFT, [[60,5,5,3],[60,5,4,4],[60,5,5,4]])` | – | `kind='deload'`, `weight=55`; also `DELOAD_AFTER.linear == 3` |
| 6 | `hist(LIFT, [[60,5,5,3],[60,5,5,5],[60,5,5,3]])` | – | `kind='hold'` |
| 7 | `hist(LIFT, [[2.5,1,1,1],[2.5,1,1,1],[2.5,1,1,1]])` | – | `kind='deload'`, `weight=2.5` |
| 8 | `hist(LIFT, [[5,1,1,1]]×3)` | – | `weight < 5` (actual: 2.5) |
| 9 | `hist(HEAVY, [[100,5,5,5]])` | `{id:HEAVY, sets:3, reps:5, prog:'linear'}` | `weight=105` |
| 10 | `hist(LIFT, [[60,5,5,5]])` | `{...cfg, inc:1}` | `weight=61` |
| 11 | `{...hist(LIFT, [[135,5,5,5]]), unit:'lb'}` | – | `weight=140` |

### 10.6 Bodyweight (`cfg = {id:LIFT, sets:3, reps:10, weight:0, prog:'linear'}`, `bw(rows) = hist(LIFT, rows, {sets:3, reps:10})`)
| # | S | cfg | expected |
|---|---|---|---|
| 1 | `bw([[0,10,10,8],[0,10,10,9],[0,10,10,8]])` | cfg | `kind='hold', weight=0, reps=10` |
| 2 | `bw([[0,10,10,10]])` | cfg | `kind='up', weight=0, reps=11` |
| 3 | `bw([[0,10,10,4]]×3)` | cfg with prog ∈ {linear, greyskull, double} | for each: `weight=0, kind='hold'` |
| 4 | `hist(LIFT, [[10,10,10,10]], {sets:3, reps:10})` | cfg | `kind='up', weight=12.5` |

### 10.7 Greyskull (`cfg = {id:LIFT, sets:3, reps:5, weight:60, prog:'greyskull'}`)
| # | S | expected |
|---|---|---|
| 1 | `hist(LIFT, [[60,5,5,5]])` | `kind='up', weight=62.5` |
| 2 | `hist(LIFT, [[60,5,5,10]])` | `kind='up', weight=65`, `why[0]` contains `'double'` |
| 3 | `hist(LIFT, [[60,5,5,3]])` | `kind='deload', weight=55`; `DELOAD_AFTER.greyskull == 1` |
| 4 | `hist(LIFT, [[60,5,5,3],[55,5,5,2]])` | `kind='deload', weight=50` |

### 10.8 Double progression (`cfg = {id:LIFT, sets:3, reps:12, repsMin:8, weight:40, prog:'double'}`, target `{sets:3, reps:12}`)
| # | rows | expected |
|---|---|---|
| 1 | `[[40,12,12,12]]` | `kind='up', weight=42.5, reps=8` |
| 2 | `[[40,10,9,9]]` | `kind='hold', weight=40, reps=10` |
| 3 | `[[40,12,12,11]]` | `reps <= 12` (actual: `hold`, 40, reps 12) |
| 4 | `[[40,9,9,9]]×3` | `kind='deload', reps=8, weight=35` |

### 10.9 Timed (`cfg = {id:LIFT, mode:'time', sets:2, sec:45, prog:'time'}`)
In `timeHist(rows)`, workout i has `d='2026-02-0'+(i+1)` and entry `{id:LIFT, target:{sets:2, sec:45, mode:'time'}, sets: row.map(sec => ({sec, w:0, done:true}))}`.

| # | S | expected |
|---|---|---|
| 1 | `timeHist([[45,45]])` | `kind='up', sec=50`, `weight` undefined |
| 2 | `timeHist([[45,38]])` | `kind='hold', sec=45` |
| 3 | `timeHist([[45,30],[45,32],[45,31]])` | `kind='deload', sec=40` |
| 4 | `hist(LIFT, [[60,5,5,5]])` (reps-only history) | `kind='first'` |

### 10.10 Policy off
| S | cfg | expected |
|---|---|---|
| `hist(LIFT, [[60,5,5,5]])` | `{id:LIFT, sets:3, reps:5, prog:'off'}` | `kind='off'`, `weight` undefined |
| `{unit:'kg', workouts:[]}` | `{id:CARDIO, sets:1, min:20}` | `kind='off'` |

### 10.11 `sessionsFor`
| S | call | expected |
|---|---|---|
| workouts: 01-01 `{id:LIFT, target:{sets:1,reps:5}, sets:[{w:60,r:5,done:true}]}`; 01-02 same exercise but `sets:[{w:60,r:0,done:false}]`; 01-03 `{id:'other', target:{}, sets:[{w:20,r:5,done:true}]}` | `sessionsFor(S, LIFT)` | `.map(d)` = `['2026-01-01']` |
| one workout 01-01 with `{id:LIFT, sets:[{w:60,r:5,done:true}]}` and no target | `sessionsFor(S, LIFT)` | length 1, no crash |

### 10.12 Legacy history without targets
`legacy(rows)`: workout i has `d='2026-03-'+pad2(i+1)` and entry `{id:LIFT, sets: row.slice(1).map(r => ({w:row[0], r, done:true}))}` with no target. `cfg = {id:LIFT, sets:3, reps:5, weight:60, prog:'linear'}`.

| rows | expected |
|---|---|
| `[[60,5,5,5]]` | `kind='up', weight=62.5` |
| 11 × `[60,5,5,5]` | `kind='up'` |
| `[[60,5,5,2]]` | `kind='hold'` |
| `[[60,5,6,5]]` | `weight=62.5` |
| `[[60,5,4,5]]` | `kind='hold'` |

### 10.13 `applyPrescription` (`sets = [{w:60,r:5,done:true},{w:60,r:5,done:false}]`)
| p | expected |
|---|---|
| `{kind:'up', weight:62.5}` | `[{w:60,r:5,done:true}, {w:62.5,r:5,done:false}]` |
| `{kind:'up', weight:42.5, reps:8}` | `[1]` = `{w:42.5, r:8, done:false}` |
| `{kind:'off'}`, `{kind:'first'}`, `null` | returns the **same** list instance |
| timed `[{sec:45,w:0,done:false}]` with `{kind:'up', sec:50}` | `[{sec:50, w:0, done:false}]` |

### 10.14 `estimate1RM`
| call | expected |
|---|---|
| `(100,1)` | 100 |
| `(62.5,1)` | 62.5 |
| `(100,5)` | 116.7 |
| `(100,10)` | 133.3 |
| `(80,8)` | 101.3 |
| `(60,3)` | 66 |
| `(101.25,7)` | 124.9 |
| `(100,3)*10` | is an integer (110) |
| `(100, 12)` | not null (140) |
| `(100, 13)` | null |
| `(60, 30)` | null |
| `(0,5)`, `(-100,5)`, `(100,0)`, `(100,-3)`, `(undefined,5)`, `(100,undefined)`, `(NaN,5)`, `(Infinity,5)`, `('','')` | null |
| `('100','5')` | 116.7 |
| `(100,5,'brzycki')` | 112.5 |
| `(100,5,'lombardi')` | 117.5 |
| `Object.keys(FORMULAS)` | contains `'epley'` |
| spread(r) = max − min over the three formulas at 100 kg | spread(1) = 0; spread(r) < 6 for r = 2..8; spread(12) > max(spread(1..11)) |
| `(100,5,'nope')` | equals `estimate1RM(100,5)` = 116.7 |

### 10.15 `bestSetOf`
| entry | expected |
|---|---|
| sets `[100×5✓, 110×3✓, 120×1✓]` | `{est:121, w:110, r:3}` |
| sets `[100×5✓, 200×5 not done]` | `.w = 100` |
| `{topW:200, sets:[100×5✓]}` | `.est = 116.7` |
| `{sets:[{min:20,speed:9,done:true}]}` | null |
| `{sets:[{sec:60,w:0,done:true}]}` | null |
| `{sets:[{sec:60,w:20,done:true}]}` | null |
| `null` | null |
| `{sets:[]}` | null |

### 10.16 `e1rmSeries` / `best1RM` / `is1RMRecord`
Fixture `S.workouts`:

| d | start | entries |
|---|---|---|
| 2026-01-01 | 1 | bench `[80×5✓]` |
| 2026-01-08 | 2 | squat `[100×5✓]` |
| 2026-01-15 | 3 | bench `[90×5✓, 90×3 not done]` |
| 2026-01-22 | 4 | bench `[85×5✓]` |
| 2026-01-29 | 5 | run `[{min:30,speed:10,done:true}]` |

| call | expected |
|---|---|
| `e1rmSeries(S,'bench').map(d)` | `['2026-01-01','2026-01-15','2026-01-22']` |
| `e1rmSeries(S,'bench').map(y)` | `[93.3, 105, 99.2]` |
| `best1RM(S,'bench')` | `{est:105, w:90, r:5, d:'2026-01-15', t:3}` |
| `e1rmSeries(S,'run')` | `[]` |
| `best1RM(S,'run')`, `best1RM(S,'nope')`, `best1RM({workouts:[]},'bench')`, `best1RM({},'bench')` | null |
| `is1RMRecord(S,'bench',{sets:[95×5✓]})` | `{est:110.8, w:95, r:5, prev:105}` |
| `is1RMRecord(S,'bench',{sets:[90×5✓]})` | null (equal is not a record) |
| `is1RMRecord(S,'bench',{sets:[80×5✓]})` | null |
| `is1RMRecord(S,'deadlift',{sets:[140×3✓]})` | `.prev = 0`, `.est = 154` |
| `is1RMRecord(S,'plank',{sets:[{sec:90,done:true}]})` | null |
| `is1RMRecord(S,'bench',{sets:[{w:200,r:5,done:false}]})` | null |

### 10.17 Effort
Fixture helpers:
- `W(n, sets)`: one workout n days before `now` with `d = isoOf(now − n days)`, `start = ms(now − n days)`, and a single entry `{id:'0025', sets: sets.map(s => ({w:60, r:8, done:true, ...s}))}`.
- `S(...ws) = {workouts: ws}`.

**`rirOf`**

| input | expected |
|---|---|
| `{rir:2}` | 2 |
| `{rpe:8}` | 2 |
| `{rpe:9.5}` | 0.5 |
| `{rir:0}` | 0 |
| `{rpe:10}` | 0 |
| `{}` | null |
| `{rir:null}` | null |
| `null` | null |
| `{rir:3, rpe:9}` | 3 |

**`toScale`**

| call | expected |
|---|---|
| `('rir',2)` | 2 |
| `('rpe',2)` | 8 |
| `('rpe',0)` | 10 |
| `('rir',null)` | null |
| `('rpe', 10-7.5)` | 7.5 |

**`displayScale`**

| S | expected |
|---|---|
| `{effort:'rpe', workouts:[]}` | `rpe` |
| `{effort:'rir', workouts:[]}` | `rir` |
| `{effort:'none', ...S(W(3,[{rpe:8},{rpe:9}]))}` | `rpe` |
| `{effort:'none', ...S(W(3,[{rir:2}]))}` | `rir` |
| `{effort:'none', workouts:[]}` | `rir` |

**`avgRir`**

| input | expected |
|---|---|
| `[{rir:1},{rir:3}]` | 2 |
| `[{rir:1},{},{rpe:7}]` | 2 |
| `[{},{rir:null}]` | null |
| `[]` | null |
| `null` | null |

**`effortSummary`**. Fixture `st = S(W(2,[{rir:1},{rir:3},{rir:2}]), W(4,[{rir:0},{rpe:6},{}]), W(40,[{rir:5},{rir:5}]))`.

| call | expected |
|---|---|
| `(st,0)` | `done=8, rated=7` |
| `(S(W(2,[{rir:4},{},{},{},{},{}])),0)` | `rated=1, avg=null` |
| 4 sets of `{rir:2}` (MIN_RATED−1) | `avg=null` |
| 5 sets of `{rir:2}` | `avg=2` |
| `(st,0)` | `hard=4, hardPct≈4/7` |
| `(st,7)` | `rated=5` |
| `(st,3)` | `rated=3` |
| `({workouts:[]},30)` | `{done:0, rated:0, hard:0, avg:null, hardPct:null}` |

**`hasEffort`**

| S | expected |
|---|---|
| `S(W(2,[{rir:0}]))` | true |
| `S(W(2,[{rpe:8}]))` | true |
| `S(W(2,[{},{rir:null}]))` | false |
| `{workouts:[]}` | false |
| `S(W(2,[{rir:2, done:false}]))` | false |

**`effortWeeks`**

| call | expected |
|---|---|
| `(S(W(1,[{rir:1},{rir:3},{}])),0)` | length 1; `[0] = {rir:2, n:2, sets:3}` |
| `(S(W(1,[{rir:1}])),0)` | `[]` |
| `(S(W(2,[{rir:1},{rir:1}]), W(30,[{rir:3},{rir:3}])),0)` | `.map(rir) = [3, 1]`; `[0].t < [1].t` |

**`effortHistogram`**

| call | expected |
|---|---|
| `(S(W(2,[{rir:0},{rir:1.5},{rir:4},{rir:7}])),0)` | `n = [1,1,0,0,2]`; `[4].tail = true`; `[0].pct = 0.25` |
| `(S(W(2,[{}])),0)` | every bin `n=0, pct=0` |

**`isHardSet`**

| input | expected |
|---|---|
| `{rir:3}` | true |
| `{rir:3.5}` | false |
| `{rpe:10}` | true |
| `{}` | false |

Note on the `effortWeeks` first case: with a real clock, "1 day ago" may fall in the previous ISO
week, but the test has a single workout, so the result is the same either way.

### 10.18 `history.js`
In the history tests, `LIFT = '0001'` (the first non-cardio exercise) and `CARDIO = '3220'`.

**`modeOf`**

| input | expected |
|---|---|
| `{id:CARDIO}` | cardio |
| `{id:LIFT}` | reps |
| `{id:'no-such-exercise'}` | reps |
| `{}` | reps |
| `null` | reps |
| `undefined` | reps |
| `{id:LIFT, mode:'time'}` | time |
| `{id:CARDIO, mode:'reps'}` | reps |
| `{id:CARDIO, mode:'time'}` | time |
| `{id:LIFT, mode:'nonsense'}` | reps |
| `{id:CARDIO, mode:''}` | cardio |
| `isTimed({id:LIFT, mode:'time'})` | true |
| `isTimed({id:LIFT})` | false |

**`fmtSec`**

| input | expected |
|---|---|
| 0 | `0:00` |
| 9 | `0:09` |
| 45 | `0:45` |
| 60 | `1:00` |
| 90 | `1:30` |
| 605 | `10:05` |
| -5 | `0:00` |
| undefined | `0:00` |
| null | `0:00` |
| NaN | `0:00` |
| 44.6 | `0:45` |

**`setLabel`**

| call | expected |
|---|---|
| `(LIFT, {w:60,r:10})` | `60×10` |
| `(CARDIO, {min:20,speed:9})` | `20 min @ 9 km/h` |
| `(LIFT, {sec:45,w:0}, {mode:'time'})` | `0:45` |
| `(LIFT, {sec:90,w:20}, {mode:'time'})` | `1:30 · 20` |
| `(LIFT, {w:0,r:0})` | `0×0` |
| `(CARDIO, {})` | `0 min @ 0 km/h` |
| `(LIFT, {w:60,r:10,rir:2})` | `60×10 (RIR 2)` |
| `(LIFT, {w:60,r:10,rir:1.5})` | `60×10 (RIR 1.5)` |
| `(LIFT, {w:60,r:10,rir:0})` | `60×10 (RIR 0)` |
| `(LIFT, {w:60,r:10})`, `(LIFT, {w:60,r:10,rir:null})` | `60×10` |
| `(LIFT, {w:60,r:10,rpe:8})` | `60×10 (RPE 8)` |
| `(LIFT, {w:60,r:10,rpe:9.5})` | `60×10 (RPE 9.5)` |
| `(LIFT, {w:60,r:10,rpe:null})` | `60×10` |
| `(LIFT, {w:60,r:10,rir:2,rpe:8})` | `60×10 (RIR 2)` |
| `(CARDIO, {min:20,speed:9,rpe:8})` | `20 min @ 9 km/h` |
| `(LIFT, {sec:45,rir:2}, {id:LIFT, mode:'time'})` | `0:45` |

**`effortOf`**

| input | expected |
|---|---|
| `{effort:'rpe'}` | rpe |
| `{effort:'rir'}` | rir |
| `{effort:'none'}` | none |
| `{}` | none |
| `{showRir:true}` | rir |
| `{effort:null, showRir:true}` | rir |
| `{effort:null}` | none |
| `{showRir:false}` | none |
| `{showRir:true, effort:'rpe'}` | rpe |
| `{showRir:true, effort:'none'}` | none |
| overlay `{unit:'kg', effort:null, ...stored}` with stored `{showRir:true}` | rir |
| stored `{showRir:false}` | none |
| stored `{}` | none |
| stored `{effort:'rpe'}` | rpe |
| stored `{showRir:true, effort:undefined}` | rir (JS spread of `undefined` overwrites null; the result is still the fallback) |
| `{effort:'rpe10'}`, `{effort:'RIR'}`, `{effort:'f'}`, `null`, `undefined` | none |
| `{effort:'nope', showRir:true}` | rir |

**`stepEffort`**

| call | expected |
|---|---|
| `('rir',null,1)` | 0 |
| `('rpe',null,1)` | 6 |
| `('rir',0,1)` | 0.5 |
| `('rir',0.5,1)` | 1 |
| `('rpe',6,1)` | 6.5 |
| `('rir',null,-1)` | null |
| `('rpe',null,-1)` | null |
| `('rir',undefined,-1)` | null |
| `('rir',0,-1)` | null |
| `('rpe',6,-1)` | null |
| `('rir',0.5,-1)` | 0 |
| `('rpe',6.5,-1)` | 6 |
| `('rir',9.5,1)` | 10 |
| `('rir',10,1)` | 10 |
| `('rpe',10,1)` | 10 |
| six `+` taps on `rpe` from null | 8.5 |
| `('rir', 0.1+0.2, 1)` | 0.8 |
| `('rpe',3,1)` | 3.5 |
| `('rpe',3,-1)` | null |
| `('none',null,1)` | null |
| `('none',2,1)` | 2 |
| `(undefined,2,-1)` | 2 |

**`capEffort`**

| call | expected |
|---|---|
| `('rir',12)` | 10 |
| `('rpe',99)` | 10 |
| `('rpe',8)` | 8 |
| `('rpe',1)` | 1 |
| `('rir',0)` | 0 |
| `('rir',null)` | null |
| `('rpe',undefined)` | undefined |
| `('none',12)` | 12 |

**Effort logging end to end**

| scenario | expected |
|---|---|
| 4 × `stepEffort('rpe', v, 1)` from null, then `setLabel(LIFT,{w:80,r:5,rpe:v})` | `80×5 (RPE 7.5)` |
| `stepEffort('rir',null,1)` gives 0; `setLabel(LIFT,{w:100,r:3,rir:0})` | `100×3 (RIR 0)` |
| `setLabel` of old `{w:60,r:10,rir:2}` | `60×10 (RIR 2)` |
| `setLabel` of new `{w:60,r:10,rpe:8}` | `60×10 (RPE 8)` |

The labels in the last two rows do not change when the profile effort is `rpe` or `none`.

**`defaultConfig`**

| call | expected |
|---|---|
| `(LIFT)` | `{sets:3, reps:10, weight:0, mode:'reps'}` |
| `(CARDIO)` | `{sets:1, min:20, speed:8}` |
| `(LIFT,'time')` | `{sets:3, sec:45, weight:0, mode:'time'}` |

**`exLine`**

| call | expected |
|---|---|
| `({id:LIFT,sets:3,reps:10},'kg')` | `3 × 10` |
| `({id:LIFT,sets:3,reps:10,weight:60},'kg')` | `3 × 10 · 60 kg` |
| `({id:LIFT,sets:3,sec:45,mode:'time'},'kg')` | `3 × 0:45` |
| `({id:LIFT,sets:2,sec:90,weight:20,mode:'time'},'kg')` | `2 × 1:30 · 20 kg` |
| `({id:CARDIO,sets:1,min:20,speed:8},'kg')` | `1 × 20 min @ 8 km/h` |

**`buildSets`**. `emptyS = {workouts:[], exWeights:{}}`.

| S | cfg | expected |
|---|---|---|
| emptyS | `{id:LIFT, sets:3, reps:8, weight:50}` | 3 × `{w:50, r:8, done:false}` |
| emptyS | `{id:LIFT, mode:'time', sets:2, sec:60, weight:20}` | 2 × `{sec:60, w:20, done:false}` |
| emptyS | `{id:CARDIO, sets:1, min:25, speed:9}` | `[{min:25, speed:9, done:false}]` |
| last entry `{id:LIFT, target:{mode:'time'}, sets:[{sec:70,w:10,done:true}]}` | `{id:LIFT, mode:'time', sets:2, sec:45, weight:0}` | 2 × `{sec:70, w:10, done:false}` |
| last entry `{id:LIFT, sets:[{w:60,r:10,done:true}]}` | `{id:LIFT, mode:'time', sets:1, sec:45, weight:0}` | `[{sec:45, w:0, done:false}]` |
| last timed entry `[{sec:70,w:10,done:true}]` | `{id:LIFT, mode:'reps', sets:1, reps:8, weight:40}` | `[{w:40, r:8, done:false}]` |
| `exWeights:{[LIFT]:{w:75}}` and last `[{w:60,r:10,done:true}]` | `{id:LIFT, sets:1, reps:8, weight:50}` | `[{w:75, r:10, done:false}]` |

**`workoutVolume`**

| workout | expected |
|---|---|
| entries: `LIFT [60×10✓, 60×10 not done]`, `LIFT(target time) [{sec:60,w:20,done:true}]`, `CARDIO [{min:20,speed:9,done:true}]` | 600 |

---

## 11. More golden values (from running the reference implementation)

| case | result |
|---|---|
| e1RM table at 100 kg, r = 1..12 (epley / brzycki / lombardi) | 1: 100/100/100 · 2: 106.7/102.9/107.2 · 3: 110/105.9/111.6 · 4: 113.3/109.1/114.9 · 5: 116.7/112.5/117.5 · 6: 120/116.1/119.6 · 7: 123.3/120/121.5 · 8: 126.7/124.1/123.1 · 9: 130/128.6/124.6 · 10: 133.3/133.3/125.9 · 11: 136.7/138.5/127.1 · 12: 140/144/128.2 |
| `estimate1RM(100, 2.5)` / `(100,12.4)` / `(100,12.5)` / `(100,0.5)` / `(100,1.2)` | 110 / null / null / null / 103.3 |
| linear hold after one miss: `hist(LIFT,[[60,5,5,3]])` | `{kind:'hold', weight:60, why:['Missed reps last time — same weight again ({0} of {1} to go).', 2, 3]}` |
| linear hold after two misses | why args `[1, 3]` |
| linear up | `why: ['Every rep last time — {0} {1} more.', 2.5, 'kg']` |
| linear, `[[61,5,5,5]]`, inc 2.5 | `up`, weight **62.5** (snapped to the grid) |
| linear deload 5 → | `{kind:'deload', weight:2.5, why:['Missed reps {0} sessions running — reset to {1} {2} and work back up.', 3, 2.5, 'kg']}` |
| greyskull double jump `[[60,5,5,10]]` | `why: ['Last set hit {0} reps — twice the target, so take a double jump of {1} {2}.', 10, 5, 'kg']` |
| greyskull 1 miss | `why: ['Missed reps — reset to {0} {1} and work back up.', 55, 'kg']` |
| first | `{policy:'linear', kind:'first', why:['Nothing logged yet — this session sets the baseline.']}` |
| bodyweight up | `why: ['Bodyweight — every rep last time, so go for {0} this time.', 11]` |
| bodyweight hold | `{kind:'hold', weight:0, reps:10, why:['Bodyweight — same target again until every set is clean.']}` |
| double, no `repsMin`, top 12, `[[40,12,12,12]]` | `up`, 42.5, reps **10** (bottom = 12−2) |
| double, `[[40,11,11,null]]` | `hold`, 40, reps **8** (the unchecked set gives low 0, so aim = bottom) |
| double climbing `[[40,10,9,9],[40,11,10,10],[40,11,11,11]]` | **`deload` to 35, reps 8** (see Q1) |
| double deload why | `['Stalled {0} sessions — deload to {1} {2}.', 3, 35, 'kg']` |
| double hold why | `['Same weight — aim for {0} reps this time.', 10]` |
| double up why | `['Top of the rep range in every set — {0} {1} more, back to {2} reps.', 2.5, 'kg', 8]` |
| time up / hold / deload why | `['Held every set for the full time — target up by {0}s.', 5]` / `['Last time came up short — same target again.']` / `['Short {0} sessions in a row — back off to {1}s and build up again.', 3, 40]` |
| time, `inc:10`: up / deload | sec 55 / sec **40** (the deload step stays at 5) |
| timed cfg **without** `prog` and routine without `prog` | `{policy:'off', kind:'off'}` |
| `readSession({id:LIFT,sets:[]}, {sets:3,reps:5})` | `{mode:'reps', goal:5, reps:[], weight:0, low:0, amrap:0, ok:false}` |
| `readSession(null, null)` | `{mode:'reps', goal:0, reps:[], weight:0, low:0, amrap:0, ok:false}` |
| `stepEffort('rpe',10.2,1)` / `('rpe',10.2,-1)` / `('rir',12,-1)` | 10 / 9.7 / 11.5 |
| `toScale('rpe', 20/7)` / `toScale('rir', 20/7)` | 7.1 / 2.9 |
| `setLabel(LIFT,{w:1234.56,r:5})` (en-GB) | `1,234.6×5` |
| `buildSets`: last done sets `[60×10, 62.5×8]` (third set unchecked), cfg sets 4 reps 5 weight 50 | `[60×10, 62.5×8, 62.5×8, 62.5×8]` |
| `buildSets`: last `[{w:60,r:0,done:true}]` | the plan values are used: `[{w:50, r:5}]` |
| effort fixture `st`, `effortSummary(st,0)` | `{done:8, rated:7, hard:4, avg:2.857142857142857, hardPct:0.5714285714285714}` |
| `effortSummary(st,7)` | `{done:6, rated:5, hard:4, avg:2, hardPct:0.8}` |
| `effortHistogram(st,0)` | n `[1,1,1,1,3]`, pct `1/7` each and `3/7` for the tail |
| heatmap: minutes per day `[10,20,30,40,50,60,70,80]` | t1=30, t2=50, t3=70. A day of 25 min is level 1, 30 is 2, 55 is 3, 70 is 4, a 0-min workout day is 1, no workout is 0 |
| heatmap: a single day of 45 min | t1=t2=t3=45, so that day is level 4 |

---

## 12. Open questions and porting decisions

1. **Double progression counts in-range progress as a stall.** `ok` means every set hit the *top*
   of the range. Three sessions of honest climbing, for example 10/9/9 → 11/10/10 → 11/11/11
   toward 12, therefore trigger a deload (verified: 40 → 35). Either port this faithfully, or
   count a double-progression stall only when `low` did not improve on the previous session.
   This needs a product decision.
2. **The time-mode deload step is fixed at 5 s**, even when `cfg.inc` is 10 or 15. The up-step
   does honour `inc`. Is this intentional?
3. **`HEAVY_BP` includes `'hips'` and `'glutes'`**, which never occur as `bp` in the catalogue or
   in custom exercises. They are harmless dead entries; keep them for parity.
4. **Stored `target` may lack `id` and `mode`.** An exercise added mid-workout stores the output
   of ExConfig, which has no `id`, and cardio configs never carry `mode`. `setLabel(id, s, target)`
   then treats such a cardio entry as `reps` and prints "0×0". `readSession` and the workout
   screen avoid this by merging `id` in. **In the port, always store `target` with `id` and an
   explicit `mode`.**
5. **Timed sets with weight can raise load PRs** (`bestWeightFor` and finish PR detection read `s.w`
   regardless of mode), and they feed `exWeights`. Should PR detection be limited to reps mode?
6. **Array order versus date order.** `lastEntryFor`, `sessionsFor`, `e1rmSeries` and
   `stallCount` rely on `S.workouts` append order. With D1 and imports, define an explicit
   order, for example `ORDER BY d, start`, and use it consistently. Otherwise an old import
   appended late becomes "last time".
7. **Window semantics differ.** Muscle-balance "Week" is the current ISO week. Effort and
   30/90-day windows are rolling from `now`. A workout without `start` uses UTC-midnight
   parsing of `d`, which shifts by the device timezone. In the port, use local-noon timestamps
   for date-only workouts.
8. **Greyskull `ok`** requires every set ≥ goal. There is no separate "AMRAP must *beat* the
   target" rule, despite the wording in POLICY_DESC. Meeting the target is enough.
9. **`estimate1RM` fractional reps.** 1.2 reps is not exactly 1, so it gives `epley(w,1)` = w × 1.0333.
   Reps are integers in the UI, so this only matters for imported data.
10. **`exWeights` is a running max**, not the latest confirmed weight. It overrides the weight in
    `buildSets` for reps work, so with policy `off` a user starts at their all-time best, not
    at last session's weight. With any other policy, `applyPrescription` overwrites it.
11. **Server duplicate.** `api/coach/payload.js` reimplements `readSession` without the
    mode filter that `nextPrescription` applies, and uses the full plan config as the fallback.
    The MCP/Worker port should reuse the single TS engine so Claude sees exactly the
    stall and deload state the app shows.
12. **Localization of `why`.** The `why` templates and `POLICY_*` strings are i18n keys. Translations
    for 11 languages live in `frontend/src/locales/*.js`, which is outside this subsystem. Port the
    keys verbatim so those locale files can be reused.
