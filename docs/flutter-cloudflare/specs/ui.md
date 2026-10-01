# openGym porting spec — USER-FACING SCREENS AND FLOWS (UI)

Source: `frontend/src/views/*.jsx`, `frontend/src/sheets.jsx`, `frontend/src/components/*.jsx`,
`frontend/src/store/useUI.js`, `frontend/src/App.jsx`, `frontend/src/lib/{nav,wakelock,push,sound,format,glyphs}.js`,
`frontend/src/index.css`. Target: Flutter app (Dart) talking to a Cloudflare Worker + D1.

Sibling specs (do not duplicate; this file references them):
- `data-model.md` — the state document `S`, every field shape, store actions, sync, HTTP API, file formats.
- `engine.md` — pure training logic: `modeOf`, `buildSets`, `nextPrescription`/`applyPrescription`,
  `bestWeightFor`, 1RM, effort statistics, muscle load, streaks. This spec only restates engine
  behaviour where the UI depends on an exact number/string.

Coach screens (`Coach.jsx`, `CoachIntake.jsx`, `CoachProposal.jsx`, `Admin*.jsx`) are out of scope;
their *entry points* on Home/Plan/Settings/Finish are documented here because the port replaces the
built-in Coach with Claude via MCP.

---------------------------------------------------------------------------------------------------

## 0. Conventions

- **`t(s, ...args)`** — every user-visible string is an English source string used as an i18n key;
  `{0}`, `{1}` are positional placeholders (replaced with `replaceAll`, also on the English
  fallback). Strings are quoted verbatim below so the port can reuse the 12 existing locale files
  (`frontend/src/locales/*.js`, 688 keys in `es.js`) — convert them to ARB with the English string
  (or a hash of it) as key. Plural forms are chosen by picking a different source string
  (`n === 1 ? '{0} workout' : '{0} workouts'`), not by ICU plural rules.
- **`S`** = persisted state (see `data-model.md §1`). **`update(fn)`** = clone S, mutate, persist,
  debounce-push to server 1500 ms. All interactions below that "set X" go through `update`.
- **`useUI`** = ephemeral UI store: `sheets[]`, `toastMsg`, `timer` (rest), `work` (work timer).
- **ISO date** `YYYY-MM-DD` in *local* time (`todayISO()`); weekday index `0=Sunday … 6=Saturday`
  (JS `getDay()`); weeks start **Monday** everywhere in the UI.
- "tap" = click/touch. "primary/tinted/plain/ghost/danger" = Button variants (§2.8).
- Colours are named by token (`--acc`, `--label-2` …); hex values in §2.

---------------------------------------------------------------------------------------------------

## 1. App shell, navigation and global overlays

### 1.1 Routes (hash router)

| Route | Screen | Notes |
|---|---|---|
| `/home` | Home | default; `*` redirects here |
| `/plan` | Plan (week schedule + routine list) | |
| `/plan/r/:id` | Routine editor | redirects to `/plan` if the id does not exist |
| `/workout` | StartChooser (no active workout) or ActiveWorkout | |
| `/stats` | Stats | |
| `/history` | History (all workouts) | |
| `/library` | Exercise library | |
| `/settings` | Settings | |
| `/coach`, `/coach/intake`, `/coach/proposal` | Coach (out of scope) | |
| `/admin` | Admin (only if `user.admin`, else redirect `/home`) | out of scope |

Shell behaviour (`App.jsx`):
- On every route change: scroll to top (`window.scrollTo(0,0)`), and the page content re-mounts
  with a fade-in (`opacity 0→1`, `translateY 4px→0`, 220 ms, ease `cubic-bezier(.32,.72,0,1)`).
- Theme/accent applied from `S.theme` (`'light'` else dark) and `S.accent` (unknown → `'lime'`).
  System status-bar colour: light `#f2f2f7`, dark `#000000`.
- Language from `S.lang` (default `'en'`), reloads locale pack.
- **Wake lock** held while `!!S.active && S.keepAwake !== false` (bound to the workout, not the
  route — browsing Stats mid-session keeps the screen on). See §1.8.
- **Auth gate**: `authed = user || isGuest`. If `!ready && !authed` → splash: a single dumbbell icon,
  34 px, colour `--label-3`, centred at 44 % viewport height. If `!authed` → Login screen replaces
  all routes and the tab bar is hidden.
- Global overlays rendered after the page, in z-order: TabBar (z 50) → RestTimer bar (z 60) →
  Modals (z 100) → Toast (z 200).
- Non-component code navigates via `nav(to)` (`lib/nav.js` — a module-level function the shell
  registers with the router's `navigate`). In Flutter: a global `GoRouter`/navigator key.

### 1.2 Tab bar (`components/TabBar.jsx`)

Hidden when not authed. Five buttons, left→right:

| Key | Icon | Label | Action |
|---|---|---|---|
| home | `house` | "Home" | nav `/home` |
| plan | `calendar` | "Plan" | nav `/plan` |
| (start) | `dumbbell` (idle) / `play` (active workout) | "Start" / "Resume" | see below |
| stats | `chart` | "Stats" | nav `/stats` |
| library | `list` | "Exercises" | nav `/library` |

- Active tab = first path segment equals key; additionally `/history` lights **Stats** and
  `/settings` lights **Home**. `/plan/r/:id` lights Plan (first segment `plan`). `/workout` and
  `/coach…` light no tab (the Start button has no "selected" state, only idle/active-workout).
- **Start button logic**:
  ```js
  if (!S.active) {
    const r = effectiveRoutine(S, todayISO())
    if (r && r.ex.length) { startFlow(r.id); return }   // straight into the body-weight check-in
  }
  nav('/workout')                                       // resume, or the StartChooser
  ```
- Visual: fixed bottom, full width, padding `7px 6px (6px+safe-bottom)`, background `--bg-el` at
  72 % opacity (light theme: `rgba(249,249,251,.78)`) with `saturate(180%) blur(24px)`, top hairline
  0.5 px `--sep-op`. Each button: icon 25 px (stroke 1.65) above 10 px/500 label. Inactive label
  colour `--label-3`, inactive icon colour `--label`; active: label+icon `--acc`, stroke 2.
  Start button: raised (`margin-top:-24px`), 52 px circle filled `--acc`, glyph 26 px stroke 2 in
  `--on-acc`, shadow `0 6px 18px -4px` accent@55 %, label in accent, weight 600. When a workout is
  active (`.rec`): disc and label **orange** (`--orange`), glyph **black**, plus an infinite "ping"
  ring: 2 px orange border scaling 1→1.45 while fading .7→0 over 1.9 s. Press: disc scales .93.

### 1.3 Modal stack: bottom sheets and centred dialogs (`components/Modals.jsx`, `useUI.openSheet`)

- `openSheet(render, {kind: 'sheet'|'center' = 'sheet', locked = false})` pushes onto a **stack**
  (`sheets[]`) and returns `{id, close, lock(v)}`. Several sheets can be open at once; newer ones
  render on top (e.g. Exercise picker → Exercise config on top of it → Custom exercise on top).
- `closeSheet(id)` removes one; `closeAll()` clears.
- Each entry renders a backdrop `rgba(0,0,0,.4)` + `blur(2px)`. Tapping the backdrop closes that
  sheet **unless `locked`**.
- **Bottom sheet**: anchored bottom, background `--bg-el` (light theme: `--bg`), top radius 22,
  padding `8px 18px (20px+safe-bottom)`, `max-height: 90vh`, scrollable, slide-up animation
  340 ms. Grab handle 36×5 px, radius 99, colour `--label-4`, margin `6 auto 14`. Title `h3`
  20 px/600, letter-spacing −.021em, margin-bottom 14.
  **Swipe-to-dismiss**: only when the sheet is scrolled to top; drag follows the finger
  (`translateY(delta)`); on release, if `delta > 90 px` and not locked → animate to 110 % and close
  after 180 ms; else spring back (200 ms). A gesture starting on a slider (`[data-nodrag]`) is
  ignored so sliders work inside sheets.
- **Centre dialog** (`kind: 'center'`): centred box `width: min(84vw, 300px)`, background
  `--bg-el` (light: white), radius 16, padding 20, shadow `0 20px 60px -12px rgba(0,0,0,.5)`, "pop"
  animation 280 ms (scale .94→1, fade in). No swipe.
- While any sheet is open the page behind is scroll-locked (restores scroll position after).
- Locked sheets in the app: required body-weight check-in (§5.2) and the Finish summary (§5.11).
- Flutter: implement a custom stack (Overlay entries or a `ValueNotifier<List<SheetEntry>>`
  rendered in a `Stack` above the router) rather than `showModalBottomSheet`, because sheets are
  opened from non-widget code, stack arbitrarily, and some are locked.

### 1.4 Confirm dialog (`confirmSheet(opts)`)

Centre dialog, text-centred: optional `title` (h3, margin-bottom 8), `message` (label-2, line-height
1.5, margin-bottom 18), confirm button (variant `danger` if `danger`, else `primary`; text
`confirmText || "Confirm"`), 8 px gap, ghost dim button `cancelText || "Cancel"`.
Confirm **closes first, then calls `onConfirm()`**. Backdrop tap = cancel. Non-blocking/callback
based.

### 1.5 Toast (`useUI.toast(msg)`, `components/Toast.jsx`)

One message at a time; a new toast replaces the current one and restarts the timer. Visible
**2200 ms**. Pill at bottom centre, `bottom: 96px + safe-bottom`, background `--surface-2` @88 %
with blur(20), radius 99, padding `11px 20px`, 15 px/500, max-width 88vw, centred text, shadow
`0 10px 30px -6px rgba(0,0,0,.5)`. Show/hide: opacity + translateY(6px→0), 220 ms. Non-interactive.

### 1.6 Timer bar (rest countdown / work countdown) — `components/RestTimer.jsx`

Global, floats above the tab bar: `position: fixed; left:12; right:12; bottom: 88px + safe-bottom`,
background `--surface` @97 % + blur(24), radius 16, padding `12px 14px`, shadow
`0 12px 34px -8px rgba(0,0,0,.55)`, slide-up entrance 220 ms. While visible the page gets extra
bottom padding (250 px + safe) so the last rows can scroll clear.

Only one of `work` / `timer` is ever non-null (`startWork` stops the rest timer). `pct = left/total*100`
(bar depletes from full to empty; width transition 1 s linear). `clock(sec) = floor(sec/60) + ':' + pad2(sec%60)`.

**Rest variant** (two rows):
- Row 1: clock (26 px/600, tabular, min-width 66) + progress bar (4 px, track `--surface-3`, fill `--acc`).
- Row 2: `[− 15s]` (sm, icon minus, text "15s") → `addRest(-15)`; `[+ 15s]` → `addRest(15)`;
  `[Skip]` (sm primary, pushed to the far right, min-width 84) → `stopRest()`. Buttons have 11 px
  vertical padding.

**Work variant** (one row, accent-outlined 0.5 px `--acc`): clock in `--acc`; middle column with
the exercise name (12 px, label-2, capitalised, ellipsis) above the bar; `[Cancel]` (sm) →
`stopWork()` (logs nothing); `[✓ Done]` (sm primary, icon check) → `finishWorkEarly()`.

Timer engine: §5.7 and §5.8.

### 1.7 Error boundary

Wraps the page (not the tab bar), re-mounted on route change. On a render error shows: empty-state
block (margin-top 18vh) with `info` icon, bold "Something went wrong", text "This screen could not
be drawn. Your data is safe on this device."; primary button (icon `reset`) "Reload openGym" →
reload app; if a workout is active also danger button (icon `trash`) "Discard the running workout"
→ `S.active = null` then reload. Flutter: `ErrorWidget.builder` / a per-route error boundary widget.

### 1.8 Screen wake lock (`lib/wakelock.js`)

Semantics to reproduce (Flutter: `wakelock_plus`; the OS does not drop it on background the way
browsers do, but keep the *intent* model):
- `wanted` = our intent; `sentinel` = live lock; `pending` = request in flight.
- `requestWakeLock()`: if already wanted → no-op; set wanted, subscribe to visibility changes, `acquire()`.
- `acquire()`: returns early unless `wanted && !sentinel && !pending && supported && document visible`;
  requests the lock; if `wanted` became false while awaiting → release the new lock immediately;
  else store it and clear `sentinel` when the browser releases it. Errors (iOS Low Power Mode)
  are swallowed silently; retried on the next "became visible".
- On becoming visible → `acquire()` again.
- `releaseWakeLock()`: `wanted=false`, unsubscribe, release the held lock.
- `useWakeLock(enabled)`: request while enabled, release on disable/unmount.

Tests (`wakelock.test.js`, vitest; a fake browser that drops the lock on background):
| Test | Setup → expectation |
|---|---|
| wakeLockSupported false | navigator has no `wakeLock` → `false` |
| wakeLockSupported true | fake has it → `true` |
| takes a lock | `requestWakeLock()` → 1 request, lock live |
| no stacking | request twice → still 1 request |
| hidden document | visibility `hidden`, request → 0 requests |
| re-acquire after background | request; background (browser releases, fires event) → live null; foreground → 2 requests, live non-null |
| survives rejection | request rejects → live null; stop rejecting; foreground → live non-null |
| release | request, release → released 1, live null; background+foreground → still 1 request |
| release during in-flight request | request (no await), release, settle → arriving sentinel released (live null); foreground → requests still 1 |

### 1.9 Sounds and haptics (`lib/sound.js`)

`beep(enabled, freq=880, dur=0.18, when=0)`: WebAudio sine oscillator; gain ramps
0.001 → 0.35 in 20 ms then exponentially → 0.001 by `dur`; `when` = delay in seconds. Gated by
`S.sound` (default `true`). `vibrate(pattern)` ignores sound setting.

| Event | Sound (freq Hz, dur s, delay s) | Vibration |
|---|---|---|
| Set checked done (any mode) | (1040, .12, 0) | 30 ms |
| Rest countdown at 3, 2, 1 s left | (660, .10, 0) each second | — |
| Rest over | (880,.15,0) + (880,.15,.25) + (1320,.40,.50) | [200,100,200] + toast "Rest over — next set!" |
| Work countdown at 3, 2, 1 s left | (660, .10, 0) | — |
| Work countdown reaches 0 | same triple as rest over | [200,100,200] |
| Work "Done" early | — | 30 ms |
| Workout finished | (880,.15,0) + (1100,.15,.18) + (1320,.30,.36) | — |

Flutter: generate tones (e.g. `flutter_soloud`/`just_audio` with short generated WAV assets per
frequency) and `HapticFeedback`/`vibration` package for patterns.

### 1.10 Notifications (`lib/push.js`, Settings)

Web build: Web Push via service worker, VAPID key from `GET /api/push/public-key`, subscribe
`POST /api/push/subscribe {subscription}`, unsubscribe `POST /api/push/unsubscribe {endpoint}`,
test `POST /api/push/test`. Uses: (a) **rest-timer alert** if the app is backgrounded — the client
fires `POST /api/push/rest-timer {seconds}` on every `startRest`/`addRest` and
`POST /api/push/rest-timer/cancel` on `stopRest` (signed-in only, fire-and-forget); server pushes
title "Rest over 💪", body "Time for your next set.", tag `rest-timer`; (b) **workout-day
reminder** at `S.reminder.time` in `S.reminder.tz` on days with a planned routine and no logged
workout. Notification tap focuses/open the app.

Mobile (Capacitor) build: reminder = local notifications, ids `100 + weekday`, one per weekday that
has an existing routine in `S.week`, title "Workout day", body "{0} is on the plan today — let’s go!"
(routine name), repeating weekly at `reminder.time`.

**Flutter recommendation**: use `flutter_local_notifications` for both: schedule a one-shot local
notification at `timer.endsAt` (cancel on stop/skip, reschedule on ±15 s) and weekly reminders
like the Capacitor build. No server push needed for these.

---------------------------------------------------------------------------------------------------

## 2. Visual design language

Philosophy (from `index.css` header): iOS-style; one type scale mostly at regular weight (600 for
titles, 400 for content); a **neutral surface ramp** (colour only on the accent and status);
**hairlines, not borders** (0.5 px, inset past the icon rail); motion that acknowledges, not
animates (presses scale ~2 %, 140–220 ms ease-out, nothing bounces). **Dark is the default theme.**
No emoji anywhere in chrome — custom stroke icon set.

### 2.1 Colour tokens

| Token | Dark (default) | Light | Use |
|---|---|---|---|
| `--bg` | `#000000` | `#f2f2f7` | page background |
| `--bg-el` | `#0e0e10` | `#f7f7fa` | sheets, bars (light sheets use `--bg`) |
| `--surface` | `#1c1c1e` | `#ffffff` | cards, list rows, grouped lists |
| `--surface-2` | `#2c2c2e` | `#ececef` | pressed, nested fills, secondary buttons, steppers |
| `--surface-3` | `#3a3a3c` | `#e3e3e8` | controls: segmented track, switch off, slider track |
| `--label` | `#ffffff` | `#000000` | primary text |
| `--label-2` | `rgba(235,235,245,.60)` | `rgba(60,60,67,.60)` | secondary text |
| `--label-3` | `rgba(235,235,245,.32)` | `rgba(60,60,67,.30)` | tertiary / placeholders / dim |
| `--label-4` | `rgba(235,235,245,.18)` | `rgba(60,60,67,.16)` | grab handle, unchecked checkbox ring |
| `--sep` | `rgba(84,84,88,.60)` | `rgba(60,60,67,.29)` | hairlines |
| `--sep-op` | `rgba(84,84,88,.34)` | `rgba(60,60,67,.20)` | hairlines over blur, chart gridlines |
| `--blue` | `#0a84ff` | `#007aff` | |
| `--green` | `#30d158` | `#34c759` | |
| `--red` | `#ff453a` | `#ff3b30` | danger, weight moving away from goal |
| `--orange` | `#ff9f0a` | `#ff9500` | active workout, rescheduled, missed muscles |
| `--yellow` | `#ffd60a` | `#ffcc00` | goal, PR badge, deload, effort/hard sets |
| `--teal` | `#40c8e0` | `#30b0c7` | |
| `--indigo` | `#5e5ce6` | `#5856d6` | |
| `--pink` | `#ff375f` | `#ff2d55` | |
| `--purple` | `#bf5af2` | `#af52de` | |
| `--mint` | `#63e6e2` | `#00c7be` | |
| `--brown` | `#ac8e68` | `#a2845e` | |
| `--grey` | `#8e8e93` | `#8e8e93` | |

### 2.2 The 8 accent colours (`S.accent`, default `'lime'`)

`ACCENTS` in `lib/format.js` (used to paint the Settings swatches — these are the dark-theme hexes):
`{ lime:'#30d158', sky:'#0a84ff', orange:'#ff9f0a', violet:'#bf5af2', pink:'#ff375f', red:'#ff453a', teal:'#40c8e0', gold:'#ffd60a' }`.

The live `--acc` maps to the *theme's* system colour, so the actual hex differs in light mode:

| Key | `--acc` dark | `--acc` light | `--acc-2` (pressed primary) | `--on-acc` dark | `--on-acc` light |
|---|---|---|---|---|---|
| lime | `#30d158` (green) | `#34c759` | `#248a3d` | `#000` | `#000` |
| sky | `#0a84ff` (blue) | `#007aff` | `#0060df` | `#fff` | `#fff` |
| orange | `#ff9f0a` | `#ff9500` | `#c76b00` | `#000` | `#000` |
| violet | `#bf5af2` (purple) | `#af52de` | `#8944ab` | `#fff` | `#fff` |
| pink | `#ff375f` | `#ff2d55` | `#d70036` | `#fff` | `#fff` |
| red | `#ff453a` | `#ff3b30` | `#d70015` | `#fff` | `#fff` |
| teal | `#40c8e0` | `#30b0c7` | `#0071a4` | `#000` | `#000` |
| gold | `#ffd60a` (yellow) | `#ffcc00` | `#b25000` | `#000` | `#000` |

(`--on-acc` = text/icon colour on a filled accent surface; chosen by measured contrast, AA 3:1 for
17 px/600 text.)

Derived: `--acc-soft = accent @16 % over transparent` (tinted buttons, `.tag.acc`, trained calendar
days, highlighted table row); `--acc-line = accent @38 %` (superset card outline).
Status tints use the same formula: danger button bg = red @15 %; PR badge bg = yellow @18 %;
"missed" chip bg = orange @16 %; "Resume" tag bg = orange @16 %.

**Heat ramp** (activity heatmap cells and muscle map), 5 levels, "more accent = more training":
| Level | Heatmap cell (`.hm-c`) | Muscle (`.bm-m`) |
|---|---|---|
| 0 | `--surface-2` | `--bm-base` = `--label` 11 % mixed into `--surface` |
| 1 | accent 30 % into `--surface-2` | accent 32 % into `--bm-base` |
| 2 | accent 55 % into `--surface-2` | accent 56 % into `--bm-base` |
| 3 | accent 78 % into `--surface-2` | accent 78 % into `--bm-base` |
| 4 | `--acc` | `--acc` |
Silhouette (non-muscle parts): `--label` 18 % into `--surface`. (`color-mix(in srgb, A p%, B)` =
linear sRGB interpolation `A*p + B*(1-p)`; Flutter: `Color.lerp(B, A, p)`.)

### 2.3 Typography

Font: system (`-apple-system, SF Pro Text/Display, Segoe UI, Roboto, system-ui`) — in Flutter use
the platform default (SF on iOS, Roboto on Android). **Tabular figures globally**
(`font-variant-numeric: tabular-nums` → `FontFeature.tabularFigures()`). Body default 17 px,
line-height 1.29, letter-spacing −.01em. Letter-spacing values below are em of the font size.

| Role | Size / weight / tracking | Where |
|---|---|---|
| Large title | 34 / 700 / −.028 | screen header `h1` (Home, Plan, Stats…), Login title |
| Sheet title | 20 / 600 / −.021 | `h3` in sheets |
| Big number | 30 / 600 / −.026, lh 1.1 | card `.big` (body weight, today's routine) |
| Stat value | 26 / 600 / −.026 | tiles, `.stat-v`, timer clock |
| Weight readout | 52 / 600 / −.035; unit 19 / 400 label-2 | WeightInput |
| Row title | 17 / 400 / −.012 | grouped list rows (`.lrow-t`) |
| Item title | 16 / 400 / −.009 | list items (`.item .tt`) |
| Button | 17 / 600 (sm 15, xs 13) | |
| Header subtitle | 15 / 400, label-2 | `.hdr .sub` |
| Section caption | 13 / 400, label-2, −.004 | `h4.sec`, card `h2`, section titles/footers (NOT uppercase) |
| Small | 13, lh 1.38 | `.small` |
| Tag | 12 / 500, capitalised | `.tag` |
| Micro caps | 11 / 500, UPPERCASE, +.03…+.045 | week-strip day labels, set table header, "TODAY" |
| Tab label | 10 / 500 | |

Dataset names (exercises, body parts, equipment) arrive lowercase → tags/chips/exercise titles are
**capitalised by display** (CSS `text-transform: capitalize` → Title Case each word). Units and
sentences opt out (`.nocap`).

### 2.4 Geometry and spacing

Radii: `sm 8`, `r 12` (buttons, fields), `lg 16` (media, timer, dialogs), `xl 22` (sheet top),
`card 14` (cards, list items, grouped lists). Page gutter 16 px; content `max-width: 560px`
centred; top padding `safe-top + 8`; bottom padding `128 + safe-bottom` (250 while the timer bar is
visible). Card: `--surface`, radius 14, padding 16, margin-bottom 12. List (`.list`): column with
8 px gap. Hit targets ≥ 44 px. Header (`.hdr`): flex row, items bottom-aligned, gap 12, margin
`8 0 18`.

### 2.5 Motion

Ease `cubic-bezier(.32,.72,0,1)`; fast 140 ms; med 220 ms. Press feedback: buttons scale .975,
icon buttons .92 (+ bg → surface-2), checkboxes/swatches .9, glyph cells .92, tab start disc .93;
list items/rows darken to `--surface-2`. Sheet slide-up 340 ms; centre pop 280 ms; view fade
220 ms; switch knob 220 ms (and stretches 27→31 px while pressed); segmented thumb slides 220 ms.
`prefers-reduced-motion` disables all animation (Flutter: `MediaQuery.disableAnimations`).

### 2.6 Iconography

Hand-drawn **stroke** icons on a 24×24 grid, live area 3…21, stroke width **1.7** (overridable per
context: 2.0–2.6 on chevrons/checks), round caps/joins, `currentColor`, sized in `em` (1em = font
size of context). Fills only for `starFill` and `dot` (and the `info` dot). Full path data in
**Appendix A** — port with `flutter_svg` (build an `SvgPicture.string` per icon with
`stroke="currentColor"` replaced) or `CustomPainter` + `path_parsing`.

Icon names: navigation `house calendar chart magnifier gear`; training `dumbbell barbell figureRun
figureStrength scale flame timer clock`; status `trophy medal target star starFill crown bolt shield
heart rocket sparkles lightbulb`; routine glyphs `arm abs legs pullup kettlebell plate machine bike
swim boxing stretch`; actions `plus minus check checkCircle xmark pencil trash link play pause reset
bell bellSlash chevronRight chevronLeft chevronDown chevronUp arrowUp arrowDown expand minimize`;
objects `person personCircle clipboard list folder globe moon sun key lock download upload wrench
flag chartLine dot history signOut shuffle info`. Aliases: `search=magnifier, settings=gear,
exercises=magnifier, weight=scale, streak=flame, done=check`.

**Routine glyphs** (`lib/glyphs.js`): `Routine.emoji` stores an icon key (legacy: a literal emoji).
`DEFAULT_GLYPH = 'figureStrength'`. Picker groups (4 rows × 5, 5-column grid, cells square radius 13
`--surface`, icon 24 px; current one filled accent / `--on-acc`):
- **Strength**: figureStrength, arm, abs, legs, pullup
- **Equipment**: dumbbell, barbell, kettlebell, plate, machine
- **Cardio**: figureRun, bike, swim, boxing, timer
- **Recovery**: stretch, moon, heart, flame, bolt

`glyphOf(v)`: falsy → default; a known icon name → itself; a legacy emoji → mapped (Appendix B);
else strip U+FE0F/U+200D, take first code point, map; else default.

Icon badge ("lrow-i"): 29×29, radius 7, icon 18 px **white** on the tint colour (default `--acc`).
Larger variants: 34×34 r8 icon 19 (WorkoutRow), 38×38 r9 icon 22 (StartChooser today card).
Neutral badge background `--surface-3` (rest/moon, "new routine", reset rows).

### 2.7 App icon / brand
Name "openGym"; login mark = dumbbell icon 54 px in accent. PWA manifest background/theme colour
`#0c0e12`, portrait. Icons `icon-180.png`, `icon-512.png` (maskable) in `frontend/public/`.

### 2.8 Component library (`components/ui.jsx` + CSS)

**Button** `variant ∈ {plain (default), primary, tinted, danger, ghost}`, `size ∈ {—, sm, xs}`,
optional leading `icon`, `trailingIcon`. Default: full width, padding 14×18, radius 12, 17/600,
gap 7, icon 19 px, bg `--surface-2`, text `--label`.
primary: bg `--acc`, text `--on-acc`, pressed bg `--acc-2`. tinted: bg `--acc-soft`, text `--acc`.
danger: bg red@15 %, text red. ghost/plain: no bg, text `--acc`, weight **400**, pressed bg
surface-2. **Important:** the React `Button` default variant is `'plain'`, which the CSS styles
exactly like ghost. So every `<Button>` in this spec without an explicit variant ("Log", "Goal",
"Add set", "Prev"/"Next", "Add exercise" in the workout, "Build my own plan", "Show more", …)
renders as **accent-coloured text on a transparent background**, not a grey filled button. The
base `.btn` grey fill (`--surface-2`) is never visible in the app.
sm: auto width, padding 8×14, 15 px, radius 8, icon 16. xs: 5×10, 13 px, radius 7.
Disabled: opacity .32, no interaction. `className="dim"` on a ghost button → text `--label-3`.

**Icon button** (`.iconbtn`): 36×36 circle, bg `--surface`, icon 18 px, pressed bg surface-2 +
scale .92. `.on-ss` variant: bg acc-soft, icon accent.

**Card**, **Section/Row (inset grouped list)**: Section = caption title (13 px label-2, padding
`0 4 7`), body (`--surface`, radius 14, clipped), optional footer (13 px label-2, padding `7 4 0`),
margin-bottom 22. Row: min-height 46, padding 11×14, gap 12; optional icon badge (tint via
`iconTint`), title 17 px + optional subtitle 13 px label-2, optional trailing children (a control),
optional `value` (17 px label-2), accessory `chevron` (label colour, 15 px, stroke 2.4) or `check`
(accent). Hairline between rows starts at x=14, or x=55 when both rows have icons. Tappable rows
darken on press. `danger` rows: title red.

**SelectRow** (replaces `<select>`): a Row with the current option's label as `value` + chevron;
tap opens a bottom sheet titled `sheetTitle || title` listing all options as rows (label +
optional subtitle), a check on the current one; tapping an option closes the sheet then calls
`onChange(value)`.

**Segmented**: track `--surface-3` (light: `rgba(118,118,128,.12)`), radius 9, padding 2; a sliding
thumb (`--surface`, light: white, radius 7, soft shadow) under the selected cell; cells equal width,
14 px, selected 500 `--label`, unselected 400 `--label-2`, optional icon 16 px. Variants: `seg-inline`
(in a row: shrink to content, min-width 132, 13 px cells) and `seg-range` (margin-bottom 10, used
for chart ranges). `value` not in options → thumb at index 0.

**Switch**: 51×31, radius 99, off bg `--surface-3`, on bg `--acc`, white 27 px knob with shadow,
translateX 20 when on; disabled opacity .4.

**Check** (round checkbox): 30×30 circle; off: transparent with inset 1.8 px ring `--label-4`;
on: filled `--acc`, check glyph `--on-acc` 16 px stroke 2.6.

**Stepper** (`[−] value [+]`): container bg `--surface-2`, radius 10; buttons 40×44 (set rows:
32×40; three-column rows: 23 or 20 wide), icon 16 stroke 2.2; value = NumberField 17/500 centred.
Optional label above (13 px label-2, centred, ellipsis). Button step:
`onChange(max(0, round((value||0) ± step, 2 decimals)))`.

**NumberField** (text input, numeric keyboard; decimal keyboard if `decimal`): accepts `,` as a
decimal separator. On each keystroke:
```js
s = raw.replace(/,/g,'.').replace(/[^0-9.]/g,'')
i = s.indexOf('.')
if (i !== -1) s = decimal ? s.slice(0,i+1) + s.slice(i+1).replace(/\./g,'') : s.slice(0,i)
n = (s === '' || s === '.') ? (nullable ? null : 0) : Math.max(0, parseFloat(s))
onChange(n)   // while focused the raw draft string (e.g. "33,") stays on screen
```
Select-all on focus; draft dropped on blur (shows the committed value). Negative numbers are
impossible. `nullable` fields (effort) clear to `null` (caller deletes the key).

**Slider** (custom, pointer-driven): height 32; track 6 px `--surface-3` radius 99; fill `--acc`;
white 26 px knob (scales 1.14 while dragging). Value = `min + f*(max-min)` snapped to `step`,
rounded to 3 decimals, clamped. Keyboard arrows ±step. Marked `data-nodrag` (doesn't dismiss sheets).

**Chips** (`.chips` horizontal scroller, gap 7, no scrollbar): chip padding 6×13, radius 99,
bg `--surface`, 14 px, capitalised; selected: bg `--acc`, text `--on-acc`, 500.

**Tag** (`.tag`): inline, bg `--surface-2`, text label-2, radius 6, padding 3×7, 12/500,
capitalised, optional leading icon; `.tag.acc`: acc-soft/accent.

**List item** (`.item`): bg `--surface`, radius 14, padding 10×12, min-height 60, gap 12; leading
thumb/badge; `.grow` column with title (`.tt` 16 px) and subtitle (`.ss` 13 px label-2, margin-top 2);
trailing tag/button/chevron (`.chev` label colour 15 px stroke 2.4).

**Thumb**: 50×50 radius 9, white background, `object-fit: cover`, exercise still image; custom
exercise (no image) → `thumb-x` placeholder: surface-2 bg, dumbbell icon 21 px label-2.
("Create your own exercise" rows use `thumb-x` with a `sparkles` icon.)

**Empty state** (`.empty`): centred, label-2, padding 44×20, 15 px, line-height 1.45; icon 34 px
label-2 above (margin-bottom 12).

**Tiles** (`.tiles`): 2-column grid gap 10; tile `--surface` radius 14 padding 14; label row
(13 px label-2, optional icon 14 px in `--label`, gap 5); value 26/600 (some callers override to
`1.1rem` or 20/22 px).

**Muscle row** (`.mrow`): name (14 px, ellipsis, flex) · bar (74×5, radius 3, track surface-2,
fill accent or override) · value (12 px label-2, right-aligned, min-width 52).
**Muscle chip** (`.mchip`): 12 px, padding 4×9, radius 99, surface-2/label-2; `.miss`: orange@16 %
bg, orange text.

**PR badge** (`.pr`): yellow@18 % bg, yellow text, radius 6, padding 3×8, 12/500, trophy icon 13 px.

**Search field** (`.search`): magnifier 16 px label-3 at left 11, input bg `--surface-2` (light:
`rgba(118,118,128,.12)`), radius 10, left padding 35.

**Text field** (`.input`/`.field`): bg `--surface`, radius 12, padding 13×15, 17 px, placeholder
label-3, focus = inset 2 px accent ring. Textarea min-height 92.

**Note box** (`.exnote`): surface bg, radius 12, padding 13×15, 15 px label-2, `pre-wrap`.

**WeightInput** (shared by body weight, goal, top-weight sheets) — §4.2.

### 2.9 Formatting helpers the UI relies on (exact behaviour)

- `fmtNum(n)` = round to **1 decimal** then locale-format with the UI language's locale
  (`en→en-GB, de→de-DE, es→es-ES, fr→fr-FR, it→it-IT, pt→pt-PT, pl→pl-PL, tr→tr-TR, ru→ru-RU,
  zh→zh-CN, ko→ko-KR, hi→hi-IN`). `60` → "60", `62.25` → "62.3" (en), "62,3" (es).
- `fmtVol(v, unit)` = `fmtNum(v) + ' ' + unit` (never abbreviated).
- `fmtDate(iso, long)`: parse at local noon; long = `{weekday:'short', day:'numeric', month:'short'}`
  (en-GB "Wed 30 Sept"), short = `{day:'numeric', month:'short'}` ("30 Sept").
- `fmtDur(ms)`: `m = floor(ms/60000)`; `m >= 60 ? floor(m/60)+'h '+(m%60)+'m' : m+' min'`.
- `durPart(ms)` = `ms >= 60000 ? [fmtDur(ms)] : []` (imported workouts without a clock omit duration).
- `exCount(n)` = "{0} exercise" / "{0} exercises".
- `fmtSec(sec)` = `m:ss` of `max(0, round(sec))` (junk → "0:00"; 44.6 → "0:45").
- `setLabel(id, set, cfg)`: cardio "`{min} min @ {fmtNum(speed)} km/h`"; time "`{fmtSec(sec)}`" +
  " · {fmtNum(w)}" if w > 0; reps "`{fmtNum(w)}×{r}`" + " (RIR x)" / " (RPE x)" if logged (RIR wins
  if both). Tests in §8.
- `exLine(cfg, unit)`: "`{sets} × {reps}`" / "`{sets} × {fmtSec(sec||45)}`" / "`{sets} × {min||20} min
  @ {speed||8} km/h`", plus " · {weight} {unit}" when weight is truthy (reps/time only).
- `weekKey(iso)` = ISO-8601 week "YYYY-W" (week-year from the Thursday).
- Day names `DAYN = [Sunday…Saturday]`, abbreviations `DAYS = [Su, Mo, Tu, We, Th, Fr, Sa]`,
  `MONTHS` short (Jan…Dec), `MONTHS_LONG` — all passed through `t()`.
- `uid()` = `Date.now().toString(36) + 5 random base36 chars`.

---------------------------------------------------------------------------------------------------

## 3. Screens

### 3.1 Login (`views/Login.jsx`) — shown when neither signed in nor guest

Layout: vertically centred column (min-height 78 vh), text-centred, max-width narrow:
dumbbell icon 54 px accent; "openGym" 34/700 (−.028em), margin `10 0 4`.

**Normal build**:
- Tagline (label-2, margin-bottom 34): "Your workouts. Your weights. Your profile."
- If WebAuthn available: primary (icon `person`) "Sign in with passkey" → `passkeyLogin()` →
  `setUser(u)`, `pullState()`, toast "Welcome back, {0}" (name). Errors: silently ignored if
  `NotAllowedError`/`AbortError` (user cancelled), else toast `e.message || "Sign-in failed"`.
  Then 10 px, button (icon sparkles) "Create new profile" → **Register sheet**.
- Else: card (small, label-2, left-aligned) "This browser doesn't support passkeys — you can still
  use openGym locally on this device."
- Ghost dim "Continue without account" → `setGuest(true)` (enters the app, local-only).
- Footer (dim small, margin-top 26): "Passkeys use {0} — no passwords." (`{0}` = "Face ID / Touch ID"
  on Apple, "fingerprint or face unlock" on Android, else "your fingerprint, face or PIN") + line
  break + "Each profile keeps its own plan, workouts & body weight."

**Register sheet**: title "Create your profile"; hint "Pick a name, then confirm with {0}. The passkey
is saved in your device — no password needed."; name input (placeholder "Your name", maxLength 40,
autofocus after 250 ms); if server config `invite_only`: invite input (placeholder "Invite code",
maxLength 40, forced UPPERCASE, letter-spacing .14em, bold, centred) + hint "This app is
invite-only — enter the code you were given."; primary "Create passkey". Validation (toasts): empty
name → "Enter a name"; invite-only and empty code → "An invite code is required". Success:
`setUser`, close; if the device already has data (`workouts|routines|bodyweight` non-empty) →
`pushState()` + toast "Profile created — data from this device moved into it"; else `pullState()`
+ toast "Welcome, {0}". Errors as above ("Registration failed").

**Demo build**: tagline "Live demo — everything stays in this browser."; primary sparkles "Start the
demo" → guest; explanatory card; link "Self-host it in a minute →".

> Port note: the Cloudflare backend is single-owner. Passkeys may be replaced (open question §12).
> Keep "Continue without account" semantics only if offline-first local mode is desired.

### 3.2 Home (`views/Home.jsx`) — "what to do now + a quick glance"

Top to bottom:

**Header**: h1 "Hi {0}" (user name) or "openGym" (guest); subtitle = today formatted
`{weekday:'long', day:'numeric', month:'long'}` (e.g. "Wednesday 30 September"). Right: icon button
`gear` → `/settings`.

**Week card** (card):
- Row: `[<]` 30×30 icon button (icon 15 px) → `weekOffset -= 1`; centre label (13 px label-2, 500):
  offset 0 → "This week", else "`{monday.date} {monday month short} – {sunday.date} {sunday month short}`";
  `[>]` → `weekOffset += 1`. (Local component state; resets when leaving Home.)
- **Week strip**: 7 equal cells Monday→Sunday of the offset week. Each cell: 2-letter day label
  (`t(DAYS[getDay()])`, 11 px uppercase label-3), date number (17 px; **today** = 31 px filled accent
  circle, `--on-acc`, 600), status dot 5 px:
  - `done` (accent) if any workout has `w.d === iso`;
  - else `ovr` (orange) if `S.dayPlan[iso] !== undefined` **and** effective routine is non-null;
  - else `plan` (label-3) if an effective routine exists (weekly plan);
  - else none.
  Tap a cell → **Day override sheet** for that date (§6.2). Cells darken on press.
- **Today row** (`.today-row`: surface-2 bg, radius 12, padding 12×14, margin-top 12): leading badge
  (29 px): active workout → orange bg + `timer`; today's effective routine → accent bg + routine
  glyph; else surface-3 + `moon`. Label "TODAY" (11 px uppercase label-3) and title (17/500,
  capitalised, ellipsis):
  - active: "{0} — in progress" (active name)
  - routine: routine name, plus " · rescheduled" if `S.dayPlan[today]` is defined
  - else "Rest day"
  Trailing: active → tag "Resume" (orange text on orange@16 %); routine → tag.acc "Start"; else
  `plus` chevron icon.
  Tap: active → nav `/workout`; routine → `startFlow(routine.id)` (§5.1); else → Day override sheet
  for today.

**Coach card** (only if the instance has the Coach and the user consented; polls status while
mounted) — out of scope; in the port this slot can show "Claude created a plan / suggestions to
review" (see §12).

**Welcome card** (only if `S.routines` is empty and no active workout): badge `sparkles` + "Welcome!"
(22 px big); text "Set up your weekly routine to get going — or load a ready-made Push / Pull / Legs
plan."; [Coach only: primary sparkles "Let the Coach build it"]; button (primary if no coach, plain
otherwise; icon sparkles) "Load starter plan (PPL)" → `loadStarterPlan()` (§6.4); button "Build my
own plan" → `/plan`.

**Body weight card**:
- Header row: h2 "Body weight"; right: sm button icon `target` showing `fmtNum(targetW)` (text
  yellow) if a goal is set, else "Goal" → **Goal sheet**; sm button icon `plus` "Log" → **Body
  weight sheet** (non-required).
- With ≥1 entry (`bw` = last entry in date-sorted `S.bodyweight`):
  - big number `fmtNum(bw.w)` + unit (16 px label-2);
  - delta vs the previous entry `bw.w − prev.w`, shown **only if non-zero**: arrow `arrowUp`/
    `arrowDown` (12 px) + `fmtNum(|delta|)`, colour `bwDeltaColor(delta, bw.w)` (§4.3);
  - date `fmtDate(bw.d, true)` right-aligned (dim small);
  - if goal: yellow line with `target` icon: "Goal {target} {unit} · " + (|target − bw| < 0.05 →
    "reached!" | target > bw → "{0} to gain" | else "{0} to lose", with `{0}` = "|diff| unit");
  - LineChart of the **last 30 entries** (`t: b.t || Date(b.d)`), height 130, goal line.
- Empty: "No entries yet — log your weight to start the curve. It's also asked before every workout."

**Streak card** (tappable → **Calendar sheet** for the current month): flame icon (orange) +
"{0} week streak" (22/600) where `{0} = streakWeeks(S)` (consecutive ISO weeks with ≥1 workout,
counting back from the current week; the current week may be empty without breaking it — see
engine.md); line 2 (small label-2): "`{workouts this ISO week}[ / {planned weekdays count}]` this
week · {0} workout(s) total". Planned count = number of weekday keys in `S.week` with a truthy
value (shown only if > 0). Trailing `calendar` icon 20 px.

### 3.3 Plan (`views/Plan.jsx`)

Header: h1 "Plan", subtitle "Your weekly routine". Right: (Coach only) `sparkles` icon button →
`/coach`; `upload` icon button (a11y "Share your plan") → **Plan tools sheet** (§4.13).

**"Week schedule"** section caption, then a list of 7 items in order **Mon, Tue, Wed, Thu, Fri, Sat,
Sun** (`[1,2,3,4,5,6,0]`): full day name; trailing tag: assigned routine → `.tag.acc` with routine
glyph + name; else `.tag` "Rest"; chevron. Tap → **Day assign sheet** (§6.1).

**"Routines"** section: caption + sm tinted button (icon plus) "New" → create
`{id: uid(), name: t('New routine'), emoji: 'figureStrength', ex: []}`, append, navigate to
`/plan/r/{id}`. List of routines in stored order: badge with glyph, name, subtitle
`exCount(ex.length)`, chevron → editor. Empty: empty-state `clipboard` "No routines yet." + line
break + "Create one or load the starter plan." and a button (sparkles) "Load starter plan (Push /
Pull / Legs)".

### 3.4 Routine editor (`views/RoutineEdit.jsx`, route `/plan/r/:id`)

If the routine id does not exist → navigate to `/plan` (e.g. after deletion).

**Header**: back icon button (`chevronLeft`) → `/plan`; name text field (20/600, −.021em) with the
routine name as initial value — **every keystroke** saves `name = value.trim() || t('Routine')`
(the field is uncontrolled, so clearing it shows empty while storing "Routine"); glyph icon button
showing `glyphOf(r.emoji)` → **Glyph picker** → sets `r.emoji = key`.

**Progression row** (grouped list with one SelectRow): icon `chartLine`, title "Progression", value
`r.prog || 'linear'`, options = policies for reps mode `off, linear, greyskull, double` with label
= POLICY_NAME and subtitle = POLICY_DESC:
| key | name | description |
|---|---|---|
| off | "No automatic progression" | "Targets stay where you set them." |
| linear | "Linear progression" | "Hit every rep in every set and the weight goes up. Repeated misses trigger a deload." |
| greyskull | "Greyskull LP" | "Two straight sets plus a final set taken to failure. Beat the target on that set and the weight goes up — double if you double the reps. One failure resets 10 %." |
| double | "Double progression" | "Work up through a rep range at the same weight. Reach the top of the range in every set and the weight goes up, reps back to the bottom." |
| (time) | "Add time" | "Hold every set for the full duration and the target goes up." (per-exercise only) |
Hint below (small dim): "Applies to every exercise in this routine that does not set its own rule."

**Exercise list** (`r.ex` in order). Superset grouping = `supersetUnits(r.ex)` (consecutive entries
sharing a non-empty `sg`). For each entry `e` at index `i` (resolved with `exOr(e.id)` — unknown ids
render as "Unknown exercise" so they stay visible and deletable):
- Above the first member of a multi-member unit: label (12/600 accent, `link` icon 13) "Superset".
- Item; members of a superset get a 3 px accent inset bar on the left edge.
- Thumb; title `ex.n` (capitalised); subtitle `exLine(e, S.unit)`.
- Trailing control column: for `i > 0` a link button (32×28, r8, icon 15) — highlighted (`on-ss`:
  acc-soft bg, accent icon) when `e.sg && r.ex[i-1].sg === e.sg`; a11y "Superset with exercise
  above" → `toggleLink(i)`. Below it two small buttons (28×24, r7, icon 12) `chevronUp` → `move(i,-1)`,
  `chevronDown` → `move(i,+1)`. These buttons stop propagation.
- Tap the item → **Exercise config sheet** (existing config, `onSave: x[i] = {id: x[i].id, sg: x[i].sg, ...cfg}`,
  `onDelete: x.splice(i,1); cleanupSg(x)`, routine `r` for inheritance).

Editing algorithms (all in one `update`):
```js
move(i, dir): j = i+dir; if (j<0 || j>=ex.length) return; swap ex[i], ex[j]; cleanupSg(ex)
toggleLink(i): if (i<1) return
  cur = ex[i], prev = ex[i-1]
  if (cur.sg && prev.sg && cur.sg === prev.sg) delete cur.sg          // unlink from above
  else { gid = prev.sg || ('sg' + uid()); prev.sg = gid; cur.sg = gid } // link to above (joins prev's group)
  cleanupSg(ex)
cleanupSg(ex): for each e with sg: keep only if ex[i-1]?.sg === e.sg || ex[i+1]?.sg === e.sg, else delete e.sg
```
Consequences to preserve: unlinking the middle of a 3-chain A-B-C dissolves the whole chain (A and C
lose their now-partnerless `sg`); linking an item that was grouped with the one below moves it into
the upper group and the lower partner is cleaned up if left alone; moving an item out of a group
breaks it the same way.

Empty list: empty-state `dumbbell` "No exercises yet — add your first one."

**Coverage card** (only if ≥1 exercise): h2 "What this session hits"; BodyMap of `loadOfRoutine(r)`
(planned set counts × muscle weights, engine.md) in the user's body style; chips of the **top 6**
worked muscles (display names: Traps, Shoulders, Chest, Upper back, Serratus, Biceps, Triceps,
Forearms, Abs, Obliques, Lower back, Glutes, Quads, Hamstrings, Adductors, Hip flexors, Calves, Shins).

Hint (small dim, `link` icon 13): "Tap the link button on an exercise to superset it with the one
above — you’ll do them back-to-back."

Primary (icon plus) "Add exercise" → **Exercise picker**; on pick → **Exercise config** (new) →
on save `ex.push({id, ...cfg})`. The picker stays open underneath (multi-add; §4.8).

Danger "Delete routine" → confirm {title "Delete routine?", message "“{0}” and its exercises will be
removed.", confirm "Delete", danger} → remove the routine, delete every `S.week[k] === id` and every
`S.dayPlan[k] === id`, navigate `/plan`. (Workouts that referenced it keep their `routineId`;
their rows fall back to the default glyph.)

### 3.5 Workout (`views/Workout.jsx`, route `/workout`)

If `S.active` → **ActiveWorkout** (§5). Else **StartChooser**:
- Header: h1 "Start workout"; subtitle "`{today's full day name}` — " + ("today is {0}" (routine
  name) | "rest day, but no one’s stopping you").
- If today's effective routine exists: card with accent border: h2 (accent) "Today's plan" + (" · " +
  "rescheduled" if a day override exists); row: big name + `exCount`; glyph badge 38×38; primary
  (icon play) "Start {0}" → `startFlow(todayR.id)`.
- If other routines exist: caption "Other routines" + list (all routines except today's): glyph
  badge, name, count, tag.acc "Start"; tap → `startFlow(r.id)`.
- Button (icon shuffle) "Freestyle workout (pick as you go)" → `startFlow(null)`.
- If no routines at all: primary "Build a plan first" → `/plan`.
(A routine with 0 exercises can be started from here; it yields an empty named session.)

### 3.6 Stats (`views/Stats.jsx`) — analytics hub

Header: h1 "Stats", subtitle "Progress & history"; right: `history` icon button → `/history`.

**Tiles** (2×2): 
| Label (icon) | Value |
|---|---|
| "Workouts" (`dumbbell`) | `S.workouts.length` |
| "This month" (`calendar`) | workouts whose `d` starts with the current `YYYY-MM` |
| "Week streak" (`flame`) | `streakWeeks(S)` |
| "Weight 30d" (`scale`) | entries with `t > now − 30 d`; if ≥2: `last.w − first.w` shown as "+x unit"/"−x unit" (22 px), colour `bwDeltaColor(delta, lastBW.w || 0)`; else "—" |

**Activity card**: h2 "Activity — last 12 months" + dim " · by time trained"; **Heatmap** (§7.2).
Tap a day with workouts: exactly 1 → **Workout detail sheet**; >1 → **Calendar sheet** opened at
that month.

**Muscle balance card** (only if any workouts):
- h2 "Muscle balance" + dim " · " + ("by hard sets" | "by sets worked"). Right: if the window has
  any done set with RIR ≤ 3 (`isHardSet`, RPE converted as `10 − rpe`), sm button (icon `flame`)
  "Hard" (yellow text, when on) / "All" → toggles hard mode and clears selection.
- Segmented (seg-range): "Week" (value 7 = **current ISO week**, not rolling 7 days) | "30d" | "90d"
  (rolling by `w.start || Date(w.d)` > now − days) | "All" (0). Default **Week**. Changing clears
  selection.
- If no workouts in window: "No workouts in this period yet."
- Else: tappable BodyMap (`loadOfWorkouts(inWin, hard ? isHardSet : null)`), tap a muscle toggles
  selection (selected muscle gets a 7-unit `--label` stroke); legend "Less [l0..l4] More".
  - With selection: one `mrow` (hairline above): bold muscle name; value "{0} sets" (load rounded to
    0.1) or "no hard sets" (hard mode) / "not trained".
  - Without: top **4** worked muscles as mrows: name, bar width `round(load/max*100)%` (yellow in
    hard mode), "{0} sets".
  - If any muscles have zero load: caption ("No hard sets in this period" | "Not trained in this
    period") + orange `mchip.miss` chips of all missed muscles in head-to-toe order.
  - If none missed and some worked: "Every muscle group got at least one hard set in this period." |
    "Every muscle group got some work in this period."

**Effort card** (only if any done set carries RIR/RPE anywhere in history):
- h2 "Effort" + dim " · how close to failure". Segmented 30d | 90d | 1Y (365) | All; default **90d**.
- Display scale `kind` = profile's effort setting if rir/rpe, else whichever scale the history has
  more of (tie → rir). `hd` = "RIR"/"RPE". `toScale(kind, rir)` = rir or `10 − rir`, 1 decimal.
- If no rated set in window: "No rated sets in this period."
- Else:
  - Left stat: avg effort (`toScale`) + " " + hd, or "—" if fewer than **5** rated sets; caption
    "average effort". Right stat (yellow): `round(hardPct*100)%` or "—"; caption "at {hd}
    {toScale(3)} or harder" (i.e. "at RIR 3 or harder" / "at RPE 7 or harder").
  - "{rated} of {done} finished sets rated".
  - If the profile's effort setting is off: yellow "Effort per set is switched off — turn it on in
    Settings to keep rating."
  - If ≥2 weekly points: caption "Week by week" + LineChart (h 140, yellow, unit hd, y inverted for
    RIR so harder is up; tooltip note "{0} sets" = week's done-set count). Weeks with <2 rated sets
    are dropped.
  - Caption "Where the sets land" + 5 histogram mrows (bins by `floor(rir)` clamped 0..4):
    label "{hd} {bin}" with bin text RIR "0","1","2","3","4+" / RPE "10","9","8","7","≤ 6"; bar
    width relative to the largest bin (min 1); colour yellow for bins 0–3, `--label-3` for 4+;
    value "`n · pct%`" or "—" when n = 0.
  - Footnote: "Most working sets belong close to failure without living there — half at the floor
    and half at the top average out to a healthy-looking middle."

**Body weight card**: header like Home's (Goal + Log buttons); segmented 1M (30) | 3M (90) | 1Y
(365) | All (0), default **3M**; LineChart (h 160, goal line) of entries with `t > now − range` (or
all). Empty → "No data yet" (from LineChart).

**Exercise progress card**: h2 "Exercise progress".
- Exercise list = unique ids across all workouts that still resolve in the exercise index (built-in
  or existing custom), sorted by name. If none: "Finish your first workout to see progress curves here."
- SelectRow "Exercise" (sheet title "Exercise progress"); default = first in list; selection kept in
  local state.
- `curMode` = mode of the most recent workout entry of that exercise (`modeOf({...target, id})`).
  Metric per set: cardio → `speed`; time → `sec`; reps → `w`. Unit: "km/h" / "s" / profile unit.
- Points: per workout containing the exercise, `y = max(0, metric of done sets…, reps-mode: topW||0)`;
  skipped if 0; `t = w.start`. `exBest` = max y.
- Est. 1RM series (reps sets only, Epley, ≤12 reps; engine.md): shown as option if non-empty.
- Effort option shown if ≥3 sessions have an average rated effort.
- Segmented options: "Top set" (always), "Est. 1RM" (if any), "Effort" (if ≥3 rated sessions);
  segmented only rendered if >1 option. Default "Top set".
- Chart (h 150): Effort → yellow, inverted for RIR, unit hd; else blue (`--blue`), unit per mode;
  on "Top set", each point with a rated session carries a **marker dot** of strength
  `m = 1 − clamp(avgRir, 0, 4)/4` (fuller dot = less left in tank) and tooltip note "{hd} {value}".
- Under the chart: last 5 sessions (newest first), each row: `fmtDate(d, true)` (label-2) and the
  done sets' `setLabel`s joined by two spaces; rows separated by hairlines.
- Caption: "Average effort per workout" | "Estimated 1RM per workout" | "Top speed per workout" |
  "Longest hold per workout" | "Best set weight per workout"; plus (not on effort) " · Best: "
  bold-accent `fmtNum(best) unit` (1RM: best.est + profile unit).
- 1RM extra line: "Best estimate from {w unit × r} on {date} — an estimate, not a tested max."
- Top-set with effort available: "A fuller dot means less left in the tank — the same weight at a
  lower {hd} is progress the line alone does not show."

**Recent workouts** (only if any): caption "Recent workouts"; sm ghost button "All {n}" with trailing
chevron → `/history`; list of the last **6** workouts newest first as **WorkoutRow** (§4.17) →
Workout detail sheet.

### 3.7 History (`views/History.jsx`)

Header: back icon (`chevronLeft`) → `/stats`; h1 "History", subtitle "{0} workouts" (count).
List of all workouts newest-first (reverse of stored order — stored order is append order) as
WorkoutRow → Workout detail sheet. Empty: `history` icon "No workouts yet."

### 3.8 Exercise library (`views/Library.jsx`, tab "Exercises")

Header: h1 "Exercises", subtitle "{0} exercises with animations" (`EXDB.length` = 1324 built-ins).
- Search field (placeholder "Search…"); typing resets paging to 40.
- Body-part chips: "All" (nocap) + every body part, alphabetical: back, cardio, chest, lower arms,
  lower legs, neck, shoulders, upper arms, upper legs, waist (labels translated, capitalised). Tap
  sets body part, **clears equipment**, resets paging.
- Equipment chips (only if the current base list has >1 equipment value): "Any equipment" + values
  ordered by frequency in the base list desc, ties alphabetical. If the selected equipment is no
  longer present in the base list it is treated as "any" (never a dead end).
- Filter: `allExercises(S)` = custom exercises first, then built-ins; body part equal; query `ql`
  (lowercased, trimmed) matches if `name.toLowerCase()` includes it, or `tg` includes, or `eq`
  includes, or `desc.toLowerCase()` includes.
- List: first row always "Create your own exercise" / "name + body part, no animation" (sparkles
  thumb, plus) → **Custom exercise sheet** prefilled with the current query; on create → opens the
  new exercise's detail sheet. Then up to `shown` (40) exercises: thumb, name (capitalised),
  subtitle "`{target or body part} · {equipment}`" (translated), tag.acc with best weight
  (`bestWeightFor` > 0, number only), sm tinted button (plus) "Plan" → **Add to routine sheet**
  (stops propagation). Tap row → **Exercise detail sheet**.
- No results: `magnifier` "No match". If more results than shown: "Show more" → +40.

### 3.9 Settings (`views/Settings.jsx`)

Header: back icon → `/home`; h1 "Settings".

**Account section** (title varies):
- Signed in: row `personCircle` (grey) with user name, subtitle "Signed in with passkey — data syncs
  to this profile."; if admin: `wrench` (indigo) "Admin dashboard" → `/admin`; `signOut` (red,
  danger) "Sign out" → confirm {"Sign out?", "Your data is synced to your profile first, then cleared
  from this device.", "Sign out", danger} → `signOut()` + `/home`; `shield` (red, danger) "Sign out
  everywhere" / "Ends this profile’s sessions on all your devices." → confirm {"Sign out everywhere?",
  "Signs this profile out on every device, including this one. Your passkeys keep working — sign in
  with them again anytime.", "Sign out everywhere", danger} → success: `/home` + toast "Signed out on
  all devices"; failure: toast "Could not sign out everywhere — you are still signed in." (nothing
  local cleared).
- Guest with WebAuthn: `sparkles` "Create passkey profile" / "Keeps your data safe and separate per
  person." (chevron) → inline register sheet (name only); `person` (blue) "Sign in with passkey".
  Footer paragraph "Guest mode — data lives only in this browser."
- Mobile build: title "Your data": `lock` "All data stays on this phone" / "No account, no cloud —
  back it up anytime with Export below."; `rocket` "Self-host openGym" → repo URL.
- Demo build: "You’re in the demo", "Reset demo data" (confirm → reseed, `/home`, toast "Demo data
  reset"), "Self-host openGym".

**General** (footer "Note: switching units only changes the label — logged numbers are not converted."):
- SelectRow `globe` (blue) "Language": English, Deutsch, Español, Français, Italiano, Português,
  Polski, Türkçe, Русский, 中文, 한국어, हिन्दी; languages without an instruction pack (de, pt) carry
  subtitle "Exercise instructions aren't available in this language yet — they stay in English."
- Row `scale` (teal) "Weight unit" + inline segmented kg | lb → `S.unit`.

**During a workout** (footer, if wake lock supported: "The screen stays on while a workout is
running, so you don’t have to unlock your phone between sets."):
- SelectRow `timer` (orange) "Rest timer": 60s, 90s, 120s, 150s, 180s → `S.restSec` (default 90).
- Row `sun` (yellow) "Keep screen awake" + Switch (`checked = supported && S.keepAwake !== false`,
  disabled if unsupported with subtitle "Not supported in this browser.") → `S.keepAwake`.
- Row `bell` (pink) "Sounds" + Switch → `S.sound`.
- Row `target` (purple) "Effort per set": an (i) help button (opens **Effort help sheet**) then inline
  segmented Off | RIR | RPE (values `none|rir|rpe`) → `S.effort = v; delete S.showRir`.

**Coach** (only if available): row sparkles "Open the Coach"/"Meet the Coach" → `/coach` (out of scope).

**Notifications** (signed in, or mobile):
- Web: if push unsupported → row `bellSlash` "Not supported in this browser.". Else Switch row `bell`
  (red) "Push notifications" / "Rest-timer alerts, even if openGym is closed." (initial state = has a
  push subscription; busy-disabled while toggling; toasts "Notifications on"/"Notifications off"/
  error message/"Could not change notification settings"). When on: `calendar` (orange) "Workout day
  reminder" switch → `S.reminder = {...reminder, on: !on, tz: localTZ()}`; when both on: `clock`
  (purple) "Reminder time" native time input (HH:MM) → `S.reminder.time` (+ tz). Footer (on + reminder
  on): "Only sent on days you have a routine planned and haven't logged a workout yet." + " Timezone:
  {0} (auto-detected, updates if you travel)." Below the section: sm button (bell) "Send test
  notification" → toast "Test sent — should arrive any second" / error.
- Mobile: "Workout day reminder" switch (asks OS permission when turning on; failure toast "Could not
  change notification settings") and "Reminder time"; footer "Reminds you at this time on days that
  have a routine planned."

**Appearance** (footer "synced with your profile" on self-hosted builds):
- Row `moon` (indigo) "Theme" + segmented [moon "Dark" | sun "Light"] → `S.theme`.
- Row `figureStrength` (teal) "Body diagram" + segmented Male | Female → `S.body` (only affects the
  muscle-map drawing).
- "Accent color": 8 swatches (32 px circles painted with the `ACCENTS` hexes, gap 12, wrap); the
  selected one gets a 2 px `--label` ring at 4 px offset → `S.accent = key`.

**Data**:
- `sparkles` "Load starter plan (PPL)" → §6.4.
- `shuffle` (teal) "Import from another app" / "FitNotes, Strong, Hevy — or body weight from Apple
  Health" → file picker (`.csv,.xml`) → parse → **Import summary sheet** (§4.18). Parse errors
  (toasts): unreadable "Could not read that file"; `error:'empty'` "That file is empty"; other error
  "That file's columns aren't recognised — see the docs for supported apps."; nothing importable
  "Nothing to import from that file".
- `upload` (blue) "Import backup" → file picker (`.json`) → must parse and have truthy `workouts` and
  `routines`, else toast "Import failed: {0}" (message, e.g. "not an openGym backup") → confirm
  {"Import backup?", "This replaces all current data with the backup file.", "Import", danger} →
  replace whole state with `DEF` overlaid by the file, push to server, toast "Backup imported".
- `download` (blue) "Export backup (JSON)" → file `opengym-backup-{YYYY-MM-DD}.json`, pretty-printed
  (2 spaces) whole `S` → toast "Backup exported" (mobile: OS share sheet).
- `trash` (red, danger) "Reset everything" → confirm {"Reset everything?", "Deletes your plan,
  workouts and body weight on this device. This cannot be undone.", "Delete everything", danger} →
  (signed in: also tell the server to forget Coach data) replace state with `DEF` (push), `/home`,
  toast "All data reset".

**Tip** (web only): `lightbulb` (yellow) "In Chrome: ⋮ menu → Add to Home screen" (Android) / "In
Safari: Share → Add to Home Screen", subtitle "to install openGym as a full-screen app." + ("Your
data syncs with your profile — sign in anywhere to see it." | "Guest data stays on this device —
export a backup now and then!").

Footer credits: "openGym · free & open source (AGPL v3)", links "source code" and "exercise data:
hasaneyldrm/exercises-dataset (CC)".

**Effort help sheet**: title "Effort per set"; text "How hard a set was, logged next to weight and
reps. Two scales for the same judgement, counted from opposite ends."; table (surface card, header
row surface-2 with 11 px uppercase label-3 "RIR | RPE | How it felt"; numbers 17/600 in 36 px
columns):
| RIR | RPE | How it felt |
|---|---|---|
| 0 | 10 | Nothing left — went to failure |
| 1 | 9 | One more rep in the tank |
| **2** | **8** | **Two more reps** ← highlighted row (acc-soft bg, accent numbers) |
| 3 | 7 | Three more reps |
| 4+ | ≤6 | Easy — warm-up territory |
Then dim text: "RIR counts the reps you left; RPE reads the same effort off a 10-point scale — so
RPE ≈ 10 − RIR. Pick the one you already think in." and "The highlighted row is where most working
sets land. Sets you have already logged keep their own scale, and nothing else reads the value —
progression and estimated 1RM are unaffected."

---------------------------------------------------------------------------------------------------

## 4. Sheet catalogue (`sheets.jsx`)

All are bottom sheets unless marked (center).

### 4.1 `confirmSheet` — §1.4 (center).

### 4.2 WeightInput (component used by 4.3, 4.4, 4.16)
```
W_LO = 1;  W_HI = unit === 'lb' ? 660 : 300
clamp(x) = max(W_LO, min(W_HI, round((x||0)*10)/10))
```
- Readout row (gap 18, margin `14 0 6`): [−] 46 px circle (surface bg, icon 19) → `clamp(v − 0.1)`;
  big readout `fmtNum(value)` 52/600 + " unit" (19 px label-2), min-width 158; [+] → `clamp(v + 0.1)`.
- Chip row centred: "−1", "−0.5", "+0.5", "+1" → `clamp(v ± …)`.
- Slider min 1, max W_HI, step 0.5; displayed value clamped into range; drag → `clamp(v)`.
- Note: an initial value of 0 is displayed as "0" but any control moves it to ≥ 1.

### 4.3 Body weight sheet `bwSheet({required, onDone})` (locked when `required`)
- Initial value: last entry's weight, else **70** (regardless of unit).
- Title: required → "Quick check-in"; else "Log body weight". Subtitle: required → "Slide or tap to
  set your weight — tracked before every workout so your curve stays honest."; else "Today, {long
  date}".
- WeightInput.
- Primary: required → "Save & start workout"; else "Save". Save: `n = round1(v)`; if `!n || n <= 0`
  → toast "Enter a valid weight"; else upsert **today's** entry (`{d: today, w: n, t: Date.now()}`;
  existing same-date entry is overwritten in place), sort entries by `d` ascending; close; then
  `onDone(n)` if given else toast "Weight saved".
- Required extras: ghost dim "Start without weighing in" → close, `onDone(null)`; ghost dim (icon
  reset) "Choose a different workout" → close, navigate `/workout` (does **not** start anything).
- Non-required extras: caption "Recent weigh-ins" + the last 3 entries (newest first): date long
  (label-2), bold "w unit", red trash icon button (32×30) → delete **all entries with that date**
  immediately (no confirm).
- Because it is locked, the required sheet cannot be dismissed by backdrop/swipe; the only exits are
  its three buttons.

### 4.4 Goal sheet `goalSheet()`
Title "Target weight"; text "Your goal is drawn as a line through the weight charts, and
gains/losses are colored by whether they move toward it."; WeightInput initial `targetW || last bw
|| 70`; primary "Save goal" → `n = round1(v)`, invalid → "Enter a valid weight"; `S.targetW = n`;
close; toast "Goal set: {n unit}" + (if any bw: " ({0} to go)" with `fmtNum(|n − bw|)`). If a goal
exists: danger "Remove goal" → `S.targetW = null`, toast "Goal removed".

`bwDeltaColor(delta, currentW)`: `!delta` → `--label-2`; no goal → `--label`; else
`up = targetW > currentW`; `(delta > 0) === up` → `--acc` (towards goal) else `--red`.

### 4.5 Exercise detail `exerciseDetailSheet(ex)`
- Title = name (capitalised). Media (autoplay GIF; §4.20).
- Tags: body part (acc), target (icon `target`) if any, equipment (icon `dumbbell`), up to 3
  secondary muscles.
- Description box if `desc`.
- If best weight > 0: trophy (yellow) "Best: " bold-accent "{best unit}" + (if logged before)
  " · last {short date}: {set labels joined ', '}".
- Primary (plus) "Add to my plan" → Add-to-routine sheet (stacks on top).
- Custom exercise only: row of "Edit" (pencil; closes, opens custom sheet in edit mode) and danger
  "Delete" (trash; `deleteCustomEx(ex, close)`).
- **Estimated 1RM** section (non-cardio exercises): caption "Estimated 1RM"; if history has a best
  estimate: "From your log: " bold-accent "{est unit}" + dim " · {w unit} × {r} on {date}"; two
  steppers "Weight (unit)" step 2.5 (init best.w or `exWeights.w` or 20) and "Reps" step 1 int
  (init best.r or 5); row "Estimate" → bold accent 20 px `est unit` or "—"; hint: est null → "Enter
  a weight and 1–{12} reps — beyond that an estimate is guesswork." else "Epley formula — a
  calculation from one set, not a tested max." (Epley `w·(1+r/30)`, r=1 → w, r>12 or w≤0 → null,
  rounded 0.1.)
- "How to" caption (+ dim " · instructions in English" when the UI language has no instruction
  pack) + numbered steps list (15 px label-2, gap 9).

### 4.6 Add to routine `addToRoutineSheet(ex)`
Title "Add “{0}”"; "Pick a routine — sets, reps & weight come next."; list of routines (glyph,
name, count, tag "already in" if the routine already contains this exercise id, plus icon) and a
final "New routine" / "Create one and start with this exercise" (sparkles on surface-3). Pick →
close → Exercise config (new) with `routine` (null for new) → on save: append `{id, ...cfg}` to the
routine (creating `{id: uid(), name: t('New routine'), emoji: 'figureStrength', ex: []}` for new) →
toast "“{0}” added to {1}" (exercise name, routine name) → if new: navigate to its editor.
Duplicates are allowed.

### 4.7 Custom exercise `customExSheet(existing, onDone, prefill)`
- Title "Create your own exercise" | "Edit custom exercise"; hint "Name it and pick a body part — it
  behaves like any other exercise, just without an animation."
- Name input (placeholder "Exercise name"; prefilled with `prefill` = the search text).
- Body-part chips (single select, required).
- If body part = cardio: hint (`figureRun`) "Cardio exercises log time + speed instead of weight × reps."
- Textarea rows 4, maxLength 1000, placeholder "Description (optional) — setup, cues, anything you
  want to remember".
- Primary "Create exercise" | "Save"; edit mode: danger (trash) "Delete exercise" → close +
  `deleteCustomEx`.
- Validation (toasts, sheet stays open): empty name → "Give it a name"; no body part → "Pick a body
  part"; another exercise (built-in or custom, excluding itself) with the same name
  case-insensitively → "“{0}” already exists".
- Create: `id = 'c' + uid()`; record `{id, n, bp, desc: desc.trim().slice(0,1000), tg: '', eq: 'custom', custom: true}`.
  Edit: updates `n, bp, desc`. Close; toast "“{0}” created" | "Saved"; `onDone(exercise)`.

`deleteCustomEx(ex, afterDelete)`: if the active workout contains it → toast "Finish your current
workout first" and stop. Confirm {"Delete “{0}”?", "It will be removed from your routines.
Already-logged workouts keep their sets.", "Delete", danger} → remove from `customEx`; remove from
every routine (+ `cleanupSg`); stamp `e.n = ex.n` onto every history entry with that id (so past
workouts stay readable); delete `exWeights[id]`; toast "Exercise deleted"; `afterDelete()`.

### 4.8 Exercise picker `exercisePicker(onPick)`
Title "Add exercise"; search placeholder "Search {0} exercises…" (count incl. customs).
- Chips: "★ Chosen ({n})" (starFill icon; only if any exercise is used in routines or workouts;
  `n` = number of distinct used ids), "All", body parts. Selecting any chip clears equipment and
  resets paging to **50**.
- Equipment chips as in Library.
- "Chosen" filter = ids with usage > 0, sorted by usage count desc (count = occurrences across all
  routine entries + all workout entries), then name.
- List: (not in Chosen) "Create your own exercise" row → custom sheet (prefill query) → `onPick(new)`;
  exercises (thumb, name, "target · equipment", star tag.acc if used, plus) → `onPick(e)`.
- **The picker does not close on pick**: the config sheet opens on top; after saving it the user is
  back in the picker and can add another. They dismiss the picker by swipe/backdrop.
- Empty Chosen: "Nothing chosen yet — add exercises and they’ll show up here." "Show more" → +50.

### 4.9 Exercise config `exConfigSheet(ex, existing, onSave, onDelete, routine)`
State `c = existing || defaultConfig(ex.id)`; `cardio = ex.bp === 'cardio'`;
`mode = cardio ? 'cardio' : modeOf({...c, id})`.
- Title name; Media; tags (Cardio acc with figureRun, target/body part, equipment); description.
- Non-cardio: segmented "Reps" | "Time" → `setMode(m)`: `c = {...defaultConfig(id, m), ...c, mode: m}`
  (keeps existing values, fills missing: time → `sets 3, sec 45, weight 0`; reps → `sets 3, reps 10, weight 0`).
- Steppers row (3 equal columns):
  - cardio: "Intervals" (sets, step 1 int), "Minutes" (min, 1 int), "Speed (km/h)" (speed, 0.5).
  - time: "Sets" (1 int), "Seconds" (sec, step 5 int), "Weight ({unit})" (weight, 2.5).
  - reps: "Sets" (1 int), "Reps" (1 int), "Weight ({unit})" (2.5).
- Time mode hint: "A timer runs while you hold the set. Leave the weight at 0 for bodyweight holds."
- **Progression fields** (not for cardio): caption "Progression"; SelectRow "Rule" (sheet title
  "Progression"): first option `''` = "Follow the routine ({0})" with the inherited policy name
  (`policyFor({id}, routine, mode)`; routine default, else reps→linear / time→off), then each policy
  allowed for the mode (reps: off/linear/greyskull/double; time: off/time). Below: description of the
  **active** policy. If active ≠ off: stepper "Step (seconds)" (step 5 int) or "Step ({unit})" (step
  1.25 decimal) showing `c.inc > 0 ? c.inc : (time ? 5 : defaultIncrement)` where defaultIncrement =
  kg: 5 for body parts upper legs/lower legs/back (else 2.5); lb: 10 / 5. If active = double: stepper
  "Reps from" = `c.repsMin || max(1, (c.reps||10) − 2)`.
- Primary "Save" (existing) | "Add to routine"; custom exercise: "Edit or delete this exercise"
  (pencil; closes, opens custom sheet); if `onDelete`: danger "Remove from routine".
- **Save normalisation** (sheet closes first):
  ```js
  sets = max(1, round(c.sets) || (cardio ? 1 : 3))
  prog = {}; if (c.prog) prog.prog = c.prog; if (c.inc > 0) prog.inc = c.inc
  cardio → {sets, min: max(1, round(c.min) || 20), speed: max(0, c.speed || 8)}          // no mode, no prog
  time   → {sets, mode:'time', sec: max(1, round(c.sec) || 45), weight: max(0, c.weight || 0), ...prog}
  reps   → reps = max(1, round(c.reps) || 10)
           out = {sets, mode:'reps', reps, weight: max(0, c.weight || 0), ...prog}
           if (policyFor({...c,id}, routine, 'reps') === 'double')
             out.repsMin = min(reps, max(1, round(c.repsMin) || max(1, reps − 2)))
  onSave(out)          // caller re-attaches id (and sg when editing)
  ```

### 4.10 Glyph picker `glyphPicker(current, onPick)` — §2.6. Tap a cell → close, `onPick(key)`.

### 4.11 Day override (reschedule) — §6.2.
### 4.12 Day assign — §6.1.

### 4.13 Plan tools `planToolsSheet()`
Title "Share your plan"; "Send your routines to a friend, or put your week on paper."
- Primary (upload) "Export plan file" (disabled unless some routine has ≥1 exercise) + dim hint "A
  small file a friend imports into their own openGym — routines only, none of your workouts or
  weigh-ins." → writes `opengym-plan-{YYYY-MM-DD}.json` (bundle name "{0}’s plan" with user name, or
  ''), close, toast "Plan file saved — send it to a friend". (Format: data-model.md §6.1.)
- (web) Tinted (download) "Print / Save as PDF" (same disabled rule) + hint "A clean
  one-page-per-plan printout — no exercise ever splits across a page."
- If disabled: "Add an exercise to a routine first — an empty plan has nothing to share."
- Caption "Got a plan from a friend?" + ghost (folder) "Import a plan file" → pick JSON → `parsePlan`
  → close → Plan import sheet; error → toast "Import failed: {0}" (e.g. "this isn’t an openGym plan file").

### 4.14 Plan import `planImportSheet(bundle)`
Title "Import “{0}”" (bundle name) | "Import this plan"; summary "{n} routine(s) · {n} exercise(s)"
[+ " · scheduled on {0} day(s)"]; "These are added as new routines — nothing you already have is
changed."; if dropped > 0 (yellow): "{0} exercise in the file isn’t in your library and was left
out." / "{0} exercises in the file aren’t in your library and were left out."; if scheduled days > 0:
row "Use this weekly schedule" / "Replaces your current Mon–Sun assignments." + Switch (default
**off**); primary "Add to my plan" → `mergePlan(s, bundle, {schedule})` → close → toast "Added {0}
routines to your plan" → `/plan`; ghost dim "Cancel".

### 4.15 Workout detail `workoutDetailSheet(w)`
Title `w.name`; subtitle = join " · " of [long date, duration (if ≥ 1 min), `fmtVol(w.vol)`, body
weight "bw unit" if recorded]. Per entry: thumb (if exercise resolves), name (resolved name, else the
stamped `e.n`, else the id) + PR badge "PR" if `w.prs` contains the id; done sets' labels joined by
"  ·  " or "no sets". Danger "Delete workout" → confirm {"Delete workout?", "This removes it from
your history for good.", "Delete", danger} → remove by id, close, toast "Workout deleted".
(No editing of finished workouts exists.)

### 4.16 Top weight `topWeightSheet(entryIdx)` — §5.9.
### 4.17 WorkoutRow (list row component)
Badge 34×34 with the glyph of the workout's routine (default glyph if the routine is gone/freestyle);
title `w.name`; subtitle join " · " of [long date, duration (if ≥ 1 min), "{0} sets" (done count),
volume]; PR badge "{n} PR" if `w.prs.length > 0`; chevron.

### 4.18 Import summary (from another app)
Title "Import from {0}" (source app) | "Import history"; date range (single date or "from – to").
Tiles: body weight file → "Weigh-ins" (count), "New" (count not already present by date); workout file
→ "Workouts", "Sets", "Exercises matched", "Added as your own". Notices: mixed units (yellow) "The
file mixes kg and lb — each set is converted to {0}."; converted (yellow) "The file is in {0} and your
profile is in {1} — weights will be converted."; unknown unit (dim) "The file does not say which unit
it uses — numbers are imported as they are."; existing days (dim) "{0} days already have data here
and will be left alone."; ratings (dim) "{0} sets bring an {1} with them — switch on Effort per set
in Settings to see it." (or without the suffix when effort is on); unmatched names caption "Not in
the library — added as your own exercises" + up to 12 chips + "+N". Primary "Import" (disabled with
text "Nothing new to import" if 0 fresh) → merge → close → toast "{0} weigh-ins imported" / "{0}
workouts imported"; ghost "Cancel". (Parsing/merge: data-model.md §6.3.)

### 4.19 Calendar `calendarSheet(startISO?)` — §6.3.

### 4.20 Media component (exercise animation)
- Nothing rendered if the exercise has no GIF (custom exercises).
- White background, radius 16, `object-fit: contain`, image height **320** (full), **120**
  (`compact`, used inside supersets), **84** (`mini`).
- Tap toggles between the animated GIF and the still JPG (`playing` local state, default playing).
  Hint pill bottom-right (black 45 %, blur, white 12/500): pause/play icon + "tap to pause" / "tap to
  play" (hidden in mini).
- `minimizable` (workout only): pill bottom-left with `minimize`/`expand` icon + "Minimize"/"Expand"
  → toggles persisted `S.gifSize` between `'full'` and `'mini'` (applies to all exercises and future
  workouts).
- Assets: `img/{ex.img}` and `gif/{ex.gif}` (1324 each, ~140 MB total). Port: host on R2/CDN, cache
  on device.

---------------------------------------------------------------------------------------------------

## 5. Guided workout flow (step by step)

### 5.1 Entry points → `startFlow(routineId | null)`
- Tab bar Start (today's routine with ≥1 exercise, no active workout).
- Home "Today" row (routine present).
- StartChooser: today's card, other routines, freestyle (`null`).
`startFlow(id)` = open the **required body-weight sheet** with `onDone: bw => beginWorkout(id, bw)`.
If a workout is already active these entry points instead resume it (tab/home); StartChooser is
only reachable with no active workout.

### 5.2 Body weight check-in (§4.3, required)
- "Save & start workout" → upsert today's weigh-in, then `beginWorkout(id, weight)`.
- "Start without weighing in" → `beginWorkout(id, null)`.
- "Choose a different workout" → close; navigate `/workout` (StartChooser) — nothing started.

### 5.3 `beginWorkout(routineId, bw)` — session build and prefill
```js
r = routineId ? S.routines.find(id) : null
entries = (r ? r.ex : []).map(cfg => {
  plan = nextPrescription(S, cfg, r)                  // engine.md
  return { id: cfg.id, sg: cfg.sg, target: {...cfg}, plan,
           sets: applyPrescription(buildSets(S, cfg), plan) }
})
S.active = { id: uid(), d: todayISO(), start: Date.now(), routineId,
             name: r ? r.name : t('Freestyle'), bw: bw || null, cur: 0, entries }
stopRest(); navigate('/workout')
```
Prefill (`buildSets`, engine.md — summary): number of sets = `max(1, cfg.sets||1)`; each set `i`
copies "last time" = the most recent finished workout entry of this exercise that had ≥1 done set,
its done set at index `i` (or its last done set if the plan grew):
- **reps**: `w = exWeights[id].w` if > 0 (the confirmed working weight wins), else last time's `w`
  (only if last time's set had `r > 0`), else `cfg.weight`; `r = last r` (if > 0) else `cfg.reps`.
- **time**: `sec`/`w` from last time only if that set had `sec > 0`, else `cfg.sec||45`, `cfg.weight||0`.
- **cardio**: `min`/`speed` from last time, else `cfg.min||20`, `cfg.speed||8`.
- Then `applyPrescription` overwrites `w`/`r`/`sec` on not-done sets with whatever the progression
  policy decided (`kind` `up|hold|deload`; `off`/`first` leave sets untouched).
- All sets start `done: false`. No effort values are prefilled.

### 5.4 ActiveWorkout screen layout
- **Header**: left icon button `xmark` (a11y "Discard") → confirm {"Discard workout?", "The sets you
  logged in this session will be lost.", "Discard", danger} → `S.active = null`, `stopRest()`,
  navigate `/home`. Centre (text-centred): name (600) and subtitle "`{elapsed}` · {done/total} sets"
  where elapsed = `floor((now − start)/1000)` as `m:ss` (minutes unbounded, e.g. "75:03"), ticking
  every second (isolated widget). Right: icon button `check` in accent (a11y "Finish") →
  `finishWorkout()` (§5.11).
- **Progress bar**: 4 px, radius 99, track surface-2, fill accent, width `done/total` (220 ms).
- Position label (small label-2): units = `supersetUnits(entries)`; `cur = min(A.cur, entries.length−1)`;
  current unit = the unit containing `cur`; "Superset {i} / {n}" if the unit has >1 entry else
  "Exercise {i} / {n}" (1-based unit index / unit count).
- **Current exercise block** (single) or **superset card** (`.ss-card`: surface bg, radius 16,
  padding 14, 1.5 px inset accent@38 % outline; header (12/600 accent, link icon, centred) "Superset ·
  do these back-to-back, rest after both"; each member block in `compact` mode separated by a "+"
  (15/600 accent)).
- Empty session (freestyle): empty-state `shuffle` "Freestyle workout — add your first exercise."
- Below: row [Prev] (icon chevronLeft, disabled at first unit) → `cur = units[i−1][0]`; [Next]
  (trailing chevronRight, disabled at last unit or no entries) → `cur = units[i+1][0]`.
- Button (plus) "Add exercise" → §5.12.
- Finish button: `exDone` = entries with ≥1 set and all sets done; `allDone = entries.length > 0 &&
  exDone === entries.length` → primary "Finish workout", else ghost dim "Finish workout early ·
  {exDone}/{entries.length} exercises". Both → `finishWorkout()`.

### 5.5 Exercise block (`ExerciseBlock`)
For entry `e`, `ex = exOr(e.id)`, `mode = modeOf({...e.target, id})`:
1. Media (minimizable; compact inside supersets).
2. Title row: name (20/600, 17 in compact, capitalised) + `info` icon button → Exercise detail sheet.
3. Tags: "Cardio" (acc, figureRun) if cardio; target or body part; equipment; "Best: {x unit}" (nocap)
   if `best > 0` where `best = cardio ? 0 : max(bestWeightFor(S, id), exWeights[id].w || 0)`.
4. "Last time ({short date}): {labels joined ', '}" (small dim) if any previous done sets.
5. **Progression line** if `plan.why` and `plan.kind !== 'off'`: 13 px, icon `arrowUp` (kind up) /
   `arrowDown` (deload) / `lightbulb` (hold, first); colour accent, **yellow for deload**; text =
   `t(...plan.why)`. Possible texts (engine.md): "Nothing logged yet — this session sets the
   baseline.", "Every rep last time — {0} {1} more.", "Last set hit {0} reps — twice the target, so
   take a double jump of {1} {2}.", "Missed reps last time — same weight again ({0} of {1} to go).",
   "Missed reps {0} sessions running — reset to {1} {2} and work back up.", "Missed reps — reset to
   {0} {1} and work back up.", "Top of the rep range in every set — {0} {1} more, back to {2} reps.",
   "Stalled {0} sessions — deload to {1} {2}.", "Same weight — aim for {0} reps this time.",
   "Bodyweight — every rep last time, so go for {0} this time.", "Bodyweight — same target again
   until every set is clean.", "Held every set for the full time — target up by {0}s.", "Short {0}
   sessions in a row — back off to {1}s and build up again.", "Last time came up short — same target
   again."
6. **Set table** card:
   - Header (11 px uppercase label-3): `#` spacer 24 | col1 | col2 | [col3] | [timed: play spacer 30] | check spacer 30.
   - Column definitions:
     | mode | col1 (field, step, decimals, header) | col2 | col3 (effort) |
     |---|---|---|---|
     | reps | `w`, 2.5, dec, "Weight ({unit})" (flex 1.4) | `r`, 1, int, "Reps" (flex 1) | if `effortOf(S)` is rir/rpe: `rir` or `rpe`, step 0.5, dec, nullable, header "RIR"/"RPE" |
     | time | `sec`, 5, int, "Seconds" | `w`, 2.5, dec, "Weight ({unit})" | — |
     | cardio | `min`, 1, int, "Duration (min)" | `speed`, 0.5, dec, "Speed (km/h)" | — |
     With an effort column the row tightens (gap 6, flex 1.2/1/0.85, stepper buttons 23 px (effort 20),
     value font 14).
   - Each row: set number bubble (24 px circle, surface-2, 12/500; **done** → accent bg, on-acc text;
     whole row opacity .45), steppers, (timed) play button, round Check. Hairline between rows (from x=32).
   - Stepper buttons: non-effort `v = max(0, round((cur||0) + dir*step, 2))`; effort →
     `stepEffort(kind, cur, dir)`:
     ```js
     EFFORT = { rir: {step .5, min 0, max 10}, rpe: {step .5, min 6, max 10} }
     if (cur == null) return dir < 0 ? null : min      // first + lands on the floor; − on empty stays empty
     n = round((cur + dir*step)*100)/100
     if (dir < 0 && n < min) return null               // stepping off the floor clears
     return dir > 0 ? Math.min(max, n) : Math.max(min, n)
     ```
     Typed values: NumberField; effort typed values are capped (`min(max, v)`) but not floored.
     A `null` value **deletes the key** from the set (never stored as null).
   - Timed rows: play button (30 px circle surface-2, accent icon) — disabled if the set is done or a
     work timer is running anywhere → §5.8.
   - Check toggles `done` → §5.6.
   - Footer row: sm "Remove set" (minus; disabled when only 1 set) → pop the **last** set; sm "Add
     set" (plus) → append a copy of the last set's values with `done: false` and no effort:
     reps `{w: last.w (or 0), r: last.r (or target.reps)}`; time `{sec: last.sec (or target.sec||45),
     w: last.w||0 (or target.weight||0)}`; cardio `{min: last.min (or target.min||20), speed:
     last.speed (or target.speed||8)}`.

### 5.6 Checking a set — `toggle(idx, i)` (exact)
```js
m = mode of entry idx
isLastUnit = unitIdx >= units.length - 1           // current unit is the last one
askTop = exJustDone = workoutDone = false
update(s => {
  e = s.active.entries[idx]
  e.sets[i].done = !e.sets[i].done
  if (e.sets[i].done) {
    beep(S.sound, 1040, .12); vibrate(30)
    isLastExInUnit = idx === unit[unit.length-1]
    unitDone = every entry in current unit has every set done
    if (isLastExInUnit && !unitDone) startRest(S.restSec)   // rest only after the LAST member of a superset
    else if (unitDone) stopRest()                            // nothing to rest for
    if (unitDone && isLastUnit) workoutDone = true
    if (e.sets.every(done)) { exJustDone = true
      if (m === 'reps' && !e.asked) { e.asked = true; askTop = true } }   // asked once per entry
  }
})
if (askTop) topWeightSheet(idx)                 // chains into complete/next (§5.9)
else if (workoutDone) workoutCompleteSheet()
else if (exJustDone && m === 'cardio') toast('Cardio logged')
else if (exJustDone && m === 'time') toast('Hold logged')
```
Notes:
- **Unchecking** a set does nothing else (a running rest timer keeps running).
- In a superset, checking a set of a non-last member does **not** start rest; rest starts after the
  last member's set. Rechecking restarts the countdown from full.
- Completing a cardio/timed exercise (or a reps exercise already confirmed) does **not**
  auto-advance; the user taps Next. Only the Top-weight sheet's "Save & next exercise" advances.
- `e.asked` is persisted on the active entry, so unchecking + rechecking later won't re-prompt.
- `workoutDone` only fires when the *current* unit is the last unit; finishing exercises out of
  order (e.g. last exercise first) does not show the complete prompt until the last unit is completed
  while being the current one.
- **No PR toast exists mid-set.** The in-session record signal is the "— new record!" text in the
  Top-weight sheet (§5.9); PR detection proper happens at finish (§5.11).

### 5.7 Rest timer engine (`useUI.startRest/addRest/stopRest`)
```js
startRest(sec): stopRest(); endsAt = now + sec*1000; timer = {left: sec, total: sec, endsAt}
                POST rest-timer push {seconds: sec} (signed-in only)
                tick every 1000 ms AND on app visibility change:
                  left = max(0, round((endsAt - now)/1000)); if (left === timer.left) return
                  if (left <= 0) { triple beep; vibrate([200,100,200]); toast('Rest over — next set!'); stopRest(); return }
                  if (left <= 3) beep(660, .1)
                  timer.left = left
addRest(d):     if (!timer) return; left = timer.left + d
                if (left <= 0) { stopRest(); return }                 // "−15" past zero = skip
                timer = {left, total: total + d, endsAt: endsAt + d*1000}; push rest-timer {seconds: left}
stopRest():     clear interval/listener; if (timer) cancel the push; timer = null
```
Duration = `S.restSec` (60/90/120/150/180, default 90). Wall-clock based (`endsAt`), so it stays
correct after backgrounding; recomputed on resume. Stopped by: skip, finish workout, discard,
starting a new workout, starting a work timer, completing a unit.

### 5.8 Work timer (timed sets)
Tap ▶ on set `i`:
```js
startWork(e.sets[i].sec || 45, exerciseName, elapsed => {
  S.active.entries[idx].sets[i].sec = elapsed        // log what was actually held
  if (!sets[i].done) toggle(idx, i)                  // then the normal check path (rest, prompts…)
})
startWork(sec, label, onDone): stopWork(); stopRest()
  total = max(1, round(sec) || 1); endsAt = now + total*1000; work = {left: total, total, endsAt, label}
  tick each second/visibility: left = max(0, round((endsAt-now)/1000)); unchanged → return
    left <= 0 → triple beep, vibrate([200,100,200]), stopWork(), onDone(total)
    left <= 3 → beep(660,.1)
finishWorkEarly(): elapsed = max(1, total - left); vibrate(30); stopWork(); onDone(elapsed)
stopWork() (Cancel): clears everything, onDone NOT called, nothing logged
```
No server push for work timers. Example: 45 s hold stopped with 7 s showing → logs `sec: 38`.
Users may also just tick the checkbox (timed on their own watch) — then `sec` stays as prefilled.

### 5.9 Top-weight confirmation `topWeightSheet(idx)` (reps exercises, first time all sets are done)
- Reads defensively; if the active workout/entry disappears the sheet closes itself.
- `maxSet = max(0, done sets' w)`; `prevBest = max(exWeights[id].w || 0, bestWeightFor(S, id))`;
  initial value `max(maxSet, prevBest) || target.weight || 0`.
- `unitDone` = every entry in its unit fully done; `isLastUnit` = its unit is the last unit.
- UI: title (checkCircle accent) "{0} done" (exercise name); text "Confirm the weight you worked with —
  your highest becomes the default next time." + (superset partner unfinished) " Then finish the
  superset partner."; WeightInput; line (small dim, centred) "Previous best: {prevBest unit}" +
  yellow " — new record!" if `maxSet > prevBest` (only when prevBest > 0).
- Buttons: unitDone → primary "Save & next exercise" (trailing chevron) or "Save" (last unit) +
  ghost dim "Just close"; not unitDone → primary "Save weight".
- `commit(advance)`: `n = round1(v)`; invalid/negative → toast "Enter a valid weight"; set
  `entry.topW = n`; `exWeights[id] = {w: max(n, current.w || 0), d: today}`; close. Then if
  `advance && unitDone`: last unit → Workout-complete dialog; else `cur = first index of next unit`.
  Otherwise toast "Tracked — next time starts at {exWeights[id].w unit}".
- Consequence: confirming a weight **raises the working-weight memory immediately** and it never
  goes down through this path (max).

### 5.10 Workout complete dialog (center, not locked)
checkCircle 44 px accent; "That's the whole workout!"; "Every exercise done — great work. Finish up,
or keep going and add another exercise."; primary (flag) "Finish workout" → close + `finishWorkout()`;
button "Continue workout" → close + toast "Keep going — tap “+ Add exercise” below".

### 5.11 Finish flow, PR detection, summary
`finishWorkout()`:
- no active → return.
- `done = 0` → confirm {"Nothing logged yet", "You haven’t checked off any sets. Finish the workout
  anyway?", "Finish anyway"} (primary, not danger).
- `done < total` → confirm {"Finish early?", "{0} set still unchecked. Finish the workout now?" /
  "{0} sets still unchecked. Finish the workout now?", "Finish workout"}.
- else finish immediately.

`doFinishWorkout()`:
```js
prs = [], e1prs = []
for e in A.entries:
  mx = max(0, ...done sets' s.w)                // NB: s.w undefined for cardio → NaN → never a PR
  if (mx > 0 && mx > bestWeightFor(S, e.id)) prs.push(e.id)     // history BEFORE this workout; includes past topW
  rec = is1RMRecord(S, e.id, e)                 // best Epley estimate of this entry beats all previous
  if (rec && !prs.includes(e.id)) e1prs.push({id: e.id, ...rec})   // {est, w, r, prev}
w = { id: A.id, d: A.d, start: A.start, end: Date.now(), routineId: A.routineId, name: A.name, bw: A.bw,
      entries: A.entries.map(e => ({id, sets: e.sets /* incl. undone */, topW: e.topW || null, target: e.target || null}))
                        .filter(e => e.sets.some(done)),
      prs }
w.vol = Σ done sets (w||0)*(r||0)
update: for each entry: mx = max(0, done w…, topW||0); if mx > 0 and > exWeights[id].w → exWeights[id] = {w: mx, d: w.d}
        S.workouts.push(w); S.active = null
stopRest(); finish triple beep; open FinishSummary (center, LOCKED)
```
(`sg`, `plan`, `asked` are not kept on finished entries. A timed set with weight can register a
weight PR through `s.w` — quirk.)

**Finish summary** (center dialog, locked — only its button closes it):
- trophy 44 px accent; "Workout complete!".
- Tiles: "Duration" `fmtDur(end − start)`; "Volume" `fmtVol`; "Sets" done count; "PRs" count or "—".
- Lines (small, accent, capitalised): trophy "New PR: {name}" per PR; chartLine "Best estimated 1RM:
  {name} · {est unit}" per e1 PR.
- Caption "What you just trained" + **BodyMap** of `loadOfWorkouts([w])` (done sets only).
- (Coach enabled + consented) **Session rating**: caption "How did that feel?"; segmented "Too easy"
  (`easy`) | "About right" (`right`) | "Brutal" (`hard`) — tapping the selected value again clears it;
  stored immediately on the saved workout as `w.rating` (key deleted when cleared). When a rating is
  set, a textarea (rows 2, maxLength 300, placeholder "Anything worth remembering? (optional)") saves
  `w.note = trimmed.slice(0,300)` on blur (deleted if empty).
  > **Port recommendation**: show rating + note always — Claude (via MCP) is the coach now and these
  > are high-value signals for analysis.
- Primary "Nice!" → close + navigate `/home`.

### 5.12 Adding an exercise mid-session
"Add exercise" → Exercise picker → Exercise config (routine = the session's routine for progression
inheritance) → on save:
```js
full = {...cfg, id}; plan = nextPrescription(S, full, routine)
S.active.entries.push({ id, target: {...cfg}, plan, sets: applyPrescription(buildSets(S, full), plan) })
S.active.cur = entries.length - 1       // jump to it
```
Added entries have no `sg` (never superset). Picker stays open for more.

### 5.13 Live presence heartbeat (signed-in only; optional in port)
While ActiveWorkout is mounted: `POST /api/activity {active: true, name, exIdx (1-based unit), exTotal
(units), setsDone, setsTotal, startedAt}` immediately and every 20 s; on unmount `{active: false}`
(beacon + fetch). Feeds the admin "training now" dashboard. Can be dropped or kept for Claude.

### 5.14 Worked examples

**A. Single lift, first time.** Routine "Push": Bench (id 0025) `{sets:3, reps:8, weight:60}`,
restSec 90, no history, policy linear.
1. Tap Start → "Quick check-in" (value 70 default) → set 80.0 → "Save & start workout". Bodyweight
   entry `{d: today, w: 80, t}`; active created; sets `[{w:60,r:8,done:false}×3]`; plan
   `{kind:'first', why:['Nothing logged yet — this session sets the baseline.']}` → lightbulb line.
2. ✓ set 1 → beep/vibrate; single-member unit, not done → rest 90 s bar. ✓ set 2 → rest restarts.
3. ✓ set 3 → unit done → rest stopped; all sets done, reps, not asked → Top-weight sheet, initial 60,
   "Save" (last unit) → `topW = 60`, `exWeights[0025] = {w:60, d}` → Workout-complete dialog →
   "Finish workout" → all done → summary: PR (60 > 0) "New PR: barbell bench press", e1RM 60·(1+8/30)=76.0
   is a record but already a PR → not listed separately.

**B. Superset A+B (2 sets each) then C.** ✓A1 → no rest (A not last in unit). ✓B1 → rest. ✓A2 → A
all done → Top-weight(A) with "Then finish the superset partner." and "Save weight" → toast "Tracked —
next time starts at …". ✓B2 → unit done → rest stopped → Top-weight(B) "Save & next exercise" →
`cur` = C.

**C. Timed plank 3×0:45 bodyweight.** ▶ set 1 → work bar "0:45"… at 0 → triple beep → `sec=45`,
auto-check → rest 90. ▶ set 2, tap "Done" at 0:07 → `sec=38`, auto-check. Set 3 done → toast "Hold
logged" (or complete dialog if last unit). No Top-weight sheet.

**D. Cardio (treadmill) 1 interval 20 min @ 8.** ✓ → (last set) toast "Cardio logged" / complete
dialog if last unit.

---------------------------------------------------------------------------------------------------

## 6. Weekly plan and reschedule flow

Model (data-model.md §1.4): `S.week` = `{ "0".."6": routineId }` (absent key = rest);
`S.dayPlan` = `{ "YYYY-MM-DD": routineId | "rest" }` per-date overrides.
`effectiveRoutineId(S, iso)`: override `'rest'` → null; override that is an **existing** routine id
→ it; otherwise (no override, or override pointing to a deleted routine) → `S.week[weekday(iso)] || null`.

### 6.1 Day assign sheet (Plan → weekday row) `dayAssignSheet(day)`
Title = full day name. List: "Rest day" (moon on surface-3; check if unassigned) → delete
`S.week[day]`; each routine (glyph, name, count; check if assigned) → `S.week[day] = id`. Closes on
pick. No toast.

### 6.2 Day override / reschedule sheet `dayOverrideSheet(iso)`
Opened from: Home week-strip cell (any week, past or future), Home "Today" row when rest, Calendar
cell without workouts.
- Title `fmtDate(iso, true)`. Text: "Weekly plan: {weekly routine name | Rest}" + (override exists,
  orange) " · changed for this day" + line break + "Sick, missed a day or want a different session?
  Pick what to train instead."
- List: each routine (check on the **effective** one) → `dayPlan[iso] = id`; "Rest / skip this
  day" (moon; check if effective is null) → `dayPlan[iso] = 'rest'`; if an override exists: "Back to
  weekly plan" (reset) → delete `dayPlan[iso]`.
- Picking closes the sheet and toasts: back → "Back to weekly plan"; rest → "{0} set to rest"
  (short date); routine → "{0} planned for {1}" (routine name, short date).
- Picking the same routine the week already has still writes an override (the dot turns orange,
  "rescheduled" appears). Past dates are allowed. No "move" operation exists — rescheduling a missed
  Monday session to Tuesday = set Tuesday's override to that routine (and optionally Monday to rest).
- Overrides are never garbage-collected.

### 6.3 Calendar sheet `calendarSheet(startISO?)`
- Month state starts at `startISO`'s month (or today's). Header: [<] icon button, "{Month} {Year}"
  (h3), [>] icon button.
- Summary (small label-2, centred): "{0} workout(s) · {fmtDur(Σ(end−start))} · {fmtVol(Σ vol)}" or
  "No workouts this month".
- Grid 7 columns, gap 5, header "Mo Tu We Th Fr Sa Su" (11 px uppercase label-3); leading blanks =
  `(firstDay.getDay()+6)%7`. Day cell: square, radius 10, surface bg, 15 px number + 5 px dot;
  with workouts → acc-soft bg + accent text (`has`) and accent dot; else orange dot if override with
  routine; label-3 dot if planned; today → inset 1.8 px accent ring.
- Tap: no workouts → close + Day override sheet; 1 workout → close + Workout detail; several → close +
  a sheet titled with the long date listing them as WorkoutRows (each → detail).
- Legend: accent "Trained", label-3 "Planned", orange "Rescheduled". Hint: "Tap a trained day for
  details · tap any other day to plan a session".

### 6.4 Starter plan `loadStarterPlan()`
Appends three new routines (new ids; no de-duplication — loading twice duplicates) and assigns
`week[1]=Push, week[3]=Pull, week[5]=Legs`; toast "Starter plan loaded — Mon Push · Wed Pull · Fri Legs".
| Routine (glyph) | Exercises `[id, sets, reps]`, weight 0, no mode |
|---|---|
| "Push Day" (barbell) | 0025 barbell bench press 4×8; 0047 barbell incline bench press 3×10; 0426 dumbbell standing overhead press 3×10; 0334 dumbbell lateral raise 3×12; 0241 cable triceps pushdown (v-bar) 3×12; 0251 chest dip 3×10 |
| "Pull Day" (pullup) | 2330 cable lat pulldown full range of motion 4×10; 0027 barbell bent over row 4×8; 1323 cable rope seated row 3×10; 0031 barbell curl 3×10; 0313 dumbbell hammer curl 3×12 |
| "Leg Day" (legs) | 0043 barbell full squat 4×8; 0085 barbell romanian deadlift 3×10; 0739 sled 45° leg press 3×12; 0585 lever leg extension 3×12; 0586 lever lying leg curl 3×12; 0605 lever standing calf raise 4×15 |
(Routine names are stored in English, untranslated.)

---------------------------------------------------------------------------------------------------

## 7. Charts (exact drawing algorithms)

### 7.1 LineChart (`components/LineChart.jsx`)
Input `points: [{t: ms, y, d?: iso, m?: 0..1, note?}]` sorted by t; options `h` (default 150), `unit`,
`color` (default accent), `axes` (true), `goal` (null), `invert` (false).
- Empty → "No data yet" (empty-state small).
- Coordinate space: width **W = 340**, height `h`, stretched to container width (non-uniform).
  Padding `l = axes ? 34 : 8, r = 12, t = 10, b = axes ? 22 : 8`.
- Single point → duplicated; x centred.
- Y range: min/max of y, extended to include `goal`; if equal ±1; then pad 12 % of range each side.
  `Y(y) = t + (invert ? f : 1−f)·(h − t − b)`, `f = (y−ymin)/(ymax−ymin)`.
- X: `X(t) = l + (t−t0)/(t1−t0)·(W−l−r)`; `t1 = last.t || t0+1`.
- Y grid: `raw = range/3`, `pow = 10^floor(log10 raw)`, step = first of `[1,2,2.5,5,10]·pow` ≥ raw;
  lines at multiples of step within range: dashed `2 4`, stroke `--sep-op` 1; labels `fmtNum(v)` at
  x = l−5 right-aligned, 9.5 px `--label-2`.
- X ticks: every 1st-of-month strictly after t0 up to t1, label month short; if none and not single →
  3 ticks at 0, ½, 1 of the span labelled "d Mon" (anchors start/middle/end). Show every
  `ceil(n/7)`-th tick. Dashed vertical line + label at y = h−7.
- Goal: dashed `7 4` yellow line (1.6) across + bold yellow label `fmtNum(goal)` at right, 5 px above.
- Area: polygon under the line filled with a vertical gradient `color` @28 % → 0 %.
- Line: 2.5 px, round joins/caps. Marker dots (if any point has `m`): radius `2.4 + 3m`, opacity
  `0.3 + 0.7m`. Last point: solid dot r 4.
- Touch/hover: nearest point by x → crosshair (dashed `3 3`, `--label-3`) and ring dot r 5 (stroke
  `--bg` 2); tooltip pill (surface-2, radius 8, 12/500, shadow) "`{long date} · {fmtNum(v)}[ unit][ ·
  note]`", positioned above (top 4 px) unless the point is too high, then below the point; clamped
  inside the chart horizontally (4 px margin). Vertical page scroll still allowed (`pan-y`).
  Flutter: `fl_chart` `LineChart` can reproduce this, or a `CustomPainter`.

### 7.2 Activity heatmap (`components/Heatmap.jsx`)
- Aggregate per date: `n` workouts, `vol`, `min += max(0, round((end||start − start)/60000))`.
- Thresholds from positive daily minutes sorted asc: `q(p) = mins[min(len−1, floor(p·len))]`;
  `t1=q(.25), t2=q(.5), t3=q(.75)`. Level: no workouts 0; minutes 0 → 1; ≥t3 → 4; ≥t2 → 3; ≥t1 → 2; else 1.
- Grid: **53 columns** (weeks 0..52) × 7 rows (Mon..Sun). `end` = Monday of the current week (noon);
  `start = end − 52 weeks`. Cell 11×11, radius 3, gap 3. Future days opacity .3; today ring 1.5 px accent.
- Month labels row (11 px label-3, 14 px per column, left offset 30): label a column when its
  Monday's date ≤ 7 and its month differs from the last labelled month and column < 51.
- Day labels column (28 px wide, 10 px label-2): "Mon", "", "Wed", "", "Fri", "", "".
- Horizontal scroll, **initially scrolled to the right end** (most recent).
- Tap: only on days with workouts → `onDay(iso)`. (Web tooltip: "iso · n workout(s) · m min · volume".)
- Legend right-aligned: "Less time" [l0..l4 10 px cells] "More time".

### 7.3 BodyMap (`components/BodyMap.jsx`)
- Geometry `lib/body-paths.js` (~94 KB; MIT, derived from MuscleMap by Melih Colpan — keep NOTICE):
  `{male|female: {front|back: {vb: "minX minY w h", p: {slug: [svgPathD…]}}}}`. ViewBoxes: male front
  `0 95 727 1280`, male back `718 95 727 1280`, female front `0 0 650 1450`, female back `823 0 650 1450`.
  Port: convert to a Dart const map and draw with `path_drawing`'s `parseSvgPathData` in a CustomPainter.
- Renders front and back side by side (gap 6), each `max-height: min(46vh, 340px)`; placeholder
  200 px high while loading.
- Paint order: inert parts (`head, hair, neck, hands, feet, knees, ankles`) as silhouette, then the
  18 muscles with level fills (§2.2); every path stroked `--surface` 2.5 px (separates muscles).
  Selected muscle: stroke `--label` width 7.
- Levels: `max = max load over the 18 muscles`; `lv = v ? clamp(ceil(v/max·4), 1, 4) : 0` (relative
  shading within the given load).
- Tappable variant (Stats): tap a muscle path → `onMuscle(slug)` (needs path hit-testing).
- Muscle load computation: engine.md (`loadOf`, primary 1.0 / secondary 0.4 / body-part fallback).

---------------------------------------------------------------------------------------------------

## 8. Tests relevant to the UI (inputs → expected outputs)

Wake lock tests: §1.8. The following (`lib/history.test.js`) pin down strings/steppers the workout
screen renders; `LIFT` = any non-cardio library id, `CARDIO` = a cardio id. (Full engine tests live
in engine.md.)

`fmtSec`: 0→"0:00", 9→"0:09", 45→"0:45", 60→"1:00", 90→"1:30", 605→"10:05"; −5, undefined, null,
NaN → "0:00"; 44.6 → "0:45".

`setLabel`:
| call | result |
|---|---|
| `(LIFT, {w:60,r:10})` | `60×10` |
| `(CARDIO, {min:20,speed:9})` | `20 min @ 9 km/h` |
| `(LIFT, {sec:45,w:0}, {mode:'time'})` | `0:45` |
| `(LIFT, {sec:90,w:20}, {mode:'time'})` | `1:30 · 20` |
| `(LIFT, {w:0,r:0})` | `0×0` |
| `(CARDIO, {})` | `0 min @ 0 km/h` |
| `(LIFT, {w:60,r:10,rir:2})` / `rir:1.5` / `rir:0` | `60×10 (RIR 2)` / `(RIR 1.5)` / `(RIR 0)` |
| `(LIFT, {w:60,r:10,rir:null})` | `60×10` |
| `(LIFT, {w:60,r:10,rpe:8})` / `rpe:9.5` / `rpe:null` | `60×10 (RPE 8)` / `(RPE 9.5)` / `60×10` |
| `(LIFT, {w:60,r:10,rir:2,rpe:8})` | `60×10 (RIR 2)` |
| `(CARDIO, {min:20,speed:9,rpe:8})` | `20 min @ 9 km/h` |
| `(LIFT, {sec:45,rir:2}, {id:LIFT,mode:'time'})` | `0:45` |

`effortOf(S)`: `{effort:'rpe'}`→rpe; `'rir'`→rir; `'none'`→none; `{}`→none; `{showRir:true}`→rir;
`{effort:null,showRir:true}`→rir; `{effort:null}`→none; `{showRir:false}`→none;
`{showRir:true,effort:'rpe'}`→rpe; `{showRir:true,effort:'none'}`→none; junk (`'rpe10'`,`'RIR'`,`'f'`),
null, undefined → none; `{effort:'nope',showRir:true}`→rir. Overlay cases `{unit:'kg', effort:null, ...stored}`:
`{showRir:true}`→rir, `{showRir:false}`→none, `{}`→none, `{effort:'rpe'}`→rpe, `{showRir:true, effort:undefined}`→rir.

`stepEffort(kind, cur, dir)`: `('rir',null,1)`→0; `('rpe',null,1)`→6; `('rir',0,1)`→0.5;
`('rir',0.5,1)`→1; `('rpe',6,1)`→6.5; `('rir',null,-1)`, `('rpe',null,-1)`, `('rir',undefined,-1)`→null;
`('rir',0,-1)`→null; `('rpe',6,-1)`→null; `('rir',0.5,-1)`→0; `('rpe',6.5,-1)`→6; `('rir',9.5,1)`→10;
`('rir',10,1)`→10; `('rpe',10,1)`→10; six `+` from null on rpe → 8.5; `('rir',0.1+0.2,1)`→0.8;
`('rpe',3,1)`→3.5; `('rpe',3,-1)`→null; `('none',null,1)`→null; `('none',2,1)`→2; `(undefined,2,-1)`→2.

`capEffort`: `('rir',12)`→10; `('rpe',99)`→10; `('rpe',8)`→8; `('rpe',1)`→1; `('rir',0)`→0;
`('rir',null)`→null; `('rpe',undefined)`→undefined; `('none',12)`→12.

Session examples: four `+` from empty on RPE → 7.5 → label `80×5 (RPE 7.5)`; one `+` on RIR → 0 →
`100×3 (RIR 0)`.

`defaultConfig`: `(LIFT)`→`{sets:3,reps:10,weight:0,mode:'reps'}`; `(CARDIO)`→`{sets:1,min:20,speed:8}`;
`(LIFT,'time')`→`{sets:3,sec:45,weight:0,mode:'time'}`.

`exLine(cfg,'kg')`: `{sets:3,reps:10}`→`3 × 10`; `+weight:60`→`3 × 10 · 60 kg`;
`{sets:3,sec:45,mode:'time'}`→`3 × 0:45`; `{sets:2,sec:90,weight:20,mode:'time'}`→`2 × 1:30 · 20 kg`;
cardio `{sets:1,min:20,speed:8}`→`1 × 20 min @ 8 km/h`.

`buildSets` (empty history `{workouts:[], exWeights:{}}`): reps `{sets:3,reps:8,weight:50}` →
3× `{w:50,r:8,done:false}`; time `{sets:2,sec:60,weight:20}` → 2× `{sec:60,w:20,done:false}`; cardio
`{sets:1,min:25,speed:9}` → `[{min:25,speed:9,done:false}]`; carries last timed `{sec:70,w:10}` into a
time plan of 2 sets; a previous reps set `{w:60,r:10}` does not seed a time plan (→ `{sec:45,w:0}`);
a previous timed set does not seed reps (→ `{w:40,r:8}`); `exWeights {w:75}` beats last `w:60` →
`{w:75, r:10}` (reps from last time).

`workoutVolume`: reps `60×10` done + undone + timed `{sec:60,w:20}` + cardio → **600**.

No component/widget tests exist in the original.

---------------------------------------------------------------------------------------------------

## 9. Strings and i18n

- ~690 source strings; every one quoted in this spec is a key. Locale files: de, es, fr, hi, it, ko,
  pl, pt, ru, tr, zh (`frontend/src/locales/*.js`, `export default { 'English': 'Translation', … }`).
  Exercise instruction packs: `frontend/src/instr/{es,fr,hi,it,ko,pl,ru,tr,zh}.js`
  (`{exerciseId: [steps]}`); de/pt fall back to English.
- Dataset terms (body parts, equipment, targets, muscle names, month/day abbreviations, glyph group
  names) are also passed through `t()` and have translations.
- Date/number formatting follows the UI language's locale (§2.9), not the device locale.
- Port: a script to convert `locales/*.js` → ARB (`app_es.arb` …) keyed by a stable slug/hash of the
  English string; keep English source text as the fallback. Spanish is fully translated.

---------------------------------------------------------------------------------------------------

## 10. Flutter port notes (mapping)

| Original | Flutter suggestion |
|---|---|
| zustand `S` + `update` | Riverpod/`ChangeNotifier` holding an immutable `AppState` (freezed) + repository that persists locally (Drift/Isar/Hive) and syncs to the Worker |
| `useUI` sheets stack | custom `SheetHost` overlay (stack of entries, `locked` flag, swipe-to-dismiss via `DraggableScrollableSheet` or manual `GestureDetector`) |
| Toast | overlay entry with 2200 ms timer, one at a time |
| Timer bar | `Positioned` overlay above the bottom nav, driven by a `TimerController` using wall-clock `endsAt` + `Timer.periodic(1s)` + `AppLifecycleState.resumed` recompute |
| Wake lock | `wakelock_plus`, enabled while active workout && keepAwake |
| Rest push | `flutter_local_notifications` zoned schedule at `endsAt` |
| Beeps / vibration | generated tone assets + `audioplayers`/`flutter_soloud`; `vibration` package for patterns |
| Icons | `flutter_svg` from Appendix A path strings (stroke 1.7, round caps) |
| LineChart / Heatmap / BodyMap | `CustomPainter` (or `fl_chart` for the line chart) |
| GIF/JPG media | `cached_network_image` from R2/CDN; GIF animates natively with `Image.network` |
| Segmented / Switch / Stepper / Slider / Check | custom widgets matching §2.8 (don't use Material defaults — the original intentionally avoids platform-looking controls) |
| Hash routes | `go_router` with the same paths; bottom nav shell (`StatefulShellRoute`) with the raised Start button |
| Native time input | `showTimePicker` / Cupertino picker |
| File import/export | `file_picker` + `share_plus` |

Keep all state-mutation semantics from `data-model.md §2.5`; the UI only calls those mutations.

---------------------------------------------------------------------------------------------------

## 11. Quirks and edge cases (preserve unless deliberately fixed)

1. Routine name field saves on every keystroke; empty name stored as "Routine" while the field shows empty.
2. Unlinking the middle of a 3-member superset dissolves the whole group (cleanupSg).
3. The exercise picker stays open after picking (intentional multi-add), so after adding a single
   exercise the user must dismiss the picker manually.
4. `WeightInput` default 70 even for lb profiles; any control clamps to ≥ 1.
5. Deleting a weigh-in has no confirmation.
6. Loading the starter plan twice duplicates the three routines.
7. Overrides (`dayPlan`) for a routine equal to the weekly one still count as "rescheduled".
8. The "That's the whole workout!" prompt fires when the **last unit** is completed while it is the
   current unit — earlier exercises are not checked. Skipping exercise 2 and finishing the last one
   still shows it; "Finish workout" then falls into the "Finish early?" confirm. Completing the last
   unit first and an earlier one afterwards never shows it.
9. Cardio exercises never register PRs (NaN max); timed sets with weight can.
10. Finished entries keep undone sets in `sets` (only filtered by "≥1 done set").
11. `Stats` "Week" window for muscle balance = current ISO week, whereas 30d/90d are rolling.
12. `Button` default variant "plain" renders as accent text without a fill.
13. The Top-weight "new record!" hint compares the session's heaviest set against
    `max(exWeights, history best)`; it is the only in-session PR signal.
14. `stepEffort` never snaps a typed below-floor value (RPE 3 → 3.5 on +).
15. `Home` week offset resets when navigating away; Stats selections (range/exercise/metric) also
    reset (component state only).

## 12. Open questions for the port

1. **Auth**: the original uses passkeys + per-profile server data + guest mode. For a single-owner
   Cloudflare deployment, is login needed at all (e.g. Cloudflare Access / a device token), and should
   guest/offline-only mode survive? Login/Register screens and the Settings account section depend on it.
2. **Coach replacement**: when Claude creates a training plan via MCP, should it write routines/week
   directly, or create a *proposal* the app shows for review (the Home "Coach card" slot, "Your plan is
   ready / {n} suggestions for you" → review screen)? The original Coach never changes anything
   without the user's say-so — recommend keeping a review/accept step.
3. **Session rating/notes**: enable always (recommended) so Claude gets subjective load data?
4. **Media hosting**: 1324 GIF + 1324 JPG (~140 MB). Bundle, host on R2, or lazy-download packs?
5. **Default language/unit**: the user writes in Spanish — default `lang: 'es'`? Unit kg?
6. **Admin heartbeat / presence** (`/api/activity`): drop, or keep as "currently training" info for Claude?
7. **Web Push** is unnecessary in a native app (local notifications suffice) — confirm the server-side
   reminder/push endpoints can be dropped from the Worker.
8. Desktop layout (≥1000 px two-column grids, floating tab bar) — needed for tablets?

---------------------------------------------------------------------------------------------------

## Appendix B. Legacy emoji → glyph map (`glyphOf`)

`💪 🦾 → arm; 🫸 → figureStrength; 🫷 → pullup; 🏋️ 🏋 🏋️‍♀️ → dumbbell; 🦵 🍑 → legs; 🔥 😤 → flame;
⚡ 💥 🧨 🚀 → bolt; 🏃 🏃‍♀️ ⛰️ 🏔️ 🐺 → figureRun; 🚴 → bike; 🏊 🦈 → swim; 🤸 🧘 🧘‍♀️ → stretch; 🥊 🦁 → boxing;
🧗 → pullup; 🎯 → target; 🏆 → trophy; 🥇 → medal; ⭐ 🌟 → star; 👑 → crown; 🛡️ ⚔️ → shield; ❤️‍🔥 → heart;
🦍 🐻 → kettlebell; 🐂 → barbell; 🤖 → machine`. Unknown → `figureStrength`.

## Appendix A. Icon path data (verbatim from `components/Icon.jsx`)

Render each as `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"
stroke-linecap="round" stroke-linejoin="round">…</svg>`. Elements with `fill="currentColor"
stroke="none"` are solid. Aliases: search/exercises→magnifier, settings→gear, weight→scale,
streak→flame, done→check.

```jsx
const P = {
  /* ---- navigation ---- */
  house: <path d="M3.5 10.7 12 3.8l8.5 6.9M5.9 9.4V19a1.4 1.4 0 0 0 1.4 1.4h9.4A1.4 1.4 0 0 0 18.1 19V9.4" />,
  calendar: <><rect x="3.4" y="5.2" width="17.2" height="15.4" rx="3.2" /><path d="M8.2 3.4v3.4M15.8 3.4v3.4M3.4 10.2h17.2" /></>,
  chart: <path d="M4.5 20.2V13M9.5 20.2V6.4M14.5 20.2v-5.1M19.5 20.2V9.6" />,
  magnifier: <><circle cx="11" cy="11" r="7" /><path d="m20.5 20.5-4.4-4.4" /></>,
  // A real cog outline (8 teeth, generated on a circle) — an earlier version drew
  // radial rays and was indistinguishable from `sun` at tab-bar size.
  gear: <><path d="M20.48 10.59 20.48 13.41 18.58 13.72 17.87 15.43 19 17 17 19 15.43 17.87 13.72 18.58 13.41 20.48 10.59 20.48 10.28 18.58 8.57 17.87 7 19 5 17 6.13 15.43 5.42 13.72 3.52 13.41 3.52 10.59 5.42 10.28 6.13 8.57 5 7 7 5 8.57 6.13 10.28 5.42 10.59 3.52 13.41 3.52 13.72 5.42 15.43 6.13 17 5 19 7 17.87 8.57 18.58 10.28Z" /><circle cx="12" cy="12" r="3.1" /></>,

  /* ---- training ---- */
  dumbbell: <><rect x="5.9" y="7.9" width="3.2" height="8.2" rx="1.3" /><rect x="14.9" y="7.9" width="3.2" height="8.2" rx="1.3" /><path d="M9.1 12h5.8M3.6 9.9v4.2M20.4 9.9v4.2" /></>,
  barbell: <path d="M2.9 12h18.2M7.4 7.4v9.2M9.8 9.3v5.4M16.6 7.4v9.2M14.2 9.3v5.4" />,
  figureRun: <><circle cx="14.2" cy="4.9" r="1.9" /><path d="M13.4 9.1 9.6 11.4l1.7 3.3-2.4 5.4M13.4 9.1l3.4 1.5 1.4 3.4M11.3 14.7l4.3.9 1.5 4.5M9.6 11.4 6 10.2" /></>,
  figureStrength: <><circle cx="12" cy="5.2" r="2" /><path d="M12 8.4v5.6M12 14 9.2 20.5M12 14l2.8 6.5M8 10.6h8M5.4 9.1v3M18.6 9.1v3" /></>,
  scale: <><rect x="3.4" y="4.4" width="17.2" height="16.2" rx="3.4" /><path d="M8.3 9.2a3.9 3.9 0 0 1 7.4 0" /><path d="M12 9.2v2.5M8.9 16.2h6.2" /></>,
  flame: <path d="M12 20.4c3.2 0 5.4-2.1 5.4-5.1 0-3.9-3.4-5.6-2.6-9.8-2.5.8-4 2.9-4 5.1 0 1-.5 1.6-1.2 1.6-.8 0-1.2-.7-1.2-1.8-1.1 1.2-1.8 2.9-1.8 4.9 0 3 2.2 5.1 5.4 5.1Z" />,
  timer: <><circle cx="12" cy="13.4" r="7.2" /><path d="M12 9.6v3.8h2.8M9.6 3.4h4.8" /></>,
  clock: <><circle cx="12" cy="12" r="8.2" /><path d="M12 7.4V12l3.1 1.9" /></>,

  /* ---- status / achievement ---- */
  trophy: <><path d="M7.6 4h8.8v4.6a4.4 4.4 0 0 1-8.8 0Z" /><path d="M7.6 5.6H4.9v1.5a3 3 0 0 0 2.9 3M16.4 5.6h2.7v1.5a3 3 0 0 1-2.9 3M12 13v3.4M8.6 20.4h6.8l-.7-4H9.3Z" /></>,
  medal: <><circle cx="12" cy="14.8" r="5.2" /><circle cx="12" cy="14.8" r="1.9" /><path d="M9.1 9.9 6.4 3.6M14.9 9.9l2.7-6.3" /></>,
  target: <><circle cx="12" cy="12" r="8.2" /><circle cx="12" cy="12" r="4.6" /><circle cx="12" cy="12" r="1.1" /></>,
  star: <path d="m12 3.9 2.6 5.3 5.8.8-4.2 4.1 1 5.8-5.2-2.7-5.2 2.7 1-5.8-4.2-4.1 5.8-.8Z" />,
  starFill: <path d="m12 3.9 2.6 5.3 5.8.8-4.2 4.1 1 5.8-5.2-2.7-5.2 2.7 1-5.8-4.2-4.1 5.8-.8Z" fill="currentColor" stroke="none" />,
  crown: <path d="M4.2 17.6h15.6M4.2 17.6 3.4 7.2l4.6 3.2L12 4.6l4 5.8 4.6-3.2-.8 10.4Z" />,
  bolt: <path d="M13.4 3.4 5.6 13.6h5.2l-.2 7 7.8-10.2h-5.2Z" />,
  shield: <path d="M12 3.6 5 6.2v5.5c0 4 2.9 7.5 7 8.7 4.1-1.2 7-4.7 7-8.7V6.2Z" />,
  heart: <path d="M12 20c-.4 0-.8-.1-1-.4l-6.2-6a4.6 4.6 0 0 1 0-6.6 4.4 4.4 0 0 1 6.2 0l1 1 1-1a4.4 4.4 0 0 1 6.2 0 4.6 4.6 0 0 1 0 6.6l-6.2 6c-.2.3-.6.4-1 .4Z" />,
  rocket: <><path d="M12 3.6c2.8 2.5 4.2 5.7 4.2 9.1v4.5H7.8v-4.5c0-3.4 1.4-6.6 4.2-9.1Z" /><circle cx="12" cy="10.3" r="1.8" /><path d="M7.8 14 5.2 16.6v3.8l2.6-2M16.2 14l2.6 2.6v3.8l-2.6-2" /></>,
  sparkles: <><path d="m8.4 3.8 1.1 2.9 2.9 1.1-2.9 1.1-1.1 2.9-1.1-2.9L4.4 7.8l2.9-1.1Z" /><path d="m16.2 12.4.8 2.1 2.1.8-2.1.8-.8 2.1-.8-2.1-2.1-.8 2.1-.8Z" /></>,
  lightbulb: <><path d="M9.2 16.4a5.6 5.6 0 1 1 5.6 0v1.8H9.2Z" /><path d="M10 20.6h4" /></>,

  /* ---- routine glyphs: what a training day actually is ---- */
  // Named after the split or the kit, because that's how people name routines
  // ("Push Day", "Leg Day", "Kettlebell") — an award icon says nothing about it.
  arm: <><circle cx="7" cy="5.8" r="1.9" /><path d="M7 8.8v4.6l-1.2 6.2M7 11.4l4.4 1.9" /><rect x="12.2" y="10.8" width="2.3" height="5" rx=".9" /><rect x="15.9" y="10.8" width="2.3" height="5" rx=".9" /><path d="M14.5 13.3h1.4" /></>,
  // Six-pack, not a grid: the centre seam runs down the gap between the crease
  // pairs and every crease stops short of the outline, so no stroke crosses another
  // (the old version drew full-width lines through a centre line — a see-through #).
  abs: <><path d="M7.8 4.4h8.4v10.4a4.2 4.2 0 0 1-8.4 0Z" /><path d="M12 6.2v9M9 8.9h2.2M12.8 8.9h2.2M9 11.6h2.2M12.8 11.6h2.2M9.3 14.2h1.9M12.9 14.2h1.9" /></>,
  legs: <><path d="M8.4 4.2h7.2" /><path d="M9.9 4.2v4.9l-1.3 4.4.9 6.3M14.1 4.2v4.9l1.3 4.4-.9 6.3" /><path d="M7.7 19.8h2.6M13.7 19.8h2.6" /></>,
  // Head lifted clear of the arm-V apex (was cy 10.5, right where the arm strokes
  // meet) so the body no longer reads as tangled lines behind a transparent head.
  pullup: <><path d="M3.6 5.1h16.8M8.5 5.5v2.3M15.5 5.5v2.3" /><circle cx="12" cy="9.6" r="1.8" /><path d="m8.5 7.8 3.5 5 3.5-5M12 13.3v3.9M12 17.2l-2.1 3.2M12 17.2l2.1 3.2" /></>,
  kettlebell: <><path d="M9.5 11V9.6a2.5 2.5 0 0 1 5 0V11" /><path d="M14.9 11.8c2.2 1.5 3.6 3.9 3.6 6.4a1.6 1.6 0 0 1-1.6 1.6H7.1a1.6 1.6 0 0 1-1.6-1.6c0-2.5 1.4-4.9 3.6-6.4Z" /></>,
  plate: <><circle cx="12" cy="12" r="8.2" /><circle cx="12" cy="12" r="2.7" /></>,
  machine: <><path d="M12 3.6v3.1" /><rect x="6.6" y="6.7" width="10.8" height="12.9" rx="1.9" /><path d="M9 10.1h6M9 13.2h6M9 16.3h6" /></>,
  bike: <><circle cx="6.2" cy="16.2" r="3.5" /><circle cx="17.8" cy="16.2" r="3.5" /><path d="m6.2 16.2 4.3-7.4h4.9l2.4 7.4M9.3 8.8h4.5M13.8 8.8l-2.6 7.4" /></>,
  swim: <><circle cx="8.8" cy="8.2" r="1.8" /><path d="m10.9 10 4.6-2.2 3.3 3.4" /><path d="M3.5 15.6c1.6-1.3 3.1-1.3 4.7 0s3.1 1.3 4.7 0 3.1-1.3 4.7 0c.9.7 1.7.9 2.6.5" /></>,
  boxing: <><path d="M7.6 8.6A4.6 4.6 0 0 1 12.2 4h1.6a5.4 5.4 0 0 1 5.4 5.4v2.4a3 3 0 0 1-3 3H7.6Z" /><path d="M7.6 14.8v2.3a2.6 2.6 0 0 0 2.6 2.6h5.2a2.6 2.6 0 0 0 2.6-2.6v-2.3" /><path d="M7.6 9.8H6.3a1.8 1.8 0 0 0 0 3.6h1.3" /></>,
  stretch: <><circle cx="14.4" cy="5.4" r="1.9" /><path d="M14.4 8.2c-3 1.4-5 4-5.8 7.4" /><path d="M8.6 15.6 6.2 20M8.6 15.6l4.6 4.4" /><path d="M12.6 9.6 18 12" /></>,

  /* ---- actions ---- */
  plus: <path d="M12 5.2v13.6M5.2 12h13.6" />,
  minus: <path d="M5.2 12h13.6" />,
  check: <path d="m4.8 12.6 4.8 4.8L19.2 6.8" />,
  checkCircle: <><circle cx="12" cy="12" r="8.2" /><path d="m8.2 12.2 2.7 2.7 5.1-5.4" /></>,
  xmark: <path d="M6.2 6.2 17.8 17.8M17.8 6.2 6.2 17.8" />,
  pencil: <><path d="M17.1 3.9a2.1 2.1 0 0 1 3 3l-9.9 9.9-4 1 1-4Z" /><path d="m15.1 5.9 3 3" /></>,
  trash: <><path d="M4.8 6.6h14.4M9.4 6.6V4.8a1.2 1.2 0 0 1 1.2-1.2h2.8a1.2 1.2 0 0 1 1.2 1.2v1.8" /><path d="M6.6 6.6 7.4 19a1.6 1.6 0 0 0 1.6 1.4h6a1.6 1.6 0 0 0 1.6-1.4l.8-12.4" /><path d="M10.4 10.2v6.4M13.6 10.2v6.4" /></>,
  link: <><path d="M10.2 13.8a3.6 3.6 0 0 0 5.4.4l2.6-2.6a3.6 3.6 0 0 0-5.1-5.1l-1.5 1.5" /><path d="M13.8 10.2a3.6 3.6 0 0 0-5.4-.4l-2.6 2.6a3.6 3.6 0 0 0 5.1 5.1l1.5-1.5" /></>,
  play: <path d="M8.4 5.6 18 12l-9.6 6.4Z" />,
  pause: <path d="M9.4 5.8v12.4M14.6 5.8v12.4" />,
  reset: <><path d="M4.4 12a7.6 7.6 0 1 0 2.3-5.4" /><path d="M4 4.4v4.4h4.4" /></>,
  bell: <><path d="M6.6 10.4a5.4 5.4 0 0 1 10.8 0c0 4 1.4 5.6 1.4 5.6H5.2s1.4-1.6 1.4-5.6Z" /><path d="M10.1 19.2a2.1 2.1 0 0 0 3.8 0" /></>,
  bellSlash: <><path d="M8.1 6.6a5.4 5.4 0 0 1 9.3 3.8c0 4 1.4 5.6 1.4 5.6H9.4M6.6 16H5.2s1.4-1.6 1.4-5.6v-.6" /><path d="M10.1 19.2a2.1 2.1 0 0 0 3.8 0M4 3.6l16 16.8" /></>,
  chevronRight: <path d="m9.6 5.6 6.6 6.4-6.6 6.4" />,
  chevronLeft: <path d="m14.4 5.6-6.6 6.4 6.6 6.4" />,
  chevronDown: <path d="m5.6 9.4 6.4 6.2 6.4-6.2" />,
  chevronUp: <path d="m5.6 14.6 6.4-6.2 6.4 6.2" />,
  arrowUp: <path d="M12 19.6V4.4M6.2 10.6 12 4.4l5.8 6.2" />,
  arrowDown: <path d="M12 4.4v15.2M6.2 13.4 12 19.6l5.8-6.2" />,
  expand: <path d="M14.4 4.4h5.2v5.2M9.6 19.6H4.4v-5.2M19.6 4.4 13.8 10.2M4.4 19.6l5.8-5.8" />,
  minimize: <path d="M19.6 9.6h-5.2V4.4M4.4 14.4h5.2v5.2M14.4 9.6l5.2-5.2M9.6 14.4l-5.2 5.2" />,

  /* ---- objects ---- */
  person: <><circle cx="12" cy="8" r="3.8" /><path d="M4.8 20.4a7.2 7.2 0 0 1 14.4 0" /></>,
  personCircle: <><circle cx="12" cy="12" r="8.4" /><circle cx="12" cy="10" r="2.9" /><path d="M6.6 18.4a5.8 5.8 0 0 1 10.8 0" /></>,
  clipboard: <><rect x="5.4" y="4.8" width="13.2" height="15.8" rx="2.6" /><path d="M9 4.8a1.6 1.6 0 0 1 1.6-1.6h2.8A1.6 1.6 0 0 1 15 4.8v1.4H9Z" /><path d="M9.2 11.6h5.6M9.2 15.2h4" /></>,
  list: <path d="M8.4 6.6h11.2M8.4 12h11.2M8.4 17.4h11.2M4.6 6.6h.01M4.6 12h.01M4.6 17.4h.01" />,
  folder: <path d="M3.6 7.4a2 2 0 0 1 2-2h3.1l2 2.4h6.7a2 2 0 0 1 2 2v7.8a2 2 0 0 1-2 2H5.6a2 2 0 0 1-2-2Z" />,
  globe: <><circle cx="12" cy="12" r="8.2" /><path d="M3.8 12h16.4M12 3.8c2.1 2.2 3.2 5.1 3.2 8.2s-1.1 6-3.2 8.2c-2.1-2.2-3.2-5.1-3.2-8.2s1.1-6 3.2-8.2Z" /></>,
  moon: <path d="M19.4 14.2A7.8 7.8 0 0 1 9.8 4.6a8.2 8.2 0 1 0 9.6 9.6Z" />,
  sun: <><circle cx="12" cy="12" r="4.4" /><path d="M12 3.6v2M12 18.4v2M20.4 12h-2M5.6 12h-2M17.94 6.06l-1.42 1.42M7.48 16.52l-1.42 1.42M17.94 17.94l-1.42-1.42M7.48 7.48 6.06 6.06" /></>,
  key: <><circle cx="8.2" cy="15.8" r="3.8" /><path d="m10.9 13.1 8-8M16.6 7.4l2 2M14.6 9.4l2 2" /></>,
  lock: <><rect x="5" y="10.4" width="14" height="10" rx="2.8" /><path d="M8.4 10.4V7.8a3.6 3.6 0 0 1 7.2 0v2.6" /></>,
  download: <path d="M12 3.8v11.4M7.6 11.2 12 15.6l4.4-4.4M4.6 19.4h14.8" />,
  upload: <path d="M12 15.6V4.2M7.6 8.2 12 3.8l4.4 4.4M4.6 19.4h14.8" />,
  wrench: <path d="M15.2 3.9a5 5 0 0 0-4.8 6.6l-6 6a2.1 2.1 0 0 0 3 3l6-6a5 5 0 0 0 6.1-6.3l-2.9 2.9-2.8-.7-.7-2.8Z" />,
  // checkered, not a pennant — this marks "finish workout", and a 2×2 grid is
  // what reads as a finish line at 16px
  flag: <><path d="M6 20.4V4.2" /><path d="M6.4 5.2h13v9.2h-13" /><path d="M12.9 5.2v9.2M6.4 9.8h13" /></>,
  chartLine: <path d="M3.6 20.2V4.4M3.6 20.2h16.8M6.4 16.4l3.9-4.8 3.1 2.7 5.2-6.6" />,
  dot: <circle cx="12" cy="12" r="4.2" fill="currentColor" stroke="none" />,
  history: <><path d="M4.5 12.2a7.6 7.6 0 1 0 2.5-5.6" /><path d="M4.1 4.4v4.3h4.3" /><path d="M12 8.3v4.2l3.1 1.9" /></>,
  signOut: <><path d="M14.2 4.6H7a1.9 1.9 0 0 0-1.9 1.9v11a1.9 1.9 0 0 0 1.9 1.9h7.2" /><path d="m16.8 8.4 3.6 3.6-3.6 3.6M20.4 12H10.2" /></>,
  shuffle: <><path d="M3.6 7.2h2.9c1.6 0 2.8.9 3.8 2.4l3 4.8c1 1.5 2.2 2.4 3.8 2.4h2.9M3.6 16.8h2.9c1.6 0 2.8-.9 3.8-2.4l.7-1.1M15.6 9.9l.7-1.1c1-1.5 2.2-2.4 3.8-2.4h1.9" /><path d="m17.9 4.3 2.8 2.1-2.8 2.1M17.9 14.7l2.8 2.1-2.8 2.1" /></>,
  info: <><circle cx="12" cy="12" r="8.2" /><path d="M12 11v5.4" /><circle cx="12" cy="7.9" r=".9" fill="currentColor" stroke="none" /></>,
}
```
