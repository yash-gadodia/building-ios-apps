# The Playbook — Expo/React Native → App Store, end to end

The ordered launch guide, distilled from shipping **Parallax** (a couples app: Expo + React Native + Supabase → TestFlight → App Store submission). `SKILL.md` is the build-phase companion (RN traps, testing, RLS); `LEARNINGS.md` is the gotcha log. This file is the **spine**: follow it top-to-bottom for the next app and nothing about launch is archaeology.

Everything here was actually done for Parallax. Where a step is app-specific, it says so. All identifiers are placeholders (`<KEY_ID>`, `<ISSUER_ID>`, `<ASC_APP_ID>`, `<REF>`, `com.<you>.<app>`) — **never commit a real one's secret sibling** (chapter 3).

## Contents

1. [Project setup](#1-project-setup)
2. [Backend: Supabase](#2-backend-supabase)
3. [Secrets discipline for a public repo](#3-secrets-discipline-for-a-public-repo)
4. [Apple Developer + App Store Connect](#4-apple-developer--app-store-connect)
5. [Push notifications](#5-push-notifications)
6. [EAS: build, submit, update](#6-eas-build-submit-update)
7. [IAP + RevenueCat](#7-iap--revenuecat)
8. [Legal + compliance](#8-legal--compliance)
9. [Review prep](#9-review-prep)
10. [Multi-agent / two-session hygiene](#10-multi-agent--two-session-hygiene)

---

## 1. Project setup

Full scaffold procedure: `SKILL.md` → *Scaffolding a new app*. The launch-relevant bones:

- **Stack:** Expo (managed + dev client) · React Native · TypeScript · **Expo Router** (file-based, `app/`) · Supabase backend · jest + jest-expo + @testing-library/react-native · pgTAP.
- **`npm install --legacy-peer-deps` is required, not optional** (reanimated/worklets peer range). Commit a `.npmrc` with `legacy-peer-deps=true` on day one — EAS cloud builds run plain `npm install` and **die at the install phase in ~20s** without it.
- Make the repo AI-native before features: `CLAUDE.md`, `.claude/rules/*`, `docs/` (templates in `templates/`). This is the highest-leverage hour of the project.
- Wire the testing bedrock immediately: jest-expo preset, one `jest-setup.ts` holding every native-module mock, co-located `*.test.tsx`. RNTL v14's async `render()`, the `act()` overlap traps, and the hollow-test ban are in `LEARNINGS.md` → *Testing* — read them before writing the first test, not after the first flake.
- The verification bar for every change, from day one:
  ```bash
  npx tsc --noEmit          # 0 errors
  npx jest                  # green (parallel AND --runInBand)
  npx expo export -p ios    # bundles every route
  supabase db reset && supabase test db   # if SQL changed
  ```
- Build **credential-bound features behind labeled gates** (`// GATE:`) that no-op gracefully, and keep the core loop solo-testable. List every gate in `docs/GO_LIVE.md` so launch is a checklist.

## 2. Backend: Supabase

### Local stack

- Local dev runs Supabase in Docker. On **colima**, the `vector` log container can't mount docker.sock → `supabase start -x vector,analytics --ignore-health-check`.
- `.env` (gitignored) points at the **local** stack — use the Mac's LAN IP, not `localhost`, so a physical phone reaches it. Local dev never touches prod.

### Migrations discipline

- Sequential `00NN_*.sql`, **idempotent** (`if not exists`, `create or replace`), **non-destructive** on live tables.
- `supabase db reset` applies the whole chain from scratch — that is your **prod dry-run**. Pair it with `supabase test db` (pgTAP).
- Anything configured in the prod **dashboard** (cron schedules, revocations) drifts from migrations — commit it *in* a migration, guarded (`if exists (select 1 from pg_extension where extname='pg_cron')`).

### RLS is the security backbone

- Every sensitive table carries an owner/group id; the policy is "current user is a member". Privacy is **never** enforced in the client.
- **Cross-user writes go through `SECURITY DEFINER` Postgres functions** called via `.rpc()` — never raw table writes for shared data.
- **Grants are not automatic**: a new table is invisible to `authenticated` until you `grant select,insert,update,delete`. RLS gates rows; the grant gates the verb.
- Prove it with **pgTAP that switches into the `authenticated` role, sets `request.jwt.claims`, and asserts real row counts** (0 for a non-member). Policy-existence checks run as owner and prove nothing. Tests must be hermetic (own `gen_random_uuid()` rows, never global counts).

### Prod project

- **Region is PERMANENT.** Pick it at creation (Parallax: first project landed in the wrong region and had to be recreated). Choose closest-to-users.
- The direct DB host (`db.<REF>.supabase.co`) is **IPv6-only** — most networks can't reach it. Push migrations through the **Session pooler** (IPv4, port **5432**; the 6543 transaction pooler is for serverless runtime, not DDL):
  ```bash
  supabase db push --db-url "postgresql://postgres.<REF>:<DB_PASSWORD>@<POOLER_HOST>:5432/postgres"
  supabase migration list --db-url "..."   # Local ↔ Remote must match
  ```
- Verify RLS landed: `select tablename, rowsecurity from pg_tables where schemaname='public';` — all `t`.

### The Management API (`api.supabase.com`) — the headless lever

- **Cloudflare blocks default curl/python user-agents** (error 1010) — always send a real `User-Agent` header.
- **Auth providers: PATCH, don't `config push`.** `PATCH /v1/projects/<REF>/config/auth` with just the fields you're setting (e.g. `external_apple_enabled` + `external_apple_client_id` = the bundle ID; the secret stays `null` for the native Sign-in-with-Apple flow). ⚠️ `supabase config push` uploads your whole local `[auth]` block (localhost site_url, redirects) and **clobbers prod**.
- **No DB password handy?** `POST /v1/projects/<REF>/database/query` runs SQL with just the access token — it can apply a migration. If you use it, also `insert into supabase_migrations.schema_migrations (version, name, statements) values (...)` so `db push` stays consistent.

### Edge functions

- `supabase/functions/` is **tsconfig-excluded and has no local Deno check** — a ReferenceError is invisible to every local gate. Re-read edge-fn diffs by hand and **smoke-invoke after every deploy**.
- Server-side keys (`ANTHROPIC_API_KEY`, `RESEND_API_KEY`, …) go in via `supabase secrets set` — never the client, never the repo.
- Set `verify_jwt = true` for user-facing functions before prod (unauth → 401), and rate-limit anything that spends money (Parallax: a `claim_*_slot` SECURITY DEFINER function capping calls/hr/user before the AI call).
- ⚠️ **The injected `SUPABASE_SERVICE_ROLE_KEY` inside a deployed edge function is the NEW `sb_secret_…` "default secret"** (Settings → API keys), **NOT the legacy JWT `service_role` key**. Any in-function bearer gate (`Authorization: Bearer <key>` compared against `Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")`) must be called with the `sb_secret_…` value — a cron sending the legacy JWT gets 401s that look like a code bug.

### Scheduled invocation (pg_cron + pg_net)

Two patterns, both used in Parallax:

1. **Plain SQL on a schedule** — `cron.schedule(...)` calling a SQL function (e.g. a daily streak reset). Commit it in a migration, guarded on the extension existing.
2. **Edge function on a schedule** — pg_cron → **pg_net** `net.http_post` to the function URL with the service-role bearer. The key **cannot live in a migration in a public repo** — store it in **Supabase Vault** and have a small SQL invoker function read it (`vault.decrypted_secrets`) at call time. Rotate in Vault when keys rotate.
3. **Make reruns safe before you schedule anything.** Give every outbound send an **at-most-once claim ledger** (`unique(entity, kind, sent_on)` + `insert … on conflict do nothing returning`) so overlapping hourly runs can't double-send — and **claim each kind immediately before its own send**, or a later failure burns the day's notification. Never point pg_cron directly at a claiming function with no sender attached.

## 3. Secrets discipline for a public repo

Building in the open is great — until the first `.p8` lands in `~/Downloads`. The pattern (full rule: this repo's `templates/rules/*` + Parallax `.claude/rules/secrets.md`):

- **`.secrets/` at repo root, gitignored** — every real key file and value lives there (`.secrets/apple/`, `.secrets/appstore/`, …), `chmod 600`. When a key is downloaded, **move it in and delete the Downloads copy**.
- **`.secrets/KEYS.md`** — the *value index*: every Key ID / Issuer ID / project ref / token, with a pointer to its file. Dashboards hide values the API can't read back — record each one **the moment you see it** or the next session re-derives it by hand.
- **`docs/CREDENTIALS.md` (tracked)** — a **map, never values**: what each credential is, where it lives (`.secrets/` + password manager + which dashboard). This is what makes the repo safely public *and* onboardable.
- **Read values from files at runtime** (`TOKEN=$(cat .secrets/expo-token)`); never inline a secret into a command, a tracked file, or logged output.
- **Enforce with a hook**: a PreToolUse/pre-commit hook blocking writes to `*.env|*.pem|*.key|*.p8|*.p12|*credentials*`. (Parallax shipped a hook missing `*.p8` — the exact type used all day. Audit the glob list against reality.)
- Client-embedded config (`EXPO_PUBLIC_*`) goes in **EAS env vars**, not the repo — even "publishable" keys, for hygiene.
- **Any leak = rotate immediately.** Rotation makes the leaked copy dead; scrubbing history does not.

## 4. Apple Developer + App Store Connect

### Account

- **Personal app → enroll Individual** (~US$99/yr, shown in local currency). **Never ship a personal app under an employer's org** — seller name, ownership, payouts, and IP attach to the team you build under.
- One Apple ID can sit on multiple teams → **pick the right team every time**: in EAS prompts *and* the App Store Connect team switcher (top-right).

### Identifiers (developer.apple.com → Certificates, Identifiers & Profiles)

- **App ID** (explicit), bundle = `app.json`'s `bundleIdentifier`. Enable the capabilities you need (Push Notifications, Sign in with Apple) at creation.
- ⚠️ **App IDs ≠ Services IDs, and identifiers are globally unique across types.** A Services ID is the *web* OAuth flow only; native RN/Expo uses the App ID. A stray Services ID on your bundle string **blocks** creating the App ID — delete it first.

### App record

App Store Connect → Apps → **＋ New App**: platform iOS, your Bundle ID, a **unique name ≤30 chars** (check availability — your first choice is probably taken; `AppName: Category` works), SKU = any private string.

### The ASC API key — mint JWTs, skip the clicking

Users and Access → **Integrations → App Store Connect API** → create a key (**Admin**), download the **`.p8` (one time only!)**, note **Key ID** + **Issuer ID**. Store in `.secrets/appstore/`.

This one key unlocks: headless EAS build+submit (no Apple password/2FA), the **entire IAP catalog** (chapter 7), IAP review-screenshot upload, build/status polling, metadata editing. The dashboard is for the few things the API can't do; the API is the default.

**Minting the ES256 JWT** — the signature must be raw `r‖s`, which plain `openssl dgst` won't give you (it emits DER); the reliable recipe is ~20 lines of Python on the `cryptography` lib:

```python
#!/usr/bin/env python3
"""Mint an ES256 App Store Connect JWT. Prints token to stdout."""
import json, time, base64
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature

KEY_PATH = ".secrets/appstore/AuthKey_<KEY_ID>.p8"
KID = "<KEY_ID>"
ISS = "<ISSUER_ID>"   # one per account, atop the Integrations page

def b64url(b): return base64.urlsafe_b64encode(b).rstrip(b"=").decode()

now = int(time.time())
header  = b64url(json.dumps({"alg": "ES256", "kid": KID, "typ": "JWT"}).encode())
payload = b64url(json.dumps({"iss": ISS, "iat": now, "exp": now + 1140,   # ≤20 min
                             "aud": "appstoreconnect-v1"}).encode())
signing_input = f"{header}.{payload}".encode()

with open(KEY_PATH, "rb") as f:
    key = serialization.load_pem_private_key(f.read(), password=None)
der_sig = key.sign(signing_input, ec.ECDSA(hashes.SHA256()))
r, s = decode_dss_signature(der_sig)
print(f"{header}.{payload}.{b64url(r.to_bytes(32,'big') + s.to_bytes(32,'big'))}")
```

Then `Authorization: Bearer <token>` against `https://api.appstoreconnect.apple.com/v1/...`. (PyJWT with `algorithm="ES256"`, `headers={"kid": KID}` works too if it's installed.)

**Known API blind spot:** agreements/contracts have **no endpoint** (`/v1/agreements` → 404) — Paid Apps Agreement status must be eyeballed in the browser (ASC → Business).

## 5. Push notifications

- **APNs auth key (`.p8`), token-based** — the legacy per-app SSL certs are dead; if a portal dialog offers "APNs SSL Certificates", ignore it. EAS can create and manage the key for you (`eas credentials` or automatically during build).
- **One APNs key serves Sandbox AND Production by design.** TestFlight and the App Store both use the **Production** APNs environment. If a key was hand-created Sandbox-only it silently fails for testers — but **don't chase "sandbox-only" ghosts** on an EAS-managed key: check expo.dev → project → credentials; keys EAS creates are Sandbox+Production.
- **Client wiring (expo-notifications):** pass the EAS `projectId` to `getExpoPushTokenAsync` (standalone builds can't mint a token without it), register the token on **every authenticated launch** (not just onboarding), store it server-side (e.g. `profiles.push_token`).
- **Remote vs local:** event-driven pushes (partner played / revealed / paired) go server-side — an edge function reads the token and POSTs to Expo's push API; **check per-ticket responses** — silence is indistinguishable from success. Daily same-device nudges can be **local scheduled notifications** — they work with zero server setup and ship before your cron does.
- **A new build is required** for push wiring to reach users — a TestFlight build cut before the client wiring predates it; OTA won't add a native capability.
- **Android is separate:** FCM key into EAS. iOS-first launches can defer it.

## 6. EAS: build, submit, update

### Setup

- **Existing repo → `eas init --id <PROJECT_ID>`.** ⚠️ Do NOT follow generic onboarding into `npx create-expo-app` — it scaffolds a blank app in a subfolder and links *that*.
- Non-interactive auth: `EXPO_TOKEN` env var (expo.dev → Access Tokens). But token-only auth **cannot create iOS credentials** — the ASC API key (ch. 4) is what unlocks headless cert/profile generation and submit.
- `eas.json`: `cli.appVersionSource: "remote"` + `autoIncrement: true` on the production profile — build numbers manage themselves.
- Profiles: `development` (dev client) / `preview` (internal distribution; Android → installable APK) / `production`. Bind each to an EAS env with `"environment": "<name>"`; create vars with `eas env:create --environment production --name EXPO_PUBLIC_... --value ...`.
- Wire submit once in `eas.json` and forget Apple prompts forever:
  ```jsonc
  "submit": { "production": { "ios": {
    "ascAppId": "<ASC_APP_ID>",
    "ascApiKeyPath": "./.secrets/appstore/AuthKey_<KEY_ID>.p8",
    "ascApiKeyId": "<KEY_ID>",
    "ascApiKeyIssuerId": "<ISSUER_ID>"
  }}}
  ```
  Then `eas build -p ios --profile production --auto-submit` (or `eas submit -p ios --latest`).

### Discipline

- **Free tier = 15 iOS + 15 Android cloud builds/month, and ERRORED builds count.** Run `npx expo-doctor` and fix locally **before** every build — don't debug by re-kicking. `eas build --local` (a Mac with Xcode) is the unlimited escape hatch.
- **Prove the pipeline on Android first** — no Apple account needed; the keystore is auto-generated in the cloud on first build.
- **Build vs OTA:** native change (new native lib, `app.json`, icons, permissions) → **build**. JS/screens/copy only → **`eas update --branch production -m "..."`** — instant, free, no review. Install `expo-updates` + `eas update:configure` early; the "channel" warning on the first build just means it isn't installed yet.
- **Working tree has concurrent WIP? Build from a clean clone.** `git clone` into a temp dir at the pushed commit and run `eas build` from there — never ship half-committed lanes because the build snapshot swept them in.

## 7. IAP + RevenueCat

### The Paid Apps Agreement chain — start it the day the account activates

Nothing money-related ships without it, and Apple's side takes time:

1. ASC → Business: **accept the Paid Apps Agreement**.
2. Submit **banking** + **tax forms** (non-US: **W-8BEN** + Certificate of Foreign Status + your country's tax questionnaire).
3. Status goes **Processing** → **Active** (hours to ~days). No API for this — eyeball it.
4. **Auto-renewable subscriptions sit at `MISSING_METADATA` until the agreement is Active** even with all metadata present. **One-time IAPs don't need it** and flip to `READY_TO_SUBMIT` as soon as their metadata is complete — that asymmetry is diagnostic, not a bug.
5. **Apply for the Small Business Program (15% commission) immediately after acceptance** — it's a separate application on the same page-cluster; there's no reason to launch at 30%.

### Creating the catalog via the ASC API (headless, proven)

Order matters:

1. `POST /v1/subscriptionGroups` (+ a `subscriptionGroupLocalizations` name).
2. `POST /v1/subscriptions` per sub (productId, period) + localizations.
3. **Availability BEFORE prices** — posting `subscriptionPrices` first 409s `ENTITY_ERROR.RELATIONSHIP.INVALID`.
4. Prices: page `…/pricePoints?filter[territory]=USA` matching `customerPrice`, then POST the price with that point.
5. One-time IAPs: `POST /v2/inAppPurchases` + `inAppPurchasePriceSchedules` (baseTerritory).
6. **Review screenshot per IAP** — required before any IAP leaves `MISSING_METADATA` (besides the agreement). Uploadable via the API (reserve → upload → commit; verify `assetDeliveryState: COMPLETE`). Min 640×920; a real screenshot of your paywall/plan-picker surface.

**The first auto-renewable subscription must be submitted together with an app version** — if you submit v1.0 without the subs attached, they wait for a 1.0.1. If the agreement is close to Active, hold the submission and ship everything in one shot.

### RevenueCat

- Products must exist in ASC **first**, with matching store identifiers; then RC project → iOS app → entitlement → products → offering/packages, all scriptable via **API v2** (legacy `sk_` keys are v1-only — generate a v2 secret key; package actions live at `/v2/projects/{id}/packages/{pkg}`).
- The **public `appl_…` SDK key is designed to ship in the client** — put it in EAS env (`EXPO_PUBLIC_REVENUECAT_IOS_KEY`), still not in the repo. The **secret key is never** client-side.
- Two dashboard-only steps the API can't do: the public SDK key read-off and the **StoreKit In-App Purchase key upload** (generate in ASC → Keys → In-App Purchase, upload to RC). Record both in `KEYS.md` when done.
- Verify end-to-end with API reads before trusting it: entitlement lookup_key matches the client constant, products attached, offering `is_current`, `subscription_key_configured: true`.

## 8. Legal + compliance

- **Privacy Policy + Terms hosted free on GitHub Pages**: put HTML under `main:/docs` (with a `.nojekyll` file) or a `gh-pages` branch, enable Pages, done — `https://<user>.github.io/<repo>/legal/privacy.html`. App Store requires the privacy URL; a couples/personal-data app should treat the terms as load-bearing too (AI features disclaim "not therapy/crisis support").
  - ⚠️ **Rapid successive pushes can wedge a Pages build.** Unjam via the API: `gh api -X POST repos/<user>/<repo>/pages/builds` re-requests a build; poll `repos/<user>/<repo>/pages/builds/latest` until `built`; then curl the live URL with a cache-buster to confirm.
- **`ITSAppUsesNonExemptEncryption: false`** in `app.json` → `ios.infoPlist` — skips the export-compliance questionnaire on every single submission (correct for apps using only standard HTTPS).
- **Account deletion is a hard requirement (5.1.1(v))** — and "delete my rows" isn't enough: erase the **Auth record** too (a JWT-gated edge function running your `delete_my_account()` RPC then `auth.admin.deleteUser`). Reviewers test it.
- **App Privacy nutrition labels** — fill accurately; mismatches are a top rejection cause. The Parallax mapping as a worked example: email (Contact Info, linked, app functionality), user content (linked, app functionality), user ID (identifiers), purchases via RevenueCat (app functionality), analytics only if enabled; **tracking = No** (no ATT prompt) unless you add an ads/attribution SDK.

## 9. Review prep

- **Seed a demo/reviewer account on prod** — reviewers must see the real experience, not the empty-state wall. For a two-sided app that means a **pre-paired couple with history** (Parallax: a couple with several revealed drops and a live streak), seeded server-side. Creds go in App Review Information → Sign-In Required, and in your `.secrets/KEYS.md`.
- **Review notes** explain the two-sided mechanics: *"this is a couples app; the demo account is pre-paired so you can see the full loop; solo users can play ahead."*
- **Working sign-up email**: Supabase's default sender is rate-limited — wire real SMTP (e.g. Resend) or reviewers literally cannot register (guideline 2.1 rejection).
- **Attach the IAPs to the app version** before submitting (and remember ch. 7: the first subs must ride with a version).
- Pre-answer the classics: account deletion built, privacy URL live, labels accurate, demo account provided, IAP through StoreKit only, **Sign in with Apple parity** (offering Google sign-in requires offering Apple's too — 4.8), app passes the verification bar.
- Sequence: TestFlight (internal testers install ~5–15 min after processing) → soak → App Store review.

## 10. Multi-agent / two-session hygiene

Running parallel Claude sessions/agents on one repo shipped Parallax fast — with rules:

- **Disjoint file-lane ownership** per agent/session, agreed up front — including **migration numbers** (two sessions numbering independently WILL collide on the `schema_migrations` version prefix; and a dashboard-created cron can duplicate a migration-created one → double-runs with user-visible harm). Reserve `00NN` explicitly.
- **Commit with explicit file paths, never `git add -A`** — a sweep commits other lanes' half-done work (and a production build cut from that tree ships it).
- **`git pull --rebase origin main` before every push**; when other lanes have uncommitted WIP, rebase with `--autostash` so their changes survive untouched.
- Two *interactive* sessions on one checkout corrupt each other — the second belongs in a **`git worktree`** (APFS `cp -c` the `node_modules` for an instant install), rebasing onto main when the first goes idle.
- Concurrent `supabase db reset` collides — tell each agent to wait + retry once on weird DB failures.
- **Pre-existing failures in another lane's files are surfaced, not fixed** — report them in your lane's summary and move on.

---

*When launch teaches you something new, append it to `LEARNINGS.md` and fold it back into the right chapter here. The point is that the next app's go-live is a checklist, not a discovery process.*
