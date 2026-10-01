import { cloudflareTest, readD1Migrations } from '@cloudflare/vitest-pool-workers'
import { defineConfig } from 'vitest/config'

export default defineConfig(async () => {
  const migrations = await readD1Migrations('./migrations')
  return {
    plugins: [
      cloudflareTest({
        wrangler: { configPath: './wrangler.jsonc' },
        miniflare: {
          bindings: {
            TEST_MIGRATIONS: migrations,
            PUBLIC_ORIGIN: 'https://opengym.test',
            OWNER_PASSWORD: 'correct horse battery staple',
            APP_ORIGINS: 'https://app.opengym.test',
            ALLOWED_REDIRECT_HOSTS: 'partner.example.com',
          },
        },
      }),
    ],
    test: {
      setupFiles: ['./test/setup.ts'],
    },
  }
})
