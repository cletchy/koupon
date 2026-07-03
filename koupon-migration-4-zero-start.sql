-- Koupon — migration 4: new members start at 0 KP, banker issues the first grant
-- Paste into Supabase SQL Editor and run. Safe on an existing database with
-- real accounts in it: this only replaces create_member(), it does not
-- touch existing rows, tables, or any other function.
--
-- What this changes:
-- * create_member() used to hardcode every new account to 100 KP on
--   signup (see migration 2). It now hardcodes 0 KP instead. A brand-new
--   account can view its balance/history but can't send or redeem until
--   it actually has KP.
-- * Nothing else changes. The banker's existing "Issue start (100)"
--   button in the app (issue_kp() with amount=100) already does exactly
--   what's needed to grant a new member their starting balance — it just
--   now has to be pressed by a banker instead of firing automatically at
--   signup. The weekly +5 drip (migration 3) is untouched and still pays
--   every active account regardless of balance, including brand-new
--   0-balance ones.
--
-- Judgment call — flag if you want this different: a new member now sits
-- at 0 KP until a banker notices and issues their start. If someone signs
-- up when no banker is around, they can't transact until one does.
-- Nothing here surfaces a pending 0-balance account to the banker — worth
-- adding a "new members" indicator to the Banker tab later if that gap
-- turns out to matter in practice.

create or replace function create_member(p_handle text, p_pin text, p_role text default 'member', p_start integer default 0)
returns uuid
language plpgsql
security definer
as $$
declare v_id uuid;
begin
  -- p_role and p_start are intentionally ignored: every self-created
  -- account is a plain, active member starting at 0 KP. The banker
  -- grants the starting balance manually via issue_kp() afterward.
  insert into members (handle, role, pin_hash, balance, status)
  values (p_handle, 'member', crypt(p_pin, gen_salt('bf')), 0, 'active')
  returning id into v_id;
  return v_id;
end;
$$;
