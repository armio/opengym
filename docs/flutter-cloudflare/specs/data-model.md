# openGym porting spec — Data model, persistence, sync & HTTP API

Source revision: `678bf5b` of `alexpcosta/opengym`.
Files read in full: `frontend/src/store/useStore.js`, `frontend/src/store/useUI.js`, `frontend/src/lib/api.js`,
`api/server.js` (595 lines), `frontend/src/lib/starter.js`, `frontend/src/lib/demoSeed.js`, `frontend/src/lib/demo.js`,
`frontend/src/lib/plan-share.js`, `frontend/src/App.jsx`, `frontend/src/main.jsx`. Also read, because they define or
change the state shape: `sheets.jsx`, `views/Workout.jsx`, `views/RoutineEdit.jsx`, `views/Plan.jsx`,
`views/Settings.jsx`, `views/Login.jsx`, `lib/history.js`, `lib/format.js`, `lib/exercises.js`, `lib/mobile.js`,
`lib/push.js`, `lib/glyphs.js`, `lib/coach.js` (state parts), `lib/import-csv.js` (merge parts), `lib/progression.js`
(field names), `api/coach/routes.js` + `cadence.js` (listed only), `public/sw.js`, `demoSeed.test.js`.

Target: Flutter app, Cloudflare Workers + D1 backend, and a remote MCP server that Claude uses to read progress and
write training plans. Sections 1 to 7 describe the current system as it is. Section 8 gives porting
recommendations. Section 9 lists bugs and quirks. Section 10 lists open questions.

---

## 0. Conventions used everywhere

| Concept | Representation | Notes |
|---|---|---|
| Entity id (`uid()`) | `Date.now().toString(36) + Math.random().toString(36).slice(2, 7)` | For example `"muo979oo50vo1"` (8 base36 chars of ms time + 5 random chars). The value is not guaranteed unique but is effectively unique. Used for routines, workouts, active workouts, sheet ids and custom exercise ids with a prefix. |
| Custom exercise id | `'c' + uid()` when created in the app. `'im' + uid()` when created by CSV import. Plain `uid()` when created by a plan-file import (see §6.1). | Library ids are 4-digit zero-padded strings `"0001"`…`"3xxx"` (1324 entries). |
| Imported workout id | `'iw' + uid()` | |
| Superset group id (`sg`) | `'sg' + uid()` (routine editor), or `uid().slice(0, 6)` (Coach `superset` change) | Opaque. Only equality between **adjacent** entries matters. |
| Server user id | `crypto.randomBytes(12).toString('base64url')` → 16 chars `[A-Za-z0-9_-]` | |
| Calendar date (`d`, `iso`) | `"YYYY-MM-DD"` in the **device's local time zone** (`todayISO()` / `isoOf(date)`) | Parsing uses `new Date(iso + 'T12:00:00')` (local noon) to avoid DST edge cases. |
| Timestamp (`t`, `start`, `end`, `_ts`, `at`) | Unix epoch **milliseconds** (number) | |
| ISO datetime | `new Date().toISOString()` | Used only for server `created`/`usedAt` and Coach `consent.agreedAt`. |
| Weekday key | JS `getDay()`: `0`=Sunday … `6`=Saturday. JSON object keys are therefore strings `"0"`…`"6"`. | The UI always displays Monday first: `[1,2,3,4,5,6,0]`. |
| Weights | Plain numbers in the profile's unit (`kg` or `lb`). **Switching unit never converts stored numbers.** It changes only the label. | UI inputs round to 0.1 (`Math.round(x*10)/10`). |
| Deep clone | `JSON.parse(JSON.stringify(o))` | Side effect: keys with `undefined` values disappear. Some code relies on this (for example `prog: undefined` in the config sheet and `why: undefined` in Coach plans). |

---

## 1. The per-user state document `S`

All user data is **one JSON document** named `S`. The client holds it in memory (zustand), mirrors it to
`localStorage['gym_state_v1']`, on the mobile build also mirrors it to a file, and when signed in syncs it **as a whole**
to `PUT /api/data`. The server stores it as `DATA_DIR/state-<uid>.json`. The document has no schema version field.
Every loaded document is overlaid on the defaults (`Object.assign(clone(DEF), loaded)`), which is a **shallow** merge.

### 1.1 Defaults (`DEF`, exported from `useStore.js`)

```js
export const DEF = {
  unit: 'kg', restSec: 90, sound: true, keepAwake: true, lang: 'en',
  theme: 'dark', accent: 'lime', body: 'male', targetW: null,
  bodyweight: [], routines: [], week: {}, dayPlan: {},
  exWeights: {}, workouts: [], active: null, customEx: [], gifSize: 'full',
  reminder: { on: false, time: '08:00', tz: null }, effort: null,
  coach: null
}
```

The shallow overlay means that a nested object in a loaded document (for example a partial `reminder`) **replaces**
the default object and is not merged with it. Code that reads `reminder` therefore always defends with
`S.reminder?.on` and `S.reminder?.time || DEF.reminder.time`.

### 1.2 Top-level keys

| Key | Type | Default | Meaning / allowed values |
|---|---|---|---|
| `unit` | `'kg' \| 'lb'` | `'kg'` | Label for every weight. There is no conversion (see §0). |
| `restSec` | int seconds | `90` | Rest-timer duration after a set. The Settings picker offers `60, 90, 120, 150, 180`. |
| `sound` | bool | `true` | Enables beeps. Vibration is not gated by this flag. |
| `keepAwake` | bool | `true` | Keeps the screen awake (Wake Lock) **while `active` is non-null**. The check is `S.keepAwake !== false`, so a missing value counts as on. |
| `lang` | string | `'en'` | One of `en, de, es, fr, it, pt, pl, tr, ru, zh, ko, hi`. An unknown value falls back to `en`. Exercise instructions exist only for `en, es, fr, it, tr, ru, zh, hi, pl, ko`. |
| `theme` | `'dark' \| 'light'` | `'dark'` | Any value other than `'light'` renders as dark. |
| `accent` | string key | `'lime'` | Keys and hex values: `lime #30d158, sky #0a84ff, orange #ff9f0a, violet #bf5af2, pink #ff375f, red #ff453a, teal #40c8e0, gold #ffd60a`. An unknown key renders as lime. |
| `body` | `'male' \| 'female'` | `'male'` | Only controls how the muscle-map body diagram is drawn. Any value other than `'female'` renders as male. |
| `gifSize` | `'full' \| 'mini'` | `'full'` | Size of the exercise animation during a workout. It toggles from the media widget and persists. |
| `effort` | `null \| 'none' \| 'rir' \| 'rpe'` | `null` | The per-set effort scale that the workout screen asks for. `null` means "never chose" (see `effortOf` below). |
| `showRir` | bool (legacy, optional) | absent | The flag that `effort` replaced. It is read only when `effort` is neither `'none'` nor a known scale. Saving the effort setting **deletes** it (`s.effort = v; delete s.showRir`). |
| `targetW` | number \| null | `null` | Goal body weight in the profile's unit. It must be `> 0` to be set. `null` means no goal. |
| `bodyweight` | `BodyWeight[]` | `[]` | Sorted by `d` ascending, with at most one entry per date (§1.7). |
| `routines` | `Routine[]` | `[]` | The plan's routines (§1.4). The array order is the display order. |
| `week` | `{ [weekday '0'..'6']: routineId }` | `{}` | The weekly schedule. A missing key means a rest day. |
| `dayPlan` | `{ [iso date]: routineId \| 'rest' }` | `{}` | Per-date reschedule overrides (§1.4.4). Old entries are never pruned. |
| `exWeights` | `{ [exId]: { w: number, d: iso } }` | `{}` | The "working weight" memory per exercise (§1.8). |
| `workouts` | `Workout[]` | `[]` | Finished sessions (§1.5). The array is appended on finish. Imports re-sort it by `d`. |
| `active` | `ActiveWorkout \| null` | `null` | The in-progress session (§1.6). It stays on the device: the server strips it on `PUT /api/data`, and a pull never overwrites the local value. |
| `customEx` | `CustomExercise[]` | `[]` | The user's own exercises (§1.9). |
| `reminder` | `{ on: bool, time: 'HH:MM', tz: string \| null }` | `{on:false,time:'08:00',tz:null}` | The "workout day" reminder. `tz` is an IANA zone. It is re-stamped with `Intl…resolvedOptions().timeZone \|\| 'UTC'` on **every** reminder edit and again on web boot when `on` is true and the zone differs (travel). |
| `coach` | object \| null | `null` | The AI Coach namespace (§1.10). `null` means the user never opted in. |
| `_ts` | epoch ms | set on every persist | "Last locally modified" time. It is the only conflict-resolution signal (§3.6). **It is overwritten by every `persist()`, including the persist that follows a pull.** |

**`effortOf(S)`** is the effective effort scale:

```js
const e = S && S.effort
return e === 'none' || EFFORT[e] ? e : (S && S.showRir ? 'rir' : 'none')
// EFFORT = { rir: {f:'rir',hd:'RIR',step:0.5,min:0,max:10}, rpe: {f:'rpe',hd:'RPE',step:0.5,min:6,max:10} }
```

`hasData(S)` returns true when `workouts.length || routines.length || bodyweight.length` is non-zero. The sync rules
use it (§3.6).

### 1.3 Exercise identity and logging mode

A plan entry or workout entry refers to an exercise by `id`, which is a library id or a custom id. The **logging mode**
comes from `modeOf(cfg)`:

```js
function modeOf(cfg) {
  const m = cfg && cfg.mode
  if (m === 'reps' || m === 'time' || m === 'cardio') return m
  return isCardio(cfg && cfg.id) ? 'cardio' : 'reps'   // isCardio: EXIDX[id]?.bp === 'cardio'
}
```

- `reps`: weight × reps. Sets look like `{ w, r, done, rir?, rpe? }`.
- `time`: a held duration. Sets look like `{ sec, w, done }`, where `w = 0` means bodyweight.
- `cardio`: duration and speed. Sets look like `{ min, speed, done }`. `speed` is always in **km/h**, independent of `unit`.

An entry without `mode` falls back to the body part, so old data is read without migration. The cardio config sheet
**does not write `mode`** for cardio exercises, so their mode always comes from the body part.

### 1.4 Plan: routines, schedule and reschedules

#### 1.4.1 `Routine`

```ts
type Routine = {
  id: string            // uid()
  name: string          // routine editor: trimmed name, or t('Routine') if empty
  emoji: string         // an icon KEY (field name kept for backward compatibility), e.g. 'barbell'
  prog?: Policy         // routine-level progression default: 'off'|'linear'|'greyskull'|'double'|'time'
  ex: RoutineExercise[] // ordered; superset = adjacent entries with equal `sg`
}
```

`emoji` values:

- **Icon keys offered by the picker**, in groups: Strength `figureStrength, arm, abs, legs, pullup`; Equipment
  `dumbbell, barbell, kettlebell, plate, machine`; Cardio `figureRun, bike, swim, boxing, timer`; Recovery
  `stretch, moon, heart, flame, bolt`. The default is `'figureStrength'`.
- **Legacy literal emoji**, mapped for display by `glyphOf()`: `'💪'→arm, '🦵'→legs, '🏋️'→dumbbell, '🔥'→flame, '🏃'→figureRun`,
  and more. Anything unrecognised renders as `figureStrength`.
- The Coach's `add-routine` change defaults to `'🏋️'`.

#### 1.4.2 `RoutineExercise` (the per-exercise plan config, also called `cfg`)

```ts
type RoutineExercise = {
  id: string                 // exercise id (library or custom)
  sets: number               // >= 1 (integer)
  mode?: 'reps'|'time'|'cardio'  // written by the config sheet for reps/time; absent for cardio & starter plan
  // reps mode
  reps?: number              // >= 1 integer (default 10)
  weight?: number            // >= 0 (default 0); planned load
  repsMin?: number           // only written when the effective policy is 'double': bottom of the rep range
  // time mode
  sec?: number               // >= 1 integer seconds (default 45)
  // weight? also used in time mode (0 = bodyweight)
  // cardio mode
  min?: number               // >= 1 integer minutes (default 20)
  speed?: number             // >= 0 km/h (default 8)
  // progression overrides (reps/time only)
  prog?: Policy              // absent = "follow the routine"
  inc?: number               // > 0: step size (unit for reps, seconds for time); absent = default
  // superset
  sg?: string                // group id shared with the adjacent partner(s)
}
```

**Values the config sheet writes on save** (`ExConfig.save` in `sheets.jsx`, `c` = form state):

```js
const sets = Math.max(1, Math.round(c.sets) || (cardio ? 1 : 3))
const prog = {}; if (c.prog) prog.prog = c.prog; if (c.inc > 0) prog.inc = c.inc
cardio: { sets, min: Math.max(1, Math.round(c.min) || 20), speed: Math.max(0, c.speed || 8) }         // no mode, no prog
time:   { sets, mode: 'time', sec: Math.max(1, Math.round(c.sec) || 45), weight: Math.max(0, c.weight || 0), ...prog }
reps:   { sets, mode: 'reps', reps: Math.max(1, Math.round(c.reps) || 10), weight: Math.max(0, c.weight || 0), ...prog,
          // only if policyFor({...c,id}, routine, 'reps') === 'double':
          repsMin: Math.min(reps, Math.max(1, Math.round(c.repsMin) || Math.max(1, reps - 2))) }
```

- The form is initialised from `existing || defaultConfig(id)`, where `defaultConfig` returns:
  - cardio: `{sets:1,min:20,speed:8}`
  - time: `{sets:3,sec:45,weight:0,mode:'time'}`
  - reps: `{sets:3,reps:10,weight:0,mode:'reps'}`
- When the user switches between the reps and time modes, the sheet keeps the values it already has and fills only the
  missing ones: `{...defaultConfig(id, m), ...x, mode: m}`.
- Stepper sizes are: sets 1, reps 1, weight 2.5, seconds 5, minutes 1, speed 0.5, and the progression step is 1.25
  (weight) or 5 (seconds).

**Progression fields**, which the progression spec covers in depth:

- `POLICIES_FOR = { reps: ['off','linear','greyskull','double'], time: ['off','time'], cardio: ['off'] }`.
- `policyFor(cfg, routine, mode)` picks the first of `cfg.prog`, `routine.prog`, and `mode === 'reps' ? 'linear' : 'off'`.
  If the policy is not allowed for the mode, the result is `'off'`.
- The routine editor displays `r.prog || 'linear'` and offers only the reps policies.
- The default increment is `defaultIncrement(exId, unit)`:
  - Heavy body parts (`upper legs, lower legs, back, hips, glutes`) step 5 kg or 10 lb.
  - All other body parts step 2.5 kg or 5 lb.
  - Time mode steps 5 s.

#### 1.4.3 `week`

`week` is `{ "1": "<routineId>", "3": "<routineId>", ... }`. A missing key means rest. A routine can appear on several
days. A key can hold a **stale** id if its routine was deleted outside the routine editor; `effectiveRoutine()` then
returns `null`.

#### 1.4.4 `dayPlan` (week reschedules / per-date overrides)

`dayPlan` is `{ "2026-09-30": "<routineId>" | "rest" }`.

- The key is absent when the date follows the weekly plan.
- A value of `'rest'` skips that date.
- A value holding a routine id trains that routine on that date instead.

`effectiveRoutineId` is used both by the client and by the server reminder, which carries its own duplicated copy:

```js
function effectiveRoutineId(S, iso) {
  const ov = S.dayPlan[iso]
  if (ov === 'rest') return null
  if (ov && S.routines.some(r => r.id === ov)) return ov   // override to an existing routine
  const wd = new Date(iso + 'T12:00:00').getDay()          // local weekday of that date
  return S.week[wd] || null                                // an override to a deleted routine falls back to the week
}
effectiveRoutine = id ? S.routines.find(r => r.id === id) || null : null
```

The calendar marks each date as trained (a workout exists), `ovr` (an override exists and resolves to a routine),
`plan` (the weekly plan has a routine), or nothing.

#### 1.4.5 Superset helpers

```js
// group consecutive indices sharing sg
function supersetUnits(items) {
  const units = []
  items.forEach((e, i) => {
    const prev = items[i - 1]
    if (i > 0 && e.sg && prev && prev.sg && e.sg === prev.sg) units[units.length - 1].push(i)
    else units.push([i])
  })
  return units
}
unitOf(units, idx) = units.find(u => u.includes(idx)) || [idx]
// drop sg that no longer has an ADJACENT partner (run after move/remove/unlink)
function cleanupSg(ex) { ex.forEach((e, i) => { if (e.sg && !(ex[i-1]?.sg === e.sg || ex[i+1]?.sg === e.sg)) delete e.sg }) }
```

A superset can have more than two members. Linking A–B and then B–C gives all three the same `sg`.

### 1.5 Finished workouts

```ts
type Workout = {
  id: string                  // = the active workout's id (uid()); imports: 'iw'+uid()
  d: string                   // local ISO date the session STARTED (active.d)
  start: number               // epoch ms
  end: number                 // epoch ms at finish (imports: may equal start → "unknown duration")
  routineId: string | null    // null = freestyle or imported
  name: string                // routine name at start time, t('Freestyle'), or import name ('Imported' default)
  bw: number | null           // body weight recorded at the pre-workout check-in, else null
  entries: WorkoutEntry[]     // only entries with >= 1 done set
  prs: string[]               // exercise ids that set a new heaviest-set record in this session
  vol: number                 // Σ over done sets of (w||0) * (r||0)  → timed & cardio contribute 0
  rating?: 'easy' | 'right' | 'hard'   // optional session feel (shown only when the Coach is on)
  note?: string               // optional, trimmed, max 300 chars (only settable after a rating)
}
type WorkoutEntry = {
  id: string                  // exercise id
  sets: SetRecord[]           // ALL sets of the session, including undone ones (done:false)
  topW: number | null         // "confirmed working weight" for reps entries, else null
  target: object | null       // copy of the plan config the session prescribed (see below); null/absent in old, imported and demo data
  n?: string                  // exercise NAME, stamped in only when a custom exercise is deleted (§2.5.6)
}
type SetRecord =
  | { w: number, r: number, done: boolean, rir?: number, rpe?: number }   // reps
  | { sec: number, w: number, done: boolean }                              // time
  | { min: number, speed: number, done: boolean }                          // cardio
```

Rules:

- A logged effort is stored **only** when present. Clearing an effort deletes the key, so the stored value is never
  `null`.
- A set carries at most one of `rir` and `rpe`. The two scales are never rewritten into each other.
- The canonical conversion is `rirOf(s) = s.rir ?? (s.rpe != null ? 10 - s.rpe : null)`.
- `target` comes from the active entry:
  - For a routine-started entry it is `{...cfg}` of the routine exercise, so it includes `id`, `sets`, `mode`,
    `reps`/`sec`/`min`/`speed`, `weight`, `prog`, `inc`, `repsMin` and `sg`.
  - For an exercise added mid-workout it is the config-sheet output **without** `id`.
  - Readers use it for the mode, `modeOf({...target, id})`, and for the prescribed reps.
- `sg`, `plan` and `asked` are **dropped** when a workout is finished.
- `prs` is computed at finish, before the workout is appended. An id is added when
  `mx = max(done sets' w) > 0 && mx > bestWeightFor(S, id)`.
  - `bestWeightFor` is the maximum over all earlier workouts of the done sets' `w` and of the entry's `topW`.
  - The current session's `topW` is **not** part of this comparison.
- Several workouts can share the same `d`.

### 1.6 Active workout (device-local, never synced)

```ts
type ActiveWorkout = {
  id: string                 // uid()
  d: string                  // todayISO() at start
  start: number              // Date.now() at start
  routineId: string | null   // null = freestyle
  name: string               // routine name or t('Freestyle')
  bw: number | null
  cur: number                // index into entries of the exercise on screen (always the first index of a superset unit when navigating)
  entries: ActiveEntry[]
}
type ActiveEntry = {
  id: string
  sg?: string                // copied from routine cfg (undefined for mid-workout additions)
  target: object             // {...cfg}
  plan: Prescription         // what progression decided when the entry was built (for the explanation line)
  sets: SetRecord[]          // pre-filled, done:false
  topW?: number              // set by the "confirm working weight" sheet
  asked?: true               // the weight-confirm sheet has already been shown for this entry
}
type Prescription = {
  policy: 'off'|'linear'|'greyskull'|'double'|'time'
  kind: 'off' | 'first' | 'up' | 'hold' | 'deload'
  weight?: number; reps?: number; sec?: number   // only the fields the policy decided
  why?: [templateString, ...args]                // i18n key + positional args, e.g. ['Every rep last time — {0} {1} more.', 2.5, 'kg']
}
```

Building the pre-filled sets with `buildSets(S, cfg)` works as follows:

- `last` is the most recent workout entry for `cfg.id` that has any done set. Only its done sets are used.
- `n = max(1, cfg.sets || 1)`.
- `prevAt(i)` returns `last.sets[i]`, or the last element of `last.sets` when the plan has grown.

The set values then depend on the mode:

- **cardio:** `{min: prev?.min ?? cfg.min||20, speed: prev?.speed ?? cfg.speed||8, done:false}`. The code uses
  `prev ? prev.min : ...`, so a present previous set always wins.
- **time:** `carried = prev && prev.sec > 0 ? prev : null`. The set is
  `{sec: carried ? carried.sec : cfg.sec||45, w: carried ? carried.w||0 : cfg.weight||0, done:false}`.
- **reps:**
  - `conf = S.exWeights[cfg.id]`.
  - `usable = prev && prev.r > 0 ? prev : null`.
  - `w = conf && conf.w > 0 ? conf.w : (usable ? usable.w : cfg.weight)`.
  - The set is `{w, r: usable ? usable.r : cfg.reps, done:false}`.

`applyPrescription(sets, p)` returns the sets unchanged when `p.kind` is `'off'` or `'first'`. Otherwise it overwrites
`w = p.weight`, `r = p.reps` and `sec = p.sec`, but only for the fields that are `!= null` and only on sets where
`!done`.

### 1.7 Body weight and goal

```ts
type BodyWeight = { d: string /* iso */, w: number /* 0.1 precision */, t: number /* epoch ms of entry */ }
```

- **Saving** (`BwSheet`): `n = Math.round(v*10)/10`, and `n` must be `> 0`. The sheet upserts the entry for
  **today's** date by setting `w` and `t = Date.now()`, then re-sorts by `d` ascending.
- **Deleting** is by date: `s.bodyweight = s.bodyweight.filter(b => b.d !== d)`. The sheet lists the 3 most recent
  entries.
- **The picker** is used for both body weight and goal:
  - The slider range is fixed at `1..300` (kg) or `1..660` (lb) with slider step 0.5.
  - Buttons step ±0.1, ±0.5 and ±1.
  - Values are clamped and rounded to 0.1.
  - The initial value is the last entry's `w`, else `70`.
- **`lastBW(S)`** is the last array element, which is the latest date.
- **Goal:** `targetW = n` (must be `> 0`), or `null` to remove it. A body-weight delta is coloured accent when it moves
  toward the goal and red when it moves away:

```js
if (!delta) return 'label-2'; if (!S.targetW) return 'label'
const up = S.targetW > currentW; return (delta > 0) === up ? 'acc' : 'red'
```

- **Pre-workout check-in:** starting any workout first opens this sheet in "required" (locked) mode.
  - "Save & start" writes today's body weight and passes `bw` to the new active workout.
  - "Start without weighing in" passes `null`.

### 1.8 `exWeights` (working-weight memory)

`exWeights` is `{ "<exId>": { w: number, d: "<iso>" } }`. It seeds the weight of the next session in `buildSets`, and
it is updated in the following places:

| Where | Rule |
|---|---|
| Weight-confirm sheet (reps entry, all sets done) | `entry.topW = n` and `exWeights[id] = { w: max(n, cur?.w ?? 0), d: todayISO() }`. `n` must be finite and `>= 0`. |
| Finish workout | Per kept entry, `mx = max(0, done sets' w..., topW or 0)`. If `mx > 0` and (no current value or `mx > cur.w`), set `{w: mx, d: workout.d}`. |
| CSV import | Per imported entry, `mx = max(0, all sets' w..., topW or 0)`. If `mx > 0` and (no current value or `w.d >= cur.d`), set `{w: mx, d: w.d}`. **The newest import wins, even if the weight is lower.** |
| Delete custom exercise | `delete exWeights[id]` |
| Demo seed | `{w: max(w, prev.w or 0), d: iso}`. Can store `w: 0` (for chest dips). |

### 1.9 Exercises: library records and custom exercises

A library record (`EXDB`, 1324 entries, bundled at build time from `hasaneyldrm/exercises-dataset` under CC):

```ts
{ id: '0025', n: 'barbell bench press', bp: 'chest', eq: 'barbell', tg: 'pectorals', mg: '...', sm: ['...'], st: ['step 1', ...], img: '0025-xxxx.jpg', gif: '0025-xxxx.gif' }
```

- `bp` (body part) is one of `waist, upper legs, back, lower legs, chest, upper arms, cardio, shoulders, lower arms, neck`.
  `BODYPARTS` is the sorted unique list.
- `eq` (equipment) is one of 28 values, such as `body weight, cable, leverage machine, barbell, dumbbell, ...`.
- `tg` is the target muscle, `sm` the secondary muscles, and `st` the English instruction steps.

A custom exercise is created by the user and synced inside `S.customEx`:

```ts
{ id: 'c'+uid(), n: string /* trimmed display name */, bp: string /* one of BODYPARTS */, desc: string /* trimmed, <= 1000 chars, may be '' */,
  tg: '', eq: 'custom', custom: true }
```

Validation when a custom exercise is created or edited:

- The name must be non-empty.
- The body part must be chosen.
- No existing exercise, library or custom, may already have the same name case-insensitively, excluding the one being
  edited.

Variants from other sources:

- **CSV import** creates `{ id: 'im'+uid(), n: lowercased name, custom: true, eq: 'custom', tg: '', desc: '', bp }`.
- **Plan-file import** creates `{ id: uid(), n, bp, desc? }`, which has **no** `custom`, `eq` or `tg` (see §9 bug B3).

Every persist calls `registerCustom(S.customEx)`, which merges the customs into the global `EXIDX` id index. Lookups
of an unknown id render a placeholder: `{id, n: t('Unknown exercise'), bp:'', tg:'', eq:'', sm:[], st:[], missing:true}`.
The combined list is `allExercises(S) = [...S.customEx, ...EXDB]`, with customs first.

### 1.10 `coach` namespace (shape only; the Coach spec owns the behaviour)

```ts
coach: null | {
  consent: null | { agreedAt: ISOString, version: 1 },       // CONSENT_VERSION = 1; consent valid iff version matches
  profile: null | { goal: 'strength'|'muscle'|'general'|'fatloss'|'endurance'|null,
                    experience: 'new'|'returning'|'regular'|null,
                    daysPerWeek: number /*default 3*/, preferredDays: number[] /*weekday ints, default [1,3,5]*/,
                    sessionMin: 30|45|60|75|90 /*default 45*/, equipment: string[] /*eq values*/,
                    limitations: string, likes: string, dislikes: string, notes: string },
  cadence: 'off' | { weekly: { day: 0..6 /*default 0*/, time: 'HH:MM' /*default '18:00'*/ } } | { everyWorkouts: number /*default 4, server clamps 1..20*/ },
  lastReview: null | { at: epochMs },
  log: CoachLogEntry[],        // max 50 (oldest dropped)
  snapshots: { at, proposalId, label, routines: Routine[], week: object }[]   // max 3; revert pops the last and restores routines+week
}
```

- `emptyCoach()` returns `{consent:null, profile:null, cadence:'off', lastReview:null, log:[], snapshots:[]}`.
- The serialized namespace is capped at 256 KiB. Past that, the oldest snapshots and then the oldest log entries are
  dropped.
- Withdrawing consent sets `consent: null, cadence: 'off'` and calls `POST /api/coach/forget`.

### 1.11 Complete example document

This example is abbreviated, but every key is shown with a realistic value.

```json
{
  "unit": "kg", "restSec": 90, "sound": true, "keepAwake": true, "lang": "en",
  "theme": "dark", "accent": "lime", "body": "male", "gifSize": "full",
  "effort": "rir",
  "targetW": 77,
  "reminder": { "on": true, "time": "07:30", "tz": "America/Puerto_Rico" },
  "bodyweight": [ { "d": "2026-09-28", "w": 78.7, "t": 1790580600000 } ],
  "routines": [
    { "id": "muo979oo50vo1", "name": "Push Day", "emoji": "barbell", "prog": "linear",
      "ex": [
        { "id": "0025", "sets": 4, "mode": "reps", "reps": 8, "weight": 60, "inc": 2.5 },
        { "id": "0334", "sets": 3, "mode": "reps", "reps": 12, "weight": 10, "sg": "sgmuo9a1b2c3d" },
        { "id": "0241", "sets": 3, "mode": "reps", "reps": 12, "weight": 25, "sg": "sgmuo9a1b2c3d" },
        { "id": "0001", "sets": 3, "mode": "time", "sec": 45, "weight": 0, "prog": "time" },
        { "id": "cmuo9zz12abc", "sets": 3, "mode": "reps", "reps": 10, "weight": 0, "prog": "double", "repsMin": 8 },
        { "id": "0685", "sets": 1, "min": 20, "speed": 8 }
      ] }
  ],
  "week": { "1": "muo979oo50vo1", "3": "muo979oohb54d", "5": "muo979oozjea2" },
  "dayPlan": { "2026-09-30": "muo979oo50vo1", "2026-10-02": "rest" },
  "exWeights": { "0025": { "w": 75, "d": "2026-09-28" } },
  "workouts": [
    { "id": "muo979osyicjp", "d": "2026-09-28", "start": 1790618820000, "end": 1790622240000,
      "routineId": "muo979oo50vo1", "name": "Push Day", "bw": 78.7,
      "entries": [
        { "id": "0025", "topW": 75,
          "target": { "id": "0025", "sets": 4, "mode": "reps", "reps": 8, "weight": 60 },
          "sets": [ { "w": 75, "r": 8, "done": true, "rir": 3 }, { "w": 75, "r": 7, "done": true, "rir": 0.5 },
                    { "w": 75, "r": 8, "done": false } ] },
        { "id": "0001", "topW": null, "target": { "id": "0001", "sets": 3, "mode": "time", "sec": 45, "weight": 0 },
          "sets": [ { "sec": 38, "w": 0, "done": true } ] }
      ],
      "prs": ["0025"], "vol": 1125, "rating": "right", "note": "Felt strong" }
  ],
  "active": null,
  "customEx": [ { "id": "cmuo9zz12abc", "n": "Nordic curl", "bp": "upper legs", "desc": "", "tg": "", "eq": "custom", "custom": true } ],
  "coach": null,
  "_ts": 1790622241000
}
```

### 1.12 Invariants and normalisation rules

1. `bodyweight` is sorted by `d` ascending, with at most one entry per `d`. Imports skip dates that already exist.
2. After an import, `workouts` is sorted by `d` ascending. A finish appends, so the array stays chronological as long as
   the clock is sane.
3. Every `sg` has at least one adjacent partner with the same value. `cleanupSg` runs after every move, remove or unlink.
4. Deleting a routine through the routine editor deletes every `week[k] === id` and every `dayPlan[k] === id`.
5. Deleting a custom exercise removes it from every routine, stamps `e.n` into the matching workout entries, and deletes
   its `exWeights` key. Workouts keep their sets.
6. Empty or cleared optional set fields (`rir`, `rpe`, etc.) are **deleted**, never stored as `null`.
7. `active` is never sent to or stored on the server.
8. The whole document must stay under **5 MiB**, which is the server's request-body limit.

---

## 2. Client store (`useStore.js`, zustand) and every mutation

### 2.1 Store fields

| Field | Initial value | Meaning |
|---|---|---|
| `S` | `loadState()`, with `registerCustom(S.customEx)` applied | The state document |
| `user` | `JSON.parse(localStorage['gym_user'])` or `null` | `{id, name, admin}` of the signed-in profile. Cached so the app renders offline. |
| `ready` | `false` | Becomes `true` when `boot()` finishes |
| `config` | `null` | Result of `GET /api/config`: `{invite_only: bool, coach?: {enabled:true, provider, providerLabel}}` |

`loadState()` reads `localStorage['gym_state_v1']`. If the value exists and parses, the result is
`Object.assign(clone(DEF), parsed)`. On any error it is `clone(DEF)`.

**localStorage keys**

| Key | Value |
|---|---|
| `gym_state_v1` | The state JSON |
| `gym_user` | `{id, name, admin}` JSON |
| `gym_guest` | `'1'` when the user is in guest mode |
| `gym_dirty` | `'1'` when the last push failed |
| `gym_demo_seeded_v1` | `'1'` (demo build only) |

The mobile build also writes the file `opengym-state.json` in the app's private data directory through Capacitor
Filesystem (`Directory.Data`, UTF-8).

### 2.2 The persist pipeline (`persist(S, push = true)`, internal)

```js
S._ts = Date.now()
registerCustom(S.customEx)
localStorage.setItem('gym_state_v1', JSON.stringify(S))
set({ S })
if (MOBILE) nativePersist()                 // debounce 800 ms → nativeSave(S) + syncReminder(S)
if (push && get().user) { clearTimeout(pushTm); pushTm = setTimeout(() => get().pushState(), 1500) }   // debounce 1.5 s
```

On `visibilitychange` to `hidden` the pipeline flushes immediately:

- If a native save is pending (mobile), it runs now.
- If a push is pending, the pipeline clears the timer and calls `pushState()` now.

### 2.3 Actions (the public API of the store)

| Action | Exact behaviour |
|---|---|
| `update(mut, push = true)` | `const S = clone(get().S); mut(S); persist(S, push)`. **If `mut` throws, nothing is persisted.** The Coach's all-or-nothing change-set application relies on this. |
| `replaceState(S, push = false)` | `persist(clone(S), push)`. |
| `isGuest()` | `localStorage['gym_guest'] === '1'`. |
| `setGuest(v)` | Sets or removes `gym_guest`, then `set({})` to force a re-render. |
| `setUser(u)` | With `u`: stores `gym_user = JSON(u)` and **removes `gym_guest`**. Without `u`: removes `gym_user`. Then `set({user: u})`. |
| `pushState()` | Returns immediately if there is no `user`. Otherwise it clears the pending push timer and sends `PUT /api/data` with body `{"state": S}` (the full `S`, including `active`; the server strips it). On success it removes `gym_dirty`. On any error it sets `gym_dirty = '1'`. **It never throws.** |
| `pullState()` | Described in §3.6.2. Any network error is ignored and the local copy is kept. |
| `signOut()` | `await pushState()`, then `POST /api/logout` with body `{}`. Both errors are swallowed. Then `clearLocalSession()`. |
| `signOutAll()` | `await pushState()`, then `POST /api/logout/all`. **If this fails, it throws and local data is NOT cleared.** On success it calls `clearLocalSession()`. |
| `clearLocalSession()` (internal) | `setUser(null)`, remove `gym_guest`, `gym_dirty` and `gym_state_v1`, then `persist(clone(DEF), false)`. The in-memory state becomes the defaults, and the key is written back with `DEF + _ts`. |
| `resetDemo()` (demo build) | Remove `gym_dirty`, then `persist(Object.assign(clone(DEF), buildDemoState()), false)`. |
| `boot()` | Described in §2.4. |

### 2.4 `boot()` for each build flavour

1. **Mobile build (`VITE_MOBILE=1`, Capacitor, no backend):**
   1. `saved = await nativeLoad()`.
   2. If `saved` exists and (`!hasData(S)` or `saved._ts >= S._ts`), call `persist(DEF ⊕ saved, false)`.
   3. Otherwise, if `hasData(S)`, call `nativeSave(S)` to seed the file mirror.
   4. Then `setGuest(true)`, `syncReminder(S)`, and `ready = true`.
2. **Demo build (`VITE_DEMO=1`, GitHub Pages, no backend):**
   1. If `gym_demo_seeded_v1` is unset, set it and call `resetDemo()`.
   2. Then `setGuest(true)` and `ready = true`.
3. **Self-hosted web (normal):**
   1. `config = await api('/api/config')`. Errors are ignored.
   2. `me = await api('/api/me')`, then `setUser(me.user)` and `await pullState()`.
   3. If `S.reminder?.on` and `S.reminder.tz !== localTZ()`, call `update(s => s.reminder = {...s.reminder, tz})`,
      which pushes.
   4. If `/api/me` fails with **401**, call `setUser(null)`. Other errors (offline) keep the cached `gym_user`, so the
      user stays signed in against local data.
   5. Always finish with `ready = true`.

The app shell (`App.jsx`) works as follows:

- `authed = user || isGuest()`.
- A splash screen shows only when `!ready && !authed`. Otherwise either `<Login/>` (not authed) or the routes render.
- Routes (hash router): `/home, /plan, /plan/r/:id, /workout, /stats, /history, /library, /settings, /coach,
  /coach/intake, /coach/proposal, /admin` (only when `user.admin`, else redirect to `/home`), and `*` redirects to
  `/home`.
- `theme` and `accent` are applied to `<html data-theme data-accent>`. The meta theme-color is `#f2f2f7` (light) or
  `#000000` (dark).
- The Wake Lock is held while `!!S.active && S.keepAwake !== false`.
- A service worker (`sw.js`) is registered only on https and not on the mobile build.

### 2.5 Catalogue of every state mutation in the app

All of these go through `update(fn)`, which pushes, unless the table says otherwise. `t(...)` means a localized string.

#### 2.5.1 Settings

| Action | Mutation |
|---|---|
| Language | `s.lang = v` |
| Unit | `s.unit = 'kg'\|'lb'`. No conversion. |
| Rest timer | `s.restSec = 60\|90\|120\|150\|180` |
| Keep awake | `s.keepAwake = bool` |
| Sounds | `s.sound = bool` |
| Effort per set | `s.effort = 'none'\|'rir'\|'rpe'; delete s.showRir` |
| Theme / body / accent | `s.theme = 'dark'\|'light'`, `s.body = 'male'\|'female'`, `s.accent = key` |
| Reminder toggle (web, visible only when push is on) | `s.reminder = {...(s.reminder \|\| DEF.reminder), on: !s.reminder?.on, tz: localTZ()}` |
| Reminder time | `s.reminder = {...(s.reminder \|\| DEF.reminder), time: 'HH:MM', tz: localTZ()}` |
| Mobile reminder toggle | Turning on first calls `syncReminder({...S, reminder:{...,on:true}}, interactive=true)`, which can show the OS permission prompt. If that fails, a toast appears and nothing is saved. Otherwise `s.reminder = {...(s.reminder \|\| DEF.reminder), on, tz: localTZ()}`. |
| Load starter plan (also on the empty Plan screen) | `s.routines.push(push, pull, legs)` (new ids every time, so repeating it duplicates routines), then `s.week[1]=push.id; s.week[3]=pull.id; s.week[5]=legs.id`. Other weekdays stay as they were. |
| Import backup (JSON) | See §6.2: `replaceState(DEF ⊕ file, push=true)` |
| Reset everything | If signed in, `POST /api/coach/forget` (fire and forget). Then `replaceState(clone(DEF), push=true)`. |
| Gif size (media widget) | `s.gifSize = mini ? 'full' : 'mini'` |

#### 2.5.2 Plan and schedule

| Action | Mutation |
|---|---|
| New routine | `s.routines.push({ id: uid(), name: t('New routine'), emoji: 'figureStrength', ex: [] })`, then navigate to `/plan/r/<id>` |
| Assign weekday | `if (v) s.week[day] = v; else delete s.week[day]` (the "Rest day" choice passes `''`) |
| Reschedule a date | `if (!v) delete s.dayPlan[iso]; else s.dayPlan[iso] = v`, where `v` is a routine id, `'rest'`, or `''` for "back to weekly plan". The sheet is reached by tapping a non-trained calendar date. |
| Rename routine (on every keystroke) | `r.name = input.trim() \|\| t('Routine')` |
| Change icon | `r.emoji = glyphKey` |
| Routine progression | `r.prog = policy` |
| Move exercise up/down | Swap `ex[i]` and `ex[i±1]` (ignored at the bounds), then `cleanupSg(ex)` |
| Superset link toggle on row i (i ≥ 1) | If `cur.sg && prev.sg && cur.sg === prev.sg`, `delete cur.sg`. Otherwise `gid = prev.sg \|\| 'sg'+uid(); prev.sg = gid; cur.sg = gid`. Then `cleanupSg(ex)`. |
| Edit exercise config | `ex[i] = { id: ex[i].id, sg: ex[i].sg, ...cfg }`. The whole config is replaced; only `id` and `sg` are preserved. |
| Remove exercise | `ex.splice(i, 1); cleanupSg(ex)` |
| Add exercise (routine editor) | `ex.push({ id: exId, ...cfg })` |
| Add to plan (library / exercise detail) | Push `{id, ...cfg}` onto the chosen routine, or onto a new routine `{id: uid(), name: t('New routine'), emoji: 'figureStrength', ex: []}` that is pushed first |
| Delete routine | `s.routines = s.routines.filter(x => x.id !== id)`, then delete the `week` keys and `dayPlan` keys whose value equals `id` |
| Import plan file | `mergePlan(s, bundle, {schedule})` (§6.1) |
| Coach: apply created plan | Snapshot, then `mergePlan`, then a log entry |
| Coach: change set | Snapshot, then the typed changes (`add-exercise, remove-exercise, swap-exercise, sets, reps, repsMin, sec, cardio, inc, exercise-prog, routine-prog, reorder, superset, add-routine, remove-routine, rename-routine, week`), then log and `lastReview`. See the Coach spec. |
| Coach: revert | Restore `routines` and `week` from the last snapshot. **Workouts are untouched.** |

#### 2.5.3 Workout lifecycle

| Step | Mutation |
|---|---|
| Start (`startFlow(routineId \| null)`) | Required body-weight sheet, then `beginWorkout(routineId, bw \| null)`. |
| `beginWorkout` | `entries = routine.ex.map(cfg => ({ id: cfg.id, sg: cfg.sg, target: {...cfg}, plan: nextPrescription(S,cfg,r), sets: applyPrescription(buildSets(S,cfg), plan) }))` (empty for freestyle). Then `s.active = { id: uid(), d: todayISO(), start: Date.now(), routineId, name: r ? r.name : t('Freestyle'), bw: bw \|\| null, cur: 0, entries }`, then stop the rest timer and navigate to `/workout`. |
| Edit a set field | `v == null` deletes `sets[i][field]`; otherwise sets `sets[i][field] = v`. Fields: `w, r, sec, min, speed, rir, rpe`. The weight/reps steppers step by 2.5/1, clamp at `>= 0` and round to 0.01. Effort steppers use `stepEffort`, and typed effort is capped by `capEffort` (§2.6). |
| Add set | Copies the last set of the right mode: cardio `{min, speed}` (target defaults 20/8); time `{sec, w}` (45/0); reps `{w: last.w or 0, r: last.r or target.reps}`. The new set has `done:false`. |
| Remove set | `pop()`, but only while `sets.length > 1` |
| Toggle a set | `done = !done`. When it becomes done: beep and vibrate. If all of the entry's sets are done and the mode is reps and `!asked`, set `asked = true` and open the weight-confirm sheet. The rest-timer and superset flow belongs to the workout spec. |
| Timed set via work timer | On completion or an early finish, `sets[i].sec = elapsedSec`, then toggle to done if it is not done yet. |
| Prev/Next | `s.active.cur = units[unitIdx ± 1][0]` |
| Add exercise mid-workout | `full = {...cfg, id}` and `plan = nextPrescription(s, full, activeRoutine)`, then push `{ id, target: {...cfg}, plan, sets: applyPrescription(buildSets(s, full), plan) }` and set `cur` to the new index. |
| Weight-confirm sheet | See §1.8. `entry.topW = n`. `exWeights[id] = {w: max(n, cur.w), d: today}`. |
| Discard (or ErrorBoundary "Discard the running workout") | `s.active = null` |
| Finish | Confirmation first when no set is done ("Nothing logged yet") or when some sets are not done ("{n} sets still unchecked"). The record is built as in §1.5, `exWeights` is updated as in §1.8, then `s.workouts.push(w); s.active = null`. |
| Rate a session (finish summary, only when the Coach is enabled and consented) | `rec.rating = 'easy'\|'right'\|'hard'`. Tapping the current value again deletes it. |
| Note (after rating) | `v = note.trim()`. If `v` is non-empty, `rec.note = v.slice(0,300)`; otherwise `delete rec.note`. Saved on blur. |
| Delete a workout | `s.workouts = s.workouts.filter(x => x.id !== w.id)`. `exWeights` is **not** recomputed. |

#### 2.5.4 Body weight and goal

See §1.7. Import (bodyweight kind) is covered in §6.3.

#### 2.5.5 Custom exercises

| Action | Mutation |
|---|---|
| Create | `(s.customEx ||= []).push({ id: 'c'+uid(), n, bp, desc, tg:'', eq:'custom', custom:true })` |
| Edit | `c.n = name; c.bp = bp; c.desc = d` |
| Delete (blocked if the active workout contains it) | `customEx` filtered. Every routine: `r.ex = r.ex.filter(e => e.id !== id); cleanupSg(r.ex)`. Every workout entry with that id: `e.n = ex.n`. Then `delete s.exWeights[id]`. |

#### 2.5.6 Imports from other apps (CSV/XML)

This is `mergeImport(S, parsed)`. The parser belongs to the import spec. See §6.3.

### 2.6 `useUI` store (ephemeral, not persisted)

| Field / action | Behaviour |
|---|---|
| `sheets: {id, render(close), kind: 'sheet'\|'center', locked}[]` | A modal stack. `openSheet(render, {kind='sheet', locked=false})` returns `{id, close, lock(v)}`. There are also `closeSheet(id)` and `closeAll()`. |
| `toastMsg` | `toast(msg)` sets it and clears it after **2200 ms**. |
| `timer: {left, total, endsAt} \| null` | The rest countdown. |
| `startRest(sec)` | Calls `stopRest()` first. Then `endsAt = now + sec*1000`, and if signed in `POST /api/push/rest-timer {seconds: sec}` (fire and forget). It ticks every 1 s and on `visibilitychange`: `left = max(0, round((endsAt-now)/1000))`. In the last 3 s it beeps (660 Hz, 0.1 s). At 0 it plays beeps 880/0.15 s, 880/0.15 s @+0.25 and 1320/0.4 s @+0.5, vibrates `[200,100,200]`, toasts "Rest over — next set!" and calls `stopRest()`. |
| `addRest(sec)` (±) | `left = tm.left + sec`. If `left <= 0`, call `stopRest()`. Otherwise `total += sec`, `endsAt += sec*1000`, and `POST /api/push/rest-timer {seconds: left}`. |
| `stopRest()` | Clears the interval and listener. If a timer existed, `POST /api/push/rest-timer/cancel` with `{}`. Sets `timer = null`. |
| `work: {left, total, endsAt, label} \| null` | Countdown for a **timed set**. It never runs together with rest (`startWork` stops rest). There is **no server push**. |
| `startWork(sec, label, onDone)` | `total = max(1, round(sec) \|\| 1)`. The tick is the same as rest. At 0 it plays the same beeps and vibration, then `onDone(total)`. |
| `finishWorkEarly()` | `elapsed = max(1, total - left)`, `vibrate(30)`, `stopWork()`, `onDone(elapsed)`. |
| `stopWork()` | Abandons the countdown without logging anything. |

`stepEffort(kind, cur, dir)` and `capEffort`:

```js
stepEffort: e = EFFORT[kind]; if (!e) return cur ?? null
  if (cur == null) return dir < 0 ? null : e.min           // + on empty starts at the bottom (RIR 0 / RPE 6)
  n = round2(cur + dir*e.step)
  if (dir < 0 && n < e.min) return null                    // stepping off the bottom clears
  return dir > 0 ? Math.min(e.max, n) : Math.max(e.min, n)
capEffort(kind, v) = (v == null || !EFFORT[kind]) ? v : Math.min(EFFORT[kind].max, v)   // typed value: ceiling only
```

---

## 3. HTTP API (`api/server.js`) and the sync model

### 3.1 General behaviour

- The server is a plain `node:http` server with no framework. Routing is an exact map lookup on
  `req.method + ' ' + url.pathname`, so the query string is ignored for matching.
- An unknown route returns **404 `{"error":"not found"}`**.
- Every response is JSON with the headers `Content-Type: application/json` and `Cache-Control: no-store`. The helper
  signature is `json(res, code, obj, extraHeaders)`.
- A handler exception returns **500 `{"error":"server error"}`** when headers have not been sent yet. **Malformed JSON
  (`bad json`) and a body over 5 MiB (`body too large`, after which the request is destroyed) surface as 500.** Neither
  has a dedicated 400 or 413 response.
- `readBody` returns `{}` for an empty body.
- The server is deployed behind nginx on the **same origin** as the web app, which WebAuthn requires. nginx proxies
  `/api/` to the API server. There is no CORS.
- The client helper `api(path, opts)`:
  - calls `fetch(path, {headers: {'Content-Type':'application/json'}, ...opts})`, which sends the cookie automatically
    because the request is same-origin;
  - parses JSON, treating a failure as `{}`;
  - if `!r.ok`, throws `Error(data.error || 'HTTP '+status)` with `.status` set.

**Environment variables**

| Var | Default | Meaning |
|---|---|---|
| `PORT` | `3000` | |
| `DATA_DIR` | `/data` | Directory created with mode 0700 (best effort) |
| `RP_ID` | `localhost` | WebAuthn RP ID, which is the domain |
| `ORIGIN` | `http://localhost:8080` | WebAuthn expected origin. Also decides the `Secure` cookie flag (https ⇒ Secure). |
| `RP_NAME` | `openGym` | |
| `ADMIN_UIDS` | `''` | Comma-separated user ids that are admins |
| `INVITE_ONLY` | off | `1\|true\|yes\|on` (case-insensitive) turns it on |
| `SESSION_DAYS` | `90` | `Math.max(1, +(env \|\| 90) \|\| 90)`. `'0'` and `'abc'` give 90, a negative value gives 1. |
| `VAPID_SUBJECT` | `ORIGIN` if https, else `'mailto:admin@localhost'` | |

### 3.2 Server-side storage (`DATA_DIR`)

| File | Content |
|---|---|
| `secret` | 64 hex chars (32 random bytes), mode 0600. The HMAC key for sessions. Deleting it signs everybody out. |
| `db.json` | `{ users: User[], creds: Cred[], subs: PushSub[], invites: Invite[] }`, pretty-printed. Written atomically (write to `.tmp`, then `rename`). Missing `subs` or `invites` default to `[]`. |
| `state-<uid>.json` | The user's state document `S` without `active`, compact JSON. The uid is sanitised with `/[^a-zA-Z0-9_-]/g → ''`. Written atomically. |
| `vapid.json` | `{publicKey, privateKey}`, generated once, mode 0600. |
| (Coach) | Coach config and per-user job files. Out of scope here. |

```ts
type User   = { id: string, name: string /*<=40*/, created: ISOString, invitedBy?: string /*invite code*/,
                sv?: number /*session version, default 0*/, disabled?: boolean, admin?: true, lastReminder?: 'YYYY-MM-DD' }
type Cred   = { id: string /*base64url credential id*/, userId: string, publicKey: string /*base64url COSE key*/,
                counter: number, transports: string[] }
type PushSub= { userId: string, endpoint: string, keys: { p256dh: string, auth: string }, created: ISOString }
type Invite = { code: string /*16 uppercase hex*/, note: string /*<=60*/, createdBy: userId, created: ISOString,
                usedBy?: userId, usedAt?: ISOString, revoked?: boolean /*checked but never set — see §9*/ }
```

The server also keeps some in-memory state, all of which is lost on restart:

- **challenges:** `cid → {challenge, name?, uid?, code?, exp}`. TTL 5 min, single use, garbage-collected every 60 s.
- **presence:** `uid → {name, exIdx, exTotal, setsDone, setsTotal, startedAt, updatedAt}`. TTL 70 s, garbage-collected
  every 30 s.
- **restTimers:** `uid → Timeout`, at most one per user.

### 3.3 Endpoint catalogue

The Auth column uses these values:

- "public": no cookie is needed.
- "session": needs a valid `gymsid` cookie, else **401 `{"error":"not signed in"}`**.
- "admin": needs a session and admin rights. Without a session the response is 401; a non-admin gets
  **403 `{"error":"forbidden"}`**.

| # | Method & path | Auth | Request body | Success response | Errors / notes |
|---|---|---|---|---|---|
| 1 | `GET /api/health` | public | none | `200 {ok:true, users:<count>}` | |
| 2 | `GET /api/config` | public | none | `200 {invite_only: bool, coach?: {enabled:true, provider, providerLabel}}` | `coach` is present only if the Coach is enabled **and** connected. |
| 3 | `GET /api/me` | session | none | `200 {user:{id, name, admin: bool}}` | 401 |
| 4 | `POST /api/register/options` | public | `{name: string, code?: string}` | `200 {cid, options}` (WebAuthn creation options JSON from simplewebauthn) | `name` is trimmed and cut to 40 chars; empty gives **400 `name required`**. `code` is trimmed and uppercased. If invite-only and no invite exists with `code === code && !usedBy && !revoked`, the response is **403 `a valid invite code is required`**. |
| 5 | `POST /api/register/verify` | public | `{cid, credential: RegistrationResponseJSON}` | `200 {user:{id,name,admin}}` + `Set-Cookie` | A missing, expired or already-used challenge gives **400 `challenge expired — try again`**. A verify exception gives **400 `verification failed: <msg>`**, and `!verified` gives **400 `not verified`**. A credential id that already exists gives **409 `credential already registered`**. If invite-only, the invite is re-checked (**403 `invite code is no longer valid — ask for a new one`**) and then burnt. |
| 6 | `POST /api/login/options` | public | `{}` | `200 {cid, options}` (request options with `allowCredentials: []`, i.e. discoverable) | |
| 7 | `POST /api/login/verify` | public | `{cid, credential: AuthenticationResponseJSON}` | `200 {user:{id,name,admin}}` + `Set-Cookie` | **400** for an expired challenge. An unknown credential id gives **404 `unknown passkey — create a profile first`**. Verify failures give **400**. On success the counter is saved *before* the user checks. A missing user gives **500 `user missing`**, and a disabled user gives **403 `this account has been disabled`**. |
| 8 | `POST /api/logout` | public | `{}` | `200 {ok:true}` + clear-cookie | The session is not invalidated server-side; only the cookie is cleared. |
| 9 | `POST /api/logout/all` | session | `{}` | `200 {ok:true}` + clear-cookie | `user.sv = (user.sv \|\| 0) + 1`, which invalidates every cookie ever issued for the account. |
| 10 | `GET /api/data` | session | none | `200 {state: S \| null}` | `null` if the file is missing or unparseable. |
| 11 | `PUT /api/data` | session | `{state: S}` | `200 {ok:true, ts: state._ts \|\| null}` | `!body.state \|\| typeof body.state !== 'object'` gives **400 `state required`** (an array would pass). The server does `delete state.active` and then overwrites the file. **There is no version or conflict check.** |
| 12 | `GET /api/push/public-key` | public | none | `200 {key: vapidPublicKey}` (base64url) | |
| 13 | `POST /api/push/subscribe` | session | `{subscription: {endpoint, keys:{p256dh, auth}}}` (a `PushSubscription.toJSON()`) | `200 {ok:true}` | Missing fields give **400 `invalid subscription`**. Existing subs with the same endpoint, from any user, are removed and then this one is appended. |
| 14 | `POST /api/push/unsubscribe` | session | `{endpoint}` | `200 {ok:true}` | Removes the sub where `userId` and `endpoint` match. |
| 15 | `POST /api/push/test` | session | `{}` | `200 {ok:true}` after sending | Push payload `{title:'openGym', body:'Test notification ✅ — this is what alerts look like.', tag:'test'}`. |
| 16 | `POST /api/push/rest-timer` | session | `{seconds: number}` | `200 {ok:true}` | `sec = max(1, min(3600, round(+seconds \|\| 0)))`. The "seconds required" 400 therefore can never trigger, and a missing value means 1 s. Replaces the user's pending timer. When it fires, the push is `{title:'Rest over 💪', body:'Time for your next set.', tag:'rest-timer'}`. |
| 17 | `POST /api/push/rest-timer/cancel` | session | `{}` | `200 {ok:true}` | |
| 18 | `POST /api/activity` | session | `{active: true, name, exIdx, exTotal, setsDone, setsTotal, startedAt}` or `{active:false}` | `200 {ok:true}` | With `active` truthy it upserts presence (`name` cut to 60 chars, numbers coerced with `+x \|\| 0`, `startedAt` defaults to now, `updatedAt = now`). Otherwise it deletes presence. The client heartbeats every **20 s** while the workout screen is mounted. On unmount it sends `navigator.sendBeacon('/api/activity', {active:false})` plus a fetch. `exIdx` is 1-based **unit** index, and `exTotal` is the unit count. |
| 19 | `GET /api/admin/users` | admin | none | `200 {users: AdminUserRow[], invite_only, now: epochMs}` | `AdminUserRow = {id, name, created\|null, disabled: bool, admin: bool, invitedBy\|null, workouts: count, lastWorkout: <last array element's d>\|null, lastSync: S._ts\|null, hasPush: bool, live: Presence\|null}`. Reads every state file. |
| 20 | `GET /api/admin/user?id=<uid>` | admin | none | `200 {user:{id,name,created,disabled,admin,invitedBy}, unit: S.unit\|\|'kg', lastSync, routines:[{id,name,emoji,count: ex.length}], bodyweight: S.bodyweight\|\|[], workouts: reversed (newest first)}` | Unknown id gives **404 `no such user`**. |
| 21 | `POST /api/admin/user/disable` | admin | `{id, disabled: bool}` | `200 {ok:true, id, disabled}` | **404** if the user is unknown. Targeting an admin gives **400 `cannot disable an admin`**. Disabling also deletes presence. A disabled user fails `readSession`, which locks them out everywhere, and cannot log in. |
| 22 | `GET /api/admin/invites` | admin | none | `200 {invites: (Invite & {usedByName: string\|null})[], invite_only}` | |
| 23 | `POST /api/admin/invites/new` | admin | `{note?}` | `200 {invite}` | `code = randomBytes(8).hex().toUpperCase()` (16 chars), regenerated until unique. `note` is cut to 60 chars. |
| 24 | `POST /api/admin/invites/revoke` | admin | `{code}` | `200 {ok:true}` | The lookup uppercases `code`. Unknown gives **404 `no such code`**. An already-used code gives **400 `already used — cannot revoke`**. A revoke **deletes** the invite from the db. |
| 25+ | Coach routes: `GET /api/coach/disclosure` (public), `GET /api/coach/status`, `POST /api/coach/plan {intake?, refine?}` → 202 `{job}`, `POST /api/coach/review {note?}` → 202, `POST /api/coach/pending/resolve {accepted[], rejected[], dismissed}`, `POST /api/coach/forget`, and admin routes `GET /api/admin/coach`, `POST /api/admin/coach/config`, `/test`, `/auth/setup-token`, `/auth/chatgpt/device`, `GET /auth/chatgpt/status`, `/auth/key`, `/auth/disconnect` | | | | Out of scope; see the Coach spec. User Coach routes return 503 when the Coach is off. Enqueue errors map to 409 busy, 429 cap, 403 consent and 503 off. |

**WebAuthn options (server side, `@simplewebauthn/server` v13)**

- **Registration:**
  - Options: `generateRegistrationOptions({ rpName, rpID, userID: Buffer.from(uid) /* utf-8 bytes of the 16-char uid */, userName: name, userDisplayName: name, attestationType: 'none', authenticatorSelection: { residentKey: 'required', userVerification: 'preferred' }, excludeCredentials: [] })`.
  - Verify: `verifyRegistrationResponse({ response, expectedChallenge, expectedOrigin: ORIGIN, expectedRPID: RP_ID, requireUserVerification: false })`.
  - The stored `publicKey` is the base64url of `credential.publicKey`, `counter = credential.counter || 0`, and
    `transports = body.credential.response.transports || []`.
  - **The display name is not unique.**
- **Login:**
  - Options: `generateAuthenticationOptions({ rpID, userVerification: 'preferred', allowCredentials: [] })`. This is
    usernameless login with a discoverable credential.
  - Verify: `verifyAuthenticationResponse({ ..., requireUserVerification: false, credential: { id, publicKey: base64urlDecode(stored), counter, transports } })`.
  - Then `cred.counter = authenticationInfo.newCounter`.
  - The user is found by **credential id**. `userHandle` is ignored.

**Client-side WebAuthn JSON encoding (`api.js`)**

The client converts the server's base64url strings to `ArrayBuffer` for `options.challenge`, `options.user.id` and
each `excludeCredentials[].id` / `allowCredentials[].id`. It serialises the credential as:

```js
{ id, rawId: b64u(rawId), type, clientExtensionResults, authenticatorAttachment: x || null,
  response: { clientDataJSON: b64u,
              // registration:
              attestationObject: b64u, transports: r.getTransports ? r.getTransports() : ['internal'],
              // authentication:
              authenticatorData: b64u, signature: b64u, userHandle: userHandle ? b64u : null } }
```

`b64u` is standard base64 with `+→-`, `/→_` and trailing `=` stripped.

### 3.4 Background processes (server)

1. **Workout-day reminder.** The server scans every **10 s**. For each user in `db.users`:
   1. Skip the user if they have no push subscription.
   2. `S = readState(uid)`. Skip if `!S?.reminder?.on`.
   3. `now = userNow(S.reminder.tz || 'UTC')`, which returns `{date, hhmm, weekday}` computed with
      `Intl.DateTimeFormat('en-CA', {timeZone, hour12:false, y/m/d/h/m 2-digit})`. An invalid zone gives `null`, and
      the user is skipped.
   4. Skip unless `S.reminder.time === now.hhmm`, which is an **exact minute match**.
   5. Skip if `user.lastReminder === now.date`.
   6. Skip if any workout has `d === now.date`.
   7. `rid = effectiveRoutineId(S, now.date)`. Skip if it is null (rest day).
   8. Set `user.lastReminder = now.date`, `saveDb()`, and push
      `{title: routine ? `${routine.emoji || '🏋️'} ${routine.name} today` : 'Workout planned today', body: "It's on your plan — let's go 💪", tag: 'day-reminder'}`.
2. **Rest-timer push.** Exactly one pending timer per user, held in memory (endpoints 16 and 17).
3. **`sendPush(userId, payload)`:**
   - Sends to every subscription of the user with `web-push` and `{urgency:'high'}`, using the default TTL.
   - Removes a subscription on HTTP 404 or 410 and saves the db.
   - The payload JSON is `{title, body, tag, url?}`.
   - The service worker shows `title || 'openGym'`, `body`, `icon-512.png` / `icon-180.png` and `tag`, with
     `renotify: true`.
   - On click it focuses any open window or opens `./`. It ignores `url`.
4. **Coach proposal push:** `{title:'Your Coach has been reading', body: n===1 ? '1 suggestion after this week' : `${n} suggestions after this week`, tag:'coach-proposal', url:'#/coach'}`.
5. **Coach cadence** runs every 60 s (see the Coach spec). It reads `S.coach` and `S.reminder.tz`.

**Mobile build reminder (client only).**

- `syncReminder(S)` cancels the local notification ids 100–106.
- If the reminder is on and permission is granted, it schedules one weekly repeating notification per weekday in `week`
  whose routine exists:
  - `id = 100 + weekday`.
  - Schedule `{on: {weekday: weekday+1 /*Capacitor 1=Sunday*/, hour, minute}, allowWhileIdle: true}`.
  - Title `t('Workout day')`, body `t('{0} is on the plan today — let’s go!', routineName)`.
- Unlike the server reminder, it ignores `dayPlan` overrides and fires even when a workout was already logged that day.

### 3.5 Sessions (cookie)

- **Cookie:** `gymsid=<payload>.<mac>`, with attributes `Path=/; Max-Age=<SESSION_DAYS*86400>; HttpOnly;[ Secure;] SameSite=Lax`.
- **Payload:** `"<uid>:<expiryEpochMs>:<sv>"`, where `expiry = now + SESSION_DAYS*86400000` and `sv = user.sv || 0`.
- **MAC:** `HMAC-SHA256(key = SECRET string, data = payload)` encoded as base64url. It is compared with `timingSafeEqual`,
  and a length mismatch rejects.
- **`readSession`** returns the user only if all of the following hold. Otherwise it returns `null`.
  1. The cookie exists.
  2. The MAC is valid.
  3. `uid` is present and `+exp >= now`.
  4. The user exists and `!disabled`.
  5. The claimed version equals `user.sv || 0`. A missing third field counts as version 0 (legacy cookies). A
     non-integer version is rejected.
- **Clear-cookie:** `gymsid=; Path=/; Max-Age=0; HttpOnly;[ Secure;] SameSite=Lax`.
- **No sliding renewal:** a cookie is only minted at register or login, so a session ends `SESSION_DAYS` after login.

### 3.6 Sync model

#### 3.6.1 Summary

- The unit of sync is the **entire state document**, `active` excluded.
- There is no per-entity merge, no server-side version and no conditional write.
- **Push:** every local mutation schedules one `PUT /api/data`, debounced by 1.5 s and flushed when the app is hidden.
  The last write to reach the server wins.
- **Pull:** happens only at boot (web), right after sign-in, and after registration when the device has no local data.
  There is no periodic or on-focus pull.
- **Conflict rule at pull time:** last writer wins by the client wall-clock `_ts`, with a "local has no data" override
  and a "dirty" override.

#### 3.6.2 `pullState()` algorithm (exact)

```js
const { state } = await api('/api/data')            // throws → caught → keep local, do nothing
const S = get().S
const dirty = localStorage.getItem('gym_dirty') === '1'
if (state && (!hasData(S) || ((state._ts || 0) >= (S._ts || 0) && !dirty))) {
  const active = S.active                           // keep the local in-progress workout
  const next = Object.assign(clone(DEF), state)
  if (active) next.active = active
  persist(next, false)                              // NOTE: re-stamps next._ts = Date.now(); does NOT push
} else if (hasData(S)) {
  await get().pushState()                           // local wins → overwrite server
}
// (state null and no local data → nothing)
```

Decision table:

| Server `state` | Local `hasData` | `gym_dirty` | `_ts` comparison | Result |
|---|---|---|---|---|
| null | false | any | n/a | nothing |
| null | true | any | n/a | push local |
| present | false | any | any | **take server** |
| present | true | false | server ≥ local | **take server** |
| present | true | false | server < local | push local |
| present | true | true | any | push local |

#### 3.6.3 Consequences and edge cases to reproduce or fix

1. **Pull re-stamps `_ts`.** After a pull, local `_ts` is "now", which is newer than the server copy. On the next boot,
   when nothing changed elsewhere, the rule pushes the identical content back. This is harmless but causes extra writes.
2. **A long-running session can overwrite another device's edits.** Device A is open while device B edits and pushes.
   A's next local edit pushes A's whole document, and B's changes are lost. Nothing re-pulls between boots.
3. **Offline edits:**
   - A failed push sets `gym_dirty`.
   - At the next boot, a dirty device pushes regardless of timestamps, which overwrites newer server data.
   - `gym_dirty` is cleared only by a successful push.
4. **Clock skew:** `_ts` is client time. A device with a fast clock tends to win.
5. **Guest to account:**
   - When registering, if the guest has data (`hasData`), the client calls `pushState()` and the local data becomes
     the profile's data. Otherwise it calls `pullState()`.
   - When a guest with local data **signs in to an existing profile**, the normal `pullState` rule applies. If the
     server `_ts` is at least the guest's `_ts`, **the guest's local data is silently replaced**. Otherwise the guest
     data overwrites the server profile.
6. **Sign-out:** the client pushes first, clears all local data and resets to `DEF`. A later sign-in pulls, because
   `hasData` is false.
7. **The server never modifies `S`** apart from stripping `active`. Only clients write it. The Coach job reads it but
   writes proposals to a separate store, and the client applies them locally.

---

## 4. Auth model (summary)

| Mode | How it is entered | Data location | Notes |
|---|---|---|---|
| **Guest** | "Continue without account" on the Login screen (`gym_guest='1'`). The demo and mobile builds are always guest. | localStorage, plus the file mirror on mobile | No server calls except `GET /api/config`. Push, rest-timer push, presence and Coach need a session. |
| **Passkey account** | "Create new profile" (name, plus an invite code if `config.invite_only`) or "Sign in with passkey" | Server `state-<uid>.json`, cached locally | Usernameless, discoverable credentials. There is no password, email or recovery. Adding a second passkey to a profile is **not supported** (registration always creates a new user). |
| **Admin** | `user.admin === true` in db.json, or the uid is listed in `ADMIN_UIDS` | | Grants `/api/admin/*` and the `/admin` route. An admin cannot be disabled through the API. |
| **Invite-only** | `INVITE_ONLY=1` | | Registration needs an unused, unrevoked code. The code is checked at options time and again at verify time, then burnt (`usedBy`, `usedAt`, and `user.invitedBy = code`). The options endpoint therefore acts as a code-validity oracle, and codes are 64-bit on purpose. |
| **Disabled** | Admin toggle | | Every session is refused and login returns 403. Data is kept. |

Client flows:

- **Login screen:** `passkeyLogin()` → `setUser(u)` → `pullState()` → toast. `NotAllowedError` and `AbortError`
  (user cancelled) are silent.
- **Register (Login sheet):**
  - The name is required. The code is required when invite-only and is uppercased as typed.
  - `passkeyRegister(name, code)` → `setUser(u)`.
  - If `hasData(S)`, `pushState()`; otherwise `pullState()`.
  - The register sheet in Settings calls `passkeyRegister(name)` **without a code** (§9 B5).
- **Sign out:** `signOut()`, which pushes, logs out and clears local data.
- **Sign out everywhere:** `signOutAll()`. If it fails, the app shows "still signed in" and leaves local data untouched.

---

## 5. Starter plan and demo seed

### 5.1 Starter plan (`starterRoutines()`)

Each call produces fresh routine ids. Every exercise gets `{id, sets, reps, weight: 0}`, with **no `mode`**. When
loaded, the schedule is Mon push, Wed pull and Fri legs. The toast reads "Starter plan loaded — Mon Push · Wed Pull ·
Fri Legs".

| Routine (`name`, `emoji`) | Exercise id | Library name | bp / eq | sets × reps |
|---|---|---|---|---|
| **Push Day**, `barbell` | 0025 | barbell bench press | chest / barbell | 4 × 8 |
| | 0047 | barbell incline bench press | chest / barbell | 3 × 10 |
| | 0426 | dumbbell standing overhead press | shoulders / dumbbell | 3 × 10 |
| | 0334 | dumbbell lateral raise | shoulders / dumbbell | 3 × 12 |
| | 0241 | cable triceps pushdown (v-bar) | upper arms / cable | 3 × 12 |
| | 0251 | chest dip | chest / body weight | 3 × 10 |
| **Pull Day**, `pullup` | 2330 | cable lat pulldown full range of motion | back / cable | 4 × 10 |
| | 0027 | barbell bent over row | back / barbell | 4 × 8 |
| | 1323 | cable rope seated row | back / cable | 3 × 10 |
| | 0031 | barbell curl | upper arms / barbell | 3 × 10 |
| | 0313 | dumbbell hammer curl | upper arms / dumbbell | 3 × 12 |
| **Leg Day**, `legs` | 0043 | barbell full squat | upper legs / barbell | 4 × 8 |
| | 0085 | barbell romanian deadlift | upper legs / barbell | 3 × 10 |
| | 0739 | sled 45° leg press (stored with mojibake `sled 45в° leg press`) | upper legs / sled machine | 3 × 12 |
| | 0585 | lever leg extension | upper legs / leverage machine | 3 × 12 |
| | 0586 | lever lying leg curl | upper legs / leverage machine | 3 × 12 |
| | 0605 | lever standing calf raise | lower legs / leverage machine | 4 × 15 |

### 5.2 Demo seed (`buildDemoState()`), demo build only

The seed is deterministic for a given "today" and local time zone. It returns a partial state that is overlaid on
`DEF`:

```js
{ routines: [push, pull, legs], week: {1: push.id, 3: pull.id, 5: legs.id}, dayPlan,
  workouts, bodyweight, exWeights, targetW: 77, effort: 'rir' }
```

**Constants**

```js
PROG = { // exId: [startWeightKg, weeklyIncrement]
  '0025':[60,1.25], '0047':[45,1], '0426':[20,0.5], '0334':[10,0.25], '0241':[25,0.75], '0251':[0,0],
  '2330':[50,1.25], '0027':[50,1], '1323':[45,1], '0031':[30,0.5], '0313':[12,0.3],
  '0043':[70,1.5], '0085':[60,1.25], '0739':[120,3], '0585':[45,1], '0586':[40,1], '0605':[60,1.5] }
WEEKS = 12; BW_FROM = 82.4; BW_TO = 78.3; TARGET_W = 77
DELOAD_WEEK = 5; RPE_UNTIL = 3; UNRATED = 0.1; NEVER_RATED = '0605'
EASY = {'0043','0085','0739','0585','0586'}          // legs trained further from failure
weekTarget(wk) = wk === 5 ? 4.5 : wk < 5 ? 2.8 - wk*0.3 : 2.6 - (wk - 6)*0.26
round(w, step) = Math.round(w / step) * step
clamp(v, lo, hi) = Math.min(hi, Math.max(lo, v))
at(date, h, m) = local-time epoch ms of that date at h:m:00.000
monday(date) = local Monday (d - ((getDay()+6)%7) days) at 12:00:00.000, epoch ms
```

**PRNG (mulberry32).** Dart must reproduce 32-bit unsigned semantics exactly: `>>> 0` means mask with `0xFFFFFFFF`,
and `Math.imul` is a 32-bit signed multiply.

```js
function rng(seed) {                   // seed = 20260723
  let a = seed >>> 0
  return () => {
    a = (a + 0x6d2b79f5) >>> 0
    let t = Math.imul(a ^ (a >>> 15), 1 | a)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}
```

**Algorithm.** The order of the `rnd()` calls matters for determinism.

```
rnd = rng(20260723); [push, pull, legs] = starterRoutines(); byWeekday = {1: push, 3: pull, 5: legs}
nowH = local hour now; today = local today 12:00; start = today - 84 days (setDate)
workouts=[], bodyweight=[], exWeights={}, best={}
for day = start .. today (inclusive, +1 calendar day):
  iso = isoOf(day); weekIdx = floor((day - start) / 7d)   // 0..12
  p = min(1, weekIdx / 12)
  if day is Mon(1) or Thu(4):                              // rnd #1 (only on these days)
     w = 82.4 + (78.3 - 82.4) * p + (rnd() - 0.5) * 0.7
     bodyweight.push({ d: iso, w: round1(w), t: at(day, 7, 30) })
  routine = byWeekday[weekday]; if (!routine) continue
  if (rnd() < 0.09) continue                               // rnd #2: missed session (~9%)
  if (iso === isoOf(today) && nowH < 18) continue          // leave today untrained until 18:00
  prs = []
  blockWk = round((monday(day) - monday(start)) / 7d)
  rir0 = weekTarget(blockWk); scale = blockWk < 3 ? 'rpe' : 'rir'
  entries = routine.ex.map((cfg, exIdx) => {
    [base, inc] = PROG[cfg.id] || [20, 0.5]
    step = base >= 40 ? 2.5 : 1.25
    back = blockWk === 5 ? 0.88 : 1
    w = base ? max(step, round((base + inc*weekIdx) * back, step)) : 0
    rateable = modeOf(cfg) === 'reps' && cfg.id !== '0605'
    sets = []
    for i in 0 .. cfg.sets-1:
      drop = (i === cfg.sets-1 && rnd() < 0.55) ? (rnd() < 0.4 ? 2 : 1) : 0   // rnd only on last set; 2nd rnd only if first true
      s = { w, r: max(4, cfg.reps - drop), done: true }
      rir = clamp(round(rir0 + (cfg.sets-1-i)*0.6 - exIdx*0.12 + (EASY.has(cfg.id) ? 1.2 : 0)
                        - (drop ? 0.5 : 0) + (rnd() - 0.5), 0.5), 0, 6)              // rnd always
      if (rateable && rnd() > 0.1)                                                  // rnd only if rateable
        if scale === 'rpe': s.rpe = clamp(10 - rir, 6, 10) else s.rir = rir
      sets.push(s)
    if (w > (best[cfg.id] || 0)) { best[cfg.id] = w; prs.push(cfg.id) }
    exWeights[cfg.id] = { w: max(w, exWeights[cfg.id]?.w || 0), d: iso }
    return { id: cfg.id, sets, topW: w || null }                  // NOTE: no `target`
  })
  bw = bodyweight.length ? last(bodyweight).w : 82.4
  startMs = at(day, 18, 5 + floor(rnd()*25))                      // rnd
  workout = { id: uid(), d: iso, start: startMs, end: startMs + (46 + floor(rnd()*26)) * 60000,   // rnd
              routineId: routine.id, name: routine.name, bw, entries, prs: weekIdx === 0 ? [] : prs }
  workout.vol = Σ entries Σ sets s.w * s.r
  workouts.push(workout)
// rest-day demo: make sure there is something to start today
dayPlan = {}
if (!byWeekday[today.getDay()] && !workouts.some(w => w.d === isoOf(today))):
  order = [push, pull, legs]; lastName = workouts.length ? last(workouts).name : legs.name
  dayPlan[isoOf(today)] = order[(order.findIndex(r => r.name === lastName) + 1) % 3].id
```

**Example output.** This run used TZ=UTC and today = 2026-09-30, a Wednesday, before 18:00. It produced 33 workouts,
24 weigh-ins and `dayPlan = {}`. The first workout:

```json
{"id":"…","d":"2026-07-08","start":1783535160000,"end":1783539240000,"routineId":"<pull>","name":"Pull Day","bw":82.4,
 "entries":[{"id":"2330","sets":[{"w":50,"r":10,"done":true,"rpe":6},{"w":50,"r":10,"done":true,"rpe":6},
   {"w":50,"r":10,"done":true,"rpe":6.5},{"w":50,"r":10,"done":true,"rpe":7.5}],"topW":50}, …,
   {"id":"0313","sets":[{"w":12.5,"r":12,"done":true,"rpe":6.5},…],"topW":12.5}],
 "prs":[],"vol":6300}
```

Final `exWeights`, abbreviated: `0025→75, 0043→87.5, 0739→152.5, 0241→33.75, 0251→0`.
Body weight runs from `{"d":"2026-07-09","w":82.6}` to `{"d":"2026-09-28","w":78.7}`. A Flutter port with the same
PRNG and date logic should reproduce these numbers for the same "today" and time zone.

### 5.3 Tests: `frontend/src/lib/demoSeed.test.js` (vitest)

`S = buildDemoState()`, and `sum = effortSummary(S, 0)`, where 0 means the whole history. These tests depend on
`effort.js`: `MIN_RATED = 5`, `HARD_RIR = 3`, `rirOf`, `isHardSet(s) = rirOf(s) != null && rirOf(s) <= 3`,
`avgRir`, `effortWeeks`, `effortHistogram` (buckets 0, 1, 2, 3 and 4+) and `displayScale`.

| Test | Assertions |
|---|---|
| rates enough history | `hasEffort(S) === true`; `sum.done > 400`; `sum.rated > MIN_RATED*20 (=100)`; `sum.avg !== null`; `sum.hardPct !== null`; `0.3 < sum.hardPct < 0.9` |
| coverage is partial | `0.7 < sum.rated / sum.done < 0.95` |
| never rates a non-reps set | For every set with `rirOf(s) != null`, `modeOf({...(e.target\|\|{}), id: e.id}) === 'reps'` |
| one exercise never rated | The ids with 0 rated sets are exactly `['0605']`. Every other id has at least 3 sessions where `avgRir(doneSets) != null`. |
| scale labels | `effortOf(S) === 'rir'`; `displayScale(S) === 'rir'`; the count of sets with `rir` is > 0 **and** the count with `rpe` (and no rir) is > 0 |
| weekly trend | `effortWeeks(S,0).length >= 10`; each week has `n >= 2` and `sets >= n`; weeks are sorted ascending by `t` with unique `t` |
| deload visible | The easiest week (max `rir`) minus the mean of the other weeks is > 1. Easiest `rir` minus hardest (min `rir`) is > 1.5. The hardest week's `t` is after the easiest week's `t`. |
| spread across scale | The histogram's Σn equals `sum.rated`. More than 2 buckets have `pct > 0.05`. The maximum `pct` is < 0.6. `hist[0].n + hist[1].n > 0` and `hist[last].n > 0`. |
| hard sets | The count of sets with `isHardSet` equals `sum.hard` and is > 50. Every hard set has `rirOf <= 3`. |
| deterministic | Two builds give the same flattening `w x r / rir / rpe` for every set |

The API tests (`api/test/*.test.js`: config, jobs, payload, validate) all cover the **Coach** and belong to the Coach
spec. There are no tests for `server.js` auth, sync or admin routes.

---

## 6. File formats

### 6.1 Plan share file (`opengym_plan: 1`)

**Purpose.** A friend imports your routines, weekly schedule and the custom exercises those routines use. The file
never carries workouts, weigh-ins or settings, and importing **merges** into the friend's data.

**Export** (`buildPlanBundle(S, name)`):

- Filename: `opengym-plan-YYYY-MM-DD.json`.
- Encoding: `JSON.stringify(bundle, null, 2)`, MIME `application/json`.
- The mobile build hands the file to the OS share sheet.
- `name` is `"<user.name>’s plan"` when signed in, else `''`.
- The export button is disabled unless at least one routine has at least one exercise. The bundle still includes empty
  routines.

```jsonc
{
  "opengym_plan": 1,                  // PLAN_FMT; any truthy value is accepted on import
  "exported": "2026-09-30",           // todayISO()
  "name": "Mario’s plan",
  "week": { "1": "<rid>", "3": "<rid>", "5": "<rid>" },  // keys inserted Mon-first [1..6,0]; only truthy entries
  "routines": [
    { "id": "<rid>", "name": "Push Day", "emoji": "barbell", "prog": "linear" /* only if set */,
      "ex": [ /* cleanEx(e) */ ] }
  ],
  "customEx": [ { "id": "c…", "n": "Nordic curl", "bp": "upper legs", "desc": "…" /* only if truthy */ } ]
                                      // only customs referenced by some routine
}
```

`cleanEx(e)` keeps only the meaningful fields, in this order:

```js
o = { id: e.id, sets: e.sets }
mode = modeOf(e)
cardio: if (e.min != null) o.min; if (e.speed != null) o.speed
time:   o.mode = 'time'; if (e.sec != null) o.sec; if (e.weight) o.weight        // mode ALWAYS written for time
reps:   if (e.reps != null) o.reps; if (e.weight) o.weight                        // mode NOT written for reps
then:   if (e.prog) o.prog; if (e.inc > 0) o.inc; if (e.repsMin != null) o.repsMin; if (e.sg) o.sg
```

**Parse and validate** (`parsePlan(raw)`):

1. `data = typeof raw === 'string' ? JSON.parse(raw) : raw`. A JSON syntax error propagates, and the UI shows
   "Import failed: <message>".
2. If `!data || !data.opengym_plan || !Array.isArray(data.routines)`, throw `t('this isn’t an openGym plan file')`.
3. `customEx = (Array.isArray(data.customEx) ? data.customEx : []).filter(c => c && c.id)`. `known` is the set of
   their ids.
4. Keep only routines where `r && Array.isArray(r.ex)`, and keep all their fields (`...r`). Within each, keep only
   `e` where `!!e && (known.has(e.id) || !!EXIDX[e.id])`. Count the rest as `dropped`. `EXIDX` includes the
   **importing** user's own customs.
5. Return `{ name: (data.name||'').trim(), routines, week: data.week || {}, customEx, dropped, routineCount,
   exerciseCount (Σ ex.length), scheduledDays (count of weekdays 0..6 with a truthy week value) }`.

**Merge** (`mergePlan(s, bundle, { schedule })`, inside `update`):

1. **Customs.** For each bundle custom `c`:
   - If an existing custom `x` has the same name (case-insensitive) and `x.bp === c.bp`, map `c.id → x.id`.
   - Otherwise create `nid = uid()` (no `'c'` prefix), push `{id: nid, n: c.n, bp: c.bp, desc?}`, and map
     `c.id → nid`.
2. **Routines.** Every routine is added as a **new** routine:
   - `{ id: uid(), name: r.name || t('Shared routine'), emoji: r.emoji, prog? (if truthy), ex: r.ex.map(e => ({...e, id: exIdMap[e.id] || e.id})) }`.
   - `ridMap[oldId] = newId`.
   - Existing routines are never modified.
3. **Schedule.** This is optional (the "Use this weekly schedule" switch, default off, shown only when
   `scheduledDays > 0`). When on:
   - Delete `s.week[d]` for all 7 days.
   - For each `[d, oldId]` of `bundle.week`, set `s.week[d] = ridMap[oldId]` when the mapping exists.
   - Days the file leaves empty become rest days, so the file **replaces** the whole week.
4. Return `{routines: bundle.routines.length}`. The UI toasts "Added {n} routines" and navigates to `/plan`.

The Coach's "create plan" proposals use this same format, with extra `why` and `name` fields that are stripped before
merging.

**Printable plan** (`planPrintHTML`, web only, printed from a hidden iframe):

- The header shows "openGym", "Weekly Training Plan", and `"<owner> · <today>"`.
- The **week schedule** lists Mon…Sun, each with the routine name or "Rest".
- Each routine **with at least one exercise** gets a card: name, "{n} exercise(s)", then its exercises. Consecutive
  exercises with the same `sg` render as a "Superset" group.
- Each exercise shows its library name (or "Unknown exercise"), a body-part tag (omitted for cardio), and a scheme
  string:
  - cardio: `"{min||20} min @ {speed||8} km/h"`, prefixed with `"{sets} × "` when sets > 1;
  - time: `"{sets} × m:ss(sec||45)"`;
  - reps: `"{sets} × {reps ?? 10}"`;
  - plus `" · {weight} {unit}"` when the weight is truthy.
- The CSS keeps each exercise, superset and routine unbroken across pages (`break-inside: avoid`).
- The footer reads "Made with openGym · opengym.duarte-santos.ch".

### 6.2 JSON backup (full export and import)

- **Export:** `JSON.stringify(S, null, 2)`, i.e. the **entire** in-memory document including `active`, `_ts`, `coach`
  and the legacy `showRir` flag. The filename is `opengym-backup-YYYY-MM-DD.json`. The mobile build uses the share
  sheet.
- **Import:**
  1. Parse the file.
  2. Require `data.workouts && data.routines` to be truthy (empty arrays pass). Otherwise the UI shows
     "Import failed: not an openGym backup".
  3. Ask for confirmation ("This replaces all current data with the backup file.").
  4. Call `replaceState(Object.assign(clone(DEF), data), push = true)`.

  This is a **full replacement**, not a merge. It restores `active` if the file contains one. `_ts` is re-stamped to
  now, so the import wins on the next pull and pushes within 1.5 s when signed in.
- There is no version field and no migration. Old files are made compatible through the tolerant readers (`modeOf`,
  `effortOf`, `glyphOf`, and the defaults in `DEF`).

### 6.3 Merge of third-party imports (`mergeImport`)

The CSV/XML parser (FitNotes, Strong, Hevy, Apple Health) belongs to the import spec. The merge step is:

```js
if (parsed.kind === 'bodyweight') {
  have = set of existing S.bodyweight[].d
  fresh = parsed.bodyweight.filter(b => !have.has(b.d))          // {d, w (converted to profile unit, 0.1), t}
  S.bodyweight = [...S.bodyweight, ...fresh].sort(by d asc)
  return { added: fresh.length, skipped: parsed.bodyweight.length - fresh.length }
}
have = set of existing S.workouts[].d                            // a DAY with any workout blocks import of that day
fresh = parsed.workouts.filter(w => !have.has(w.d))
used = ids referenced by fresh entries
S.customEx = [...S.customEx, ...parsed.customEx.filter(c => used.has(c.id) && !EXIDX[c.id])]
S.workouts = [...S.workouts, ...fresh].sort(by d asc)
for each fresh workout w, entry e: mx = max(0, ...e.sets.map(s => s.w||0), e.topW||0)
  if (mx > 0 && (!S.exWeights[e.id] || w.d >= S.exWeights[e.id].d)) S.exWeights[e.id] = { w: mx, d: w.d }
return { added, skipped }
```

An imported workout has this shape: `{ id: 'iw'+uid(), d, start, end (>= start; equals start when unknown), routineId: null, name: workoutName || 'Imported', entries: [{ id, sets: [...done:true], topW: max w or null }], prs: [], vol }`.
Imported sets are `{w, r, done:true, rir?|rpe?}` or cardio `{min, speed (km/h), done:true}`. Imported entries have
no `target`.

---

## 7. Behaviour matrix for each build flavour

| | Self-hosted web | Demo (GitHub Pages) | Mobile (Capacitor) |
|---|---|---|---|
| Backend | yes | no | no |
| Auth | passkeys or guest | guest only (seeded) | guest only |
| Persistence | localStorage + server | localStorage | localStorage + `opengym-state.json` file (the file wins when its `_ts` is at least the local one) |
| Reminders | server Web Push (respects `dayPlan`, skips days already trained) | none | local notifications per weekday in `week` |
| Rest-timer background alert | server push | none | none (local only) |
| Coach | if `config.coach.enabled && user` | canned demo provider | hidden |

The Flutter app replaces all three. The natural mapping is the mobile flavour plus an optional Cloudflare account.

---

## 8. Porting notes for Flutter + Cloudflare Workers/D1 + MCP (recommendations)

These notes are not part of the original behaviour. They flag decisions the port has to make.

1. **Keep the document model as the canonical client model.** Everything in §1 is JSON-serialisable and tolerant of
   missing keys. Recommendations for Dart:
   - Model it with nullable fields and preserve unknown keys: keep a `Map<String, dynamic> extra` per object, so data
     written by a newer client or by the MCP survives a round-trip.
   - Reproduce the defaults overlay (`DEF ⊕ loaded`, shallow).
   - Keep "delete the key instead of storing null" for optional set fields. Readers treat an absent key and `null`
     differently in places, for example `s.rir != null`.
2. **Storage in D1.** Two viable designs:
   - **Faithful:** a `user_state(user_id PK, state_json TEXT, ts INTEGER, version INTEGER)` table plus
     `users`, `credentials`, `push_subs`/`devices` and `invites` tables mirroring §3.2. The MCP parses `state_json`.
     This is simple but the MCP has to read the whole document, and D1 rows have a size limit, so check it against the
     5 MiB body cap.
   - **Normalised:** tables `routines`, `routine_exercises`, `week_schedule`, `day_overrides`, `workouts`,
     `workout_entries`, `sets`, `bodyweight`, `ex_weights`, `custom_exercises` and `settings`. The client still syncs
     a document, and the Worker explodes and assembles it. The MCP gets cheap SQL for "progress" queries. Either way,
     **add a server version or ETag** (`If-Match` on PUT, 409 on mismatch, then client pull, merge and retry).
     Otherwise, when Claude writes a plan through MCP, the next push of any open client silently overwrites it
     (§3.6.3 item 2).
3. **MCP write path.** Creating plans means writing `routines`/`week` in exactly the §1.4 and §6.1 shapes.
   - Reusing `mergePlan` semantics (add as new routines, optionally replace the week) is the safest contract, and it
     equals the Coach's "create" proposal.
   - The server must bump the version and `_ts`. Clients must **pull on resume or foreground** (the web app pulls only
     at boot) or subscribe to changes.
   - Validate exercise ids against the library plus the customs, as `parsePlan` does, and drop the unknown ones.
4. **Passkeys on Flutter.**
   - The RP ID must be a domain the app is associated with: iOS `webcredentials:` in the
     apple-app-site-association file, and Android `assetlinks.json` with
     `delegate_permission/common.get_login_creds`.
   - Android origins arrive as `android:apk-key-hash:<b64>`, so the Worker's `expectedOrigin` must accept an **array**
     of origins.
   - A WebAuthn verifier that runs on Workers is needed; `@simplewebauthn/server` works on Workers.
   - The challenge store must move from process memory to KV (TTL 300 s) or a Durable Object.
5. **Session transport.** A mobile client should use a bearer token, keeping the same `uid:exp:sv` HMAC format, in the
   `Authorization` header instead of a SameSite cookie. Keep `sv` for "sign out everywhere". The MCP server needs its
   own OAuth 2.1 flow, which Claude remote MCP requires; map an OAuth grant to the same user id.
6. **Timers and jobs.**
   - Replace the reminder `setInterval(10s)` with a **Cron Trigger** every minute, or better, schedule local
     notifications on the device as the Capacitor build does.
   - Replace the in-memory rest-timer push with a Durable Object alarm, or drop it in favour of local notifications
     scheduled by the app.
   - Web Push (VAPID) becomes FCM/APNs.
   - The presence map becomes KV or a DO with a TTL, or is dropped.
7. **Time zones.** Workout dates `d` are the **device-local** calendar date. MCP queries that group by week should use
   `weekKey` (ISO week, Monday start) with the stored `d`, not UTC.
8. **Unit.** Weights are stored in the profile unit without conversion. The MCP must read `S.unit` and label or convert
   accordingly. Speed is always km/h.

---

## 9. Bugs and quirks in the original

Each of these needs a decision: reproduce it or fix it.

- **B1** The server reminder title uses `routine.emoji`, which is now a glyph **key**. A push therefore reads
  "barbell Push Day today". Only legacy literal emoji render as intended.
- **B2** `POST /api/push/rest-timer`: the clamp makes `sec >= 1`, so the "seconds required" 400 is dead code, and a
  missing `seconds` value schedules a 1-second alert.
- **B3** Plan-file-imported custom exercises lack `tg`, `eq` and `custom`. The Library and exercise-picker search run
  `e.tg.includes(q)` and `e.eq.includes(q)` when the name does not match, which throws a `TypeError` for these records
  as soon as the user types a query. Such exercises also do not show the custom edit/delete UI.
- **B4** The `revoked` invite flag is checked but never set. `revoke` deletes the invite outright.
- **B5** The Settings "Create passkey profile" sheet never sends an invite code. On an invite-only instance it always
  fails with 403, while the Login screen's sheet works.
- **B6** `pullState` re-stamps `_ts` on the pulled copy (§3.6.3 item 1). Offline-dirty and long-open sessions
  overwrite newer server data. This is whole-document LWW by client clock.
- **B7** `userNow` uses `hour12:false`, which some ICU versions render as `24:xx` at midnight. A reminder set to
  `00:xx` may then never match. Use `hourCycle: 'h23'`.
- **B8** Malformed JSON and oversize bodies return 500 instead of 400 or 413.
- **B9** Exercise 0739's name contains mojibake (`45в°`).
- **B10** Deleting a workout does not recompute `exWeights`.
- **B11** A finished workout keeps undone sets (`done:false`) inside `entries[].sets`. Readers must filter by `done`.
- **B12** Loading the starter plan twice duplicates the routines.
- **B13** The mobile reminder ignores `dayPlan` and fires even when the user already trained that day. The server
  reminder does neither.
- **B14** `GET /api/health` leaks the user count publicly.
- **B15** Each registration creates a new user, so there is no way to add a second passkey (for example a new phone
  without synced passkeys) to an existing profile.

---

## 10. Open questions

1. **Sync granularity for the Flutter app and MCP.** Should the port keep the whole-document LWW sync, preferably with
   an ETag, or move to entity-level sync? Either way, the MCP writing plans makes concurrent writers a real case.
2. **Should `active` (the in-progress workout) sync?** Today it is device-local on purpose.
3. **Coach namespace.** Does Claude-over-MCP replace the in-app Coach? If it does, `S.coach` and its snapshots/revert
   can be dropped or reused for MCP-authored changes. Reuse would give a "revert Claude's last plan change" feature
   for free.
4. **Guest mode.** Should the Flutter app keep an offline-only guest mode, and how should guest data be adopted on
   sign-in to an existing profile? Today it silently overwrites in one direction or the other (§3.6.3 item 5).
5. **Admin and invite features.** A single-user Cloudflare deployment probably needs neither. Should they be ported?
6. **Web Push vs native.** Should the rest-timer and reminder alerts become purely local notifications, which needs no
   server?
7. **Unit conversion.** Should the port keep the "label only" behaviour, or store canonical kg for MCP analytics?
8. **Which of the bugs in §9 should be fixed, and which reproduced for data compatibility?** B1, B3 and B6 affect the
   stored data or the MCP contract directly.
