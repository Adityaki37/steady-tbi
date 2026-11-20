-- Fix set_member_details: its "details" parameter had the same name as the
-- circle_members.details column, so the UPDATE failed as ambiguous (HTTP 400).
-- Parameters are now referenced by function name.
create or replace function private.set_member_details(c uuid, member uuid, name text, details text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_owner(set_member_details.c) then raise exception 'Only the survivor can change this' using errcode = '42501'; end if;
  if char_length(btrim(coalesce(set_member_details.name, ''))) > 80
     or char_length(btrim(coalesce(set_member_details.details, ''))) > 80 then
    raise exception 'Use up to 80 characters';
  end if;
  update public.circle_members m
    set display_name = nullif(btrim(coalesce(set_member_details.name, '')), ''),
        details = nullif(btrim(coalesce(set_member_details.details, '')), '')
    where m.circle_id = set_member_details.c and m.user_id = set_member_details.member;
  if not found then raise exception 'That person is not in your circle'; end if;
end $$;
