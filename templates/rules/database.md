# Supabase / data layer

Backend is Supabase (Postgres + Auth + Realtime). Migrations `supabase/migrations/00NN_*.sql`; typed client `src/lib/supabase.ts`; hand-written types in `src/types/db.ts`.

> Local dev on colima (not OrbStack): `supabase start -x vector,analytics --ignore-health-check`, then `supabase db reset` + `supabase test db`.

## RLS is the security backbone (don't bypass)
- Every sensitive table carries an owner/group id; policy = "current user is a member of this group."
- **Server-gated state** (a reveal, a publish, an unlock): a member can read the gated rows ONLY when the gate column flips (e.g. `state = 'revealed'`). Enforced in RLS — never in the client. **Prove it** with a pgTAP test that switches into the `authenticated` role, sets `request.jwt.claims`, and asserts **real row counts** (a non-member / pre-gate member reads **0 rows**). Policy-existence checks run as the RLS-exempt owner and prove nothing.
- **Grants are NOT automatic.** Default privileges grant `authenticated` only `Dxt`, not DML — a new table is invisible to logged-in users until `grant select,insert,update,delete ... to authenticated`. RLS still gates rows. Every migration adding a table MUST grant itself.
- **All cross-user writes go through SECURITY DEFINER functions** (`create_*`, `join_*`, `submit_*`, etc.) called via `supabase.rpc(...)`, never raw client table writes for shared data.
- `service_role` / secrets never ship in the client — only the public URL + anon key (`.env`, gitignored).

## Migrations & local dev
- New schema → a new `00NN_*.sql`, **idempotent** (`if not exists`, `create or replace`, `on conflict do nothing`). Apply non-destructively (`supabase migration up`) to preserve local data; `supabase db reset` for a clean verify (wipes + re-seeds).
- **Never** `DROP TABLE`/`DROP COLUMN`/destructive `ALTER` on a live table in a forward migration. Relaxing a constraint (drop NOT NULL) is fine.
- A NULL membership slot (deleted/absent member) breaks `author = member_x` checks via NULL comparison — handle explicitly, and don't apply a "null = done" shortcut meant for a *dissolved* member to a *pending* one. Key such logic on `status`.
- After agent psql work the local DB is dirty → `supabase db reset` before trusting `supabase test db`.

## supabase-js typing
- Typed `.rpc()`/`.update()` sometimes infers args as `never` (generated `Database` generic). Use one documented `// @ts-expect-error`. **Never `as any`.** Add new RPCs/tables to `src/types/db.ts`.

## Gated stub pattern
Credential-bound features (push, payments, AI, OAuth) are built to a labeled stub that no-ops gracefully (mark `// GATE:`). The app runs end-to-end in demo/solo mode with zero setup; every gate is listed in `docs/GO_LIVE.md`.
