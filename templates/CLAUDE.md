# <APP_NAME>

<ONE_LINE_WHAT_IT_IS>. Design source of truth: `<design_dir>`.

Read ARCHITECTURE.md before planning or structural changes. The agent auto-follows clarify → plan → implement → test → self-review, scaled to task size.

## Commands
- **Install**: `npm install` (use `--legacy-peer-deps` if reanimated/worklets peer range errors)
- **Dev**: `npx expo start` (press `i` iOS sim, `a` Android) · **Bundle check**: `npx expo export -p ios`
- **Test**: `npm test` (jest) · **Typecheck**: `npm run typecheck`
- **Local backend**: `supabase start` → `supabase db reset` · **DB tests**: `supabase test db` (pgTAP)

## Stack
- **App**: Expo SDK <NN>, React Native <X>, TypeScript, **Expo Router** (file-based, `app/`)
- **Backend**: **Supabase** (Postgres + Auth + Realtime); RLS is the privacy backbone
- **State**: Zustand + @tanstack/react-query + supabase-js; Reanimated, react-native-svg, expo-blur
- **Tests**: jest + jest-expo + @testing-library/react-native; pgTAP for SQL/RLS

## React Native fidelity (see `.claude/rules/frontend.md`)
- `lineHeight` is **pixels**, never a multiplier (`fontSize*1.4`, NOT `1.5`).
- Every `<Text>` needs its **own explicit `color`** — RN does not inherit color from parent Views.
- Reuse the atoms in `src/components`. Tokens from `src/design`. Don't reimplement.

## Supabase (see `.claude/rules/database.md`)
- All cross-user writes go through SECURITY DEFINER functions; never trust the client. Gates enforced in RLS (pgTAP-proven).
- supabase-js typed `.rpc()`/`.update()` may infer `never` — use a documented `// @ts-expect-error`, never `as any`.

## Conventions
- TypeScript everywhere; **no `any` / `@ts-ignore`** in source. Keep it simple; match surrounding code; don't refactor unrelated code while fixing a bug; no comments unless they clarify non-obvious intent.

## Workflow / Do NOT
- After 2 failed attempts, stop and rethink. **Verify before claiming done** — `npm test` + `npm run typecheck` + `npx expo export` (+ a sim screenshot for UI). Delegate verbose runs to subagents.
- Don't commit secrets (`.env`/keys). Don't `npm install` stray deps in fixes.
