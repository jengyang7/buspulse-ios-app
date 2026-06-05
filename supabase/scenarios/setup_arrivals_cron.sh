#!/usr/bin/env bash
# Schedule the refresh-arrivals edge function via pg_cron + pg_net.
#
# Stores the edge base URL and cron secret in Vault, then schedules a job that
# POSTs to the function every minute. Re-runnable (idempotent).
#
# Local:  ./supabase/scenarios/setup_arrivals_cron.sh
# Cloud:  EDGE_BASE_URL=https://<ref>.supabase.co ./supabase/scenarios/setup_arrivals_cron.sh
set -euo pipefail
cd "$(dirname "$0")/../.."

# Cron secret must match supabase/functions/.env (CRON_SECRET).
CRON_SECRET="$(grep '^CRON_SECRET=' supabase/functions/.env | cut -d= -f2-)"
[ -n "$CRON_SECRET" ] || { echo "CRON_SECRET missing in supabase/functions/.env" >&2; exit 1; }

# From inside the DB container, the local gateway is reachable as kong:8000.
EDGE_BASE_URL="${EDGE_BASE_URL:-http://kong:8000}"

# Everything as ONE statement (a DO block) so the CLI's prepared-statement path
# accepts it. Written to a temp file with placeholders, then substituted, so the
# dollar-quotes survive the shell untouched.
SQL_FILE="$(mktemp)"
trap 'rm -f "$SQL_FILE"' EXIT
cat > "$SQL_FILE" <<'SQL'
do $outer$
begin
  delete from vault.secrets where name in ('edge_base_url','cron_secret');
  perform vault.create_secret('__URL__', 'edge_base_url');
  perform vault.create_secret('__SECRET__', 'cron_secret');
  perform cron.unschedule(jobid) from cron.job where jobname = 'refresh-arrivals';
  perform cron.schedule('refresh-arrivals', '* * * * *', $cron$
    select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'edge_base_url')
             || '/functions/v1/refresh-arrivals',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')
      ),
      body := '{}'::jsonb
    );
  $cron$);
end
$outer$;
SQL
sed -i '' "s|__URL__|${EDGE_BASE_URL}|; s|__SECRET__|${CRON_SECRET}|" "$SQL_FILE"
supabase db query --local --file "$SQL_FILE"
echo "Scheduled refresh-arrivals (every 1 min) → ${EDGE_BASE_URL}/functions/v1/refresh-arrivals"
