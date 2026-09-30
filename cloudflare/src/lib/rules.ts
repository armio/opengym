/** Validation limits shared by sync, proposals and import (contract §3.2). */

/** Workout and exercise ids: 1–64 characters of `[A-Za-z0-9_-]`. */
export const ROW_ID = /^[A-Za-z0-9_-]{1,64}$/

export const MAX_DOC_BYTES = 512 * 1024

export const MAX_WORKOUT_BYTES = 256 * 1024
