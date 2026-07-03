-- Koupon — lightweight synced-backend schema
-- Paste this whole file into Supabase: SQL Editor -> New query -> Run.
-- Safe to re-run: drops and recreates the three tables (fine pre-launch,
-- there's no real data yet), and functions use CREATE OR REPLACE.
--
-- If you already have real accounts in an existing project, do NOT run
-- this file -- it drops the tables. Use koupon-migration-2-issuer-role.sql
-- instead, which ALTERs an existing database in place.
--
-- Design notes:
-- * This is the LIGHTWEIGHT track (not the double-entry ledger blueprint in
--   koupon-ledger-design.md). Balances are simple integer columns, not
--   derived from immutable entries. Good enough for a trusted-family app;
--   revisit the heavier design if KP ever needs real audit/compliance rigor.
-- * All writes happen through SECURITY DEFINER functions below, never
--   directly against the tables. RLS on the tables blocks direct writes
--   from the client entirely, so every mutation is PIN-checked server-side.
-- * PINs are hashed with bcrypt (pgcrypto), never stored or returned in
--   plaintext.
-- * Three roles: member < banker < issuer. Only an issuer can assign
--   roles or suspend/reactivate an account (assign_role,
--   set_member_status) -- self-signup always creates an active member
--   starting at 0 KP, never a banker or issuer. The banker issues the
--   member's first KP by hand afterward (Banker tab -> Issue start). No
--   account starts as issuer; see the bootstrap note at the bottom of
--   this file.
-- * The old QR "backup code -> banker -> restore code" flow is gone. The
--   server keeps the full history permanently, so undoing a mistake is
--   reverse_transaction() below: banker or issuer picks the bad entry,
--   it's reversed with a linked correction entry. No codes to copy or lose.

create extension if not exists pgcrypto;

-- ---------- clean slate (safe pre-launch: no real data yet) ----------

drop table if exists history cascade;
drop table if exists members cascade;
drop table if exists rewards cascade;

-- ---------- tables ----------

create table members (
  id uuid primary key default gen_random_uuid(),
  handle text unique not null,
  role text not null default 'member' check (role in ('member','banker','issuer')),
  status text not null default 'active' check (status in ('active','suspended')),
  pin_hash text not null,
  balance integer not null default 0 check (balance >= 0),
  created_at timestamptz not null default now()
);

create table history (
  id bigserial primary key,
  member_id uuid not null references members(id) on delete cascade,
  dir text not null check (dir in ('in','out')),
  kind text not null check (kind in ('transfer','mint','redeem','reset','correction')),
  counterparty text,
  amount integer not null check (amount > 0),
  note text,
  reversed boolean not null default false,
  reverses_id bigint references history(id),
  created_at timestamptz not null default now()
);

create table rewards (
  id bigserial primary key,
  name text not null,
  cost integer not null check (cost > 0),
  created_at timestamptz not null default now()
);

-- ---------- lock the tables down; all writes go through functions below ----------

alter table members enable row level security;
alter table history enable row level security;
alter table rewards enable row level security;

-- everyone (anon) can read handles/roles/balances and the log and reward
-- list -- fine for a small trusted-family app where balances aren't secret.
-- nothing is writable directly; every mutation goes through a function.
create policy "members readable" on members for select using (true);
create policy "history readable" on history for select using (true);
create policy "rewards readable" on rewards for select using (true);

-- ---------- functions ----------

-- create a new member. Always an active plain member starting at 0 KP --
-- p_role and p_start are accepted for client compatibility but ignored,
-- so self-signup can never grant banker/issuer or a chosen starting
-- balance. The banker grants the real starting balance afterward via
-- issue_kp(). Role changes go through assign_role() (issuer-only).
create or replace function create_member(p_handle text, p_pin text, p_role text default 'member', p_start integer default 0)
returns uuid
language plpgsql
security definer
as $$
declare v_id uuid;
begin
  insert into members (handle, role, pin_hash, balance, status)
  values (p_handle, 'member', crypt(p_pin, gen_salt('bf')), 0, 'active')
  returning id into v_id;
  return v_id;
end;
$$;

-- verify a handle+pin pair; returns the member row on success, no rows on failure
create or replace function verify_pin(p_handle text, p_pin text)
returns table(id uuid, handle text, role text, status text, balance integer)
language sql
security definer
as $$
  select id, handle, role, status, balance from members
  where handle = p_handle and pin_hash = crypt(p_pin, pin_hash);
$$;

-- let a member change their own PIN. Requires the current PIN, exactly
-- like every other mutation -- just self-service instead of
-- banker/issuer-driven. New PIN must be 4-6 digits, same rule the app
-- already enforces at signup.
create or replace function change_pin(p_handle text, p_old_pin text, p_new_pin text)
returns void
language plpgsql
security definer
as $$
declare v_id uuid;
begin
  if p_new_pin is null or length(p_new_pin) < 4 or length(p_new_pin) > 6 or p_new_pin !~ '^[0-9]+$' then
    raise exception 'PIN must be 4-6 digits';
  end if;

  select id into v_id from members
    where handle = p_handle and pin_hash = crypt(p_old_pin, pin_hash)
    for update;
  if v_id is null then raise exception 'bad handle or current PIN'; end if;

  update members set pin_hash = crypt(p_new_pin, gen_salt('bf')) where id = v_id;
end;
$$;

-- move KP between two members, atomically, with a row lock so concurrent
-- sends can't both pass the balance check (the double-spend guard).
-- Both sides must be active.
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

-- banker or issuer mints KP to a member (start grant, monthly drip, ad hoc).
-- Caller and recipient must both be active.
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

-- banker or issuer sets a member's balance directly (blunt reset, e.g.
-- fresh start). History isn't erased -- a correction entry is logged.
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

-- banker or issuer reverses one specific past transaction for a member.
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

  -- flip the effect: an 'in' entry gets debited back, an 'out' entry gets credited back
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

-- banker or issuer adds a reward to the shared list
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

-- redeem a reward: debits the member (must be active); banker fulfills
-- the reward in person, same as before (no banker "account" holds the KP).
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

-- issuer-only: assign any role to any member. Blocks demoting the last
-- active issuer, so admin control can never be accidentally lost.
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

-- issuer-only: suspend/reactivate a member. Blocks suspending the last
-- active issuer for the same reason.
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

-- allow the anon (public) role to call these functions; RLS on the tables
-- still blocks any direct table writes, so this is the only door in.
grant execute on function create_member, verify_pin, change_pin, transfer_kp, issue_kp,
  reset_member, reverse_transaction, add_reward, redeem_reward,
  assign_role, set_member_status
  to anon;

-- ---------- one-time bootstrap: promote your own account to issuer ----------
-- No account is an issuer after this script runs -- there's no issuer yet
-- to promote anyone else, by design. Create your account through the app
-- first (it'll be a normal member), then run this once with your own
-- handle to become the first issuer:

-- update members set role = 'issuer' where handle = '@tania';
