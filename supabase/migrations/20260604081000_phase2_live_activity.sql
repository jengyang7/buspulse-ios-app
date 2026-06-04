-- Phase 2 — Global live-activity counters for the home banner.
--
-- The banner used per-location numbers from the visible tiles. To make the app
-- feel more alive, we want network-wide social proof: total commuters timing a
-- queue right now and total boards fed back in the last hour, across ALL
-- locations.
--
-- queue_sessions is RLS-locked to each owner (a client only sees its own rows),
-- so the aggregate must come from a SECURITY DEFINER function. It returns only
-- two integers — no rows, no PII — so it's safe to expose to anon/authenticated.

create or replace function public.live_activity()
returns table(reports integer, active integer)
language sql
security definer
set search_path = ''
as $$
  select
    (select count(*)::int from public.queue_sessions
       where status = 'boarded' and boarded_at >= now() - interval '60 minutes'),
    (select count(*)::int from public.queue_sessions
       where status = 'active');
$$;

grant execute on function public.live_activity() to anon, authenticated;
