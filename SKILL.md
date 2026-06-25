---
name: building-ios-apps
description: Use when starting, scaffolding, planning, or building a new iOS (or cross-platform) app with Expo + React Native + Supabase — covers project setup, the RN fidelity traps, the Supabase RLS security model, testing discipline, native-module rebuilds, the simulator dev loop, and the go-live checklist. Also use when a session produces a reusable, non-obvious lesson worth carrying to the next app.
---

# Building iOS apps (Expo + React Native + Supabase)

**Core principle: each app should be easier to build than the last.** This is the accumulated, *transferable* playbook distilled across apps (seed: Parallax, a Gen-Z couples app). Apply it on day one so you never re-pay for a lesson already learned. When a session teaches something non-obvious, **append it** (see *Capturing learnings*).

`LEARNINGS.md` (next to this file) is the running cross-project log — read it too; it's the long tail this file summarizes.

## The stack that works

- **App:** Expo (managed, with a dev client) · React Native · TypeScript · **Expo Router** (file-based, `app/`).
- **Backend:** **Supabase** (Postgres + Auth + Realtime). **RLS is the security backbone**, not the client.
- **State:** Zustand (UI/local) + @tanstack/react-query + supabase-js. Animations: Reanimated. Blur: expo-blur. SVG: react-native-svg. Gradients: expo-linear-gradient.
- **Tests:** jest + jest-expo + @testing-library/react-native (JS); **pgTAP** (`supabase test db`) for SQL/RLS.

Pin versions to one Expo SDK; let `npx expo install` pick RN/Reanimated/etc. so native peers match.

## Make the repo AI-native on day one (highest leverage)

The single biggest multiplier: **encode the rules in the repo, not in your head.** Before building features, scaffold:

- **`CLAUDE.md`** — the contract loaded every session: stack, commands, conventions, hard "do nots". Keep it <60 lines.
- **`.claude/rules/`** — the hard-won specifics an agent can't infer: `frontend.md`, `database.md`, `testing.md`, `workflow.md`, `git.md`.
- **`ARCHITECTURE.md` + `docs/`** — deeper context read on demand (keeps CLAUDE.md lean).
- **Memory** — durable cross-session facts.

Templates for all of these are in `templates/` — copy them and adapt. Time spent here pays back every turn (it's what stops an agent from "fixing" valid RN code or shipping a hollow test).

## React Native fidelity traps (the expensive ones)

These cost real hours the first time. They are in `templates/rules/frontend.md` — the worst offenders:

- **`lineHeight` is PIXELS, not a CSS multiplier.** `lineHeight: 1.5` clips text to an invisible sliver. Use `fontSize * ~1.4` (e.g. 14 → 20).
- **Every `<Text>` needs its own explicit `color`.** RN does NOT inherit color from a parent `<View>` (default black) → white-on-dark text renders invisible.
- **Web→RN swaps:** a `linear-gradient(...)` string is NOT a valid `backgroundColor`/`color` → use `expo-linear-gradient`. Gradient text → MaskedView. CSS blur → expo-blur. keyframes → Reanimated. `pointerEvents` is a prop, not a style key.
- **Absolute overlays (headers/toasts) need an opaque or blurred backdrop** or scrolling content bleeds through them. (Parallax: a transparent `TopBar` overlapped scrolled content — fix was a frosted blur backdrop.)
- **Build the atom library once** (Button, Text wrappers, Card, Icon, design tokens) and *reuse* it. Don't reimplement per screen.

## Supabase backend patterns (the security model)

Full detail in `templates/rules/database.md`. The non-negotiables:

- **RLS is the privacy backbone.** Every sensitive table carries an owner/group id; the policy is "current user is a member." Never enforce privacy in the client.
- **Cross-user / cross-partner writes go through `SECURITY DEFINER` Postgres functions** called via `.rpc()`. Never trust client-side table writes for shared data.
- **Server-gated reveals/state transitions live in the DB**, proven by pgTAP that switches into the `authenticated` role + sets `request.jwt.claims` and asserts **real row counts** (a pre-reveal/non-member reads **0 rows**). Policy-existence checks are NOT proof.
- **Grants are NOT automatic.** New table → it's invisible to `authenticated` until you `grant select,insert,update,delete ... to authenticated`. RLS still gates rows; the grant gates the verb.
- **Migrations:** sequential `00NN_*.sql`, idempotent (`if not exists`, `create or replace`), **non-destructive** (no `DROP`/destructive `ALTER` on live tables). A clean `supabase db reset` applying the *whole chain* is your prod dry-run.
- **`// @ts-expect-error`, not `as any`,** for the supabase-js typed-`.rpc()`-infers-`never` quirk.

## Testing discipline

Detail in `templates/rules/testing.md`. The rules that matter:

- **Tests must exercise the thing**: `render()` + a real query/assertion, or `toJSON()` smoke. **NEVER `expect(<JSX/>).toBeTruthy()`** — a JSX literal is always truthy and tests nothing. This bug ships repeatedly; reject it in review.
- **Exact assertions** (`toBe(7)`, `toBeCloseTo(0.42)`) — never `> 0` / "truthy".
- **Pure logic first.** Keep scoring/parsing/date logic in an RN-free `src/domain/*` and unit-test it with exact values — highest ROI.
- **All native-module mocks live in one `jest-setup.ts`** (reanimated, safe-area, expo-router, supabase, async-storage, env). New screen imports a native module that throws in jest? Add its mock there — don't disable the test. Template: `templates/jest-setup.ts`.
- Hollow tests are worse than none — they make CI green while testing nothing.

## Native modules & dev-client rebuilds (a crash class)

- Adding a dep with a **native module** (e.g. `expo-notifications`, anything with iOS pods) means the **installed dev-client binary is stale** — the JS bundle references a native module the binary lacks. Symptom: red screen `Cannot find native module 'X'` at the top-level `import`, *before* any runtime guard runs.
- **Fix: rebuild the native client** — `npx expo run:ios` (installs pods + recompiles). A Metro `--clear` reload is NOT enough.
- Guarding usage at call sites does NOT save you if the *import* eval touches the native module. Lazy-require inside the guard, or just rebuild.
- Reanimated/Fabric can crash natively (`EXC_BAD_ACCESS` in `cloneShadowTreeWithNewProps`, `0xdeaddead` poison) when an animation commits onto an unmounted node — often a transient dev-mode artifact of Fast Refresh *while animations run*. Boot clean before treating it as a real bug.

## The dev loop + verification bar

Run on the **simulator** and look at pixels — a build succeeding ≠ the screen looking right.

```bash
xcrun simctl list devices booted                 # is a sim up?
curl -s http://127.0.0.1:8081/status             # is Metro up? -> packager-status:running
xcrun simctl launch booted <bundleId>            # launch
xcrun simctl io booted screenshot /tmp/s.png     # capture — then VIEW it
```

**Definition of done (every change, show the output):**
```
npx tsc --noEmit          # 0 errors
npx jest                  # green (run --runInBand too to catch timer-leak flake)
npx expo export -p ios    # bundles every route
supabase db reset && supabase test db   # if SQL changed: full chain + pgTAP
```
Plus a screenshot for anything user-facing. Never claim done/fixed/passing from inference. After **2 failed attempts at the same approach, stop and rethink** — investigate root cause, don't brute-force.

## The "gated stub" pattern (credential-bound features)

Push notifications, payments (RevenueCat), AI (Anthropic edge fn), OAuth — all need creds you won't have while building. **Build the full UI + wiring behind a labeled stub that no-ops gracefully** (mark with a `// GATE:` comment), so the app runs end-to-end in a demo/solo mode with zero setup. List every gate in a `docs/GO_LIVE.md` (template provided) so go-live is a checklist, not an archaeology dig.

Make the core loop **solo-testable**: a `sim_partner`/demo path so a two-sided flow completes with one person, and feature hooks fall back to local sample data when there's no session.

## Scaffolding a new app

1. `npx create-expo-app@latest <name>` (TypeScript) → `cd` in → `git init`.
2. Copy `templates/CLAUDE.md`, `templates/rules/*` → `.claude/rules/`, `templates/jest-setup.ts`, `templates/DEV_SETUP.md`, `templates/GO_LIVE.md`; fill the `<PLACEHOLDERS>`.
3. `npx expo install expo-router expo-linear-gradient expo-blur react-native-reanimated react-native-safe-area-context @supabase/supabase-js @react-native-async-storage/async-storage zustand`. Install with `--legacy-peer-deps` if reanimated's peer range errors.
4. `supabase init` → author `0001_*.sql` from the reveal-gate pattern in `templates/migration-rls-pattern.sql` → `supabase start` → `supabase db reset`.
5. Wire jest (`jest-expo` preset + `jest-setup.ts`), add the `tsc/jest/export` scripts.
6. Add a `seed-test-user` script so you can sign in without the email step.
7. Verify the empty app boots on the sim + the verification bar is green **before** building features.

## Capturing learnings (the compounding protocol)

When a session produces a non-obvious lesson — a real root cause, a gotcha, a 2+-attempt fix — **append it before moving on**, so the next app never re-pays:

1. One-line entry in this repo's `LEARNINGS.md` (newest first), tagged `[setup] [rn] [supabase] [testing] [native] [workflow]`.
2. If it's a rule the agent should always follow, fold it into the matching `templates/rules/*.md` so future scaffolds inherit it.
3. If it's a transferable *pattern*, summarize it in the relevant section above.

The test: "Would a future app waste time rediscovering this?" If yes, write it down now. Knowledge compounds; rabbit holes shouldn't repeat.

## Templates index

- `templates/CLAUDE.md` — project contract starter
- `templates/rules/{frontend,database,testing,workflow,git}.md` — the hard-won rule set
- `templates/jest-setup.ts` — all native-module mocks in one place
- `templates/migration-rls-pattern.sql` — reveal-gate / RLS + SECURITY DEFINER reference
- `templates/DEV_SETUP.md` · `templates/GO_LIVE.md` — onboarding + launch checklists
