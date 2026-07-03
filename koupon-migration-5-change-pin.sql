-- Koupon — migration 5: let members change their own PIN
-- Paste into Supabase SQL Editor and run. Purely additive: adds one new
-- function and re-grants execute. Does not touch existing tables, rows,
-- or any other function.
--
-- What this changes:
-- * New function change_pin(handle, old_pin, new_pin). Requires the
--   current PIN to authorize, exactly like every other mutation in this
--   app (transfer_kp, redeem_reward, etc.) -- just self-service instead
--   of banker/issuer-driven. Rejects a new PIN that isn't 4-6 digits,
--   matching the client-side rule already enforced at signup.
-- * Grants execute on change_pin to anon, same as the other member-
--   facing functions.
-- * No table changes. No effect on existing PINs until a member
--   actively uses the new "Change your PIN" control in Settings.

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

grant execute on function change_pin to anon;
