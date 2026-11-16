-- Physician is a separate circle role. Existing membership and sharing choices stay intact.
alter table public.circle_members
  drop constraint circle_members_role_check,
  add constraint circle_members_role_check check (role in ('caregiver', 'clinician', 'physician'));
alter table public.circle_invitations
  drop constraint circle_invitations_role_check,
  add constraint circle_invitations_role_check check (role in ('caregiver', 'clinician', 'physician'));
alter table public.circle_permissions
  drop constraint circle_permissions_role_check,
  add constraint circle_permissions_role_check check (role in ('caregiver', 'clinician', 'physician'));

insert into public.circle_permissions(circle_id, role, kind, can_read, can_add, can_edit, can_delete)
select c.id, 'physician', k, true, k = 'notes', k = 'notes', k = 'notes'
from public.circles c
cross join unnest(array['symptoms', 'observations', 'notes', 'attachments']) k;

create or replace function private.create_circle(n text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare c uuid;
begin
  if auth.uid() is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  insert into public.circles(owner_id,name) values(auth.uid(),n) returning id into c;
  insert into public.circle_permissions(circle_id,role,kind,can_read,can_add,can_edit,can_delete)
  select c,r,k,
    (r='caregiver' and k='observations') or (r in ('clinician','physician')),
    (r='caregiver' and k='observations') or (r in ('clinician','physician') and k='notes'),
    (r='caregiver' and k='observations') or (r in ('clinician','physician') and k='notes'),
    (r='caregiver' and k='observations') or (r in ('clinician','physician') and k='notes')
  from unnest(array['caregiver','clinician','physician']) r cross join unnest(array['symptoms','observations','notes','attachments']) k;
  return c;
end $$;
create or replace function private.invite(c uuid, recipient text, r text) returns text
language plpgsql security definer set search_path = '' as $$
declare token text;
begin
  if not private.is_owner(c) then raise exception 'Only survivor can invite' using errcode = '42501'; end if;
  if r not in ('caregiver','clinician','physician') or recipient is null or recipient !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Invalid invitation'; end if;
  token := gen_random_uuid()::text || gen_random_uuid()::text;
  insert into public.circle_invitations(circle_id,recipient_email,recipient_user_id,role,token_hash)
  values(c, lower(btrim(recipient)), (select u.id from auth.users u where lower(u.email)=lower(btrim(recipient)) limit 1), r, encode(sha256(convert_to(token,'UTF8')),'hex'));
  return token; -- returned once to owner; owner shares explicitly, no automatic email
end $$;
