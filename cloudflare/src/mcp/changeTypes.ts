/**
 * The closed list of change types (coach.md §4.4) as Claude learns it: in propose_changes' schema
 * and in the review prompt. The validator in src/coach enforces it.
 */
export const CHANGE_TYPE_GUIDE = `Change type; target fields in brackets, then the after value:
- add-exercise [routineId]: {id, sets, mode, reps | sec | min+speed, weight?, prog?, position?}. weight only for an exercise they have not trained (capped at their best); position = index to insert at (default: the end).
- remove-exercise [routineId, exId]: null.
- swap-exercise [routineId, exId]: {id, sets?, reps?, weight?}. Keeps the rest of the old slot (mode, time, planned weight unless you give one, policy, step, superset); cannot swap between cardio and non-cardio.
- sets [routineId, exId]: whole number 1–10.
- reps [routineId, exId]: whole number 1–100. The next session becomes a new baseline at the new target.
- repsMin [routineId, exId]: whole number 1–100 (bottom of the double-progression range).
- sec [routineId, exId]: seconds 5–3600. The next session becomes a new baseline.
- cardio [routineId, exId]: {min?, speed?} (minutes 1–180, km/h).
- reorder [routineId]: every exercise id of the routine exactly once, in the new order.
- superset [routineId, exId]: {link: true, with: "<another exId in the routine>"} or {link: false}.
- routine-prog [routineId]: off | linear | greyskull | double.
- exercise-prog [routineId, exId]: a policy valid for the exercise's mode (reps: off|linear|greyskull|double; time: off|time; cardio: off).
- inc [routineId, exId]: progression step > 0 in meta.unit (seconds for time mode).
- add-routine []: {name, emoji?, prog?, ex: [{id, sets, mode, reps | sec | min+speed}]}. Schedule it with a week change in a later proposal, once the owner has accepted it.
- remove-routine [routineId]: null; its weekdays become rest.
- rename-routine [routineId]: the new name (≤ 40 characters).
- week [weekday]: a routine id from the plan, "rest" or null (both make it a rest day).
There is no change that sets a load: the progression engine owns it.`
