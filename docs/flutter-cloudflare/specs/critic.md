# Completeness critic: corrections and additions to the five porting specs

Scope: `data-model.md`, `engine.md`, `ui.md`, `coach.md`, `library.md` (all in this folder), checked
against the source at `/home/user/opengym` (HEAD `3d545a3`, app code identical to `678bf5b`).
Paths below are relative to `frontend/src/` unless they start with `api/`, `frontend/` or `docs/`.

How to read this file:

- **§1** lists claims I checked against the source (27 of them), with the verdict for each.
- **§2** lists corrections, where a spec says something wrong or incomplete.
- **§3** lists behaviour that no spec covers. Most of it is either a bug to decide on or a rule the
  MCP write path has to respect.
- **§4** lists platform items for Flutter, Workers and D1 that the specs do not mention.
- **§5** lists features the original does **not** have, so nobody ports phantom features.
- **§6** lists consolidated open questions.

The scripts that reproduced the behaviour in §3 are in `scratchpad/critic/` (`reps.mjs`, `sec.mjs`,
`size.mjs`, `keys.mjs`, run with plain `node`, some with a `TZ=` prefix).

---

## 1. Claims verified against the source

| # | Spec § | Claim | Verdict | Source |
|---|---|---|---|---|
| 1 | data-model §1.1 | `DEF` defaults (`restSec 90`, `reminder {on:false,time:'08:00',tz:null}`, `effort:null`, `coach:null`, `gifSize:'full'`) | ✓ | `store/useStore.js:9-23` |
| 2 | data-model §3.1 | `SESSION_DAYS = Math.max(1, +(env‖90)‖90)`: `'0'`/`'abc'` give 90, a negative value gives 1 | ✓ | `api/server.js:29` |
| 3 | data-model §3.3 #16 | rest-timer clamp `max(1,min(3600,round(+seconds‖0)))`, so the 400 branch is dead code | ✓ | `api/server.js` (route `POST /api/push/rest-timer`) |
| 4 | data-model §3.6.2 | `pullState` decision logic, including keeping local `active` and re-stamping `_ts` | ✓ | `store/useStore.js:118-130`, `:47-57` |
| 5 | data-model §3.4 | Server reminder runs every 10 s, needs an exact `hhmm` match, and skips days already trained or overridden to rest | ✓ | `api/server.js` (the `setInterval(…,10000)` block) |
| 6 | data-model §5.2 | Demo `weekTarget` formula; `start = today − 84 d` | ✓ | `lib/demoSeed.js:24-27, 64` |
| 7 | engine §4.8 | Time-mode deload step is hard-coded to 5; linear/greyskull `up` returns no `reps` | ✓ | `lib/progression.js:174, 204-214` |
| 8 | engine §10 | Test counts: progression 53, onerm 21, effort 23, history 40 | ✓ (grep of `it(`/`test(`) | `lib/*.test.js` |
| 9 | engine §7.3 | `loadOf([{0025,4},{0001,3}])` = `{chest:4, triceps:1.6, deltoids:1.6, abs:3, hip-flexors:1.2, lower-back:1.2}` | ✓ | `lib/muscles.js`, EXDB `0001.sm` |
| 10 | engine §1.1 | "`workouts` … chronological by APPEND order, **not re-sorted**" | ✗ incomplete, see C3 | `lib/import-csv.js:519` |
| 11 | ui.md §5.6 | `toggle()` logic: rest after the last superset member, `asked` once per entry, prompt order | ✓ | `views/Workout.jsx:185-210` |
| 12 | ui.md §4.3 | Deleting a weigh-in has no confirmation and removes every entry with that date | ✓ | `sheets.jsx:105` |
| 13 | ui.md §2.8 | `Button` default variant `plain` renders exactly like `ghost` | ✓ | `components/ui.jsx` (`Button`), `index.css:263-264` |
| 14 | ui.md §0 / §9 | "12 locale files … 688 keys in es.js … ~690 source strings" | ✗ see C1 | `frontend/scripts/check-locales.mjs` output |
| 15 | ui.md §3.2 | Today row adds " · rescheduled" whenever `dayPlan[today]` is defined | ✗ partial, see C4 | `views/Home.jsx:99` |
| 16 | ui.md §1.5 | Toast is visible for 2200 ms, one at a time | ✓ | `store/useUI.js:35-39` |
| 17 | ui.md §5.7 | Rest timer is stopped by skip, finish, discard, new workout, work timer or unit complete | ✓, but the work timer is **not** stopped by finish, discard or new workout (G1) | `sheets.jsx:787, 946`; `views/Workout.jsx:241` |
| 18 | coach.md §7.5 | `superset` apply uses tag `uid().slice(0,6)` and runs no `cleanupSg` afterwards | ✓ | `lib/coach.js:291-305` |
| 19 | coach.md §7.5 B5 | `add-routine` gives cardio exercises `reps` and drops `min`/`speed` | ✓ | `lib/coach.js:306-316` |
| 20 | coach.md §8 | Pending proposals expire after 14 days; timeout 5 min; `perProfileDaily` default 10 | ✓ | `api/coach/jobs.js:28-30`, `api/coach/config.js:43` |
| 21 | coach.md §9 | `everyWorkouts` is clamped to 1..20 | ✓ | `api/coach/cadence.js:29` |
| 22 | coach.md §7.7 | The created-plan "Use this weekly schedule" switch defaults **on** (the plan-file import switch defaults off) | ✓ | `views/CoachProposal.jsx:49`; `sheets.jsx:621` |
| 23 | coach.md §3.4 | Server `modeOf` resolves custom exercises through the library only; `canonicalPlan` also consults customs | ✓ | `api/coach/payload.js:51-55, 101-108` |
| 24 | library.md §4.2 | 11 locale files with 781 keys each | ✓ ("11 locales, 781 keys each — in sync.") | `frontend/scripts/check-locales.mjs` |
| 25 | library.md §2.1 / data-model B3 | Search calls `e.tg.includes(ql)` and `e.eq.includes(ql)` with no guard | ✓, and the crash reaches further than B3 says (C6) | `views/Library.jsx:19`, `sheets.jsx:422` |
| 26 | data-model §6.1 | "The UI toasts 'Added {n} routines'" | ✗ minor, see C2 | `sheets.jsx:625` |
| 27 | library.md §9.11 | `mergeImport`: existing dates win, customs are appended only when used, `exWeights` uses newest-date-wins | ✓ | `lib/import-csv.js:507-525` |

All four `api/test/*.test.js` suites are transcribed in coach.md, **except** the first 9 tests of
`api/test/config.test.js`. Those cover provider credential encryption, provider migration and "the
instance job log records outcomes, never contents". Dropping them is fine because the provider
adapters disappear in the MCP design. The **principle** of the last one should carry over to any MCP
audit log: record outcome, class and timing, never payload contents.

---

## 2. Corrections to the specs

**C1 — ui.md §0 and §9: wrong locale counts.**

- There are **11** locale files (`de es fr hi it ko pl pt ru tr zh`); English is the source and has
  no file.
- Each file has **781** keys, not 688 (`node frontend/scripts/check-locales.mjs` prints
  "11 locales, 781 keys each — in sync.").
- 601 distinct literal `t('…')` keys appear in the code. About 180 locale keys are only ever reached
  through dynamic `t(variable)` calls: body parts, equipment, targets, secondary muscles, month and
  day abbreviations, `POLICY_NAME`/`POLICY_DESC`, `MUSCLE_NAME`, `why` templates and glyph group
  names. **Convert every locale dictionary wholesale to ARB or JSON. Do not extract keys from call
  sites**, or the dynamic keys are lost.
- 27 literal keys have no translation in any locale, so they always render in English. Most are
  demo-only. Two show in the normal app: `'Exercise'` (Stats "Exercise progress" SelectRow title,
  `views/Stats.jsx:234`) and `'No exercises yet.'` (print view, `lib/plan-share.js:178`).
- `views/Admin.jsx` and `views/AdminCoach.jsx` use untranslated English literals throughout.

**C2 — data-model §6.1 step 4: plan-import toast.** The key is `t('Added {0} routines to your plan',
bundle.routineCount)` (`sheets.jsx:625`); ui.md §4.14 has it right. The count is the parsed
`routineCount`. On the mobile build, plan export goes through the share sheet and shows **no toast**
(`sheets.jsx:586`).

**C3 — engine §1.1: `workouts` order.**

- Normal finishes append, but `mergeImport` re-sorts the whole array with
  `sort((a,b) => a.d < b.d ? -1 : 1)` (`lib/import-csv.js:519`).
- That comparator never returns 0, so the relative order of two workouts on the same `d` is
  engine-defined (V8's TimSort happens to keep them in place).
- The same comparator sorts `bodyweight` (`sheets.jsx:99`, `lib/import-csv.js:511`); that is harmless
  there because there is at most one entry per date.
- **Port:** use a stable sort by `(d, start)`. This matters because `lastEntryFor`, `sessionsFor`,
  `stallCount` and `e1rmSeries` all read array order (engine Q6).

**C4 — ui.md §3.2: Today-row suffix.** The code is `{todayOvr && routine ? ' · ' + t('rescheduled') : ''}`
(`views/Home.jsx:99`).

- It needs a non-null effective routine, so an override to `'rest'` shows no suffix.
- It is also appended **while a workout is active**, giving "Push — in progress · rescheduled".

**C5 — ui.md §3.9: two small Settings deviations.**

- The "Keep screen awake" row is **hidden** on the mobile build when the Wake Lock API is missing
  (`views/Settings.jsx:126`). It is not shown disabled there.
- The Settings "Create passkey profile" sheet toasts `'Profile created — data moved into it'`
  (`views/Settings.jsx:352`). That is a different key from the Login sheet's `'Profile created — data
  from this device moved into it'`, and its hint is `'Pick a name, then confirm with your device.'`

**C6 — data-model §9 B3: the crash has more sources.** `mergePlan` creates customs as
`{id: uid(), n, bp, desc?}` without `tg`, `eq` or `custom` (`lib/plan-share.js:111`). It is used by
**both** plan-file import **and** Coach "accept created plan" (`lib/coach.js:231`), so every
Coach-invented custom exercise also crashes Library and Picker search
(`views/Library.jsx:19`, `sheets.jsx:422`).

**Port rule for the MCP writer:** always create customs in the app's full shape,
`{id:'c'+uid(), n, bp, desc:'', tg:'', eq:'custom', custom:true}`, and make search null-safe.

**C7 — engine §1.3 and data-model §1.5: which workouts lack `target`.** Legacy workouts (before
v1.2.2), **all imported workouts** and **all demo-seed workouts** have no `target`. For those,
readers fall back to the current plan config (`readSession(entry, fallback)`), so their "hit or miss"
verdict changes whenever the plan changes.

**C8 — data-model §3.1: env table.** It omits `COACH_DISABLED` (kill switch, `api/coach/config.js:25`)
and `COACH_CODEX_HOME` (`api/coach/config.js:20`). Both are Coach-only and go away in the MCP design.

---

## 3. Gaps: behaviour no spec covers

### G1 — The work timer survives finish, discard and starting a new workout (bug)

**Belongs in:** ui.md §5.4, §5.8, §5.11; data-model §2.6.

- `beginWorkout` (`sheets.jsx:787`), `doFinishWorkout` (`sheets.jsx:946`) and the Discard confirm
  (`views/Workout.jsx:241`) all call `stopRest()` only. None of them calls `stopWork()`.
- A running hold countdown (`store/useUI.js:87-113`) therefore keeps going. At 0 it beeps and
  vibrates, then runs `onDone`:

  ```js
  mutEntry(idx, en => { en.sets[i].sec = elapsed })   // update(s => fn(s.active.entries[idx]))
  if (!useStore.getState().S.active.entries[idx].sets[i].done) toggle(idx, i)   // views/Workout.jsx:177-183
  ```

- With `active === null` this throws inside `update`, so nothing is persisted, and the error goes
  uncaught in the interval.
- If a **new** workout has been started in the meantime and has an entry `idx` with set `i`, the old
  timer writes `sec` into the new session and ticks that set done. That is silent data corruption.

**Port:** `stopWork()` in `beginWorkout`, `finishWorkout`/`doFinishWorkout` and discard. Key the
work-timer callback by active workout id plus entry and set index, and ignore it when the active id
no longer matches.

Related, a stale closure. `toggle` inside `onDone` is the closure from the render in which the timer
started (`units`, `unit`, `A`). It computes `unitDone` from **stale** partner entries
(`views/Workout.jsx:195`). In a superset, sets ticked on the partner during the hold are therefore
not seen. The result can be a rest timer where the unit is actually complete, and a missing
top-weight or "whole workout" prompt. **Port:** recompute units and `unitDone` from current state
inside the callback.

### G2 — Calendar opens on the wrong month west of UTC (bug)

**Belongs in:** ui.md §6.3; engine §0 already warns about `new Date('YYYY-MM-DD')` in general.

- `Calendar` does `new Date(start)` with an ISO **date-only** string (`sheets.jsx:718`), which parses
  as **UTC midnight**, and then `setDate(1)`.
- Stats → heatmap → a day with several workouts on the 1st of a month calls `calendarSheet(iso)`
  (`views/Stats.jsx:210`). West of UTC this opens the **previous** month.
- Reproduced: `TZ=America/Puerto_Rico` with `'2026-09-01'` gives August; UTC and Europe/Madrid give
  September (`scratchpad/critic/size.mjs`).

**Port:** parse `DateTime(y, m, 1)` from the string.

### G3 — Changing a rep or hold target in the plan does not change what the next session prefills

**Belongs in:** engine §2.14 and §4.8 (the rule is stated, the consequence is not); coach.md §4.4
(`reps` and `sec` change types). **This is critical for the MCP write path.**

Prefill precedence, from `lib/history.js:158-163` and `lib/progression.js:154-241`:

| Field | Winner, first match | Where the plan value (`cfg.*`) actually counts |
|---|---|---|
| `w`, reps mode | `p.weight` if `kind ∈ {up,hold,deload}` → `exWeights[id].w` if > 0 → last session's set `w` at the same index (when that set had `r > 0`) → `cfg.weight` | only for an exercise with no `exWeights` and no usable last set |
| `r`, reps mode | `p.reps` (bodyweight up/hold, `double`) → last session's `r` (if > 0) → `cfg.reps` | `double` uses `cfg.reps` as the top and `cfg.repsMin` as the bottom |
| `sec`, time mode | `p.sec` (`time` policy: `last.goal + inc`, `last.goal`, or `deloadTo(last.goal,5)`) → last timed `sec` → `cfg.sec` | only when there is no timed history (or `last.goal` is 0) |
| sets count | `cfg.sets`; extra positions copy last session's final done set | always |

Consequence, reproduced in `scratchpad/critic/reps.mjs` (history 60×5×3 hit at target 5; the plan
then changes `reps` to 8):

```
linear    → up 62.5, prefilled 62.5×5 ×3        (new target 8 is not shown anywhere in the session)
greyskull → same
off       → prefilled 60×5
double    → up 62.5, reps 6 (bottom = max(1, 8−2))
after 3 sessions done as prefilled (62.5×5) vs target 8 → linear DELOAD to 57.5
```

- For time: 45 s hit, then the plan changes `sec` to 60. Policy `time` prefills **50** (`last.goal + 5`,
  `lib/progression.js:170`); policy `off` prefills 45. The next session is judged against 60
  (`scratchpad/critic/sec.mjs`).
- The workout screen never shows the target reps or seconds (`ExerciseBlock`,
  `views/Workout.jsx:57-139`). Only the prefilled rows and the `why` line are visible.
- So a Coach or MCP `reps`/`sec` change under `linear`, `greyskull` or `off` can quietly create
  "misses" and, after 3 sessions, a deload.

Decision for the port, pick one:

- (a) Reproduce faithfully, and document in the MCP tool descriptions that `reps`/`sec` changes only
  alter the judging threshold.
- (b) Recommended: when `cfg.reps`/`cfg.sec` differs from the last stored `target.reps`/`target.sec`,
  treat the next session as a new baseline (`kind:'first'`-like), prefill the new target, and show a
  target line in the workout.

### G4 — Mode and body part must agree, or the routine editor rewrites the entry (MCP validation rule)

**Belongs in:** coach.md §6, §13 Q1; engine §2.1.

`ExConfig` (`sheets.jsx:487-509`) decides the form from the **body part**, not from `cfg.mode`:
`cardio = isCardio(ex.id)`, then `mode = cardio ? 'cardio' : modeOf({...c, id})`.

- **Non-cardio exercise with `mode:'cardio'`** (the Coach can emit this through `add-exercise`). The
  workout logs it as min × speed. Opening it in the routine editor shows Reps/Time with neither
  segment matching, reps steppers with empty values, and **Save writes `{mode:'reps', reps:10}`**,
  losing `min`/`speed`.
- **Cardio-body-part exercise with `mode:'reps'` or `'time'`.** The editor shows the cardio form and
  Save writes `{sets, min, speed}` with no `mode`, so it reverts to cardio.
- `buildPlanBundle` omits `mode:'reps'` (`lib/plan-share.js` `cleanEx`). A cardio-body-part exercise
  explicitly set to reps therefore turns back into cardio in a shared plan file.

**Port rule, enforced in the Worker validator:** `mode === 'cardio'` if and only if `bp === 'cardio'`.
Non-cardio exercises take `reps|time`. Always write `mode` explicitly.

### G5 — Policy must be valid for the mode at the routine level too (MCP validation rule)

**Belongs in:** coach.md §13 Q13; engine §4.3.

- `policyFor` does **not** fall back when the value is invalid (`lib/progression.js:66-71`). The
  routine editor only offers the reps policies (`views/RoutineEdit.jsx:51-53`).
- A Coach or MCP `routine-prog: 'time'` therefore turns progression **off** for every reps exercise
  in that routine without an exercise-level `prog`. The editor's SelectRow then shows the raw value
  "time", because no option matches.
- **Rule:** `routine.prog ∈ {off, linear, greyskull, double}`; `ex.prog ∈ POLICIES_FOR[mode]`.

### G6 — Plan files and Coach bundles carry no unit (units kg/lb)

**Belongs in:** data-model §6.1, library.md §9.8, coach.md §4.2.

- `buildPlanBundle` returns `{opengym_plan, exported, name, week, routines, customEx}` with **no
  unit** (`lib/plan-share.js:56`). `weight` and `inc` are raw numbers in the sender's unit.
- Importing a kg plan into an lb profile, or the reverse, silently mislabels every load and step.
- Switching `S.unit` in Settings converts nothing: `bodyweight`, `targetW`, `exWeights`, plan
  `weight`/`inc` and history `w` all keep their numbers (data-model covers this for history, not for
  `inc`).
- Unit-independent constants that the specs mention only in passing:
  - workout weight stepper: 2.5 per tap
  - config weight stepper: 2.5
  - progression-step stepper: 1.25
  - WeightInput buttons: ±0.1, ±0.5, ±1
  - slider step: 0.5

  All are identical for lb profiles. Only `defaultIncrement` (5/10 lb vs 2.5/5 kg) and the
  WeightInput ceiling (300 kg vs 660 lb) depend on the unit.
- Speed is always km/h. The original distance is **not stored**; imports convert km to speed
  (`speed = km / (min/60)`). Reconstruct distance as `min/60 × speed`.

**Port:** add `unit` to the plan and bundle format, and convert on import (or refuse) when it differs.
The MCP should read `S.unit` before writing any `weight`/`inc`.

### G7 — No reliable user time zone on the server

**Belongs in:** data-model §1.2, §3.4; coach.md §9.

- `S.reminder.tz` is `null` by default. It is stamped only when the reminder switch or time is
  touched (`views/Settings.jsx:264, 331, 337`) or at web boot when `reminder.on`
  (`store/useStore.js:189-194`).
- Coach cadence falls back to `'UTC'`, and the Coach payload's `meta.today` is the **server UTC**
  date.
- A Worker or MCP that needs "today", "this week" or "what's planned today" for the user has no
  trustworthy zone. The workout `d` values are device-local dates.

**Port:** add a top-level `tz` (IANA), stamped on every boot or resume. Optionally store
`tzOffsetMin` per workout. Compute "today" in the Worker from that zone.

### G8 — Strings stored as data are in the UI language at write time

**Belongs in:** data-model §1.4, §1.5; coach.md §7.4.

These values are persisted **already translated**:

- `name: t('Freestyle')` for freestyle workouts (`sheets.jsx:785`)
- `t('New routine')` (`views/Plan.jsx:22`, `sheets.jsx:317`)
- `t('Routine')` when a routine name is cleared (`views/RoutineEdit.jsx:45`)
- `t('Shared routine')` (`lib/plan-share.js:119`)
- Coach snapshot labels `t('Before the Coach’s plan')` / `t('Before the Coach’s changes')` and the
  revert summary `t('Reverted the last Coach changes.')` (`lib/coach.js:187, 224, 350`)

These are stored in English:

- `'Imported'` (`lib/import-csv.js:416`)
- the starter routine names (`lib/starter.js:5-9`)

So Claude will see mixed-language names, and matching by name, such as "Freestyle", is unreliable.
Use `routineId === null` to mean freestyle or imported.

### G9 — Every set edit during a workout pushes the whole document

**Belongs in:** data-model §2.2, §8.

- `mutEntry` uses `update(fn, true)` (`views/Workout.jsx:157`). Every keystroke in a set field, every
  tick, add or remove set, the `cur` change on Prev/Next, and the `gifSize` toggle all persist the
  entire state to localStorage and schedule a full `PUT /api/data` 1.5 s later.
- The server then discards the only part that changed (`active`, which it strips).
- A 60-minute session produces dozens of full-document writes.

**Port:**

- Store `active` separately from the synced document, locally only, for example in its own
  file or box.
- Do not schedule a push when only `active` changed.
- With a normalised D1 schema, upsert diffs.

The D1 free tier now **fails** queries once the daily row-write or row-read limit is exceeded
(Cloudflare changelog, 2026-09-01: "D1 enforces free tier daily query limits"). Whole-document push
times exploded rows would hit that limit.

### G10 — Timers are memory-only; a killed app loses them but not the scheduled push

**Belongs in:** ui.md §5.7, §5.8; data-model §2.6.

- `useUI.timer` and `useUI.work` are never persisted (`store/useUI.js:20-24`). `S.active` is.
- After a reload or process kill mid-rest, the countdown is gone. If the user was signed in, the
  server rest-timer push still fires later (`api/server.js`, `scheduleRestTimer`).

**Port with local notifications:** either persist `{kind, endsAt, total, label, activeId,
entryIdx, setIdx}` and restore on resume, or cancel the scheduled rest notification on cold start.
Otherwise the user gets an orphan "Rest over" alert.

### G11 — The workout-day reminder: reproducing the server semantics with local notifications

**Belongs in:** ui.md §1.10 and data-model §3.4 (both recommend local notifications but do not say
how to keep the server rules).

- The server reminder respects `dayPlan` overrides (including `'rest'`) and skips a day that already
  has a workout. The Capacitor build does neither: it schedules weekly repeats per `S.week` weekday
  (`lib/mobile.js:227-249`).
- To keep the **server** semantics on-device, weekly repeats are not enough:
  - Schedule one-shot notifications per date for the next N days (for example 14), computed with
    `effectiveRoutineId(S, iso)`.
  - Reschedule after every persist. `syncReminder` already runs 800 ms after each persist.
  - Cancel today's notification when a workout with `d === today` is finished.
- The title should use the routine **name**, not the glyph key. Server bug B1 renders
  "barbell Push Day today".

### G12 — Media offline behaviour (service worker)

**Belongs in:** ui.md §4.20 and library.md §5 (both say "cache on device" without the policy).

`frontend/public/sw.js`:

| Request | Handling |
|---|---|
| any path containing `/img/` or `/gif/` | **cache-first** in cache `opengym-rt-v1`, filled lazily on first view |
| other same-origin GETs | network-first, cache on success, offline fallback to cache then `index.html` |
| `/api/*` | never cached |

The web app can therefore replay only media it has already shown while offline. Gyms often have poor
signal. **Port:** use a persistent image cache and optionally prefetch the JPG and GIF for every
exercise in `S.routines` after plan changes, within the licence constraints in library.md §5.3.

### G13 — `prs` is a frozen snapshot

**Belongs in:** data-model §1.5, engine §8.1.

- `w.prs` is computed once at finish against the history of that moment (`sheets.jsx:919-936`). It is
  never recomputed when an earlier workout is deleted, when older history is imported, or when a
  custom exercise is removed.
- Imported workouts always have `prs: []` (`lib/import-csv.js:416`).
- If the same exercise appears twice in one session (added mid-workout twice), `prs` can contain the
  id twice.
- For MCP analytics, **recompute PRs from sets** (`bestWeightFor` / e1RM series in `start` order)
  instead of trusting `w.prs`.

### G14 — What the MCP needs to know about session data that does not exist

**Belongs in:** coach.md §14 and data-model §8. These are data-availability facts for the analysis
tools.

- **Sets carry no timestamp.** Only the workout's `start` and `end` exist, so rest intervals and set
  durations cannot be computed. Timed sets carry `sec`.
- **No warm-up flag.** Imported warm-ups become normal done sets (library.md §9.13 #5); in-app sets
  have no type at all.
- **Unchecked sets are kept** (`done:false`) with their prefilled values, which look like real
  numbers. Always filter on `done`.
- **Effort** exists only on reps sets, and only when the profile logs it (often partial).
  Aggregate with `rirOf`, as effort.js does.
- **Session feel.** `rating` (`easy|right|hard`) and `note` are written **only when the Coach was
  enabled and consented** (`sheets.jsx:885, 901`), so almost all histories lack them.
- **Active changes do not reach a running session.** Routine edits (including MCP writes) do not
  affect an **active** session: entries are snapshotted at `beginWorkout`.
- **Rationale is discarded.** Plan config has no field for notes or rationale; a Coach `why` is
  stripped at apply (`lib/coach.js:227-230`). If Claude's reasoning should live next to the plan, add
  a new optional field (for example `r.note`, `e.note`). Tolerant readers ignore it, but
  `cleanEx` in plan-share would drop it; decide whether it travels.

### G15 — Smaller UI facts the specs do not state

- **Numbers in inputs are not localised.** `NumberField` shows the raw JS number ("62.5") even in es,
  while labels use `fmtNum` ("62,5") (`components/ui.jsx`, `NumberField`). It accepts both `,` and
  `.` as input.
- **`why` arguments are not localised either.** `t(...plan.why)` substitutes `String(n)`
  (engine §0 notes this), so an es user reads "2.5 kg" in the progression line but "2,5" in labels.
- **The Home week strip always opens the day-override sheet**, even for a trained day
  (`views/Home.jsx:66`). The Calendar opens workout detail for trained days instead.
- **The plan print view prints body parts in raw English** (`esc(ex.bp)`, `lib/plan-share.js:168`).
  Only the capitalisation is CSS.
- **The TopWeight toast can mislead.** "Tracked — next time starts at {exWeights.w}" is only true
  under policy `off` or `first`. Otherwise the prescription overwrites the weight (G3).
- **The backup-import file input is not reset** after reading (`views/Settings.jsx:42-53`), so picking
  the same file twice does nothing. The CSV import input is reset (`views/Settings.jsx:203`).
- **Admin screens are not specified by any spec.** `views/Admin.jsx` (users list with live presence,
  per-user drill-down, disable, invites) and `views/AdminCoach.jsx` (provider setup) exist. They are
  probably dropped for a single-owner deployment; if kept, they need a spec.

---

## 4. Platform items for Flutter, Workers and D1 that no spec lists

**P1 — Flutter dependencies missing from the scaffold (`app/pubspec.yaml`)** for feature parity:

| Package | Needed for |
|---|---|
| `flutter_local_notifications` + `timezone` + `flutter_timezone` | reminder, rest alert, G7 |
| `file_picker` | JSON backup, plan file, CSV/XML import |
| `share_plus` | export via the share sheet |
| `go_router` | route parity |
| `flutter_svg` or `path_drawing` | icon set, body map |
| `vibration` (or `HapticFeedback`) plus a tone player (`audioplayers` / `flutter_soloud`) | haptics and beeps |
| `collection` | stable `mergeSort` for `rankOf` and C3 |

`wakelock_plus`, `intl`, `shared_preferences`, `path_provider`, `uuid`, `fl_chart` and
`cached_network_image` are already present.

**P2 — Android manifest.**

- `POST_NOTIFICATIONS` (Android 13+, runtime prompt).
- `SCHEDULE_EXACT_ALARM` or `USE_EXACT_ALARM`. The Capacitor build declares `SCHEDULE_EXACT_ALARM`
  (`frontend/android/app/src/main/AndroidManifest.xml`); `docs/MOBILE.md:102-103` says the
  permission is requested only when the reminder is switched on.
- `RECEIVE_BOOT_COMPLETED`, so scheduled notifications survive a reboot.
- `INTERNET`.
- iOS: a notification permission request is needed.

**P3 — D1 sizing for the "faithful" whole-document table.**

- A demo workout serialises to about 1.05 KB. A real one is about 1.3–1.6 KB, because it carries
  `target`.
- 4 sessions a week for 5 years is about 1.1–1.6 MB, plus up to 256 KiB of `coach` namespace.
- Cloudflare documents a per-value/row size cap (about 2 MB; confirm on `d1/platform/limits`, which
  the docs search did not return). A single `state_json` row therefore approaches the cap within the
  horizon the app is meant for.
- Prefer at least splitting `workouts` into their own rows (one row per workout JSON) even in the
  "faithful" design (data-model §8.2).

**P4 — MCP "today" and week computations.** Use the stored `tz` from G7 together with `weekKey`
(ISO week, Monday start, week number not zero-padded; engine §3). Never use Worker UTC.

---

## 5. Features the original does **not** have (do not port phantom behaviour)

Confirmed by reading the views, `sheets.jsx` and the README roadmap (`README.md`, "Roadmap").

**Plan and programming:**

- No per-exercise rest time. `restSec` is global: 60/90/120/150/180.
- No RPE/RIR **targets** in the plan. Effort is logged, never prescribed.
- No percentage or training-max programming (5/3/1), no periodised blocks, no plan start or end
  dates, no deload-week scheduling. The plan is a static `week` plus per-date `dayPlan` overrides;
  deloads come only from the engine.
- Only one starter plan (PPL).
- No "move" operation between dates. Rescheduling means an override on each date (ui.md §6.2).

**Logging:**

- No warm-up or drop-set types, and no set timestamps.
- No per-set or per-exercise notes. There is a session note of up to 300 characters (Coach-gated),
  plus the custom-exercise `desc`.
- No editing of a finished workout, only deletion. No undo for a workout deletion.
- No drag-to-reorder. Up and down buttons only.
- No plate calculator.

**Data:**

- No body measurements other than body weight.
- No unit conversion when switching kg and lb.
- No distance field for cardio.
- No translated exercise **names**. Only instructions are translated, in 10 of 12 languages (not de
  or pt).

**Accounts, sync and hosting:**

- No account deletion endpoint, and no second passkey per profile.
- No periodic or on-focus sync pull.
- No offline media pre-download.

---

## 6. Consolidated open questions (new ones only; the per-spec lists stand)

1. **G3.** Should a plan target change (`reps`/`sec`) reset the progression baseline and prefill the
   new target? This decides the semantics of the MCP `reps`/`sec` change tools.
2. **G4/G5.** Enforce `mode`↔`bp` agreement and `POLICIES_FOR` at every write path (MCP, plan import,
   Coach), or teach the editor to represent mismatches?
3. **G6.** Add `unit` to plan and bundle files and convert on import? Should the MCP always write in
   the profile unit?
4. **G7.** Add a top-level `tz` to the synced document, stamped on every app resume?
5. **G9.** Split `active` out of the synced document entirely, which also solves the MCP concurrency
   window, and switch to diff sync?
6. **G11.** Reminder semantics for local notifications: faithful to the server (respect overrides,
   skip trained days, per-date scheduling) or to the Capacitor build (weekly repeat)?
7. **G14.** Add optional `note` fields on routines and exercises so Claude's plan rationale survives
   apply?
8. **G1/G2.** Fix the work-timer lifetime and the calendar UTC-parse bugs? Recommended: fix both.
   Neither is covered by tests.
