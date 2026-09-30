import type { D1Migration } from 'cloudflare:test'

declare global {
  namespace Cloudflare {
    interface Env {
      /** Migrations read by vitest.config.ts and applied in test/setup.ts. */
      TEST_MIGRATIONS: D1Migration[]
    }
    interface GlobalProps {
      /** Types `exports.default` from `cloudflare:workers` in tests. */
      mainModule: typeof import('../src/index')
    }
  }
}

export {}
