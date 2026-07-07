-- Koupon — migration 6: let banker/issuer adjust an existing reward's price
-- Paste into Supabase SQL Editor and run. Purely additive: adds one new
-- function and re-grants execute. Does not touch existing tables, rows,
-- or any other function.
--
-- What this changes:
-- * New function update_reward(banker_handle, banker_pin, reward_id, new_cost).
--   Same auth pattern as add_reward -- caller must be an active banker or
--   issuer. Only changes cost; the reward's name is untouched. This is
--   deliberately a plain UPDATE, not a history-logged transaction --
--   rewards aren't KP balances, so there's nothing to reconcile, just the
--   shared price list.
-- * Grants execute on update_reward to anon, same as the other
--   banker/issuer-facing functions.
-- * No table changes. Existing rewards and their current prices are
--   untouched until a banker or issuer actively edits one.

create or replace function update_reward(p_banker_handle text, p_banker_pin text, p_reward_id bigint, p_cost integer)
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

  update rewards set cost = p_cost where id = p_reward_id;
  if not found then raise exception 'reward not found'; end if;
end;
$$;

grant execute on function update_reward to anon;
