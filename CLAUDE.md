# Notes for Claude

## Owner context

- The owner has a **paid Apple Developer Program** membership. Do not warn about free
  provisioning limits (7-day expiry, missing HealthKit or other capabilities); assume TestFlight
  and every paid capability are available.
- The owner's iPhone build uses the bundle identifier `cc.armio.gym`.
- Production backend: `https://gym.armio.cc` (Cloudflare Worker `opengym`, D1 `opengym-db`,
  KV `opengym-oauth`). The Claude MCP connector is `https://gym.armio.cc/mcp`.
- The owner writes in Spanish; the app UI and `docs/flutter-cloudflare/SETUP.md` are in Spanish.

## Flutter + Cloudflare port

- Contract: `docs/flutter-cloudflare/ARCHITECTURE.md`. Setup guide: `docs/flutter-cloudflare/SETUP.md`.
- Worker (`cloudflare/`): `npm run typecheck`, `npm test`. Deploy with `scripts/deploy.sh`.
- App (`app/`): `flutter analyze`, `flutter test`, `flutter build web`. Format with `dart format -l 120`.
- Never print or commit `OWNER_PASSWORD` or Cloudflare API tokens.
