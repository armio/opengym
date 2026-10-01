# Porting spec: exercise library, muscles, i18n, glyphs, media and history import

Source: openGym (`/home/user/opengym`, HEAD `3d545a3`). Target: Flutter app (Dart), a Cloudflare Workers + D1 backend (TypeScript), and a remote MCP server that lets Claude read progress and write training plans.

This spec covers these files:

| File | Role |
|---|---|
| `frontend/src/lib/exercises-data.js` (888,199 B, one line) | The built-in catalogue `EXDB` (1,324 exercises, English) |
| `frontend/src/lib/exercises.js` | Index and helpers: `EXIDX`, `BODYPARTS`, `equipmentOf`, customs, media URLs, `isCardio`, `exOr` |
| `frontend/src/lib/muscles.js` | Muscle taxonomy, per-exercise muscle weights, load, heat levels |
| `frontend/src/lib/i18n.js` + `frontend/src/locales/*.js` + `frontend/src/instr/*.js` | UI strings and translated exercise instructions |
| `frontend/src/lib/glyphs.js` | Routine icon keys and the legacy emoji mapping |
| `frontend/src/components/Media.jsx` | GIF/JPG display, and the thumbnail fallback |
| `frontend/src/lib/import-csv.js` (526 lines) | FitNotes / Strong / Hevy / generic CSV and Apple Health import |
| `frontend/src/lib/import-effort.test.js` | Tests for importing RPE/RIR (reproduced in §9.14) |
| `scripts/build-coach-library.mjs` → `api/coach/library.json` | The slim catalogue the AI Coach uses |
| `scripts/build-instructions.mjs` | Regenerates `src/instr/*.js` from upstream |
| `scripts/fetch-media.sh`, `docker-compose.yml`, `web/nginx.conf` | How media is fetched and served |

Several call sites outside the listed files were also read because they define behaviour: `Library.jsx` and the `ExercisePicker` (search and filter), `sheets.jsx` (the `ExerciseDetail` and `CustomExForm` sheets, `deleteCustomEx`, `ImportSummary` and `importFromApp`), `format.js` (`uid`, `fmtNum`), `history.js` (`effortOf`, `setLabel`) and `api/coach/payload.js` (the consumers of `library.json`).

All golden vectors in this document were produced by running the original JS in Node 22 with `TZ=UTC`. The harness is in `scratchpad/harness/`.

---

## 1. The exercise catalogue (`EXDB`)

### 1.1 File format

`exercises-data.js` is one line: `export const EXDB=[{...},{...},...];`. It is a verbatim projection of upstream `hasaneyldrm/exercises-dataset/data/exercises.json`, pinned at commit `7455efae41b330c265e7cd4b78dfa848e7ce5ebd`. Every field matches upstream exactly (checked for all 1,324 records), and **the array order is the same as upstream**.

- The order is **not** alphabetical: there are 46 violations of a base-collation sort, and the order is not by id either (for example `0577` comes before `0576`).
- **Array order matters.** The import matcher resolves collisions by first occurrence (§9.5), so the port must preserve it.

### 1.2 Record schema

Every record has exactly these 10 keys, in this order. There are no optional fields, no nulls and no empty strings.

| Key | Type | Meaning | Upstream field | Invariants |
|---|---|---|---|---|
| `id` | string | Primary key | `id` | Always 4 digits (`/^\d{4}$/`), unique, from `0001` to `5201`. First digits: 0→704, 1→383, 2→94, 3→142, 5→1. Keep it as a **string**; the leading zeros matter. |
| `n` | string | Name, always lowercase | `name` | 1,318 distinct names (6 duplicated pairs, §1.5). Max 67 chars. Can contain `()`, `-`, `/`, `°`, `v. 2`, `(male)` |
| `bp` | string | Body part (the category) | `body_part` (== `category`) | 10 values |
| `eq` | string | Equipment | `equipment` | 28 values |
| `tg` | string | Primary target muscle | `target` | 19 values |
| `mg` | string | "Muscle group" (the main synergist) | `muscle_group` | 29 values. **Always equals `sm[0]`.** The app never reads it. |
| `sm` | string[] | Secondary muscles | `secondary_muscles` | Length 1–6 (1:338, 2:753, 3:201, 4:28, 5:2, 6:2). 40 distinct values, 2,581 occurrences |
| `st` | string[] | English instruction steps | `instruction_steps.en` | 4–11 steps (4:82, 5:503, 6:426, 7:221, 8:72, 9:15, 10:2, 11:3) |
| `img` | string | Still thumbnail file name | `image` minus the `images/` prefix | Always `` `${id}-${media_id}.jpg` `` |
| `gif` | string | Animation file name | `gif_url` minus the `videos/` prefix | Always `` `${id}-${media_id}.gif` ``, with the same stem as `img` |

`media_id` is 7 characters from `[A-Za-z0-9]` (for example `EIeI8Vf`). Upstream fields that openGym drops: `category` (duplicates `body_part`), `instructions.<lang>` (the joined paragraph), `media_id` (embedded in the file names), `created_at`, and `attribution` (always `"© Gym visual — https://gymvisual.com/"`).

### 1.3 Distinct values, counts and Spanish labels

The Spanish labels come from `frontend/src/locales/es.js`. Every locale file (de, es, fr, it, pt, pl, tr, ru, zh, ko, hi) has a key for **every** bp, eq, tg and sm value; none is missing. The "muscle slug" column is the `ALIAS` mapping from `muscles.js` (§3).

**`bp`, body part (10 values).** The UI sorts them with `[...new Set].sort()`, which gives `back, cardio, chest, lower arms, lower legs, neck, shoulders, upper arms, upper legs, waist`.

| bp | count | es |
|---|---|---|
| upper arms | 292 | brazos |
| upper legs | 227 | piernas |
| back | 203 | espalda |
| waist | 169 | abdomen |
| chest | 163 | pecho |
| shoulders | 143 | hombros |
| lower legs | 59 | pantorrillas |
| lower arms | 37 | antebrazos |
| cardio | 29 | cardio |
| neck | 2 | cuello |

**`eq`, equipment (28 values, plus `custom` for user exercises)**

| eq | count | es | | eq | count | es |
|---|---|---|---|---|---|---|
| body weight | 325 | peso corporal | | medicine ball | 13 | balón medicinal |
| dumbbell | 294 | mancuerna | | rope | 10 | cuerda |
| cable | 157 | polea | | roller | 8 | rodillo |
| barbell | 154 | barra | | resistance band | 7 | banda de resistencia |
| leverage machine | 81 | máquina de palanca | | bosu ball | 3 | bosu |
| band | 54 | banda | | olympic barbell | 2 | barra olímpica |
| smith machine | 48 | máquina Smith | | wheel roller | 2 | rueda abdominal |
| kettlebell | 41 | kettlebell | | upper body ergometer | 1 | ergómetro de brazos |
| weighted | 36 | con lastre | | skierg machine | 1 | SkiErg |
| stability ball | 28 | fitball | | hammer | 1 | martillo |
| ez barbell | 23 | barra EZ | | stationary bike | 1 | bici estática |
| assisted | 15 | asistido | | tire | 1 | neumático |
| sled machine | 15 | trineo | | trap bar | 1 | barra hexagonal |
| | | | | elliptical machine | 1 | elíptica |
| | | | | stepmill machine | 1 | escaladora |
| *(custom)* | – | propio | | | | |

**`tg`, target muscle (19 values)**

| tg | count | es | muscle slug |
|---|---|---|---|
| abs | 169 | abdominales | abs |
| pectorals | 158 | pectorales | chest |
| biceps | 151 | bíceps | biceps |
| glutes | 144 | glúteos | gluteal |
| delts | 143 | deltoides | deltoids |
| triceps | 141 | tríceps | triceps |
| upper back | 88 | espalda alta | upper-back |
| lats | 81 | dorsales | upper-back |
| calves | 59 | gemelos | calves |
| quads | 44 | cuádriceps | quadriceps |
| forearms | 37 | antebrazos | forearm |
| cardiovascular system | 29 | sistema cardiovascular | *(null)* |
| hamstrings | 28 | isquiotibiales | hamstring |
| spine | 19 | columna | lower-back |
| traps | 15 | trapecios | trapezius |
| adductors | 6 | aductores | adductors |
| serratus anterior | 5 | serrato anterior | serratus |
| abductors | 5 | abductores | gluteal |
| levator scapulae | 2 | elevador de la escápula | trapezius |

All 29 `cardio` exercises have `tg = "cardiovascular system"`, and every exercise with that target is in `cardio`.

**`sm`, secondary muscles (40 values; the counts are occurrences)**

| sm | n | es | slug | | sm | n | es | slug |
|---|---|---|---|---|---|---|---|---|
| shoulders | 400 | hombros | deltoids | | ankles | 11 | tobillos | null |
| hamstrings | 289 | isquiotibiales | hamstring | | feet | 8 | pies | null |
| forearms | 277 | antebrazos | forearm | | rotator cuff | 6 | manguito rotador | deltoids |
| triceps | 268 | tríceps | triceps | | latissimus dorsi | 5 | dorsal ancho | upper-back |
| biceps | 194 | bíceps | biceps | | ankle stabilizers | 4 | estabilizadores de tobillo | null |
| quadriceps | 161 | cuádriceps | quadriceps | | soleus | 4 | sóleo | calves |
| calves | 147 | gemelos | calves | | wrists | 3 | muñecas | forearm |
| glutes | 136 | glúteos | gluteal | | upper chest | 3 | pecho superior | chest |
| core | 94 | core | abs | | wrist flexors | 2 | flexores de muñeca | forearm |
| chest | 91 | pecho | chest | | wrist extensors | 2 | extensores de muñeca | forearm |
| hip flexors | 77 | flexores de cadera | hip-flexors | | abdominals | 2 | abdominales | abs |
| obliques | 72 | oblicuos | obliques | | sternocleidomastoid | 2 | esternocleidomastoideo | null |
| lower back | 71 | zona lumbar | lower-back | | hands | 2 | manos | null |
| rhomboids | 54 | romboides | upper-back | | groin | 1 | ingle | adductors |
| trapezius | 47 | trapecio | trapezius | | grip muscles | 1 | agarre | forearm |
| upper back | 37 | espalda alta | upper-back | | lower abs | 1 | abdominales inferiores | abs |
| traps | 33 | trapecios | trapezius | | lats | 1 | dorsales | upper-back |
| deltoids | 28 | deltoides | deltoids | | inner thighs | 1 | cara interna del muslo | adductors |
| rear deltoids | 20 | deltoides posterior | deltoids | | shins | 1 | espinillas | tibialis |
| brachialis | 14 | braquial | biceps | | | | | |
| back | 11 | espalda | upper-back | | | | | |

**`mg` (29 values, all equal to `sm[0]`):** shoulders 191, forearms 165, biceps 164, triceps 161, hamstrings 127, quadriceps 110, glutes 71, obliques 67, hip flexors 66, chest 53, trapezius 36, traps 32, deltoids 24, calves 11, ankles 11, core 7, lower back 6, rotator cuff 4, soleus 4, rhomboids 2, wrist flexors 2, latissimus dorsi 2, abdominals 2, ankle stabilizers 1, upper back 1, wrist extensors 1, lats 1, wrists 1, hands 1.

**Cardio exercises (29, `id:name:eq`):** 3220 astride jumps (male), 3672 back and forth step, 3360 bear crawl, 1160 burpee, 2331 cycle cross trainer (leverage machine), 1201 dumbbell burpee (dumbbell), 3221 half knee bends (male), 3636 high knee against wall, 0501 jack burpee, 3224 jack jump (male), 2612 jump rope (rope), 0630 mountain climber, 3638 push to run, 0685 run, 0684 run (equipment), 3219 scissor jumps (male), 3222 semi squat jump (male), 3656 short stride run, 3361 skater hops, 3671 ski step, 3223 star jump (male), 2138 stationary bike run v. 3 (stationary bike), 0798 stationary bike walk (leverage machine), 3318 swing 360, 2141 walk elliptical cross trainer (elliptical machine), 3655 walking high knees lunge, 3666 walking on incline treadmill (leverage machine), 2311 walking on stepmill (stepmill machine), 3637 wheel run. Where no equipment is given, it is body weight.

**Neck exercises (2):** 1403 neck side stretch, 0716 side push neck stretch.

### 1.4 Three full example entries

```json
{"id":"0001","n":"3/4 sit-up","bp":"waist","eq":"body weight","tg":"abs","mg":"hip flexors",
 "sm":["hip flexors","lower back"],
 "st":["Lie flat on your back with your knees bent and feet flat on the ground.",
       "Place your hands behind your head with your elbows pointing outwards.",
       "Engaging your abs, slowly lift your upper body off the ground, curling forward until your torso is at a 45-degree angle.",
       "Pause for a moment at the top, then slowly lower your upper body back down to the starting position.",
       "Repeat for the desired number of repetitions."],
 "img":"0001-2gPfomN.jpg","gif":"0001-2gPfomN.gif"}
```

```json
{"id":"0025","n":"barbell bench press","bp":"chest","eq":"barbell","tg":"pectorals","mg":"triceps",
 "sm":["triceps","shoulders"],
 "st":["Lie flat on a bench with your feet flat on the ground and your back pressed against the bench.",
       "Grasp the barbell with an overhand grip slightly wider than shoulder-width apart.",
       "Lift the barbell off the rack and hold it directly above your chest with your arms fully extended.",
       "Lower the barbell slowly towards your chest, keeping your elbows tucked in.",
       "Pause for a moment when the barbell touches your chest.",
       "Push the barbell back up to the starting position by extending your arms.",
       "Repeat for the desired number of repetitions."],
 "img":"0025-EIeI8Vf.jpg","gif":"0025-EIeI8Vf.gif"}
```

```json
{"id":"3220","n":"astride jumps (male)","bp":"cardio","eq":"body weight","tg":"cardiovascular system","mg":"quadriceps",
 "sm":["quadriceps","hamstrings","calves"],
 "st":["Stand with your feet shoulder-width apart.",
       "Bend your knees and lower your body into a squat position.",
       "Jump explosively upwards, extending your legs and arms.",
       "While in the air, spread your legs apart and bring your arms out to the sides.",
       "Land softly with your feet shoulder-width apart, bending your knees to absorb the impact.",
       "Repeat for the desired number of repetitions."],
 "img":"3220-f9lVSSI.jpg","gif":"3220-f9lVSSI.gif"}
```

Example of a non-obvious name: `2330` is `"cable lat pulldown full range of motion"` (back, cable, lats, sm `["biceps","rhomboids","rear deltoids"]`). It is the import alias for "lat pulldown".

### 1.5 Data quirks the port must know about

- **Mojibake in 4 names** (they come from upstream): `0738 "sled 45в° calf press"`, `0739 "sled 45в° leg press"`, `1464 "sled 45в° leg press (back pov)"` and `0740 "sled 45в° leg wide press"`. The intended character is `°`; `1465 "sled 45° leg press (side pov)"` is correct. The import alias "leg press" resolves to `0739`, so a display name shows `в°`. **Open question:** fix the display name only, and keep the matcher's normalisation identical? In `wordsOf`, `в` and `°` are both stripped, so `sled 45 leg press` stays the same either way.
- **Six duplicated names**, which are different ids with the same `n`: 0088/1371 "barbell seated calf raise", 0454/1628 "ez barbell spider curl", 0577/0576 "lever chest press", 0655/0656 "push-up (on stability ball)", 0697/1766 "self assisted inverse leg curl", 0763/1394 "smith reverse calf raises". Custom-exercise duplicate checks compare against these names too.
- **18 word-bag collisions** in the import matcher (§9.5): different entries that normalise to the same sorted bag. The first one in array order wins. Most are "X" vs "weighted X", because `weighted` is a filler word. Full list: `barbell calf raise seated` (0088, 1371), `bar cable lateral pulldown` (0150, 2616), `decline sit up` (0282, 3670), `calf donkey raise` (0284, 0833), `drop push up` (1275, 1310), `close dumbbell grip press` (1731, 0296), `arm bench curl dumbbell incline one over standing` (0422, 1680), `barbell curl ez spider` (0454, 1628), `hanging hip leg raise` (1764, 0866), `chest lever press` (0577, 0576), `muscle up` (0631, 3286), `pull up` (0652, 0841), `ball on push stability up` (0655, 0656), `russian twist` (0687, 0846), `assisted curl inverse leg self` (0697, 1766), `sissy squat` (1489, 0851), `calf raise reverse smith` (0763, 1394), `bench dip three` (1753, 1754). The first id listed is the winner. In total there are 1,306 distinct bags for 1,324 entries.
- 40 names contain ` v. N`, 29 contain `(male)` and 4 contain `(female)`.

### 1.6 Regenerating from upstream

`data/exercises.json` upstream is 17,391,530 bytes. It is a JSON array of 1,324 objects with these keys: `id, name, category, body_part, equipment, instructions{en,es,it,tr,ru,zh,hi,pl,ko,fr}, instruction_steps{same langs: string[]}, muscle_group, secondary_muscles, target, image, gif_url, media_id, created_at, attribution`. The mapping to EXDB is `n=name` (already lowercase upstream), `bp=body_part`, `eq=equipment`, `tg=target`, `mg=muscle_group`, `sm=secondary_muscles`, `st=instruction_steps.en`, `img=image.replace('images/','')` and `gif=gif_url.replace('videos/','')`. The repository has no script that builds `exercises-data.js`; it was produced once. `build-instructions.mjs` (§4.4) builds only the non-English packs.

---

## 2. `exercises.js` API: index, helpers and custom exercises

```js
export const EXIDX = {}                 // id -> exercise (built-ins + registered customs)
EXDB.forEach(e => { EXIDX[e.id] = e })
export const BODYPARTS = [...new Set(EXDB.map(e => e.bp))].sort()   // 10, code-unit order (see §1.3)
```

**`equipmentOf(list)`** returns the equipment values present in `list`, most common first. Ties are broken by the name in ascending code-unit order, and falsy `eq` is skipped:

```js
const c = {}; list.forEach(e => { if (e.eq) c[e.eq] = (c[e.eq] || 0) + 1 })
return Object.keys(c).sort((a, b) => c[b] - c[a] || (a < b ? -1 : 1))
```

Callers derive this list from the list **already filtered** by body part and search, so every chip has results behind it.

**Custom exercises** live in the synced state as `S.customEx` (an array). `registerCustom(list)` first removes the previously registered custom ids from `EXIDX`, then adds every entry in `list`. It is called on state load and on every state replace. `allExercises(S)` returns `[...(S.customEx || []), ...EXDB]`, with customs **first**.

Custom exercise shapes:

| Origin | Shape |
|---|---|
| User-created (`CustomExForm`) | `{ id: 'c' + uid(), n: <trimmed name as typed>, bp, desc: <trimmed, max 1000 chars>, tg: '', eq: 'custom', custom: true }` |
| Created by import (§9.7) | `{ id: 'im' + uid(), n: name.toLowerCase(), custom: true, eq: 'custom', tg: '', desc: '', bp }` |

Custom exercises have no `sm`, `st`, `img`, `gif` or `mg`. The UI checks `ex.custom` to show the Edit and Delete buttons.

`uid()` is `Date.now().toString(36) + Math.random().toString(36).slice(2, 7)`, which gives a string of roughly 13 base-36 characters. Treat it as an opaque string.

**`CustomExForm` validation, in order:**
1. `name.trim()` is empty → toast "Give it a name".
2. No body part chosen → "Pick a body part".
3. Duplicate check: `allExercises(S).find(e => e.n.toLowerCase() === name.toLowerCase() && e.id !== existing?.id)`. On a match, show the toast `“{0}” already exists` with the existing name.
4. `desc = desc.trim().slice(0, 1000)`.

An edit updates `n`, `bp` and `desc` in place. When `bp === 'cardio'`, the form shows the hint "Cardio exercises log time + speed instead of weight × reps."

**`deleteCustomEx(ex)`** refuses (toast "Finish your current workout first") while `S.active.entries` contains the id. Otherwise, after confirmation, it:
- filters the exercise out of `S.customEx`;
- removes it from every routine's `ex` and cleans up orphaned superset ids;
- **stamps the name into history** by setting `e.n = ex.n` on every workout entry with that id;
- runs `delete S.exWeights[id]`.

**Media URLs.** The base paths are set at build time: `IMG_BASE = VITE_IMG_BASE || 'img/'` and `GIF_BASE = VITE_GIF_BASE || 'gif/'`. Then `imgSrc(ex) = IMG_BASE + ex.img` and `gifSrc(ex) = GIF_BASE + ex.gif` (see §5).

**`isCardio(idOrEx)`**: resolve the argument (a string is looked up in `EXIDX`), then `?.bp === 'cardio'`. This decides the default logging mode (`cardio` means minutes and speed; otherwise weight × reps).

**`exOr(id)`** returns `EXIDX[id]`, or this placeholder, so a view never crashes on an unknown id:
```js
{ id, n: t('Unknown exercise'), bp: '', tg: '', eq: '', sm: [], st: [], missing: true }
```

### 2.1 Library and picker search (for UI parity)

These rules apply to both `Library.jsx` and `ExercisePicker` in `sheets.jsx`.

```js
const ql = q.toLowerCase().trim()
base = allExercises(S).filter(e => (!bp || e.bp === bp) &&
  (!ql || e.n.toLowerCase().includes(ql) || e.tg.includes(ql) || e.eq.includes(ql) || (e.desc || '').toLowerCase().includes(ql)))
eqOpts = equipmentOf(base)
eqOn = eqOpts.includes(eq) ? eq : ''          // drop an equipment filter that the search emptied
list = eqOn ? base.filter(e => e.eq === eqOn) : base
```

- Matching is a plain substring test against the **English** `n`, `tg`, `eq` and the custom `desc`. Translated labels are **not** searched (see the open questions).
- Pagination: the Library shows 40 results and adds 40 per "Show more"; the Picker uses 50. The count resets whenever the query or a filter changes.
- Choosing a body-part chip resets the equipment filter. The equipment chip row appears only when `eqOpts.length > 1`.
- The Picker has an extra "★ Chosen" filter (`bp === '★'`) that shows only exercises used in any routine or workout, sorted by usage count descending, then by `n` ascending.
- Each row shows `Thumb`, the capitalised `n`, the subtitle `t(e.tg || e.bp) · t(e.eq)`, and (Library only) the best weight tag.
- The Library header reads `t('{0} exercises with animations', EXDB.length)`, which gives 1,324. The Picker placeholder is `t('Search {0} exercises…', all.length)`, which includes customs.
- The first row of both lists is "Create your own exercise", which opens the form prefilled with the query.

**Exercise detail** shows, in order:
1. The capitalised name.
2. `Media`.
3. Tags: `t(bp)` (accent), `t(tg)` if set, `t(eq)`, and the first 3 `sm` values translated.
4. `desc`, for customs.
5. "Best: X unit · last <date>: <set labels>".
6. The button "Add to my plan".
7. For customs, Edit and Delete.
8. The 1RM widget when the exercise is not cardio.
9. "How to" with `instrFor(ex)` as an ordered list. When the UI language has no instruction pack, the header adds " · instructions in English".

---

## 3. `muscles.js`: muscle taxonomy and load

```js
export const MUSCLES = ['trapezius','deltoids','chest','upper-back','serratus','biceps','triceps','forearm',
  'abs','obliques','lower-back','gluteal','quadriceps','hamstring','adductors','hip-flexors','calves','tibialis']  // 18, head-to-toe order
export const INERT = ['head','hair','neck','hands','feet','knees','ankles']   // silhouette only, never shaded
export const MUSCLE_NAME = { trapezius:'Traps', deltoids:'Shoulders', chest:'Chest', 'upper-back':'Upper back',
  serratus:'Serratus', biceps:'Biceps', triceps:'Triceps', forearm:'Forearms', abs:'Abs', obliques:'Obliques',
  'lower-back':'Lower back', gluteal:'Glutes', quadriceps:'Quads', hamstring:'Hamstrings', adductors:'Adductors',
  'hip-flexors':'Hip flexors', calves:'Calves', tibialis:'Shins' }   // i18n keys
```

The Spanish `MUSCLE_NAME` labels are: Trapecio, Hombros, Pecho, Espalda alta, Serrato, Bíceps, Tríceps, Antebrazos, Abdominales, Oblicuos, Espalda baja, Glúteos, Cuádriceps, Isquiotibiales, Aductores, Flexores de cadera, Gemelos, Tibiales.

The **`ALIAS`** table maps a dataset spelling (lowercased and trimmed) to a slug, or to `null` for a muscle the map does not draw. The mapping appears in the "slug" columns of §1.3; the complete literal is:

```js
{ abs:'abs', pectorals:'chest', biceps:'biceps', glutes:'gluteal', delts:'deltoids', triceps:'triceps',
  'upper back':'upper-back', lats:'upper-back', calves:'calves', quads:'quadriceps', forearms:'forearm',
  hamstrings:'hamstring', spine:'lower-back', traps:'trapezius', adductors:'adductors',
  'serratus anterior':'serratus', abductors:'gluteal', 'levator scapulae':'trapezius', 'cardiovascular system':null,
  shoulders:'deltoids', deltoids:'deltoids', 'rear deltoids':'deltoids', 'rotator cuff':'deltoids',
  quadriceps:'quadriceps', core:'abs', abdominals:'abs', 'lower abs':'abs', chest:'chest', 'upper chest':'chest',
  'hip flexors':'hip-flexors', obliques:'obliques', 'lower back':'lower-back', rhomboids:'upper-back',
  trapezius:'trapezius', back:'upper-back', 'latissimus dorsi':'upper-back', brachialis:'biceps', soleus:'calves',
  shins:'tibialis', wrists:'forearm', 'wrist flexors':'forearm', 'wrist extensors':'forearm', 'grip muscles':'forearm',
  groin:'adductors', 'inner thighs':'adductors',
  ankles:null, feet:null, hands:null, 'ankle stabilizers':null, sternocleidomastoid:null }
```

Every `tg` and `sm` value in the dataset has an entry. A spelling that is not in the table (for example a future dataset change) evaluates to `undefined` and is silently dropped.

**`BY_BODYPART`** is the fallback used when nothing in the exercise is recognised (always the case for custom exercises). Within each group the weights sum to 1:

```js
{ chest:{chest:1}, back:{'upper-back':0.75,'lower-back':0.25}, shoulders:{deltoids:1},
  'upper arms':{biceps:0.5,triceps:0.5}, 'lower arms':{forearm:1}, waist:{abs:0.7,obliques:0.3},
  'upper legs':{quadriceps:0.4,hamstring:0.35,gluteal:0.25}, 'lower legs':{calves:0.8,tibialis:0.2},
  neck:{trapezius:1}, cardio:{} }
```

`SECONDARY = 0.4`.

```js
function musclesOf(ex) {               // -> { slug: weight 0..1 }
  if (!ex) return {}
  const out = {}
  const add = (name, w) => { const slug = ALIAS[String(name||'').toLowerCase().trim()]; if (slug) out[slug] = Math.max(out[slug]||0, w) }
  add(ex.tg, 1); (ex.sm || []).forEach(m => add(m, SECONDARY))
  if (!Object.keys(out).length) Object.assign(out, BY_BODYPART[ex.bp] || {})
  return out
}
```

Two consequences. A primary muscle is never downgraded by a secondary (the `max`). A cardio exercise gets its secondaries at 0.4 and nothing for `tg`, because `cardiovascular system` maps to null.

- **`loadOf(items)`**: `items` is `[{id, sets}]`. Skip items where `!sets`. Otherwise `load[slug] += musclesOf(EXIDX[id])[slug] * sets`. The unit is "effective sets"; volume in kg is deliberately **not** used.
- **`loadOfWorkouts(workouts, pick?)`** counts, per entry, `sets.filter(s => s.done && (!pick || pick(s))).length`.
- **`loadOfRoutine(r)`** uses `c.sets || 1` for each `r.ex` item.
- **`loadOfActive(active)`** counts the done sets of the workout in progress.
- **`levelsOf(load)`**: take `max = Math.max(0, ...MUSCLES.map(m => load[m]||0))`. For each muscle, `lv = !v ? 0 : max<=0 ? 0 : clamp(ceil(v/max*4), 1, 4)`, which gives levels 0–4, relative to the most-worked muscle.
- **`rankOf(load)`** returns `{ worked: MUSCLES.filter(load>0).sort(desc by load), missed: MUSCLES.filter(!(load>0)) }`. **The sort must be stable** (JS `Array.prototype.sort` is), so ties stay in `MUSCLES` order. Dart's `List.sort` is not stable: use `mergeSort` from `package:collection` or sort by `(−load, MUSCLES.indexOf)`.

**Golden vectors:**

| id | musclesOf |
|---|---|
| 0025 barbell bench press | `{chest:1, triceps:0.4, deltoids:0.4}` |
| 0043 barbell full squat | `{gluteal:1, quadriceps:0.4, hamstring:0.4, calves:0.4, abs:0.4}` |
| 0032 barbell deadlift | `{gluteal:1, hamstring:0.4, lower-back:0.4}` |
| 2330 cable lat pulldown… | `{upper-back:1, biceps:0.4, deltoids:0.4}` |
| 3220 astride jumps (cardio) | `{quadriceps:0.4, hamstring:0.4, calves:0.4}` |
| 1403 neck side stretch | `{trapezius:1}` |
| 0001 3/4 sit-up | `{abs:1, hip-flexors:0.4, lower-back:0.4}` |
| 0294 dumbbell biceps curl | `{biceps:1, forearm:0.4}` |
| custom `{bp:'upper legs', tg:''}` | `{quadriceps:0.4, hamstring:0.35, gluteal:0.25}` |
| custom `{bp:'cardio'}` | `{}` |

`loadOf([{id:'0025',sets:4},{id:'0043',sets:3},{id:'2330',sets:3}])` gives:
- **load:** `{chest:4, triceps:1.6, deltoids:2.8, gluteal:3, quadriceps:1.2, hamstring:1.2, calves:1.2, abs:1.2, upper-back:3, biceps:1.2}`. These are float sums; compare with a tolerance.
- **levelsOf:** trapezius 0, deltoids 3, chest 4, upper-back 3, serratus 0, biceps 2, triceps 2, forearm 0, abs 2, obliques 0, lower-back 0, gluteal 3, quadriceps 2, hamstring 2, adductors 0, hip-flexors 0, calves 2, tibialis 0.
- **rankOf:** `worked = [chest, upper-back, gluteal, deltoids, triceps, biceps, abs, quadriceps, hamstring, calves]` and `missed = [trapezius, serratus, forearm, obliques, lower-back, adductors, hip-flexors, tibialis]`.

The body-map SVG geometry is in `body-paths.js` (MuscleMap, MIT) and is outside this spec.

---

## 4. Internationalisation (`i18n.js`, `locales/`, `instr/`)

### 4.1 Languages

```js
LANGS = { en:'English', de:'Deutsch', es:'Español', fr:'Français', it:'Italiano', pt:'Português', pl:'Polski',
          tr:'Türkçe', ru:'Русский', zh:'中文', ko:'한국어', hi:'हिन्दी' }                     // 12 UI languages
INSTR_LANGS = ['en','es','fr','it','tr','ru','zh','hi','pl','ko']                      // de and pt: instructions stay English
DATE_LOCALES = { en:'en-GB', de:'de-DE', es:'es-ES', fr:'fr-FR', it:'it-IT', pt:'pt-PT', pl:'pl-PL',
                 tr:'tr-TR', ru:'ru-RU', zh:'zh-CN', ko:'ko-KR', hi:'hi-IN' }            // default 'en-GB'
```

The language is stored in the synced state as `S.lang` (default `'en'`). The Settings picker lists `LANGS`. For a language that is not in `INSTR_LANGS`, it adds the subtitle "Exercise instructions aren't available in this language yet — they stay in English."

### 4.2 `t(s, ...args)`

- **The key is the English source string.** `t(s)` returns `dict[s] || s`, so a missing key falls back to English.
- Placeholders `{0}`, `{1}`, … are replaced with `args[i]` using `replaceAll`, including on the English fallback. Numbers are stringified.
  - JS quirk: `String.replaceAll` treats `$&`, `$1` and similar in the replacement as patterns. The port should do a plain literal replace, which is fine.
- **Plurals are separate keys**, for example `t(n === 1 ? '{0} exercise' : '{0} exercises', n)`.
- Taxonomy values are keys too: the UI calls `t(e.bp)`, `t(e.eq)`, `t(e.tg)` and `t(sm)`, and `t('custom')` gives "propio".

`locales/<lang>.js` is `export default { 'English string': 'translation', ... }`. Each of the 11 files has 781 keys (46–77 KB each). For Flutter, the recommendation is to convert each file to a JSON map (`assets/i18n/es.json`) and keep the same English-key lookup, so the strings port unchanged. The UI strings this subsystem uses, with their Spanish values, are listed in §9.12 and in the appendix.

### 4.3 Instructions per language

- `instrFor(ex) = (instr && instr[ex.id]) || ex.st || []`. When the current language has a pack, its steps are used; otherwise the English `st` steps, or `[]` for customs.
- `setLang(l)`:
  1. An unknown `l` becomes `'en'`.
  2. If the language is unchanged and something has already loaded, return.
  3. Otherwise lazy-load the locale dictionary and, if the language is in `INSTR_LANGS` and is not `'en'`, the instruction pack.
  4. If loading fails, both are reset to English.
  5. Subscribers are notified; React uses `useSyncExternalStore`.

**Pack format** (`frontend/src/instr/<lang>.js`): `// generated by scripts/build-instructions.mjs — do not edit\nexport default {"<id>":["step",...],...}`.

| lang | bytes | ids |
|---|---|---|
| es | 718,996 | 1324 |
| fr | 713,854 | 1324 |
| it | 682,804 | 1324 |
| tr | 732,549 | 1324 |
| ru | 1,056,970 | 1324 |
| zh | 481,572 | 1324 |
| hi | 1,585,040 | 1324 |
| pl | 655,377 | 1324 |
| ko | 658,228 | 1324 |

Every pack covers **all 1,324 ids**, and for every id the step count is the same as in English `st`. Key order in the file is irrelevant: JS puts integer-like keys such as `"1000"` first, and keys with a leading zero such as `"0001"` keep insertion order. Treat the pack as a map.

Example, `es["0025"]`:
```json
["Túmbate sobre un banco con los pies apoyados en el suelo y la espalda presionada contra el banco.",
 "Agarra la barra con un agarre pronado un poco más ancho que la separación de los hombros.",
 "Levanta la barra del soporte y sostenla directamente sobre el pecho con los brazos completamente extendidos.",
 "Baja la barra lentamente hacia el pecho, manteniendo los codos pegados al cuerpo.",
 "Haz una pausa breve cuando la barra toque el pecho.",
 "Empuja la barra de vuelta a la posición inicial extendiendo los brazos.",
 "Repite el número de repeticiones deseado."]
```

**Exercise names are not translated**, either upstream or in openGym. There is no `name_es`.

### 4.4 `scripts/build-instructions.mjs`

`node scripts/build-instructions.mjs [path-to-exercises.json]`. With no argument, it fetches `https://raw.githubusercontent.com/hasaneyldrm/exercises-dataset/main/data/exercises.json`. That URL tracks **main**, not the pinned commit.

For each lang in `['es','fr','it','tr','ru','zh','hi','pl','ko']`:
- The pack is `pack[ex.id] = ex.instruction_steps[lang]` for each exercise where that array is non-empty.
- It is written to `frontend/src/instr/<lang>.js` with the header comment shown in §4.3.

### 4.5 Date and number formatting (context)

- `fmtNum(n) = (Math.round(n*10)/10).toLocaleString(DATE_LOCALES[lang])`. For example, `setLabel` renders `"60×10 (RIR 2)"`.
- `fmtDate(iso, long)` uses `toLocaleDateString(dateLocale(), long ? {weekday:'short', day:'numeric', month:'short'} : {day:'numeric', month:'short'})` on `iso + 'T12:00:00'`.
- In Dart, use `intl` `NumberFormat` and `DateFormat` with the same locale ids.

---

## 5. Exercise media (JPG stills and GIF animations)

### 5.1 Locating media by id

For an exercise, `img = "<id>-<media_id>.jpg"` and `gif = "<id>-<media_id>.gif"`. The `media_id` **cannot be derived from the id**, so the file name must be stored per exercise. It is included in the exported JSON as `mediaId`, `img` and `gif`. Custom exercises have neither field.

Upstream layout: `images/<img>` holds the stills and `videos/<gif>` holds the animations. Both are 180×180 px; the JPG is JFIF baseline, 3 components.

Where openGym serves them from:

| Build | Still | Animation |
|---|---|---|
| Self-hosted (docker) | `img/<img>`, served by nginx from the bind mount `./media/img` | `gif/<gif>` from `./media/gif` |
| Demo (GitHub Pages) and native mobile build (`build:mobile`, Capacitor) | `https://cdn.jsdelivr.net/gh/hasaneyldrm/exercises-dataset@7455efae41b330c265e7cd4b78dfa848e7ce5ebd/images/<img>` | `…@7455efae…/videos/<gif>` |
| Vite dev server | Proxies `/img` and `/gif` to `MEDIA_TARGET` (default `http://127.0.0.1:8888`) | same |

The jsDelivr responses carry `access-control-allow-origin: *` and `cache-control: public, max-age=31536000, s-maxage=31536000, immutable`, with `content-type: image/gif` or `image/jpeg`.

**Size.** The repo docs say "~140 MB" for the media. I measured 21 files spread across the catalogue (every 66th): the average JPG is 6,341 B and the average GIF is 93,296 B. That puts the total at about 8 MB of JPG plus about 117 MB of GIF, roughly 125 MB for 1,324 × 2 files. Example: `0025-EIeI8Vf.gif` is 124,389 B. (The jsDelivr package API refuses to list the package because it is over 50 MB, so no exact total was available.)

**How media is fetched:**
- `docker-compose.yml`, `media` service (image `alpine/git`, runs once): if `/out/img` is empty, it runs `git clone --depth 1 https://github.com/hasaneyldrm/exercises-dataset /tmp/ds`, then `cp images/*.jpg → ./media/img` and `videos/*.gif → ./media/gif`. Note that this clones **main**, not the pinned commit. `web` depends on the service completing successfully and mounts both directories read-only at `/usr/share/nginx/html/img` and `/gif`.
- `scripts/fetch-media.sh` does the same manually into `./media/img` and `./media/gif`.

### 5.2 `Media.jsx` behaviour

- **`<Media ex compact? minimizable? id?>`**:
  - Returns nothing when `!ex.gif`, which covers customs.
  - Autoplays the GIF (`playing = true`). A tap toggles `playing`: when not playing it shows the JPG still, which is how "pause" works.
  - The hint reads "tap to pause" or "tap to play", with a pause or play icon.
  - With `minimizable` (the workout view), a button toggles the persisted setting `S.gifSize` between `'full'` (the default) and `'mini'`. The labels are "Minimize" and "Expand". In mini mode the hint is hidden, and the size carries over across exercises and workouts.
  - `compact` is a smaller variant used in superset cards.
- **`<Thumb ex>`**: `<img loading=lazy src=imgSrc(ex)>`. When there is no `img`, it shows a placeholder tile with the `dumbbell` icon.
- **In Flutter:**
  - Use `Image.network` or `cached_network_image` for the JPG.
  - For "pause", swap to the JPG rather than trying to pause the GIF.
  - Keep `gifSize` in synced settings.

### 5.3 License (important for a redistributed mobile app)

- **Upstream `LICENSE` at the pinned commit:** MIT covers the code, tooling, dataset structure and **instruction text and translations**. A **MEDIA EXCEPTION** says the images and GIFs are **© Gym visual (https://gymvisual.com/)**. They are included in the dataset with the rights holder's written permission, **only at 180×180**, and every use must carry the attribution **"© Gym visual — https://gymvisual.com/"**. Reuse is governed by Gym visual's Terms (https://gymvisual.com/content/3-terms-and-conditions-of-use), not by MIT. Cloning the repository grants no licence to the media.
- **openGym `NOTICE.md`:** the names, instructions (English in `exercises-data.js`, other languages in `src/instr/`), images and animations come from hasaneyldrm/exercises-dataset and are **not** covered by openGym's AGPL. The media is not distributed in the repository; it is downloaded on first run. Anyone redistributing with the media included should review the upstream licence first. `NOTICE.md` also includes an AGPL §7 app-store exception and the MIT notice for MuscleMap (the body-map paths).
- **Discrepancy:** `fetch-media.sh`, `docker-compose.yml` and the Settings footer (`exercise data: hasaneyldrm/exercises-dataset (CC)`) all say "CC", which is **wrong** for the pinned commit. openGym's UI **does not show the Gym visual attribution anywhere**.
- **What the port must do:**
  - Show "© Gym visual — https://gymvisual.com/" wherever the media appears, or at least on an About screen together with the dataset credit.
  - Never upscale or re-encode the media above 180×180.
  - Prefer hotlinking the pinned jsDelivr URLs, as openGym's own mobile build does, over mirroring the files into R2. Mirroring means redistributing, which needs Gym visual's permission. See the open questions.
- **The instruction text is MIT.** It is fine to seed D1 with it or bundle it as a Flutter asset.
- **openGym's own code is AGPL-3.0**, and a port of its logic is a derivative work. Open question: will the new app be AGPL too?

---

## 6. `glyphs.js`: routine icons

Routines store an icon **key** in the field `r.emoji` (the name is historic). `glyphOf(v)` also accepts a legacy emoji.

```js
DEFAULT_GLYPH = 'figureStrength'
GLYPH_GROUPS = [ {key:'Strength',  items:['figureStrength','arm','abs','legs','pullup']},
                 {key:'Equipment', items:['dumbbell','barbell','kettlebell','plate','machine']},
                 {key:'Cardio',    items:['figureRun','bike','swim','boxing','timer']},
                 {key:'Recovery',  items:['stretch','moon','heart','flame','bolt']} ]   // group keys are i18n keys (es: Fuerza, Equipo, Cardio, Recuperación)
GLYPHS = GLYPH_GROUPS.flatMap(g => g.items)   // 20, the picker offers only these
```

`LEGACY` maps emoji to a key:

```
💪→arm 🦾→arm 🫸→figureStrength 🫷→pullup 🏋️→dumbbell 🏋→dumbbell 🏋️‍♀️→dumbbell 🦵→legs 🍑→legs
🔥→flame ⚡→bolt 💥→bolt 🧨→bolt 😤→flame 🏃→figureRun 🏃‍♀️→figureRun 🚴→bike 🏊→swim
🤸→stretch 🧘→stretch 🧘‍♀️→stretch 🥊→boxing 🧗→pullup ⛰️→figureRun 🏔️→figureRun 🚀→bolt
🎯→target 🏆→trophy 🥇→medal ⭐→star 🌟→star 👑→crown 🛡️→shield ⚔️→shield ❤️‍🔥→heart
🦍→kettlebell 🐂→barbell 🐻→kettlebell 🦁→boxing 🐺→figureRun 🦈→swim 🤖→machine
```

```js
function glyphOf(v) {
  if (!v) return DEFAULT_GLYPH
  if (ICON_NAMES.includes(v)) return v            // ANY icon name passes, not only GLYPHS
  if (LEGACY[v]) return LEGACY[v]
  const base = [...v].filter(c => c !== '️' && c !== '‍')[0]   // first code point, ignoring VS16 and ZWJ
  return LEGACY[base] || DEFAULT_GLYPH
}
```

`ICON_NAMES` (from `Icon.jsx`, 77 names): house calendar chart magnifier gear dumbbell barbell figureRun figureStrength scale flame timer clock trophy medal target star starFill crown bolt shield heart rocket sparkles lightbulb arm abs legs pullup kettlebell plate machine bike swim boxing stretch plus minus check checkCircle xmark pencil trash link play pause reset bell bellSlash chevronRight chevronLeft chevronDown chevronUp arrowUp arrowDown expand minimize person personCircle clipboard list folder globe moon sun key lock download upload wrench flag chartLine dot history signOut shuffle info.

In Flutter, map each key to an icon (Material, Cupertino or custom SVG). Claude, through the MCP server, should be told to pick from the 20 `GLYPHS`.

---

## 7. Coach library (`api/coach/library.json`)

`scripts/build-coach-library.mjs` has two modes: write, and `--check` (for CI). `--check` exits with status 1 and the message "api/coach/library.json is out of date — run: node scripts/build-coach-library.mjs" when the file is stale.

The script produces exactly:

```js
JSON.stringify({ generated_from: 'frontend/src/lib/exercises-data.js', count: EXDB.length,
                 exercises: EXDB.map(e => ({ id: e.id, n: e.n, bp: e.bp, tg: e.tg, eq: e.eq })) }) + '\n'
```

The committed file is 125,794 B, holds 1,324 entries in EXDB order, and is currently in sync (verified). It leaves out instructions, images and secondary muscles ("they would quadruple a payload the model has no use for").

Three examples:
```json
{"id":"0001","n":"3/4 sit-up","bp":"waist","tg":"abs","eq":"body weight"}
{"id":"0002","n":"45° side bend","bp":"waist","tg":"abs","eq":"body weight"}
{"id":"0003","n":"air bike","bp":"waist","tg":"abs","eq":"body weight"}
```

Consumers in `api/coach/payload.js`:
- `LIB_BY_ID = new Map(...)`.
- `libraryHas(id)` and `libraryName(id)`; `validate.js` rejects a proposal that references an id which is neither in the library nor one of the user's `customEx` ids.
- `librarySlice(S, equipment)`: `wanted` is the list of lowercased equipment strings, and customs are mapped to `{id, n, bp, tg:null, eq:'custom', custom:true}`. If `wanted` is non-empty, `base` is the library filtered to those equipment values; otherwise `base` is the whole library. The function returns `[...customs, ...(base.length ? base : LIBRARY)]`, falling back to the full library when the filter matches nothing.

**Port:** seed a D1 table `exercises` from `exercises.json` (§10). The MCP server can then offer something like `search_exercises(query, bodyPart?, equipment?, target?)` that returns `{id, name, bodyPart, target, equipment}`, and validate every exercise id in a plan Claude writes against it plus the user's customs.

---

## 8. Serving (`web/nginx.conf`, `docker-compose.yml`) and the Cloudflare equivalent

`nginx.conf` has one server listening on `:80` with root `/usr/share/nginx/html`:

- `location /api/` → `proxy_pass http://api:3000`, HTTP/1.1, with `Host`, `X-Real-IP`, `X-Forwarded-For` and `X-Forwarded-Proto` set. This keeps the API on the same origin, which WebAuthn passkeys require.
- `location /` → `try_files $uri $uri/ /index.html`, the SPA fallback.
- `location ~* \.(js|css|json|html)$` → `Cache-Control: no-cache, must-revalidate`.
- `location ~* \.(png|jpg|jpeg|gif|ico|svg|woff|woff2|webp|avif)$` → `expires 30d` and `Cache-Control: public, max-age=2592000, immutable`.
- gzip is on for text/plain, css, json, javascript and svg, with `gzip_min_length 1024`.
- Latent quirk: regex locations beat the non-`^~` prefix `/api/`, so an API path ending in `.json` would be served statically instead of proxied.

`docker-compose.yml` defines three services:
- `media`: the one-time clone described in §5.
- `api`: `ghcr.io/duartesantos8/opengym-api`, `PORT=3000`, `DATA_DIR=/data`, `COACH_CODEX_HOME=/codex`, with volumes `./data:/data` and `./data/codex:/codex`.
- `web`: nginx plus the built SPA, on port `${WEB_PORT:-8080}:80`, with the media bind mounts.

**Cloudflare mapping:**
- The API becomes a Worker. Same-origin is no longer needed: a Flutter app is not a browser origin, and auth will be token or OAuth, not passkeys.
- The static catalogue becomes a bundled Flutter asset plus a D1 seed.
- The media becomes the pinned jsDelivr URLs, or R2 with `Cache-Control: public, max-age=31536000, immutable` if the licence question is resolved.

---

## 9. History import (`import-csv.js`)

The importer is pure logic. It never touches state until `mergeImport`, and a bad row never throws: it is counted and skipped. In the original, the entry point is Settings → Data → **"Import from another app"**, with the subtitle "FitNotes, Strong, Hevy — or body weight from Apple Health". The file input accepts `.csv,.xml,text/csv,text/xml`, and the file is read as UTF-8 text.

### 9.1 Dispatch: `parseImport(text, {unit})`

`unit` is the profile unit, `'kg'` or `'lb'`.

```js
if (s.includes('HKQuantityTypeIdentifier') || /^\s*</.test(s)) return parseBodyweight(s, opts)   // XML
const asWorkouts = parseWorkoutCSV(s, opts); if (!asWorkouts.error) return asWorkouts
const asWeights = parseBodyweight(s, opts);  return asWeights.error ? asWorkouts : asWeights       // weight-only CSV
```

It returns one of three things: a workouts result, a bodyweight result, or `{error:'empty'|'unrecognised'}`. The UI maps them like this:

| Result | Toast (es) |
|---|---|
| An exception | "Could not read that file" (No se pudo leer ese archivo) |
| `empty` | "That file is empty" (Ese archivo está vacío) |
| Any other error | "That file's columns aren't recognised — see the docs for supported apps." (No se reconocen las columnas del archivo — consulta la documentación.) |
| Zero workouts or zero weigh-ins | "Nothing to import from that file" (No hay nada que importar de ese archivo) |
| Anything else | Opens the summary sheet (§9.12) |

### 9.2 `parseCSV(text)`: an RFC-4180-ish state machine

- Strip one leading BOM (U+FEFF).
- Quoted fields may contain commas, CR/LF, and `""` for an escaped quote. A quote character starts quoting **anywhere** in a field, not only at its start.
- An unquoted `\n`, `\r` or `\r\n` ends a row.
- Rows where every field is `''` are dropped, including blank lines and `,` lines.
- The last row is pushed at EOF if it is non-empty.
- The separator is always `,`: no semicolon or tab detection. Fields are **not** trimmed here.

```js
for (let i = 0; i < s.length; i++) { const c = s[i]
  if (quoted) { if (c === '"') { if (s[i+1] === '"') { field += '"'; i++ } else quoted = false } else field += c }
  else if (c === '"') quoted = true
  else if (c === ',') { row.push(field); field = '' }
  else if (c === '\n' || c === '\r') { if (c === '\r' && s[i+1] === '\n') i++; row.push(field); field = ''; if (row.some(x => x !== '')) rows.push(row); row = [] }
  else field += c }
row.push(field); if (row.some(x => x !== '')) rows.push(row)
```

Golden vectors:

| Input | Output |
|---|---|
| `a,b\n1,2` | `[["a","b"],["1","2"]]` |
| `﻿a,b\r\n"x, y","he said ""hi"""\r\n` | `[["a","b"],["x, y","he said \"hi\""]]` |
| `a,b\n\n,\n3,4` | `[["a","b"],["3","4"]]` |
| `"multi\nline",2\n` | `[["multi\nline","2"]]` |

### 9.3 Header normalisation, column map, source detection

`norm(h) = h.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim()`. For example `Weight (kg)` becomes `weight kg`, `exercise_title` becomes `exercise title`, and `Set Order` becomes `set order`.

`COLUMNS` is ordered. The **first field whose alias list contains the normalised header, and which is not yet mapped**, takes that column index. Each column maps to at most one field.

| field | normalised aliases |
|---|---|
| exercise | `exercise`, `exercise name`, `exercise title` |
| date | `date`, `workout date` |
| startTime | `start time` |
| endTime | `end time` |
| workoutName | `workout name`, `title` |
| category | `category`, `body part`, `muscle group` |
| weightKg | `weight kg` |
| weightLb | `weight lbs`, `weight lb` |
| weight | `weight` |
| weightUnit | `weight unit`, `unit` |
| reps | `reps`, `repetitions` |
| rpe | `rpe`, `rpe rating` |
| rir | `rir`, `reps in reserve` |
| distanceKm | `distance km` |
| distance | `distance` |
| distanceUnit | `distance unit` |
| seconds | `seconds`, `duration seconds` |
| time | `time`, `duration` |
| setType | `set type` |
| note | `comment`, `comments`, `notes`, `note` (mapped but **never used**) |

`detectSource(header)` works on the normalised headers and returns the first match:

1. `exercise title` and `set index` → **"Hevy"**
2. `exercise name` and `set order` → **"Strong"**
3. `exercise` and `kind` → **"FitNotes (iOS)"**
4. `exercise` and `weight unit` → **"FitNotes"**
5. `exercise` and `category` → **"FitNotes"**
6. Otherwise `null`, and the summary title becomes "Import history".

### 9.4 Supported formats: real header rows and their mapping

| App | Header (verbatim) | Resulting map (column index) |
|---|---|---|
| FitNotes (Android) | `Date,Exercise,Category,Weight,Weight Unit,Reps,Distance,Distance Unit,Time,Comment` | `{date:0, exercise:1, category:2, weight:3, weightUnit:4, reps:5, distance:6, distanceUnit:7, time:8, note:9}`; source "FitNotes" |
| FitNotes 2 (iOS) | `Date,Exercise,Category,Weight (kg),Weight (lbs),Reps,Distance,Distance Unit,Time,Notes,Kind` | `{date:0, exercise:1, category:2, weightKg:3, weightLb:4, reps:5, distance:6, distanceUnit:7, time:8, note:9}` (Kind is used only for detection); source "FitNotes (iOS)" |
| Strong | `Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE` | `{date:0, workoutName:1, time:2, exercise:3, weight:5, reps:6, distance:7, seconds:8, note:9, rpe:11}`; source "Strong". **`Duration` (the workout length, e.g. `2h 38m`) lands in `time`.** |
| Hevy | `title,start_time,end_time,description,exercise_title,superset_id,exercise_notes,set_index,set_type,weight_kg,reps,distance_km,duration_seconds,rpe` | `{workoutName:0, startTime:1, endTime:2, exercise:4, setType:8, weightKg:9, reps:10, distanceKm:11, seconds:12, rpe:13}`; source "Hevy". `description`, `superset_id` and `exercise_notes` are ignored. An imperial Hevy export's `weight_lbs` maps to `weightLb`. |
| Generic (Lyfta, spreadsheets) | Any header containing a date (or start time) column and an exercise column | Loose matching as above |
| Apple Health | `export.xml`, `<Record type="HKQuantityTypeIdentifierBodyMass" … unit="kg\|lb" value="…" startDate="…"/>` | Body weight only (§9.10) |
| Weight-only CSV | A date (or start time) column and a `weight`, `weight kg` or `weight lbs` column, with no exercise column | Body weight (§9.10) |

Typical date formats: FitNotes writes `YYYY-MM-DD`, Strong writes `YYYY-MM-DD HH:MM:SS`, and Hevy writes `12 Jan 2026, 18:00`.

### 9.5 Exercise name matching

**Normalisation (`wordsOf`):**

```js
let k = String(name||'').toLowerCase().replace(/[()[\]]/g, ' ').replace(/[^a-z0-9]+/g, ' ').trim()
SYN.forEach(([re, to]) => { k = k.replace(re, to) })            // applied IN ORDER, each is global (/g)
return k.split(' ').filter(w => w && !FILLER.has(w))
```

**`SYN`, in this order.** `\b` is a JS word boundary; after the previous step the string contains only `[a-z0-9 ]`.

| # | Pattern | Replacement |
|---|---|---|
| 1 | `\bbb\b` | `barbell` |
| 2 | `\bdb\b` | `dumbbell` |
| 3 | `\bkb\b` | `kettlebell` |
| 4 | `\bohp\b` | `overhead press` |
| 5 | `\bbw\b` | `body weight` |
| 6 | `\bbodyweight\b` | `body weight` |
| 7 | `\bmachine\b` | `lever` |
| 8 | `\bsmith machine\b` | `smith` (**never fires**, because #7 already turned `machine` into `lever`) |
| 9 | `\bez bar\b` | `ez barbell` |
| 10 | `\bpull ups?\b` | `pull up` |
| 11 | `\bchin ups?\b` | `chin up` |
| 12 | `\bpush ups?\b` | `push up` |
| 13 | `\bsit ups?\b` | `sit up` |
| 14 | `\bdips?\b` | `dip` |
| 15 | `\braises?\b` | `raise` |
| 16 | `\bcurls?\b` | `curl` |
| 17 | `\bpresses\b` | `press` |
| 18 | `\bextensions?\b` | `extension` |
| 19 | `\bcables?\b` | `cable` |
| 20 | `\bseated\b` | `seated` (no-op) |
| 21 | `\bassisted\b` | `assisted` (no-op) |

`FILLER = {the, a, with, and, v, variation, version, pulley, weighted}`. The `v` entry covers names like "v. 2", where the `2` survives.

`keyOf(name) = wordsOf(name).sort().join(' ')` is a sorted bag of words, compared with plain JS code-unit string sort. Duplicate words are kept.

**Indexes**, built lazily and once, over `EXDB` in array order:
- `exact`: `Map<bag, id>`, where the **first** id with a given bag wins (§1.5).
- `all`: `[{id, set: Set(words), n: words.length}]`. Here `n` counts words **including duplicates**, while `set` removes them.

**Curated `ALIAS_EX`** has 56 keys, which collapse to 53 bags. Each key goes through `wordsOf` and a sort to become a bag, and later keys overwrite earlier ones with the same bag (none of them conflict). This table is the intended place to extend matching.

| alias key | bag | id | dataset name |
|---|---|---|---|
| `bench press` | `bench press` | 0025 | barbell bench press |
| `barbell bench press` | `barbell bench press` | 0025 | barbell bench press |
| `flat bench press` | `bench flat press` | 0025 | barbell bench press |
| `incline bench press` | `bench incline press` | 0047 | barbell incline bench press |
| `decline bench press` | `bench decline press` | 0033 | barbell decline bench press |
| `close grip bench press` / `close-grip bench press` | `bench close grip press` | 0030 | barbell close-grip bench press |
| `squat` | `squat` | 0043 | barbell full squat |
| `back squat` | `back squat` | 0043 | barbell full squat |
| `barbell squat` | `barbell squat` | 0043 | barbell full squat |
| `front squat` | `front squat` | 0042 | barbell front squat |
| `deadlift` | `deadlift` | 0032 | barbell deadlift |
| `romanian deadlift` | `deadlift romanian` | 0085 | barbell romanian deadlift |
| `rdl` | `rdl` | 0085 | barbell romanian deadlift |
| `sumo deadlift` | `deadlift sumo` | 0117 | barbell sumo deadlift |
| `lat pulldown` | `lat pulldown` | 2330 | cable lat pulldown full range of motion |
| `lat pull down` | `down lat pull` | 2330 | 〃 |
| `pulldown` | `pulldown` | 2330 | 〃 |
| `shrug` | `shrug` | 0095 | barbell shrug |
| `shrugs` | `shrugs` | 0095 | barbell shrug |
| `overhead press` / `ohp` | `overhead press` | 0091 | barbell seated overhead press |
| `military press` | `military press` | 0091 | 〃 |
| `shoulder press` | `press shoulder` | 0091 | 〃 |
| `barbell row` | `barbell row` | 0027 | barbell bent over row |
| `bent over row` / `bent-over row` | `bent over row` | 0027 | 〃 |
| `dumbbell row` | `dumbbell row` | 0292 | dumbbell one arm bent-over row |
| `one arm dumbbell row` | `arm dumbbell one row` | 0292 | 〃 |
| `leg curl` | `curl leg` | 0586 | lever lying leg curl |
| `lying leg curl` | `curl leg lying` | 0586 | 〃 |
| `seated leg curl` | `curl leg seated` | 0586 | 〃 (the seated leg curl is filed under the lying one) |
| `leg press` | `leg press` | 0739 | sled 45в° leg press |
| `leg extension` | `extension leg` | 0585 | lever leg extension |
| `calf raise` | `calf raise` | 1372 | barbell standing calf raise |
| `standing calf raise` | `calf raise standing` | 1372 | 〃 |
| `seated calf raise` | `calf raise seated` | 0088 | barbell seated calf raise |
| `lateral raise` | `lateral raise` | 0334 | dumbbell lateral raise |
| `side raise` | `raise side` | 0334 | 〃 |
| `reverse fly` | `fly reverse` | 0348 | dumbbell lying rear lateral raise |
| `rear delt fly` | `delt fly rear` | 0348 | 〃 |
| `bicep curl` | `bicep curl` | 0294 | dumbbell biceps curl |
| `biceps curl` | `biceps curl` | 0294 | 〃 |
| `dumbbell curl` | `curl dumbbell` | 0294 | 〃 |
| `preacher curl` | `curl preacher` | 0070 | barbell preacher curl |
| `barbell curl` | `barbell curl` | 0031 | barbell curl |
| `tricep pushdown` | `pushdown tricep` | 0241 | cable triceps pushdown (v-bar) |
| `triceps pushdown` | `pushdown triceps` | 0241 | 〃 |
| `pushdown` | `pushdown` | 0241 | 〃 |
| `skullcrusher` | `skullcrusher` | 0060 | barbell lying triceps extension skull crusher |
| `skull crusher` | `crusher skull` | 0060 | 〃 |
| `lying triceps extension` | `extension lying triceps` | 0061 | barbell lying triceps extension |
| `lunge` | `lunge` | 0054 | barbell lunge |
| `lunges` | `lunges` | 0054 | 〃 |
| `cable crossover` | `cable crossover` | 1269 | cable standing up straight crossovers |
| `cable cross over` | `cable cross over` | 1269 | 〃 |

**Algorithm (`matchExercise(name)`, which returns an id or null):**

```js
const w = wordsOf(name); if (!w.length) return null
const sorted = w.slice().sort().join(' ')
const aliased = aliasIndex().get(sorted); if (aliased && EXIDX[aliased]) return aliased      // 1. curated alias
const exact = idx.exact.get(sorted); if (exact) return exact                                // 2. exact bag
const q = new Set(w); let best = null, bestExtra = Infinity, ties = 0                        // 3. unique superset
for (const c of idx.all) {
  if (![...q].every(word => c.set.has(word))) continue       // candidate must contain every query word
  const extra = c.n - q.size; if (extra > 2) continue          // at most 2 extra words
  if (extra < bestExtra) { best = c.id; bestExtra = extra; ties = 1 } else if (extra === bestExtra) ties++
}
return ties === 1 ? best : null                                 // ambiguous → null (becomes a custom exercise)
```

Parenthesised qualifiers are **kept** as words, so `Bench Press (Barbell)` becomes the bag `barbell bench press`. That is why "(Barbell)" lines up with the dataset's leading equipment word, and also why a curated alias stops matching once a qualifier is added (see `Bicep Curl (Dumbbell)` below). Within one import, results are cached per `keyOf(name)`.

**Golden vectors.** Where the Dataset column is empty, the result is `null` and the name becomes a custom exercise.

| Input | wordsOf (joined) | → id | Dataset |
|---|---|---|---|
| Bench Press (Barbell) | bench press barbell | 0025 | barbell bench press |
| Bench Press (Dumbbell) | bench press dumbbell | 0289 | dumbbell bench press |
| Incline Bench Press (Barbell) | incline bench press barbell | 0047 | barbell incline bench press |
| Incline Bench Press (Dumbbell) | incline bench press dumbbell | 0314 | dumbbell incline bench press |
| Squat (Barbell) | squat barbell | 0043 | barbell full squat |
| Front Squat (Barbell) | front squat barbell | 0042 | barbell front squat |
| Deadlift (Barbell) | deadlift barbell | 0032 | barbell deadlift |
| Romanian Deadlift (Barbell) | romanian deadlift barbell | 0085 | barbell romanian deadlift |
| Romanian Deadlift (Dumbbell) | romanian deadlift dumbbell | 1459 | dumbbell romanian deadlift |
| Sumo Deadlift (Barbell) | sumo deadlift barbell | 0117 | barbell sumo deadlift |
| Lat Pulldown (Cable) | lat pulldown cable | 0197 | cable pulldown (pro lat bar) — *note: not 2330* |
| Lat Pulldown (Machine) | lat pulldown lever | 0673 | reverse grip machine lat pulldown |
| Leg Press (Machine) | leg press lever | 2287 | lever alternate leg press |
| Leg Press | leg press | 0739 | sled 45в° leg press |
| Leg Extension (Machine) | leg extension lever | 0585 | lever leg extension |
| Lying Leg Curl (Machine) | lying leg curl lever | 0586 | lever lying leg curl |
| Seated Leg Curl (Machine) | seated leg curl lever | 0599 | lever seated leg curl |
| Bicep Curl (Dumbbell) | bicep curl dumbbell | **null** | |
| Bicep Curl (Barbell) | bicep curl barbell | **null** | |
| Hammer Curl (Dumbbell) | hammer curl dumbbell | 0313 | dumbbell hammer curl |
| Preacher Curl (Barbell) | preacher curl barbell | 0070 | barbell preacher curl |
| Triceps Pushdown (Cable - Straight Bar) | triceps pushdown cable straight bar | **null** | |
| Tricep Pushdown | tricep pushdown | 0241 | cable triceps pushdown (v-bar) |
| Skullcrusher (Barbell) | skullcrusher barbell | 1721 | barbell reverse grip skullcrusher — *not 0060* |
| Overhead Press (Barbell) | overhead press barbell | 0091 | barbell seated overhead press |
| Overhead Press (Dumbbell) | overhead press dumbbell | 0426 | dumbbell standing overhead press |
| OHP | overhead press | 0091 | barbell seated overhead press |
| Seated Overhead Press (Dumbbell) | seated overhead press dumbbell | **null** | |
| Lateral Raise (Dumbbell) | lateral raise dumbbell | 0334 | dumbbell lateral raise |
| Lateral Raise (Cable) | lateral raise cable | 0178 | cable lateral raise |
| Face Pull (Cable) | face pull cable | **null** | |
| Seated Cable Row | seated cable row | 0861 | cable seated row |
| Seated Row (Cable) | seated row cable | 0861 | cable seated row |
| Bent Over Row (Barbell) | bent over row barbell | 0027 | barbell bent over row |
| Dumbbell Row | dumbbell row | 0292 | dumbbell one arm bent-over row |
| Pull Up / Pull Ups / Weighted Pull Up | pull up | 0652 | pull-up |
| Chin Up | chin up | 1326 | chin-up |
| Push Up / Push-ups | push up | 0662 | push-up |
| Dips | dip | **null** | |
| Chest Dip | chest dip | 0251 | chest dip |
| Plank | plank | 2135 | weighted front plank |
| Hip Thrust (Barbell) | hip thrust barbell | **null** | |
| Calf Raise | calf raise | 1372 | barbell standing calf raise |
| Standing Calf Raise (Machine) | standing calf raise lever | 0605 | lever standing calf raise |
| Seated Calf Raise | seated calf raise | 0088 | barbell seated calf raise |
| Shrug (Barbell) | shrug barbell | 0095 | barbell shrug |
| Shrug (Dumbbell) | shrug dumbbell | 0406 | dumbbell shrug |
| Lunge (Dumbbell) | lunge dumbbell | 0336 | dumbbell lunge |
| Walking Lunge | walking lunge | 1460 | walking lunge |
| Cable Crossover | cable crossover | 1269 | cable standing up straight crossovers |
| Running / Treadmill / Cycling | running / treadmill / cycling | **null** | |
| Rowing Machine | rowing lever | **null** | |
| Flat Barbell Bench Press | flat barbell bench press | **null** | |
| Barbell Squat | barbell squat | 0043 | barbell full squat |
| BB Bench Press | barbell bench press | 0025 | barbell bench press |
| DB Curl | dumbbell curl | 0294 | dumbbell biceps curl |
| Close Grip Bench Press | close grip bench press | 0030 | barbell close-grip bench press |
| Close-Grip Bench Press (Barbell) | close grip bench press barbell | 0030 | 〃 |
| Decline Bench Press (Barbell) | decline bench press barbell | 0033 | barbell decline bench press |
| Leg Curl | leg curl | 0586 | lever lying leg curl |
| Reverse Fly (Dumbbell) | reverse fly dumbbell | 0383 | dumbbell reverse fly |
| Crunch | crunch | 0832 | weighted crunch |
| Russian Twist | russian twist | 0687 | russian twist |
| Hanging Leg Raise | hanging leg raise | 0472 | hanging leg raise |
| Farmers Walk | farmers walk | 2133 | farmers walk |
| Good Morning (Barbell) | good morning barbell | 0044 | barbell good morning |
| Arnold Press (Dumbbell) | arnold press dumbbell | 2137 | dumbbell arnold press |
| T Bar Row | t bar row | 0606 | lever t bar row |
| Kettlebell Swing | kettlebell swing | 0549 | kettlebell swing |
| Goblet Squat (Kettlebell) | goblet squat kettlebell | 0534 | kettlebell goblet squat |
| Bulgarian Split Squat / Glute Bridge / Sit Up | … | **null** | |
| Burpee | burpee | 1160 | burpee |
| Jump Rope | jump rope | 2612 | jump rope |
| Military Press | military press | 0091 | barbell seated overhead press |
| EZ Bar Curl | ez barbell curl | 0447 | ez barbell curl |
| Smith Machine Squat | smith lever squat | **null** | (SYN ordering bug) |
| Pec Deck (Machine) / Chest Fly (Dumbbell) / Cable Fly | … | **null** | |
| Assisted Pull Up | assisted pull up | 0017 | assisted pull-up |
| `""` / `(Barbell)` | `""` / barbell | null / null | |

The port must reproduce this table exactly. If the matcher is improved later, for example by adding aliases, update the vectors deliberately.

### 9.6 Value parsers

```js
const num = v => { const n = parseFloat(String(v ?? '').replace(',', '.')); return isFinite(n) ? n : 0 }
```

- Only the **first** comma is replaced, and `parseFloat` reads the longest numeric prefix. So `"12kg"` gives 12 and `"1,234.5"` gives 1.234.
- A Dart `num` must emulate this: match `^\s*[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?` on the prefix, and return 0 on no match or on Infinity or NaN.

```js
const effortNum = (raw, zeroMeansRated) => {
  const s = String(raw ?? '').trim(); if (!s) return null
  const n = parseFloat(s.replace(',', '.'))
  if (!isFinite(n) || n < 0 || (n === 0 && !zeroMeansRated)) return null
  return Math.min(10, Math.round(n * 100) / 100) }
```

Vectors, as `(raw, zeroMeansRated) → result`:
- `('8',F) → 8`, `('0',F) → null`, `('0',T) → 0`, `('',T) → null`
- `('12',F) → 10`, `('-3',F) → null`, `('hard',F) → null`
- `('8,5',F) → 8.5`, `('7.333',F) → 7.33`

`LB_TO_KG = 0.45359237`.

**`parseWhen(s)` returns `{d:'YYYY-MM-DD', t: msSinceMidnight|null}` or null.** It trims `s` and tries these patterns in order, all anchored at `^`. Anything after the match is ignored, including seconds, a `Z` or an offset.

1. `^(\d{4})-(\d{1,2})-(\d{1,2})(?:[T ](\d{1,2}):(\d{2}))?` gives `d = Y-pad(M)-pad(D)`.
2. `^(\d{1,2})\s+([A-Za-z]{3})[a-z]*\.?\s+(\d{4})(?:,?\s+(\d{1,2}):(\d{2}))?`, valid only if the month's first 3 letters (lowercased) are in `MON`. Example: `22 Dec 2025, 08:00`.
3. `^([A-Za-z]{3})[a-z]*\.?\s+(\d{1,2}),?\s+(\d{4})(?:,?\s+(\d{1,2}):(\d{2}))?`, same `MON` check. Example: `Jan 12, 2026, 6:30`.
4. `^(\d{1,2})[/.](\d{1,2})[/.](\d{4})(?:[, ]+(\d{1,2}):(\d{2}))?` is **day-first when ambiguous**: `day = +a>12 ? a : +b>12 ? b : a; mon = (day === a) ? b : a` (a string comparison).

`MON = {jan:1, feb:2, …, dec:12}`. `hm(h, mi) = h === undefined ? null : (parseInt(h)||0)*3600000 + (parseInt(mi)||0)*60000`; in Dart, a missing group is `null`. Nothing validates the ranges: `2024-13-45` and `13/13/2024` pass, which yields an invalid date downstream. AM/PM is not supported (`6:30 PM` gives 06:30).

| Input | Output |
|---|---|
| `2020-12-30 18:51:52` | `{d:'2020-12-30', t:67860000}` |
| `2024-03-07` / `2024-3-7` | `{d:'2024-03-07', t:null}` |
| `2024-03-07T06:05:00Z` | `{d:'2024-03-07', t:21900000}` (the Z is ignored) |
| `22 Dec 2025, 08:00` | `{d:'2025-12-22', t:28800000}` |
| `22 December 2025` | `{d:'2025-12-22', t:null}` |
| `12 Jan 2026, 18:00` | `{d:'2026-01-12', t:64800000}` |
| `Jan 12, 2026, 6:30` | `{d:'2026-01-12', t:23400000}` |
| `Sept 3, 2025` | `{d:'2025-09-03', t:null}` |
| `07/03/2024` | `{d:'2024-03-07', t:null}` (day-first) |
| `13/03/2024` / `03/13/2024` | `{d:'2024-03-13', t:null}` |
| `07.03.2024 18:30` | `{d:'2024-03-07', t:66600000}` |
| `7/3/2024, 9:05` | `{d:'2024-03-07', t:32700000}` |
| `2024/03/07`, `garbage`, `""`, `31 Foo 2024` | `null` |

**`toMinutes(v)`** turns a duration into minutes:
- Empty gives 0.
- If the value contains `:`, split it and `parseInt` each part (invalid parts become 0). With 3 parts, `sec = h*3600 + m*60 + s`; otherwise `sec = p0*60 + p1`. Return `round(sec/60*10)/10`.
- Otherwise, if `/(\d+)\s*h/i` or `/(\d+)\s*m/i` matches, return `h*60 + m`, with no rounding. This handles Strong's `2h 38m`.
- Otherwise return `round(num(s)*10)/10`, so a bare number is taken as minutes.

Vectors: `01:30:00 → 90`, `1:30 → 1.5`, `90 → 90`, `2h 38m → 158`, `45m → 45`, `1h → 60`, `0:45 → 0.8`, `"" → 0`, `abc → 0`, `12,5 → 12.5`.

**`toKm(v, unit)`** returns `num(v) * (KM[String(unit || 'km').toLowerCase().trim()] ?? 1)`, where `KM = {m:0.001, km:1, cm:0.00001, in:0.0000254, ft:0.0003048, yd:0.0009144, mi:1.609344}`. An unknown unit uses factor 1.

Vectors: `(5,km) → 5`, `(5000,m) → 5`, `(3,mi) → 4.828032`, `(100,yd) → 0.09144`, `(5,'') → 5`, `(5,furlong) → 5`, `(1,5,km) → 1.5`.

### 9.7 `parseWorkoutCSV(text, {unit='kg'})`: the algorithm

1. `rows = parseCSV(text)`. If there are fewer than 2 rows, return `{error:'empty'}`.
2. `map = mapHeader(rows[0])` and `source = detectSource(rows[0])`.
3. `dateCol` is `'date'` if mapped, else `'startTime'` if mapped, else none. With no date column or no `exercise` column, return `{error:'unrecognised'}`.
4. `cell(r, f)` returns `''` when `f` is not mapped, else `String(r[map[f]] ?? '').trim()`. A short row gives `''`.
5. For each data row, in file order:
   - `name = cell('exercise')` and `when = parseWhen(cell(dateCol))`. If either is missing, `skipped++` and continue.
   - **Weight and row unit.** Explicit columns win over the generic column plus unit:
     - If `weightKg` is mapped and non-empty, `w = num(...)` and `rowUnit = 'kg'`.
     - Else if `weightLb` is mapped and non-empty, `w = num(...)` and `rowUnit = 'lb'`.
     - Else `w = num(cell('weight'))`, and with `u = cell('weightUnit').toLowerCase()`, `rowUnit = u.startsWith('lb') ? 'lb' : u.startsWith('kg') ? 'kg' : ''`. So `lbs` → lb, `kgs` → kg, and `pounds` → '' (a quirk).
     - Track `sawLb` and `sawKg`.
   - `reps = Math.round(num(cell('reps')))`.
   - `secs = num(cell('seconds'))`, and `mins = secs > 0 ? round(secs/60*10)/10 : toMinutes(cell('time'))`.
   - `km = (distanceKm mapped && non-empty) ? num(cell('distanceKm')) : toKm(cell('distance'), cell('distanceUnit'))`.
   - If `!w && !reps && !mins && !km`, `skipped++` and continue.
   - If `/warm/i.test(cell('setType'))`, `warmups++`. This is **only counted**: the set is still imported as a normal done set.
   - **Resolve the exercise**, cached by `key = keyOf(name)`:
     - Look up `id = resolved.get(key)`. If absent, compute `matchExercise(name)` and cache it (null included).
     - A non-null id means `matched++`.
     - Otherwise reuse, or create once per key, the custom exercise `{ id: 'im'+uid(), n: name.toLowerCase(), custom: true, eq: 'custom', tg: '', desc: '', bp }`, and `unmatched.add(name)`, which stores the first spelling seen. Here `bp = CATEGORY_BP[cell('category').toLowerCase()] || ((km || (mins && !reps)) ? 'cardio' : 'upper legs')`, evaluated on the row that creates it.
     - `CATEGORY_BP = {chest:'chest', back:'back', lats:'back', shoulders:'shoulders', delts:'shoulders', legs:'upper legs', quads:'upper legs', hamstrings:'upper legs', glutes:'upper legs', calves:'lower legs', abs:'waist', core:'waist', obliques:'waist', arms:'upper arms', biceps:'upper arms', triceps:'upper arms', forearms:'lower arms', cardio:'cardio', 'full body':'upper legs', olympic:'upper legs', neck:'neck'}`
   - **Build the set.** `isCardio = (km > 0 || mins > 0) && !reps`.
     - Cardio: `{ min: mins||0, speed: mins>0 ? round(km/(mins/60)*10)/10 : 0, done: true }`, with speed in km/h.
     - Otherwise: `{ w, r: reps||0, done: true, u: rowUnit }`. `u` is temporary and is removed in step 6.
   - **Effort**, only on non-cardio sets:
     - `rir = effortNum(cell('rir'), true)`. If it is non-null, set `set.rir = rir` and `rirSets++`.
     - Otherwise `rpe = effortNum(cell('rpe'), false)`. If that is non-null, set `set.rpe` and `rpeSets++`.
     - A set holds one scale only, and RIR wins. The key is **absent** when there is no rating; it is never null.
   - **Group by date.** `day = byDate.get(when.d)`. The first time a date is seen, it becomes `{ex: Map<id, sets[]>, name: cell('workoutName')||'', start: when.t, end: null}`.
     - If `day.name` is still empty, take this row's workout name.
     - If `endTime` is mapped, parse it with `parseWhen`; when its `t != null`, `day.end = t`, so the **last** row with an end time wins.
     - Push the set onto `day.ex[id]`. Insertion order is kept, both for the exercise entries and for the sets.
   - `sets++`.
6. **Unit conversion (per row):**
   - `fileUnit = sawLb && !sawKg ? 'lb' : sawKg && !sawLb ? 'kg' : ''` and `mixedUnits = sawLb && sawKg`.
   - `toKg(x) = round(x*LB_TO_KG*10)/10` and `toLb(x) = round(x/LB_TO_KG*10)/10`.
   - For each set with `w`: `u = s.u || fileUnit`. If `u` is empty or equals the profile unit, keep `w`; otherwise convert. Then drop `u`.
   - `converted = (fileUnit && fileUnit !== unit) || mixedUnits`.
7. **Build the workouts**, one per date, sorted ascending by the `d` string:
   ```js
   entries = [...day.ex].map(([id, ss]) => ({ id, sets: converted(ss), topW: Math.max(0, ...ws) || null }))
   base  = new Date(d + 'T00:00:00').getTime()          // LOCAL midnight (device TZ)
   start = base + (day.start ?? 18*3600000)              // no clock → 18:00 local
   end   = day.end != null ? base + day.end : start;  end = end > start ? end : start
   w = { id: 'iw'+uid(), d, start, end, routineId: null, name: day.name || 'Imported', entries, prs: [] }
   w.vol = Σ_entries Σ_sets (s.w||0) * (s.r||0)          // cardio sets add 0
   ```
   Several sessions on the same date (for example two Hevy workouts) are **merged into one workout**. It takes the first session's name and start and the last end time.
8. Return:
   ```
   { kind:'workouts', source, workouts, customEx:[...created.values()],
     matched: <distinct non-null resolved ids>, matchedSets: <rows matched>, created: <#customs>,
     unmatchedNames: [...unmatched].sort(), sets, skipped, warmups, fileUnit, mixedUnits, converted,
     rpeSets, rirSets, from: dates[0]||null, to: dates.at(-1)||null }
   ```

The stored **set shapes** are:
- weighted: `{w, r, done:true, rpe?|rir?}`
- cardio: `{min, speed, done:true}`

Imported sets never use the time mode (`{sec, w}`).

### 9.8 Unit semantics, summarised

The app never converts on its own: weights are stored in the profile unit. An import converts **only the rows whose unit is known and differs from the profile**. A row without a unit follows the file unit, and when the file states no unit at all, numbers are taken as-is and the UI warns about it.

### 9.9 Golden vectors for `parseWorkoutCSV` (TZ=UTC; `uid` stubbed as `UID<n>`)

- **Mixed units** (FitNotes), profile kg:
  - Rows: `Deadlift,Legs,185,lbs,5`, then `100,kgs,3` on 2024-01-01, then `90,(blank unit),5` on 2024-01-02.
  - Sets: 83.9×5 and 100×3, then 90×5 (a blank unit in a mixed file is not converted).
  - Flags: `mixedUnits:true, converted:true, fileUnit:''`. Volumes: day 1 is 719.5, day 2 is 450. Matched id `0032`.
- **Strong `Duration` quirk:**
  - Rows: `2024-01-01 07:00:00,Morning,1h 5m,Plank,1,0,0,0,0,,,`, then a bench row.
  - The Plank row becomes `{min:65, speed:0, done:true}` under id 2135, because `Seconds` is 0, so `time`, which holds the **workout** Duration, is used.
  - Bench gives `{w:60, r:10}`. The name is "Morning" and the start is 07:00 UTC.
- **Hevy, two sessions on one day:**
  - Rows: `AM` 07:00–08:00 Squat warm-up 40×10, and `PM` 18:00–19:30 Deadlift 140×5.
  - Result: one workout named "AM", `start = 07:00`, `end = 19:30`, `warmups: 1`, and both sets done. `fileUnit:'kg'`.
- **Custom creation:**
  - Rows: `Zercher Hold Thing` in category Shoulders at 40×8 → custom with `bp 'shoulders'`. `Rowing Erg` with 2000 m in `00:08:00` → custom cardio with set `{min:8, speed:15}`. `Wall Sit Hold` with only a time of `00:01:30` → custom cardio with `{min:1.5, speed:0}`.
  - `unmatchedNames` is sorted: `["Rowing Erg","Wall Sit Hold","Zercher Hold Thing"]`.
- **Profile lb, file kg**: `Weight (kg)=100` gives `w: 220.5`, with `converted:true, fileUnit:'kg'`.
- **Skipped rows**: a missing date, a missing name, `0,0`, or `bad date` → `workouts:[]`, `skipped:4`, `from/to:null`.
- **No date column** → `{error:'unrecognised'}`.
- A full example of the output shape (Hevy, 2 sets):
  ```json
  {"kind":"workouts","source":"Hevy","workouts":[{"id":"iwUID1","d":"2026-01-12","start":1768240800000,"end":1768244400000,
   "routineId":null,"name":"Push","entries":[{"id":"0025","sets":[{"w":60,"r":10,"done":true,"rpe":8},{"w":60,"r":8,"done":true,"rpe":9.5}],"topW":60}],
   "prs":[],"vol":1080}],"customEx":[],"matched":1,"matchedSets":2,"created":0,"unmatchedNames":[],"sets":2,"skipped":0,
   "warmups":0,"fileUnit":"kg","mixedUnits":false,"converted":false,"rpeSets":2,"rirSets":0,"from":"2026-01-12","to":"2026-01-12"}
  ```

### 9.10 `parseBodyweight(text, {unit='kg'})`: Apple Health and weight CSVs

- **XML path**, taken when the text contains `HKQuantityTypeIdentifierBodyMass`. The file is scanned with a regex, never parsed into a DOM (Health exports can be hundreds of MB; in Flutter, stream it or run it in an isolate):
  ```js
  re = /<Record[^>]*type="HKQuantityTypeIdentifierBodyMass"[^>]*>/g
  val = /value="([\d.]+)"/ ; dt = /startDate="([^"]+)"/ || /creationDate="([^"]+)"/ ; u = /unit="([^"]+)"/
  ```
  - Records without a value or a date, or where `parseWhen(dt)` fails, are skipped.
  - When a record has a unit, `fileUnit = /lb/i ? 'lb' : 'kg'`. The **last** record's unit wins for the whole file (a quirk).
  - `out.set(when.d, {w: parseFloat(value), t: new Date(dt).getTime() || null})`: **one weigh-in per day, and the last record in the file wins.** JS parses `"2024-03-07 21:00:00 +0100"` as an instant; Dart needs a custom parser, since the ISO form needs `T` and `+01:00`.
- **CSV path**, for anything else:
  - Fewer than 2 rows gives `{error:'empty'}`.
  - `wCol = map.weightKg ?? map.weightLb ?? map.weight` and `dCol = map.date ?? map.startTime`. If either is missing, `{error:'unrecognised'}`.
  - `fileUnit` is `'kg'` when `weightKg` is mapped, `'lb'` when `weightLb` is mapped, and `''` for a generic `weight` column. The `weightUnit` column is **ignored** here.
  - Each row needs `when` and a non-zero `w = num(cell)`. `t = new Date(when.d).getTime() + (when.t ?? 0)`. Note that `new Date('YYYY-MM-DD')` is **UTC** midnight, unlike the local midnight in §9.7.
- An empty `out` gives `{error:'unrecognised'}`.
- `converted = !!fileUnit && fileUnit !== unit`. The conversion is lb→kg `round(x*LB_TO_KG*10)/10`, kg→lb `round(x/LB_TO_KG*10)/10`, or no conversion `round(x*10)/10`.
- The result is `{kind:'bodyweight', source:'Apple Health', bodyweight:[{d, w, t: t || new Date(d).getTime()}] (sorted by d), fileUnit, converted, from, to}`. `source` is "Apple Health" even for a CSV (a quirk).

Vectors (TZ=UTC):
- An XML file with 3 lb records: 03-07 07:58 at 180.4, 03-07 21:00 at 181, and 03-09 at 179.6.
  - Profile kg: `[{d:'2024-03-07', w:82.1, t:1709841600000}, {d:'2024-03-09', w:81.5, t:1709964000000}]`, with `fileUnit:'lb', converted:true`.
  - Profile lb: the weights stay 181 and 179.6, `converted:false`.
- `Date,Weight (kg)\n2024-03-07,80.25\n2024-03-08,\n08/03/2024,80.4` gives `[{d:'2024-03-07', w:80.3, t:1709769600000}, {d:'2024-03-08', w:80.4, t:1709856000000}]` with `fileUnit:'kg'`.
- `Date,Weight\n2024-03-07,80.25` with profile lb gives `w:80.3, fileUnit:'', converted:false`.
- `foo,bar\n1,2` gives `{error:'unrecognised'}`. `only header` gives `{error:'empty'}`.

### 9.11 `mergeImport(S, parsed)`: idempotent, and existing days win

- **Body weight:**
  - `fresh` is the parsed entries whose `d` is not already in `S.bodyweight`.
  - `S.bodyweight = [...S.bodyweight, ...fresh].sort(by d asc)`.
  - Return `{added: fresh.length, skipped: total - fresh.length}`.
- **Workouts:**
  1. `fresh` is the parsed workouts whose `d` has no existing workout. The match is on **date only**, and a whole day is skipped even when the existing workout is different.
  2. `used` is the set of all entry ids in `fresh`. Append to `S.customEx` only the parsed customs whose id is in `used` and not already in `EXIDX`.
  3. `S.workouts = [...S.workouts, ...fresh].sort(by d asc)`.
  4. Seed the weight suggestions: for each fresh workout (ascending by date) and each entry, take `mx = max(0, ...sets.w, topW||0)`. If `mx > 0` and either `!S.exWeights[id]` or `w.d >= cur.d`, set `S.exWeights[id] = {w: mx, d: w.d}`.
  5. Return `{added, skipped}`.

  Vector: the existing day is 2024-01-01, and `exWeights['0043'] = {w:90, d:'2023-12-01'}`. Importing squat on 01-01 (100), 01-03 (110) and 01-02 (105), plus a custom on 01-03 (50), gives `{added:2, skipped:1}`. The days become `[01-01, 01-02, 01-03]`, `exWeights['0043'] = {w:110, d:'2024-01-03'}`, and `exWeights[imUID] = {w:50, d:'2024-01-03'}`.

### 9.12 Import summary UI (`ImportSummary`), which must be ported

- **Title:** `source ? t('Import from {0}', source) : t('Import history')` (es: "Importar de {0}" / "Importar historial").
- **Subtitle:** `from === to ? fmtDate(from, true) : fmtDate(from, true) + ' – ' + fmtDate(to, true)`.
- **`have`:** the number of parsed days already present in state. `fresh = total − have`.
- **Tiles:**
  - Body weight: "Weigh-ins" (Pesajes) showing the total, and "New" (Nueva) showing `fresh`.
  - Workouts: "Workouts" (Entrenos), "Sets" (Series), "Exercises matched" (Ejercicios reconocidos) showing `parsed.matched`, and "Added as your own" (Añadidos como propios) showing `parsed.created`.
- **Notices, in order:**
  1. `mixedUnits`, shown in yellow: "The file mixes kg and lb — each set is converted to {0}." Otherwise, if `converted`: "The file is in {0} and your profile is in {1} — weights will be converted."
  2. For workouts where `!fileUnit && !mixedUnits`: "The file does not say which unit it uses — numbers are imported as they are."
  3. If `have > 0`: "{0} days already have data here and will be left alone."
  4. For workouts where `rirSets + rpeSets > 0`: `count = rirSets || rpeSets` and `scale = rirSets ? 'RIR' : 'RPE'`. The message depends on the effort setting. When `effortOf(S) === 'none'`: "{0} sets bring an {1} with them — switch on Effort per set in Settings to see it." Otherwise: "{0} sets bring an {1} with them."
  5. If there are unmatched names: the heading "Not in the library — added as your own exercises", the first 12 names as chips, and a `+N` chip for the rest.
- **Primary button:** "Import", or "Nothing new to import" and disabled when `fresh == 0`. It calls `mergeImport` and then shows the toast "{0} weigh-ins imported" or "{0} workouts imported". A secondary button reads "Cancel".

`effortOf(S)` returns `S.effort` when it is `'none'`, `'rir'` or `'rpe'`; otherwise it returns `S.showRir ? 'rir' : 'none'`, for legacy backups. `setLabel(id, s)` for a reps set is `` `${fmtNum(w)}×${r}` `` plus `" (RIR x)"` or `" (RPE x)"`. When both are present, RIR is preferred.

### 9.13 Known quirks: replicate or fix, deliberately

Replicate these by default, so that imports give the same results as openGym:
1. **SYN order:** rule #7 (`machine`→`lever`) runs before #8 (`smith machine`→`smith`), so "Smith Machine Squat" does not match.
2. **Curated aliases do not survive a qualifier:** "Bicep Curl (Dumbbell)" gives null, even though "Bicep Curl" gives 0294. "Lat Pulldown (Cable)" gives 0197, not 2330. "Skullcrusher (Barbell)" gives 1721, not 0060. "Leg Press (Machine)" gives 2287 "lever alternate leg press".
3. **`weighted` is a filler word**, so "Plank" gives "weighted front plank" and "Weighted Pull Up" gives the plain "pull-up".
4. **Strong's `Duration` goes into `time`**, so a timed row with Seconds=0 gets the whole workout length.
5. **Warm-up sets are counted but imported as working sets.**
6. **Same-date sessions are merged.** Dedupe is on the date only.
7. **The `note` column is never stored.** Hevy's `exercise_notes` and `description` are ignored.
8. A weight unit of `pounds` is not recognised, because the check is `startsWith('lb')`.
9. The last record's unit applies to the whole Health file. `source` is "Apple Health" even for a CSV.
10. Dates are not range-checked. A numeric date is read day-first, and AM/PM is ignored.
11. `num` reads `1,234.5` as 1.234. Only the first comma is replaced.
12. `start` uses **local** midnight plus the time of day, with 18:00 when there is no clock. Body-weight `t` uses **UTC** midnight for a date-only CSV value.

### 9.14 The test cases in `import-effort.test.js` (all must pass in the port)

Helpers:
- `rows(head, ...lines) = parseWorkoutCSV([head, ...lines].join('\n'), {unit:'kg'})`
- `setsOf(p)` flattens every set of every workout in file order.

Headers:
- `HEVY = 'title,start_time,end_time,exercise_title,set_index,set_type,weight_kg,reps,rpe'`
- `STRONG = 'Date,Workout Name,Exercise Name,Set Order,Weight,Reps,Seconds,RPE'`
- `FITNOTES = 'Date,Exercise,Category,Weight,Reps,Distance,Distance Unit,Time'`

| # | Input | Expected |
|---|---|---|
| 1 | HEVY with `Push,"12 Jan 2026, 18:00","12 Jan 2026, 19:00",Bench Press (Barbell),0,normal,60,10,8` and the same row with `1,normal,60,8,9.5` | `error` undefined; rpe `[8, 9.5]`; `rpeSets 2`, `rirSets 0` |
| 2 | STRONG `2026-01-12 18:00:00,Push,Bench Press (Barbell),1,60,10,0,7.5` | `sets[0].rpe === 7.5`; `rpeSets 1` |
| 3 | `Date,Exercise,Weight,Reps,RIR` with `2026-01-12,Bench Press,60,10,2` and `…,60,6,0` | rir `[2, 0]` (0 RIR means failure and is kept); `rirSets 2`; every `rpe` undefined |
| 4 | HEVY rows with an empty end time; the first row's rpe is blank and the second's is `8` | `'rpe' in s[0] === false`; `s[1].rpe === 8`; `rpeSets 1` |
| 5 | STRONG `…,1,60,10,0,0` (RPE 0) | no `rpe` key; `rpeSets 0` |
| 6 | STRONG `…,1,60,10,0,12` | `rpe === 10` (capped) |
| 7 | STRONG with RPE `hard` and with `-3` | neither set has `rpe`; `rpeSets 0`; `sets 2` (still imported) |
| 8 | `Date,Exercise,Weight,Reps,RPE,RIR` with `2026-01-12,Bench Press,60,10,8,2` | `rir === 2`, no `rpe`; `setLabel('0025', s) === '60×10 (RIR 2)'` |
| 9 | `Date,Exercise,Distance,Distance Unit,Time,RPE` with `2026-01-12,Running,5,km,00:30:00,7` | `s.min === 30`; no `rpe`; `rpeSets 0` |
| 10 | FITNOTES `2026-01-12,Bench Press,Chest,60,10,,,` | the set **deep-equals** `{w:60, r:10, done:true}`; `rpeSets + rirSets === 0` |
| 11 | `Date,Exercise,Weight,Weight Unit,Reps,RPE` with `2026-01-12,Bench Press,135,lbs,10,8`, profile kg | `w === 61.2`, `rpe === 8`, and `'u' in s === false` |
| 12 | Backup round trip: `S = {unit:'kg', effort:'rpe', workouts:[{d, entries:[{id:'0025', sets:[{w:60,r:10,rpe:8,done:true},{w:60,r:8,rir:1,done:true},{w:60,r:12,done:true}]}]}]}` → `JSON.parse(JSON.stringify(S))` spread over `{unit:'kg', workouts:[], routines:[], effort:null}` | `effortOf === 'rpe'`; labels `'60×10 (RPE 8)'`, `'60×8 (RIR 1)'`, `'60×12'`; the third set has no rpe and no rir |
| 13 | Legacy backup `{showRir:true, workouts:[], routines:[]}`, and one without the flag | `effortOf` gives `'rir'` and `'none'` respectively |

I replayed cases 1–11 against the original code, and all pass. The harness is `scratchpad/harness/tests.mjs`. Cases 12–13 depend on `history.js` and belong to the history/effort spec.

---

## 10. Exported catalogue (`exercises.json`) and the export script

- **Script:** `scratchpad/export-exercises.mjs`. Run it as `node export-exercises.mjs [repoRoot] [outFile]`; the defaults are `/home/user/opengym` and `<script dir>/exercises.json`.
- **Inputs:** `exercises-data.js`, `instr/es.js` and `locales/es.js`.
- **Checks:** unique 4-digit ids, and `img`/`gif` equal to `` `${id}-${mediaId}.jpg|gif` ``.
- **Output:** `scratchpad/exercises.json` is a JSON array of 1,324 objects in EXDB order. It is **1,863,682 bytes** (about 250 KB gzipped), and all 1,324 records carry `instructions_es`.

```json
{"id":"0025","name":"barbell bench press","bodyPart":"chest","equipment":"barbell","target":"pectorals","muscleGroup":"triceps",
 "secondary":["triceps","shoulders"],"instructions":["Lie flat on a bench …", "…"],"instructions_es":["Túmbate sobre un banco …","…"],
 "bodyPart_es":"pecho","equipment_es":"barra","target_es":"pectorales","secondary_es":["tríceps","hombros"],
 "mediaId":"EIeI8Vf","img":"0025-EIeI8Vf.jpg","gif":"0025-EIeI8Vf.gif"}
```

`name_es` is deliberately absent, because no name translations exist. The media URL is `<base>/images/<img>` or `<base>/videos/<gif>`, where `<base> = https://cdn.jsdelivr.net/gh/hasaneyldrm/exercises-dataset@7455efae41b330c265e7cd4b78dfa848e7ce5ebd`.

When converting app state or the MCP interface, map these short keys to the long ones: `n→name`, `bp→bodyPart`, `eq→equipment`, `tg→target`, `sm→secondary`, `st→instructions`. Keep the short keys in synced user state (`customEx`, workouts and so on) if round-tripping openGym backups matters. See the open questions.

## 11. Recommendations for the port

- **Flutter:**
  - Bundle `exercises.json` as an asset. Parse it once in an isolate into `Map<String, Exercise>`, plus a `List` kept in order.
  - Keep `EXIDX` semantics: customs are merged into the index, and `exOr` returns a placeholder.
  - Port `muscles.js` literally, with a stable sort.
  - Port `import-csv.js` as a pure Dart library whose tests reproduce §9.2–§9.14 exactly. `file_picker` gives the bytes; decode them as UTF-8 and allow malformed input.
  - Stream Apple Health XML: a regex over chunks, or a lightweight SAX scan on `<Record`.
- **D1 table** `exercises(id TEXT PRIMARY KEY, name TEXT, body_part TEXT, equipment TEXT, target TEXT, muscle_group TEXT, secondary TEXT /*JSON*/, instructions TEXT /*JSON*/, instructions_es TEXT /*JSON*/, media_id TEXT, img TEXT, gif TEXT, ord INTEGER)`, with indexes on `body_part`, `equipment` and `target`. Add a separate `custom_exercises(user_id, id, name, body_part, desc, …)` table.
- **MCP tools** should expose the catalogue: a search with filters, a detail tool returning steps in the user's language, and validation of plan exercise ids against the library plus customs. They should also expose muscle load and levels (§3) so Claude can reason about balance.
- **Import on the server (optional):** the parser is pure, so the same TypeScript port could run in the Worker, for example so Claude can import a CSV the user uploads. Keep one implementation per language, both tested against §9's vectors.
- **Attribution:** show "© Gym visual — https://gymvisual.com/" and "Exercise data: hasaneyldrm/exercises-dataset (MIT)" in the About screen, and next to the media if possible.

## 12. Open questions

1. **Media licensing:** hotlink the pinned jsDelivr URLs (zero hosting; the files are served by upstream), or mirror them to R2 (redistribution needs Gym visual's permission)? Offline use would need local caching, and whether that counts as redistribution has to be settled either way.
2. Fix the `в°` mojibake and the SYN ordering bug (`smith machine`), and add aliases such as "bicep curl (dumbbell)", "hip thrust", "face pull" and "dips"? Or keep bit-for-bit parity with openGym?
3. Exercise names exist only in English. Should the Spanish UI search the translated taxonomy labels (bodyPart_es and the others)? Should we machine-translate names, which is new data?
4. Should synced state keep openGym's short keys (`n`, `bp`, `eq`, `tg`, `sm`, `st`), so openGym backups and plan files import unchanged, or move to long names with a converter?
5. **Import semantics:** keep "existing date wins" and merging same-day sessions? Keep warm-ups as working sets? These affect the progress analysis Claude does.
6. How much of openGym's own AGPL code the port copies decides the new app's licence, and the AGPL §7 app-store exception in NOTICE.md applies only to the openGym copyright holder's distribution.
7. The upstream `main` branch may drift from the pinned commit that `build-instructions.mjs` and `docker-compose` clone. Pin every fetch to `7455efae…` so ids, media names and instruction packs stay consistent.

## Appendix A: UI strings for this subsystem (English key → es)

These are the keys from `locales/es.js`. Keep the English string as the lookup key.

```json
{
 "Import from {0}": "Importar de {0}",
 "Import history": "Importar historial",
 "Weigh-ins": "Pesajes",
 "New": "Nueva",
 "Workouts": "Entrenos",
 "Sets": "Series",
 "Exercises matched": "Ejercicios reconocidos",
 "Added as your own": "Añadidos como propios",
 "The file mixes kg and lb — each set is converted to {0}.": "El archivo mezcla kg y lb — cada serie se convierte a {0}.",
 "The file is in {0} and your profile is in {1} — weights will be converted.": "El archivo está en {0} y tu perfil en {1} — los pesos se convertirán.",
 "The file does not say which unit it uses — numbers are imported as they are.": "El archivo no indica la unidad — los números se importan tal cual.",
 "{0} days already have data here and will be left alone.": "{0} días ya tienen datos aquí y no se tocarán.",
 "{0} sets bring an {1} with them — switch on Effort per set in Settings to see it.": "{0} series traen un {1} — activa «Esfuerzo por serie» en Ajustes para verlo.",
 "{0} sets bring an {1} with them.": "{0} series traen un {1}.",
 "Not in the library — added as your own exercises": "No están en la biblioteca — añadidos como ejercicios propios",
 "Import": "Importar",
 "Nothing new to import": "Nada nuevo que importar",
 "Cancel": "Cancelar",
 "{0} weigh-ins imported": "{0} pesajes importados",
 "{0} workouts imported": "{0} entrenamientos importados",
 "Could not read that file": "No se pudo leer ese archivo",
 "That file is empty": "Ese archivo está vacío",
 "That file's columns aren't recognised — see the docs for supported apps.": "No se reconocen las columnas del archivo — consulta la documentación.",
 "Nothing to import from that file": "No hay nada que importar de ese archivo",
 "Imported": "Imported",
 "Unknown exercise": "Ejercicio desconocido",
 "Exercises": "Ejercicios",
 "{0} exercises with animations": "{0} ejercicios con animaciones",
 "Search…": "Buscar…",
 "All": "Todo",
 "Any equipment": "Cualquier equipo",
 "Create your own exercise": "Crea tu propio ejercicio",
 "name + body part, no animation": "nombre + parte del cuerpo, sin animación",
 "No match": "Sin resultados",
 "Show more": "Mostrar más",
 "Plan": "Plan",
 "Add exercise": "Añadir ejercicio",
 "Search {0} exercises…": "Buscar entre {0} ejercicios…",
 "Chosen": "Elegidos",
 "Nothing chosen yet — add exercises and they’ll show up here.": "Nada elegido aún — añade ejercicios y aparecerán aquí.",
 "How to": "Cómo hacerlo",
 "instructions in English": "instrucciones en inglés",
 "Best:": "Mejor:",
 "Add to my plan": "Añadir a mi plan",
 "Edit": "Editar",
 "Delete": "Eliminar",
 "Expand": "Ampliar",
 "Minimize": "Minimizar",
 "tap to pause": "toca para pausar",
 "tap to play": "toca para reproducir",
 "Give it a name": "Ponle un nombre",
 "Pick a body part": "Elige una parte del cuerpo",
 "“{0}” already exists": "«{0}» ya existe",
 "Saved": "Guardado",
 "“{0}” created": "«{0}» creado",
 "Edit custom exercise": "Editar ejercicio propio",
 "Name it and pick a body part — it behaves like any other exercise, just without an animation.": "Ponle nombre y elige una parte del cuerpo — funciona como cualquier otro ejercicio, solo que sin animación.",
 "Exercise name": "Nombre del ejercicio",
 "Cardio exercises log time + speed instead of weight × reps.": "Los ejercicios de cardio registran tiempo + velocidad en vez de peso × reps.",
 "Description (optional) — setup, cues, anything you want to remember": "Descripción (opcional) — preparación, consejos, lo que quieras recordar",
 "Save": "Guardar",
 "Create exercise": "Crear ejercicio",
 "Delete exercise": "Eliminar ejercicio",
 "Finish your current workout first": "Termina primero tu entrenamiento actual",
 "Delete “{0}”?": "¿Eliminar «{0}»?",
 "It will be removed from your routines. Already-logged workouts keep their sets.": "Se quitará de tus rutinas. Los entrenamientos ya registrados conservan sus series.",
 "Exercise deleted": "Ejercicio eliminado",
 "Edit or delete this exercise": "Editar o eliminar este ejercicio",
 "Strength": "Fuerza",
 "Equipment": "Equipo",
 "Cardio": "Cardio",
 "Recovery": "Recuperación",
 "custom": "propio"
}
```

`"Imported"` has no es entry. It is stored as **data** (the default `name` of an imported workout) and is never passed through `t()`. Other keys used by this subsystem: `"Import from another app"`, `"FitNotes, Strong, Hevy — or body weight from Apple Health"`, `"Exercise instructions aren't available in this language yet — they stay in English."`, and the muscle names in §3.

## Appendix B: reproduction harness

`scratchpad/harness/` holds `import-csv.mjs` and `muscles.mjs`. Both are verbatim copies with their imports redirected to `shim.mjs`, which loads EXDB and stubs `uid`.

| Script | What it does |
|---|---|
| `tests.mjs` | Replays import-effort cases 1–11 |
| `vectors.mjs` | Matcher, date, duration, distance, effort, CSV, header, muscle and body-weight vectors |
| `more.mjs` | Edge cases and merge |
| `coll.mjs` | Bag collisions and data quirks |
| `alias.mjs` | The alias table |

Run each one with `TZ=UTC node <file>`.
