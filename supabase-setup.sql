-- Inspection Data Hub: private per-user Supabase snapshot
-- Run once in Supabase Dashboard > SQL Editor.
-- Requires Supabase Auth users. Never use a service_role key in the browser.
create table if not exists public.inspection_snapshots (
  user_id uuid primary key references auth.users(id) on delete cascade,
  payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.inspection_snapshots enable row level security;
revoke all on public.inspection_snapshots from anon;
grant select, insert, update on public.inspection_snapshots to authenticated;
drop policy if exists "Read own inspection snapshot" on public.inspection_snapshots;
create policy "Read own inspection snapshot" on public.inspection_snapshots
for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists "Insert own inspection snapshot" on public.inspection_snapshots;
create policy "Insert own inspection snapshot" on public.inspection_snapshots
for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists "Update own inspection snapshot" on public.inspection_snapshots;
create policy "Update own inspection snapshot" on public.inspection_snapshots
for update to authenticated using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);
