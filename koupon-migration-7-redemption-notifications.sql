-- Koupon migration 7: redemption notifications for banker + issuer
-- Paste into Supabase SQL Editor -> New query -> Run, against the existing
-- live project. Non-destructive: only adds columns and one function, does
-- not touch existing tables' data or any other function.
--
-- What this does:
-- * Adds fulfilled / fulfilled_by / fulfilled_at to the history table, so a
--   redemption ('redeem' kind entries) can be marked as handed over.
-- * Backfills all EXISTING redemptions as already fulfilled -- there's no
--   way to know retroactively which ones the banker already delivered in
--   person, so only redemptions made after this migration runs will show
--   up as pending. Without this backfill every past redemption would
--   suddenly appear as an unfulfilled notification.
-- * Adds fulfill_redemption(), the banker/issuer-only RPC the app calls to
--   clear a pending redemption.
-- * The app surfaces pending redemptions (and a tab badge count) on the
--   Banker tab, which is already visible to both banker and issuer roles --
--   so this single list serves as the notification to both.

alter table history add column if not exists fulfilled boolean not null default false;
alter table history add column if not exists fulfilled_by text;
alter table history add column if not exists fulfilled_at timestamptz;

-- backfill: existing redemptions are assumed already handled
update history set fulfilled = true, fulfilled_at = now()
  where kind = 'redeem' and fulfilled = false;

create or replace function fulfill_redemption(p_banker_handle text, p_banker_pin text, p_history_id bigint)
returns void
language plpgsql
security definer
as $$
declare v_banker_id uuid; v_banker_status text; v_row history%rowtype;
begin
  select id, status into v_banker_id, v_banker_status from members
    where handle = p_banker_handle and pin_hash = crypt(p_banker_pin, pin_hash) and role in ('banker','issuer');
  if v_banker_id is null then raise exception 'not authorized as banker'; end if;
  if v_banker_status <> 'active' then raise exception 'your account is suspended'; end if;

  select * into v_row from history where id = p_history_id for update;
  if v_row is null then raise exception 'history entry not found'; end if;
  if v_row.kind <> 'redeem' then raise exception 'not a redemption entry'; end if;
  if v_row.fulfilled then raise exception 'already marked fulfilled'; end if;

  update history set fulfilled = true, fulfilled_by = p_banker_handle, fulfilled_at = now()
    where id = p_history_id;
end;
$$;

grant execute on function fulfill_redemption to anon;
