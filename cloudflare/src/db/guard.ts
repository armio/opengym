/**
 * Atomic preconditions for compound writes (contract §3.4): a guard statement inserts an invalid
 * row into `guard` when its condition holds, which fails the CHECK constraint and rolls back the
 * whole batch.
 */

export class PreconditionFailedError extends Error {
  constructor() {
    super('precondition failed')
  }
}

/** Aborts the batch when `failWhen` (an SQL boolean expression) is true. */
export function guard(db: D1Database, failWhen: string, ...params: unknown[]): D1PreparedStatement {
  return db.prepare(`INSERT INTO guard (ok) SELECT 0 WHERE ${failWhen}`).bind(...params)
}

function isGuardFailure(error: unknown): boolean {
  const text = error instanceof Error ? `${error.message} ${String(error.cause ?? '')}` : String(error)
  return /CHECK constraint failed/i.test(text) && /\bok\b/.test(text)
}

/** Runs a batch; a failed guard surfaces as `PreconditionFailedError`, anything else is rethrown. */
export async function runGuardedBatch(db: D1Database, statements: D1PreparedStatement[]): Promise<D1Result[]> {
  try {
    return await db.batch(statements)
  } catch (error) {
    if (isGuardFailure(error)) throw new PreconditionFailedError()
    throw error
  }
}
