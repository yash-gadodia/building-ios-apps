# Testing

Stack: **jest** + **jest-expo** preset + **@testing-library/react-native** for JS/TS; **pgTAP** (`supabase test db`) for SQL/RLS. Co-located `*.test.ts(x)`; `npm test`.

## Rules
- **Tests must actually exercise the thing.** `render()` + a real query/`fireEvent` (or `toJSON()` smoke). **NEVER `expect(<Component/>).toBeTruthy()`** — a JSX literal is always truthy and tests nothing. Reject this in review.
- **Exact assertions** — assert the exact expected value (`toBe`, floats with `toBeCloseTo`). Never `> 0` / "truthy".
- **Pure logic first** — keep scoring/parsing/date/business logic RN-free in `src/domain/*` and unit-test it with exact values. Highest ROI.
- `render()` from RNTL v14 is **async** — `const { ... } = await render(<X/>)`. Matchers entrypoint `@testing-library/react-native/matchers`.
- `getByText` + regex can match multiple nodes (an atom renders its label in >1 layer) → use `getAllByText(...).length`.
- **No hollow/weak tests to make CI pass.** Don't `.skip`, don't weaken an assertion, don't revert a real render to a truthy stub.

## jest mocks (all in `jest-setup.ts`)
Native modules are mocked globally so screens render in jest: reanimated (incl. `withRepeat`/`withSequence`/`Easing`), safe-area-context, expo-router, supabase-js (chainable from/rpc/channel/auth), async-storage, expo-blur, default env. A new screen importing a native module that throws in jest → add its mock here, don't disable the test.

## pgTAP (security-critical)
- `supabase/tests/*.sql` via `supabase test db`. MUST be **hermetic**: create own rows with `gen_random_uuid()`; never assert global catalog counts.
- Keep the **enforcement** assertions: a non-member / pre-gate member reads **0 rows**; after the gate flips, partner rows become readable. Valid pgTAP (`ok`/`is`/`isnt`/`throws_ok`).
- Run clean: `supabase db reset && supabase test db`. A FAIL right after agent psql work is usually dirty state — reset first.

## Verify before "done"
`npm test` (green, pristine output) + `npm run typecheck` (0) + `npx expo export -p ios` (bundles). Run jest both parallel and `--runInBand` to catch timer-leak flake. Don't claim passing without showing the run.
