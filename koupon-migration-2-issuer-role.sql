-- Koupon — migration 2: issuer role + membership status
-- Paste into Supabase SQL Editor and run. Safe on an existing database
-- with real accounts in it: this ALTERs in place, it does not drop
-- members/history/rewards (unlike the original schema file, which is
-- only for a brand-new project).
--
-- What this adds:
-- * A third role, 'issuer', above 'banker'. Issuers can assign any
--   role to anyone and suspend/reactivate accounts. Issuers can also
--   do everything a banker can (issue_kp, reset_member,
--   reverse_transaction, add_reward now accept role IN ('banker','issuer')).
-- * A 'status' column on members ('active' / 'suspended'). Suspended
--   accounts can't send, redeem, or (if a banker) issue/reset/reverse.
--   Reading balance/history still works, so nothing is destroyed.
-- * Closes two gaps in the original signup flow: new accounts can no
--   longer self-assign 'banker', and can no longer set an arbitrary
--   starting balance. create_member now always creates role='member'
--   with a fixed 100 KP starting balance, regardless of what's passed
--   in (matches the "everyone starts with a fixed 100 KP" rule from
--   the original design brief). Role changes only happen via
--   assign_role() by an issuer from here on.
-- * A safety rail: you cannot demote or suspend the *last* active
--   issuer, so there's no way to accidentally lock everyone out.

-- ---------- schema changes ----------

alter table members drop constraint if exists members_role_check;
alter table members add constraint members_role_check check (role in ('member','banker','issuer'));

alter table members add column if not exists status text not null default 'active';
alter table members drop constraint if exists members_status_check;
alter table members add constraint members_status_check check (status in ('active','suspended'));

-- ---------- tightened create_member: always member, always 100 KP ----------

create or replace function create_member(p_handle text, p_pin text, p_role text default 'member', p_start integer default 100)
returns uuid
language plpgsql
security definer
as $$
declare v_id uuid;
begin
  -- p_role and p_start are intentionally ignored: every self-created
  -- account is a plain, active member starting at a fixed 100 KP.
  -- Role changes and balance corrections happen through assign_role()
  -- and issue_kp()/reset_member(), both issuer/banker-only.
  insert into members (handle, role, pin_hash, balance, status)
  values (p_handle, 'member', crypt(p_pin, gen_salt('bf')), 100, 'active')
  returning id into v_id;
  return v_id;
end;
$$;

-- ---------- verify_pin now also returns status ----------

drop function if exists verify_pin(text, text);

create function verify_pin(p_handle text, p_pin text)
returns table(id uuid, handle text, role text, status text, balance integer)
language sql
security definer
as $$
  select id, handle, role, status, balance from members
  where handle = p_handle and pin_hash = crypt(p_pin, pin_hash);
$$;

-- ---------- transfer_kp: both sides must be active ----------

create or replace function transfer_kp(p_from_handle text, p_from_pin text, p_to_handle text, p_amount integer, p_note text default '')
returns void
language plpgsql
security definer
as $$
declare v_from_id uuid; v_to_id uuid; v_from_balance integer; v_from_status text; v_to_status text;
begin
  if p_amount <= 0 then raise exception 'amount must be positive'; end if;

  select id, balance, status into v_from_id, v_from_balance, v_from_status from members
    where handle = p_from_handle and pin_hash = crypt(p_from_pin, pin_hash)
    for update;
  if v_from_id is null then raise exception 'bad handle or pin'; end if;
  if v_from_status <> 'active' then raise exception 'your account is suspended'; end if;
  if v_from_balance < p_amount then raise exception 'insufficient balance'; end if;

  select id, status into v_to_id, v_to_status from members where handle = p_to_handle for update;
  if v_to_id is null then raise exception 'recipient not found'; end if;
  if v_to_status <> 'active' then raise exception 'recipient account is suspended'; end if;

  update members set balance = balance - p_amount where id = v_from_id;
  update members set balance = balance + p_amount where id = v_to_id;

  insert into history (member_id, dir, kind, counterparty, amount, note)
    values (v_from_id, 'out', 'transfer', p_to_handle, p_amount, p_note);
  insert into history (member_id, dir, kind, counterparty, amount, note)
    values (v_to_id, 'in', 'transfer', p_from_handle, p_amount, p_note);
end;
$$;

-- ---------- issue_kp: caller must be banker or issuer, both active ----------

create or replace function issue_kp(p_banker_handle text, p_banker_pin text, p_to_handle text, p_amount integer, p_note text default 'Issued')
returns void
language plpgsql
security definer
as $$
declare v_banker_id uuid; v_banker_status text; v_to_id uuid; v_to_status text;
begin
  if p_amount <= 0 then raise exception 'amount must be positive'; end if;

  select id, status into v_banker_id, v_banker_status from members
    where handle = p_banker_handle and pin_hash = crypt(p_banker_pin, pin_hash) and role in ('banker','issuer');
  if v_banker_id is null then raise exception 'not authorized as banker'; end if;
  if v_banker_status <> 'active' then raise exception 'your account is suspended'; end if;

  select id, status into v_to_id, v_to_status from members where handle = p_to_handle for update;
  if v_to_id is null then raise exception 'recipient not found'; end if;
  if v_to_status <> 'active' then raise exception 'recipient account is suspended'; end if;

  update members set balance = balance + p_amount where id = v_to_id;

  insert into history (member_id, dir, kind, counterparty, amount, note)
    values (v_to_id, 'in', 'mint', p_banker_handle, p_amount, p_note);
end;
$$;

-- ---------- reset_member: caller must be banker or issuer ----------

create or replace function reset_member(p_banker_handle text, p_banker_pin text, p_target_handle text, p_new_balance integer)
returns void
language plpgsql
security definer
as $$
declare v_banker_id uuid; v_banker_status text; v_target_id uuid; v_old_balance integer;
begin
  if p_new_balance < 0 then raise exception 'balance cannot be negative'; end if;

  select id, status into v_banker_id, v_banker_status from members
    where handle = p_banker_handle and pin_hash = crypt(p_banker_pin, pin_hash) and role in ('banker','issuer');
  if v_banker_id is null then raise exception 'not authorized as banker'; end if;
  if v_banker_status <> 'active' then raise exception 'your account is suspended'; end if;

  select id, balance into v_target_id, v_old_balance from members where handle = p_target_handle for update;
  if v_target_id is null then raise exception 'member not found'; end if;

  update members set balance = p_new_balance where id = v_target_id;

  insert into history (member_id, dir, kind, counterparty, amount, note)
    values (v_target_id, case when p_new_balance >= v_old_balance then 'in' else 'out' end,
            'reset', p_banker_handle, abs(p_new_balance - v_old_balance),
            'Reset by banker: '||v_old_balance||' -> '||p_new_balance);
end;
$$;

-- ---------- reverse_transaction: caller must be banker or issuer ----------

create or replace function reverse_transaction(p_banker_handle text, p_banker_pin text, p_history_id bigint)
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
  if v_row.reversed then raise exception 'already reversed'; end if;

  if v_row.dir = 'in' then
    update members set balance = greatest(balance - v_row.amount, 0) where id = v_row.member_id;
  else
    update members set balance = balance + v_row.amount where id = v_row.member_id;
  end if;

  update history set reversed = true where id = p_history_id;

  insert into history (member_id, dir, kind, counterparty, amount, note, reverses_id)
    values (v_row.member_id, case when v_row.dir = 'in' then 'out' else 'in' end,
            'correction', p_banker_handle, v_row.amount,
            'Reversed by banker (undo of #'||p_history_id||')', p_history_id);
end;
$$;

-- ---------- add_reward: caller must be banker or issuer ----------

create or replace function add_reward(p_banker_handle text, p_banker_pin text, p_name text, p_cost integer)
returns void
language plpgsql
security definer
as $$
declare v_banker_id uuid; v_banker_status text;
begin
  if p_cost <= 0 then raise exception 'cost must be positive'; end if;
  select id, status into v_banker_id, v_banker_status from members
    where handle = p_banker_handle and pin_hash = crypt(p_banker_pin, pin_hash) and role in ('banker','issuer');
  if v_banker_id is null then raise exception 'not authorized as banker'; end if;
  if v_banker_status <> 'active' then raise exception 'your account is suspended'; end if;
  insert into rewards (name, cost) values (p_name, p_cost);
end;
$$;

-- ---------- redeem_reward: member must be active ----------

create or replace function redeem_reward(p_handle text, p_pin text, p_reward_id bigint)
returns void
language plpgsql
security definer
as $$
declare v_id uuid; v_balance integer; v_status text; v_name text; v_cost integer;
begin
  select id, balance, status into v_id, v_balance, v_status from members
    where handle = p_handle and pin_hash = crypt(p_pin, pin_hash) for update;
  if v_id is null then raise exception 'bad handle or pin'; end if;
  if v_status <> 'active' then raise exception 'your account is suspended'; end if;

  select name, cost into v_name, v_cost from rewards where id = p_reward_id;
  if v_name is null then raise exception 'reward not found'; end if;
  if v_balance < v_cost then raise exception 'insufficient balance'; end if;

  update members set balance = balance - v_cost where id = v_id;
  insert into history (member_id, dir, kind, counterparty, amount, note)
    values (v_id, 'out', 'redeem', 'banker', v_cost, 'Redeem: '||v_name);
end;
$$;

-- ---------- new: assign_role (issuer-only) ----------

create or replace function assign_role(p_issuer_handle text, p_issuer_pin text, p_target_handle text, p_new_role text)
returns void
language plpgsql
security definer
as $$
declare v_issuer_id uuid; v_issuer_status text; v_target_id uuid; v_target_role text; v_other_issuers integer;
begin
  if p_new_role not in ('member','banker','issuer') then raise exception 'invalid role'; end if;

  select id, status into v_issuer_id, v_issuer_status from members
    where handle = p_issuer_handle and pin_hash = crypt(p_issuer_pin, pin_hash) and role = 'issuer';
  if v_issuer_id is null then raise exception 'not authorized as issuer'; end if;
  if v_issuer_status <> 'active' then raise exception 'your account is suspended'; end if;

  select id, role into v_target_id, v_target_role from members where handle = p_target_handle for update;
  if v_target_id is null then raise exception 'member not found'; end if;

  if v_target_role = 'issuer' and p_new_role <> 'issuer' then
    select count(*) into v_other_issuers from members
      where role = 'issuer' and status = 'active' and id <> v_target_id;
    if v_other_issuers = 0 then raise exception 'cannot demote the last active issuer'; end if;
  end if;

  update members set role = p_new_role where id = v_target_id;
end;
$$;

-- ---------- new: set_member_status (issuer-only) ----------

create or replace function set_member_status(p_issuer_handle text, p_issuer_pin text, p_target_handle text, p_status text)
returns void
language plpgsql
security definer
as $$
declare v_issuer_id uuid; v_issuer_status text; v_target_id uuid; v_target_role text; v_other_issuers integer;
begin
  if p_status not in ('active','suspended') then raise exception 'invalid status'; end if;

  select id, status into v_issuer_id, v_issuer_status from members
    where handle = p_issuer_handle and pin_hash = crypt(p_issuer_pin, pin_hash) and role = 'issuer';
  if v_issuer_id is null then raise exception 'not authorized as issuer'; end if;
  if v_issuer_status <> 'active' then raise exception 'your account is suspended'; end if;

  select id, role into v_target_id, v_target_role from members where handle = p_target_handle for update;
  if v_target_id is null then raise exception 'member not found'; end if;

  if v_target_role = 'issuer' and p_status = 'suspended' then
    select count(*) into v_other_issuers from members
      where role = 'issuer' and status = 'active' and id <> v_target_id;
    if v_other_issuers = 0 then raise exception 'cannot suspend the last active issuer'; end if;
  end if;

  update members set status = p_status where id = v_target_id;
end;
$$;

-- ---------- grants ----------

grant execute on function assign_role, set_member_status to anon;

-- ---------- one-time bootstrap: promote your own account to issuer ----------
-- No account is an issuer yet after this migration -- there's no issuer to
-- promote anyone else, by design. Run this once, with your own handle, to
-- become the first issuer. Uncomment and edit the handle below, then run
-- just this one line separately (after the rest of the script above has
-- already succeeded):

-- update members set role = 'issuer' where handle = '@tania';
