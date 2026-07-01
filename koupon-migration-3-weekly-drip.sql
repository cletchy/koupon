-- Koupon — migration 3: automated weekly +5 KP drip
-- Paste into Supabase SQL Editor and run. Non-destructive (only adds a
-- table, functions, and a cron schedule) -- safe on your existing data.
--
-- What this adds:
-- * drip_log: one row per (member, ISO week) that's already been paid.
--   This is what makes the drip idempotent -- running it twice in the
--   same week (cron firing late + a manual trigger, say) tops nobody up
--   twice. Same "one drip per user per period" guarantee the heavier
--   ledger blueprint calls for, just done with a unique key instead of
--   a full double-entry ledger.
-- * weekly_drip(amount): pays every ACTIVE account (member, banker, and
--   issuer alike -- matches "every account" from the original design
--   brief, not just plain members) the given amount, once per ISO week
--   (Monday-anchored). One bad row can't abort the whole run -- each
--   member is credited in its own sub-transaction.
-- * run_weekly_drip_now(): an issuer-only wrapper around weekly_drip(),
--   so an issuer can trigger this week's drip early from the app
--   (Issuer tab -> "Run this week's drip now") without touching SQL.
--   Safe to press even if the scheduled run already happened this
--   week -- it'll just report 0 credited.
-- * A pg_cron schedule: every Monday at 08:00 UTC, calls weekly_drip(5).
--
-- Judgment calls made here -- flag if you want these different:
-- * Amount stays 5 KP, just weekly instead of manual/monthly. That's
--   roughly 4x the original monthly issuance rate -- worth watching
--   against reward pricing over time, same lever the design brief
--   flagged as the main thing to monitor.
-- * 08:00 UTC on Mondays. To change the time, re-run the cron.schedule
--   block at the bottom with a different cron expression.
--
-- IMPORTANT free-tier caveat: Supabase projects on the free tier pause
-- after about a week with no API activity at all. A paused project's
-- cron jobs don't fire until something wakes it (any request to the
-- app does this). If the family goes quiet for over a week, that
-- Monday's drip may run late rather than on time -- it'll still land
-- correctly once the project wakes, just not exactly on schedule.

-- ---------- drip_log: tracks who's already been paid this week ----------

create table if not exists drip_log (
  member_id uuid not null references members(id) on delete cascade,
  period date not null,
  created_at timestamptz not null default now(),
  primary key (member_id, period)
);
alter table drip_log enable row level security;
-- no policies -- nothing reads or writes this directly from the client,
-- only weekly_drip() below (SECURITY DEFINER) touches it.

-- ---------- weekly_drip: the actual payout, idempotent per ISO week ----------

create or replace function weekly_drip(p_amount integer default 5)
returns integer
language plpgsql
security definer
as $$
declare
  v_period date := date_trunc('week', now())::date; -- Monday of the current ISO week
  v_member record;
  v_count integer := 0;
begin
  if p_amount <= 0 then raise exception 'amount must be positive'; end if;

  for v_member in select id, handle from members where status = 'active' loop
    begin
      insert into drip_log (member_id, period) values (v_member.id, v_period)
        on conflict (member_id, period) do nothing;
      if found then
        update members set balance = balance + p_amount where id = v_member.id;
        insert into history (member_id, dir, kind, counterparty, amount, note)
          values (v_member.id, 'in', 'mint', 'issuer', p_amount, 'Weekly drip');
        v_count := v_count + 1;
      end if;
    exception when others then
      -- one bad row shouldn't block everyone else's drip
      raise notice 'weekly_drip failed for %: %', v_member.handle, sqlerrm;
    end;
  end loop;

  return v_count;
end;
$$;

-- ---------- issuer-callable manual trigger ----------

create or replace function run_weekly_drip_now(p_issuer_handle text, p_issuer_pin text)
returns integer
language plpgsql
security definer
as $$
declare v_issuer_id uuid; v_issuer_status text; v_count integer;
begin
  select id, status into v_issuer_id, v_issuer_status from members
    where handle = p_issuer_handle and pin_hash = crypt(p_issuer_pin, pin_hash) and role = 'issuer';
  if v_issuer_id is null then raise exception 'not authorized as issuer'; end if;
  if v_issuer_status <> 'active' then raise exception 'your account is suspended'; end if;

  v_count := weekly_drip(5);
  return v_count;
end;
$$;

grant execute on function run_weekly_drip_now to anon;

-- ---------- schedule it ----------
-- If this errors with something like "extension pg_cron is not
-- available", enable it first via the Supabase dashboard:
-- Database -> Extensions -> search "pg_cron" -> toggle it on -- then
-- re-run just this last section below.

create extension if not exists pg_cron;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'koupon-weekly-drip') then
    perform cron.unschedule('koupon-weekly-drip');
  end if;
end $$;

select cron.schedule(
  'koupon-weekly-drip',
  '0 8 * * 1',  -- minute hour day month day-of-week (1 = Monday), UTC
  $$select weekly_drip(5);$$
);

-- Sanity check: this should show one row, "koupon-weekly-drip", schedule
-- "0 8 * * 1", active = true.
select jobname, schedule, active from cron.job where jobname = 'koupon-weekly-drip';
