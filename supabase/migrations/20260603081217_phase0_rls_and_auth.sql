-- Phase 0 — RLS policies, auth profile bootstrap, realtime publication.
-- See BACKEND_DESIGN.md §4 (RLS) and §5 (realtime).

-- Auto-create a profile row when a new auth user signs up -----------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name, email, locale)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'display_name',
             new.raw_user_meta_data ->> 'full_name',
             new.raw_user_meta_data ->> 'name'),
    new.email,
    coalesce(new.raw_user_meta_data ->> 'locale', 'en')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Enable RLS ------------------------------------------------------------------
alter table profiles       enable row level security;
alter table operators      enable row level security;
alter table locations      enable row level security;
alter table routes         enable row level security;
alter table route_stops    enable row level security;
alter table queue_sessions enable row level security;
alter table wait_estimates enable row level security;
alter table wait_history   enable row level security;
alter table reward_ledger  enable row level security;

-- World-readable reference + computed data (anon + authenticated) -------------
create policy "operators are public"      on operators      for select using (true);
create policy "locations are public"      on locations      for select using (true);
create policy "routes are public"         on routes         for select using (true);
create policy "route_stops are public"    on route_stops    for select using (true);
create policy "wait_estimates are public" on wait_estimates for select using (true);
create policy "wait_history is public"    on wait_history   for select using (true);

-- Profiles: a user sees and edits only their own row --------------------------
create policy "own profile readable" on profiles
  for select using ((select auth.uid()) = id);
create policy "own profile updatable" on profiles
  for update using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);
-- Insert is handled by the SECURITY DEFINER trigger above; no client insert
-- policy on purpose. reward_points / reputation are not client-writable here
-- (tightened in Phase 1/3 once the points RPC lands).

-- Queue sessions: a user reads and creates only their own ---------------------
-- Phase 0 keeps the raw insert; Phase 1 replaces it with start_queue() RPC and
-- locks direct inserts down.
create policy "own sessions readable" on queue_sessions
  for select using ((select auth.uid()) = user_id);
create policy "own sessions insertable" on queue_sessions
  for insert with check ((select auth.uid()) = user_id);
create policy "own sessions updatable" on queue_sessions
  for update using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- Reward ledger: read-only to the owner; writes only via SECURITY DEFINER -----
create policy "own ledger readable" on reward_ledger
  for select using ((select auth.uid()) = user_id);

-- Realtime: client subscribes to live tile updates (§5) -----------------------
alter publication supabase_realtime add table wait_estimates;
