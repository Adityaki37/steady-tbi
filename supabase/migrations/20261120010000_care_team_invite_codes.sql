-- Short invite codes for a survivor's care team.
--
-- The survivor adds a caregiver, clinician or physician with a name and a detail
-- (caregiver: relationship, e.g. "Mother"; clinician/physician: kind of doctor,
-- e.g. "Neurologist"). Steady returns a short code such as K7QF-29MD. The person
-- signs in with the matching role and enters the code to join.
--
-- Code-only: no email is needed, so anyone holding the code can use it. Limits:
-- one use, expires after 3 days, survivor can revoke it, wrong guesses are
-- capped at 10 per account per hour, and only the stored SHA-256 is kept.
-- The existing email invitations keep working unchanged.

alter table public.circle_invitations
  alter column recipient_email drop not null,
  add column recipient_name text check (recipient_name is null or char_length(btrim(recipient_name)) between 1 and 80),
  add column recipient_details text check (recipient_details is null or char_length(recipient_details) <= 80),
  add column is_code boolean not null default false,
  add constraint circle_invitations_email_or_code check (is_code or recipient_email is not null);

alter table public.circle_members
  add column display_name text check (display_name is null or char_length(display_name) <= 80),
  add column details text check (details is null or char_length(details) <= 80);

-- Failed code attempts, for rate limiting. Not readable by any API role.
create table private.invite_code_attempts (
  user_id uuid not null references auth.users(id) on delete cascade,
  attempted_at timestamptz not null default now()
);
create index invite_code_attempts_user_idx on private.invite_code_attempts(user_id, attempted_at desc);

-- Upper-case and drop spaces and dashes, so "k7qf 29md" matches "K7QF-29MD".
create function private.normalize_invite_code(code text) returns text
language sql immutable set search_path = '' as $$
  select upper(regexp_replace(coalesce(code, ''), '[\s-]', '', 'g'))
$$;

create function private.invite_code_hash(code text) returns text
language sql immutable set search_path = '' as $$
  select encode(sha256(convert_to('steady-code:' || private.normalize_invite_code(code), 'UTF8')), 'hex')
$$;

create function private.create_invite_code(c uuid, r text, name text, details text) returns text
language plpgsql security definer set search_path = '' as $$
declare
  -- 31 symbols with no 0/O, 1/I/L look-alikes: 31^8 is about 8.5e11 codes.
  alphabet constant text := '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  bytes bytea;
  code text := '';
  b int;
  i int;
  tries int := 0;
begin
  if not private.is_owner(c) then raise exception 'Only the survivor can add people' using errcode = '42501'; end if;
  if r not in ('caregiver', 'clinician', 'physician') then raise exception 'Choose caregiver, clinician or physician'; end if;
  if name is null or char_length(btrim(name)) not between 1 and 80 then raise exception 'Enter a name of 1 to 80 characters'; end if;
  if details is not null and char_length(btrim(details)) > 80 then raise exception 'Use up to 80 characters for the detail'; end if;
  loop
    code := '';
    -- Random bytes from UUIDv4s, skipping the version/variant bytes (6 and 8),
    -- with rejection sampling so every symbol is equally likely.
    while char_length(code) < 8 loop
      bytes := decode(replace(gen_random_uuid()::text, '-', ''), 'hex');
      for i in 0..15 loop
        continue when i in (6, 8);
        b := get_byte(bytes, i);
        continue when b >= 248; -- 248 = 8 * 31
        code := code || substr(alphabet, b % 31 + 1, 1);
        exit when char_length(code) = 8;
      end loop;
    end loop;
    exit when not exists (select 1 from public.circle_invitations where token_hash = private.invite_code_hash(code));
    tries := tries + 1;
    if tries > 5 then raise exception 'Could not make a unique code, try again'; end if;
  end loop;
  insert into public.circle_invitations(circle_id, recipient_email, role, token_hash, expires_at,
                                        recipient_name, recipient_details, is_code)
  values (c, null, r, private.invite_code_hash(code), now() + interval '3 days',
          btrim(name), nullif(btrim(coalesce(details, '')), ''), true);
  return substr(code, 1, 4) || '-' || substr(code, 5, 4); -- shown once to the survivor
end $$;

create function private.accept_invite_code(code text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  invitation public.circle_invitations;
  account_role text;
begin
  if auth.uid() is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if (select count(*) from private.invite_code_attempts
      where user_id = auth.uid() and attempted_at > now() - interval '1 hour') >= 10 then
    raise exception 'Too many tries. Wait an hour, then try again.' using errcode = '42501';
  end if;
  select * into invitation from public.circle_invitations
    where token_hash = private.invite_code_hash(code) and is_code
      and accepted_at is null and revoked_at is null and expires_at > now()
    for update;
  if not found or private.is_owner(invitation.circle_id) then
    -- Return null instead of raising: an error would roll back this attempt row,
    -- and the guess limit would never count. The app shows null as "wrong code".
    insert into private.invite_code_attempts(user_id) values (auth.uid());
    return null;
  end if;
  -- The account's chosen role must match the role the survivor picked. This is a
  -- convenience check against joining as the wrong kind of person; the circle role
  -- that controls access always comes from the invitation, never from the account.
  select u.raw_user_meta_data ->> 'steady_role' into account_role from auth.users u where u.id = auth.uid();
  if account_role is distinct from invitation.role then
    raise exception 'This code is for a %. Sign in with a % account.', invitation.role, invitation.role using errcode = '42501';
  end if;
  -- Conflict is deliberately an error: a code never silently changes an existing role.
  insert into public.circle_members(circle_id, user_id, role, display_name, details)
  values (invitation.circle_id, auth.uid(), invitation.role, invitation.recipient_name, invitation.recipient_details);
  update public.circle_invitations set accepted_at = now(), recipient_user_id = auth.uid() where id = invitation.id;
  return invitation.circle_id;
end $$;

-- The email path must never accept a code invitation (those have no email to match).
create or replace function private.accept_invite(token text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare invitation public.circle_invitations; email text;
begin
  if auth.uid() is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  select lower(u.email) into email from auth.users u where u.id=auth.uid() and u.email_confirmed_at is not null;
  select * into invitation from public.circle_invitations
    where token_hash=encode(sha256(convert_to(token,'UTF8')),'hex') and not is_code
      and accepted_at is null and revoked_at is null and expires_at>now() for update;
  if not found or email is null or invitation.recipient_email is null or invitation.recipient_email<>email
     or (invitation.recipient_user_id is not null and invitation.recipient_user_id<>auth.uid()) or private.is_owner(invitation.circle_id) then
    raise exception 'Invalid, expired or mismatched invitation' using errcode = '42501';
  end if;
  -- Conflict is deliberately an error: an invitation never silently changes an existing role.
  insert into public.circle_members(circle_id,user_id,role) values(invitation.circle_id,auth.uid(),invitation.role);
  -- Bind other pending invitations to this verified account, including invitations
  -- created before sign-up. Later email changes cannot evade member revocation.
  update public.circle_invitations set recipient_user_id=auth.uid()
    where circle_id=invitation.circle_id and recipient_email=email and recipient_user_id is null;
  update public.circle_invitations set accepted_at=now() where id=invitation.id;
  return invitation.circle_id;
end $$;

-- The survivor can correct a joined person's name or detail later.
create function private.set_member_details(c uuid, member uuid, name text, details text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_owner(c) then raise exception 'Only the survivor can change this' using errcode = '42501'; end if;
  if name is not null and char_length(btrim(name)) > 80 or details is not null and char_length(btrim(details)) > 80 then
    raise exception 'Use up to 80 characters';
  end if;
  update public.circle_members
    set display_name = nullif(btrim(coalesce(name, '')), ''), details = nullif(btrim(coalesce(details, '')), '')
    where circle_id = c and user_id = member;
  if not found then raise exception 'That person is not in your circle'; end if;
end $$;

create function public.create_invite_code(c uuid, r text, name text, details text) returns text
language sql security invoker set search_path = '' as $$ select private.create_invite_code(c, r, name, details) $$;
create function public.accept_invite_code(code text) returns uuid
language sql security invoker set search_path = '' as $$ select private.accept_invite_code(code) $$;
create function public.set_member_details(c uuid, member uuid, name text, details text) returns void
language sql security invoker set search_path = '' as $$ select private.set_member_details(c, member, name, details) $$;

revoke all on function private.normalize_invite_code(text), private.invite_code_hash(text),
  private.create_invite_code(uuid, text, text, text), private.accept_invite_code(text),
  private.set_member_details(uuid, uuid, text, text) from public, anon;
grant execute on function private.normalize_invite_code(text), private.invite_code_hash(text),
  private.create_invite_code(uuid, text, text, text), private.accept_invite_code(text),
  private.set_member_details(uuid, uuid, text, text) to authenticated;
revoke all on function public.create_invite_code(uuid, text, text, text), public.accept_invite_code(text),
  public.set_member_details(uuid, uuid, text, text) from public, anon;
grant execute on function public.create_invite_code(uuid, text, text, text), public.accept_invite_code(text),
  public.set_member_details(uuid, uuid, text, text) to authenticated;
revoke all on private.invite_code_attempts from public, anon, authenticated;
