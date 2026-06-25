-- Reference: RLS + SECURITY DEFINER + server-gated reveal pattern.
-- The shape that makes a two-sided / shared-data feature secure. Adapt names.
-- Pairs with a pgTAP test that proves the gate with REAL row counts (see below).

-- 1) Sensitive table carries the group id; RLS = "caller is a member".
create table if not exists public.items (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  author uuid not null references public.profiles(id) on delete set null,
  payload jsonb not null,
  created_at timestamptz not null default now()
);
alter table public.items enable row level security;

-- GRANTS ARE NOT AUTOMATIC: authenticated gets only Dxt by default. Without this
-- the table is invisible to logged-in users ("permission denied"). RLS still gates rows.
grant select, insert, update, delete on public.items to authenticated;

-- A member can INSERT/SELECT their group's items...
create policy items_member_rw on public.items
  for all
  using (exists (select 1 from public.groups g
                 where g.id = items.group_id
                   and (g.member_a = auth.uid() or g.member_b = auth.uid())))
  with check (author = auth.uid());

-- 2) THE GATE: a member may read the OTHER member's items only once the group's
-- drop is 'revealed'. This is the privacy backbone — enforced here, not in the client.
create policy items_partner_after_reveal on public.items
  for select
  using (exists (select 1 from public.group_drops d
                 where d.group_id = items.group_id
                   and d.state = 'revealed'));

-- 3) Cross-user writes go through a SECURITY DEFINER function, never raw client writes.
-- It validates membership via auth.uid() and computes the gate server-side.
create or replace function public.submit_item(p_group uuid, p_payload jsonb)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v_a uuid; v_b uuid; v_status text;
begin
  select member_a, member_b, status into v_a, v_b, v_status
  from public.groups where id = p_group;
  if not (auth.uid() = v_a or auth.uid() = v_b) then
    raise exception 'Unauthorized: not a member';
  end if;

  insert into public.items (group_id, author, payload)
  values (p_group, auth.uid(), p_payload);

  -- Reveal only when BOTH real members have submitted. A NULL member counts as
  -- done ONLY when the group is not 'pending' (dissolved survivor), so a solo
  -- "answer-ahead" on a pending group stays held. Key the shortcut on status.
  update public.group_drops set state = case
    when ((v_a is null and v_status <> 'pending') or exists (select 1 from public.items where group_id = p_group and author = v_a))
     and ((v_b is null and v_status <> 'pending') or exists (select 1 from public.items where group_id = p_group and author = v_b))
    then 'revealed' else state end
  where group_id = p_group;

  return json_build_object('ok', true);
end;
$$;
grant execute on function public.submit_item(uuid, jsonb) to authenticated;

-- 4) PROVE IT (pgTAP, hermetic): switch into the authenticated role, set the JWT
-- claim, and assert REAL row counts — a pre-reveal partner reads 0 of the other's
-- items; after both submit, they read them. Owner-role policy-existence checks
-- prove nothing. See templates/rules/testing.md.
--   set local role authenticated;
--   select set_config('request.jwt.claims', json_build_object('sub', '<uuid>', 'role','authenticated')::text, true);
--   select is((select count(*)::int from public.items where author = '<partner>'), 0, 'pre-reveal: 0 rows');
