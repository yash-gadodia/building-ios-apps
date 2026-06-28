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

## Supabase / backend
- `[supabase]` RLS reveal gate must be proven by a pgTAP test that switches to the `authenticated` role + sets `request.jwt.claims` and asserts **real row counts** (0 for non-member/pre-reveal). Policy-existence checks run as owner and prove nothing.
- `[supabase]` Grants aren't automatic — a new table is invisible to `authenticated` (only `Dxt` by default) until `grant select,insert,update,delete`. RLS gates rows; grant gates the verb.
- `[supabase]` A NULL membership slot (deleted/absent partner) breaks `author = member_x` completion checks (NULL comparison) — handle it explicitly; and a "null = done" shortcut for a *dissolved* member is WRONG for a *pending* one. Key such logic on `status`, not just NULL. (Answer-ahead reveal hold.)
- `[supabase]` `supabase db reset` applying the whole migration chain from scratch is the prod dry-run; pair with `supabase test db`. Local Supabase on colima: `supabase start -x vector,analytics --ignore-health-check`.
- `[supabase]` supabase-js typed `.rpc()`/`.update()` can infer `never` — use one documented `// @ts-expect-error`, never `as any`.

## Testing
- `[testing]` `expect(<Component/>).toBeTruthy()` tests nothing (JSX is always truthy). Require `render()` + a real assertion. Reject hollow tests in review.
- `[testing]` Put all native-module mocks in one `jest-setup.ts`; a screen importing a new native module just needs its mock added there — never disable the test.
- `[testing]` Run the suite both parallel and `--runInBand` — a single leaked `setTimeout` presents as flake only one way.
- `[testing]` `getByText` with a regex can match multiple nodes when an atom renders its label in more than one layer → use `getAllByText(...).length`.

## Native / build
- `[native]` Adding a native-module dep → the installed dev-client binary is stale → red screen `Cannot find native module 'X'` at the top-level import. Fix is `npx expo run:ios` (pods + rebuild), NOT a Metro `--clear`.
- `[native]` Reanimated/Fabric `EXC_BAD_ACCESS` in `cloneShadowTreeWithNewProps` (`0xdeaddead`) is usually a transient Fast-Refresh-while-animating dev artifact — boot clean before treating it as a real bug.

## Deployment / EAS
- `[deploy]` Link an EXISTING repo to EAS with `eas init --id <project-id>` — NOT `npx create-expo-app` (Expo's generic onboarding suggests it; it scaffolds a blank app in a subfolder and links the wrong thing).
- `[deploy]` If `--legacy-peer-deps` is needed locally, EAS Build dies at the install phase in ~20s with no clear reason. Fix: a tracked `.npmrc` with `legacy-peer-deps=true`.
- `[deploy]` Android builds need NO Apple account — EAS auto-generates the keystore in the cloud on first build; `preview` profile → installable APK. Prove the pipeline on Android while the Apple account activates.
- `[deploy]` `EXPO_PUBLIC_*` env vars → EAS env vars (`eas env:create --environment <preview|production> ...`), and bind each build profile with `"environment": "<name>"` in eas.json. Never commit them (even publishable keys) for a public repo.
- `[deploy]` Apple Developer: a personal app must NOT ship under an employer's org — seller name, app ownership, revenue payouts, and IP attach to the team you build under. One Apple ID can be on multiple teams → always pick the right team in EAS + the App Store Connect switcher. Enroll **Individual** for personal apps (~US$99/yr, shown in local currency).
- `[deploy]` Hands-off iOS builds: an App Store Connect API key (`.p8` + Key ID + Issuer ID, Admin role, generated under the RIGHT team) lets EAS build+submit without Apple password/2FA prompts.
- `[deploy]` Set up `expo-updates` + `eas update:configure` early → ship JS-only fixes without rebuild/resubmit. The "channel" warning on first build just means expo-updates isn't installed yet.

## Workflow / product
- `[workflow]` After a `supabase db reset`, the app's cached auth session is stale (refresh token wiped) → app signs out on next launch. Re-seed + re-sign-in to test authed screens.
- `[workflow]` osascript keystroke injection and sim taps aren't reliably scriptable here — rely on render-level tests + screenshots of states reachable without typing.
- `[product]` Don't gate the whole app behind a two-sided precondition (e.g. partner pairing). Let users in at peak intent and gate only the part that truly needs the second party; hold the server-side reveal instead. (Solo answer-ahead.)
