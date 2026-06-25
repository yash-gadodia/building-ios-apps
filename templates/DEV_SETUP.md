# Dev Setup — running <APP_NAME> locally

From-scratch guide to run the app on a Mac.

## 1. Prerequisites
| Tool | Why | Install |
|---|---|---|
| macOS (Apple Silicon) | iOS builds | — |
| Node 20+ LTS | Expo runtime | `brew install node` |
| Xcode + a simulator | iOS dev build | App Store → open once → install a sim |
| Docker (OrbStack) | local Supabase | `brew install orbstack` |
| Supabase CLI | local Postgres/Auth/Realtime | `brew install supabase/tap/supabase` |

Check: `node -v` (≥20) · `xcrun simctl list devices | grep Booted` · `docker ps` · `supabase --version`.

## 2. Install JS deps
```bash
npm install --legacy-peer-deps   # the flag is REQUIRED — reanimated/worklets peer range
```

## 3. Environment
```bash
cp .env.example .env
```
`.env` needs the public URL + anon key (anon key is safe client-side — RLS is the backbone):
```
EXPO_PUBLIC_SUPABASE_URL=http://<your-LAN-IP>:54321   # ipconfig getifaddr en0 — NOT localhost
EXPO_PUBLIC_SUPABASE_ANON_KEY=<anon key from `supabase start`>
```
Use the Mac LAN IP so a physical phone on the same Wi-Fi reaches it; the sim accepts it too.

## 4. Backend (local Supabase)
```bash
supabase start          # boots Postgres + Auth + Realtime + Studio in Docker
supabase db reset       # applies all migrations + seed (wipes local data)
./scripts/seed-test-user.sh   # a pre-confirmed user so you can skip the email step
```
On colima instead of OrbStack: `supabase start -x vector,analytics --ignore-health-check`.
Studio: http://127.0.0.1:54323 · Mailpit (catches signup emails): http://127.0.0.1:54324

## 5. Run
```bash
npx expo start          # press i (iOS sim). First run with a native dep: npx expo run:ios
```

## Troubleshooting
- **`Cannot find native module 'X'`** → you added a native dep; rebuild: `npx expo run:ios` (Metro `--clear` is not enough).
- **App signed out after `supabase db reset`** → the refresh token was wiped; re-seed + sign in again.
- **pgTAP FAIL right after psql work** → dirty DB; `supabase db reset` first.
