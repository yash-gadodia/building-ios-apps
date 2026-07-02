# Cross-project iOS learnings

Running log of non-obvious lessons, newest first. One line each, tagged. When a session teaches something a future app would otherwise re-pay for, add it here (and fold rules into `templates/rules/*` if always-applicable). Tags: `[setup] [rn] [supabase] [testing] [native] [workflow] [product]`.

Seed source: **Parallax** (Expo + RN + Supabase couples app, 2026).

## Setup
- `[setup]` `npm install` errors on reanimated/worklets peer range → use `--legacy-peer-deps` (required, not optional).
- `[setup]` `.env` Supabase URL must be the Mac **LAN IP** (`ipconfig getifaddr en0`), not `localhost`, so a physical phone reaches it; the sim accepts LAN IP too.
- `[setup]` supabase-js default auth storageKey is derived from the URL host (`sb-<firsthostsegment>-auth-token`) — matters if you ever inspect/inject AsyncStorage.

## React Native fidelity
- `[rn]` `lineHeight` is **pixels**, not a multiplier — `lineHeight: 1.5` makes text an invisible sliver. Use `fontSize * ~1.4`.
- `[rn]` Every `<Text>` needs its own explicit `color`; RN doesn't inherit color from parent Views (defaults black → invisible on dark).
- `[rn]` A `linear-gradient(...)` string is not a valid RN color/background → use expo-linear-gradient. Gradient text → MaskedView. Blur → expo-blur.
- `[rn]` Absolute overlay headers/toasts need an opaque or blurred backdrop, else scrolled content bleeds through (transparent `TopBar` overlap bug → frosted blur fix).
- `[rn]` A slow/odd animation can be a per-leg-vs-full-cycle semantics bug, not a per-screen tweak — check the timing math before tweaking call sites.
- `[rn]` In a **size-parameterized atom** (logo/wordmark/badge), `letterSpacing` and internal gaps must be **em-relative** (`size * factor`), never hardcoded px — a value tuned at one size is wrong at another (the wordmark's `letterSpacing: 0.25` was right at 25px, wrong at the 64px logo → `size * 0.01`). For a clean multi-glyph mark, the gap *between* repeated elements must equal the gap to neighbors, and `marginBottom ≈ size*0.22` lands a `flex-end` element on the text baseline.

## Supabase / backend
- `[supabase]` Anything configured in the prod dashboard (pg_cron schedules, RPC revocations) drifts from migrations — commit them IN migrations (guard `if exists (select 1 from pg_extension where extname='pg_cron')`), and re-grant dev-only helper RPCs in `seed.sql` (local-only) instead of leaving them executable in prod.
- `[supabase]` RLS reveal gate must be proven by a pgTAP test that switches to the `authenticated` role + sets `request.jwt.claims` and asserts **real row counts** (0 for non-member/pre-reveal). Policy-existence checks run as owner and prove nothing.
- `[supabase]` Grants aren't automatic — a new table is invisible to `authenticated` (only `Dxt` by default) until `grant select,insert,update,delete`. RLS gates rows; grant gates the verb.
- `[supabase]` A NULL membership slot (deleted/absent partner) breaks `author = member_x` completion checks (NULL comparison) — handle it explicitly; and a "null = done" shortcut for a *dissolved* member is WRONG for a *pending* one. Key such logic on `status`, not just NULL. (Answer-ahead reveal hold.)
- `[supabase]` `supabase db reset` applying the whole migration chain from scratch is the prod dry-run; pair with `supabase test db`. Local Supabase on colima: `supabase start -x vector,analytics --ignore-health-check`.
- `[supabase]` supabase-js typed `.rpc()`/`.update()` can infer `never` — use one documented `// @ts-expect-error`, never `as any`.

- `[supabase]` Changing a function's `returns table (...)` shape errors on `create or replace` — `drop function if exists` first (and re-grant after).
- `[supabase]` If a reveal/score is server-stored with adjustments (e.g. a late-round haircut), every OTHER surface that recomputes from raw rows silently contradicts it — make stored-value-wins (`coalesce(stored, recomputed)`) the rule in each aggregate/history function.

## Testing
- `[testing]` RNTL v14: `fireEvent` self-wraps in `act()` — calling it INSIDE another `act()` yields "overlapping act() calls" warnings; for controlled inputs drive `element.props.onChangeText(...)` directly inside ONE act. Screens starting Animated loops on mount → `jest.useFakeTimers()` (or mock `Animated.timing`) to keep output act-clean.
- `[testing]` `expect(<Component/>).toBeTruthy()` tests nothing (JSX is always truthy). Require `render()` + a real assertion. Reject hollow tests in review.
- `[testing]` Put all native-module mocks in one `jest-setup.ts`; a screen importing a new native module just needs its mock added there — never disable the test.
- `[testing]` Run the suite both parallel and `--runInBand` — a single leaked `setTimeout` presents as flake only one way.
- `[testing]` `getByText` with a regex can match multiple nodes when an atom renders its label in more than one layer → use `getAllByText(...).length`.

- `[testing]` RNTL v14: `fireEvent.press` that must RE-RENDER the tree (toggling local state) needs `await act(async () => { fireEvent.press(...) })` — presses that only assert a mock was CALLED pass without it, which hides the bug until the first state-toggle test.
- `[testing]` pgTAP: a row-tuple comparison containing a NULL yields NULL (test fails with "have: NULL") — assert nullable columns with explicit `is null` AND-chains, never `(a,b,c) = (x,null,z)`.
- `[testing]` pgTAP/psql: a VOLATILE function's inserts are invisible to the SAME statement's snapshot — call the function in one statement, assert its effects in the next (and never put a volatile fn call inside a WHERE, it re-executes per row).
- `[testing]` Cross-role fixtures under RLS: stash values as superuser in a `create temp table` + `grant select ... to authenticated` — works under pg_prove where psql `\gset` may not.

## Native / build
- `[native]` WidgetKit with no local Xcode: `@bacons/apple-targets` (config plugin + Swift target under `targets/`) compiles only on EAS — validate locally with `npx expo config --type prebuild` (do NOT run prebuild in a repo with no tracked `ios/`); the same package's `ExtensionStorage` is a zero-extra-dep App Group data bridge (lazy-require it so jest/Expo Go no-op).
- `[native]` Adding a native-module dep → the installed dev-client binary is stale → red screen `Cannot find native module 'X'` at the top-level import. Fix is `npx expo run:ios` (pods + rebuild), NOT a Metro `--clear`.
- `[native]` Reanimated 4.3.x `EXC_BAD_ACCESS` in `cloneShadowTreeWithNewProps*` (`0xdead…`) racing a `setNativeProps` commit (react-native-svg caller) is a REAL production crash (upstream #9293/#9402), fixed in 4.4–4.5 — upgrade reanimated+worklets together; only suspect a Fast-Refresh artifact after a clean boot reproduces nothing.

## Deployment / EAS
- `[deploy]` EAS free tier = 15 iOS + 15 Android cloud builds/month; ERRORED builds count against quota; `eas submit` and OTA updates are free. Batch native change-sets into one build, OTA everything JS-only, and `eas build --local` (own Mac + Xcode) is the unlimited escape hatch.
- `[deploy]` A NEW native target (widget/extension) makes `eas build --non-interactive` fail with "Distribution Certificate is not validated" — drive the interactive flow with an `expect` script auto-answering defaults. ASC API-key env vars (`EXPO_ASC_API_KEY_PATH/EXPO_ASC_KEY_ID/EXPO_ASC_ISSUER_ID` + `EXPO_APPLE_TEAM_ID/TYPE`) provision certs/profiles headlessly but SKIP App Group identifier syncing (cookies-auth only).
- `[deploy]` App Groups: the capability can be enabled via ASC API (`POST /v1/bundleIdCapabilities`, type `APP_GROUPS`) but registering/assigning the group identifier is dev-portal-only → builds fail "profile doesn't include the App Groups capability" until done by hand; the next build then regenerates profiles automatically.
- `[deploy]` The ASC API can create the ENTIRE IAP catalog headlessly (subscriptionGroups → subscriptions → localizations → **availability BEFORE prices** — posting subscriptionPrices first 409s `ENTITY_ERROR.RELATIONSHIP.INVALID` — then pricePoints lookup by customerPrice with pagination; one-time IAPs via `/v2/inAppPurchases` + priceSchedules with baseTerritory). Still human: In-App Purchase key generation, review screenshots, Paid Apps agreement.
- `[deploy]` RevenueCat API: legacy `sk_` keys are v1-only (v2 config API rejects them — generate a v2 secret key); package actions live at `/v2/projects/{id}/packages/{pkg}` (the offering-nested path 404s); the public `appl_` SDK key and the StoreKit-2 subscription-key upload are dashboard-only (no API). Products must exist in ASC first with matching store identifiers.
- `[deploy]` Supabase Management API (`api.supabase.com`) Cloudflare-blocks default curl/python user-agents (error 1010) — send a real `User-Agent`. `POST /v1/projects/{ref}/database/query` applies migrations when you have the access token but not the DB password; insert into `supabase_migrations.schema_migrations` afterwards so `db push` stays consistent.
- `[deploy]` Link an EXISTING repo to EAS with `eas init --id <project-id>` — NOT `npx create-expo-app` (Expo's generic onboarding suggests it; it scaffolds a blank app in a subfolder and links the wrong thing).
- `[deploy]` If `--legacy-peer-deps` is needed locally, EAS Build dies at the install phase in ~20s with no clear reason. Fix: a tracked `.npmrc` with `legacy-peer-deps=true`.
- `[deploy]` Android builds need NO Apple account — EAS auto-generates the keystore in the cloud on first build; `preview` profile → installable APK. Prove the pipeline on Android while the Apple account activates.
- `[deploy]` `EXPO_PUBLIC_*` env vars → EAS env vars (`eas env:create --environment <preview|production> ...`), and bind each build profile with `"environment": "<name>"` in eas.json. Never commit them (even publishable keys) for a public repo.
- `[deploy]` Apple Developer: a personal app must NOT ship under an employer's org — seller name, app ownership, revenue payouts, and IP attach to the team you build under. One Apple ID can be on multiple teams → always pick the right team in EAS + the App Store Connect switcher. Enroll **Individual** for personal apps (~US$99/yr, shown in local currency).
- `[deploy]` Hands-off iOS builds: an App Store Connect API key (`.p8` + Key ID + Issuer ID, Admin role, generated under the RIGHT team) lets EAS build+submit without Apple password/2FA prompts.
- `[deploy]` Set up `expo-updates` + `eas update:configure` early → ship JS-only fixes without rebuild/resubmit. The "channel" warning on first build just means expo-updates isn't installed yet.

## Workflow / product
- `[workflow]` Fan-out agents on one repo need DISJOINT file ownership lists (including migration numbers); two agents running `supabase db reset` concurrently collide — tell each to wait+retry once on weird db failures.
- `[workflow]` Cloud provider dashboards hide config the API can't read back (RevenueCat public keys, ASC vendor number) — record every dashboard-only value in a gitignored `KEYS.md` index the moment it's seen, or the next session re-derives it by hand.
- `[workflow]` After a `supabase db reset`, the app's cached auth session is stale (refresh token wiped) → app signs out on next launch. Re-seed + re-sign-in to test authed screens.
- `[workflow]` osascript keystroke injection and sim taps aren't reliably scriptable here — rely on render-level tests + screenshots of states reachable without typing.
- `[product]` Don't gate the whole app behind a two-sided precondition (e.g. partner pairing). Let users in at peak intent and gate only the part that truly needs the second party; hold the server-side reveal instead. (Solo answer-ahead.)
- `[workflow]` Two interactive Claude sessions on ONE checkout corrupt each other — the second session should build in a `git worktree` (APFS `cp -c` the node_modules for an instant install) and rebase onto main when the first goes idle.
- `[workflow]` When background agents share a worktree, commit with EXPLICIT file paths per lane — a `git add -A` sweeps other agents' half-done work into your commit.
