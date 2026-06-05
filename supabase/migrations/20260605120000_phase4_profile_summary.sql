-- Phase 4 — Profile summary for the account screen.
--
-- The Profile tab showed hardcoded stats. This exposes the signed-in user's real
-- numbers in one call: their cached reward balance plus aggregates over their own
-- queue_sessions. queue_sessions is RLS-locked to the owner, so we run as
-- SECURITY DEFINER and scope everything to auth.uid(). Returns a single row of
-- only the caller's own data — no PII leak.
--
--   trips_logged   every queue the user has started (any status)
--   reports_shared boards that fed the shared estimate (status = 'boarded')
--   avg_wait_min   mean boarded wait (boarded_at - started_at), 0 if none yet

create or replace function public.profile_summary()
returns table(
  display_name   text,
  email          text,
  reward_points  integer,
  trips_logged   integer,
  reports_shared integer,
  avg_wait_min   integer
)
language sql
security definer
set search_path = ''
as $$
  select
    coalesce(p.display_name, split_part(p.email, '@', 1)) as display_name,
    p.email,
    p.reward_points,
    (select count(*)::int from public.queue_sessions s
       where s.user_id = auth.uid())                          as trips_logged,
    (select count(*)::int from public.queue_sessions s
       where s.user_id = auth.uid() and s.status = 'boarded') as reports_shared,
    coalesce((
      select round(avg(extract(epoch from (s.boarded_at - s.started_at)) / 60.0))::int
        from public.queue_sessions s
       where s.user_id = auth.uid()
         and s.status = 'boarded'
         and s.boarded_at is not null), 0)                    as avg_wait_min
  from public.profiles p
  where p.id = auth.uid();
$$;

grant execute on function public.profile_summary() to authenticated;
