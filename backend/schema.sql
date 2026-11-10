-- Steady: fictional-data prototype. Apply only to a NEW Supabase project.
-- No existing project is targeted by this source file.
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create table public.circles (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null unique references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 100),
  created_at timestamptz not null default now()
);
create table public.circle_members (
  circle_id uuid not null references public.circles(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('caregiver','clinician')),
  primary key (circle_id, user_id)
);
create index circle_members_user_idx on public.circle_members(user_id, circle_id);
create table public.circle_permissions (
  circle_id uuid not null references public.circles(id) on delete cascade,
  role text not null check (role in ('caregiver','clinician')),
  kind text not null check (kind in ('symptoms','observations','notes','attachments')),
  can_read boolean not null default false,
  can_add boolean not null default false,
  can_edit boolean not null default false,
  can_delete boolean not null default false,
  primary key (circle_id, role, kind)
);
create table public.records (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  kind text not null check (kind in ('symptoms','observations','notes','attachments')),
  author_id uuid not null references auth.users(id),
  title text not null check (char_length(btrim(title)) between 1 and 100),
  body text not null default '' check (char_length(body) <= 3000),
  severity integer check (severity is null or (severity between 1 and 5 and kind = 'symptoms')),
  file_path text,
  file_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((kind = 'attachments' and file_path is not null and file_name is not null)
      or (kind <> 'attachments' and file_path is null and file_name is null)),
  check (file_path is null or file_path ~ ('^' || circle_id::text || '/[0-9a-f-]{36}\.(png|jpg|jpeg|pdf)$'))
);
create index records_circle_kind_date_idx on public.records(circle_id, kind, created_at desc);
create index records_author_idx on public.records(author_id);
create table public.circle_invitations (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  recipient_email text not null check (char_length(recipient_email) <= 254),
  recipient_user_id uuid references auth.users(id) on delete cascade,
  role text not null check (role in ('caregiver','clinician')),
  token_hash text not null unique,
  expires_at timestamptz not null default now() + interval '7 days',
  accepted_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);
create index invitations_circle_idx on public.circle_invitations(circle_id);
create table public.check_ins (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  sender_id uuid not null references auth.users(id),
  body text not null default 'A demo caregiver suggested a gentle check-in.' check (char_length(body) between 1 and 500),
  category text not null default 'general' check (category in ('general','symptom_break')),
  created_at timestamptz not null default now()
);
create index check_ins_circle_date_idx on public.check_ins(circle_id, created_at desc);
create index check_ins_sender_idx on public.check_ins(sender_id);
-- Per-device APNs registration. A user owns only their own tokens; caregivers
-- never see survivor tokens through RLS (the symptom-break send runs server-side
-- in a definer function / Edge Function service context, below).
create table public.device_tokens (
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null check (char_length(token) between 1 and 400),
  platform text not null default 'ios' check (platform in ('ios')),
  environment text not null default 'sandbox' check (environment in ('sandbox','production')),
  updated_at timestamptz not null default now(),
  primary key (user_id, token)
);
create index device_tokens_user_idx on public.device_tokens(user_id);

-- Narrow guarded lookups avoid recursive RLS. Authorization is database data,
-- never user_metadata or a client-selected role. All definer functions are private.
create function private.is_owner(c uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists(select 1 from public.circles where id = c and owner_id = auth.uid())
$$;
create function private.is_member(c uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and (private.is_owner(c) or exists(select 1 from public.circle_members where circle_id = c and user_id = auth.uid()))
$$;
create function private.assigned_role(c uuid) returns text
language sql stable security definer set search_path = '' as $$
  select case when auth.uid() is null then null when private.is_owner(c) then 'survivor'
  else (select role from public.circle_members where circle_id = c and user_id = auth.uid()) end
$$;
create function private.allowed(c uuid, k text, a text) returns boolean
language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and a in ('read','add','edit','delete') and k in ('symptoms','observations','notes','attachments') and
    (private.is_owner(c) or exists (
      select 1 from public.circle_members m join public.circle_permissions p on p.circle_id = m.circle_id and p.role = m.role
      where m.circle_id = c and m.user_id = auth.uid() and p.kind = k and
      case a when 'read' then p.can_read when 'add' then p.can_add
             when 'edit' then p.can_read and p.can_edit when 'delete' then p.can_read and p.can_delete else false end
    ))
$$;
create function private.create_circle(n text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare c uuid;
begin
  if auth.uid() is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  insert into public.circles(owner_id,name) values(auth.uid(),n) returning id into c;
  insert into public.circle_permissions(circle_id,role,kind,can_read,can_add,can_edit,can_delete)
  select c,r,k,
    (r='caregiver' and k='observations') or (r='clinician'),
    (r='caregiver' and k='observations') or (r='clinician' and k='notes'),
    (r='caregiver' and k='observations') or (r='clinician' and k='notes'),
    (r='caregiver' and k='observations') or (r='clinician' and k='notes')
  from unnest(array['caregiver','clinician']) r cross join unnest(array['symptoms','observations','notes','attachments']) k;
  return c;
end $$;
create function private.invite(c uuid, recipient text, r text) returns text
language plpgsql security definer set search_path = '' as $$
declare token text;
begin
  if not private.is_owner(c) then raise exception 'Only survivor can invite' using errcode = '42501'; end if;
  if r not in ('caregiver','clinician') or recipient is null or recipient !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Invalid invitation'; end if;
  token := gen_random_uuid()::text || gen_random_uuid()::text;
  insert into public.circle_invitations(circle_id,recipient_email,recipient_user_id,role,token_hash)
  values(c, lower(btrim(recipient)), (select u.id from auth.users u where lower(u.email)=lower(btrim(recipient)) limit 1), r, encode(sha256(convert_to(token,'UTF8')),'hex'));
  return token; -- returned once to owner; owner shares explicitly, no automatic email
end $$;
create function private.accept_invite(token text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare invitation public.circle_invitations; email text;
begin
  if auth.uid() is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  select lower(u.email) into email from auth.users u where u.id=auth.uid() and u.email_confirmed_at is not null;
  select * into invitation from public.circle_invitations
    where token_hash=encode(sha256(convert_to(token,'UTF8')),'hex') and accepted_at is null and revoked_at is null and expires_at>now() for update;
  if not found or email is null or invitation.recipient_email<>email or (invitation.recipient_user_id is not null and invitation.recipient_user_id<>auth.uid()) or private.is_owner(invitation.circle_id) then
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
create function private.revoke_removed_member_invites() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  -- Called only by the DELETE trigger after the member-delete RLS check. Null
  -- auth.uid is reserved for administrative/cascade deletion, never API clients.
  if auth.uid() is not null and not private.is_owner(old.circle_id) then raise exception 'Denied' using errcode='42501'; end if;
  update public.circle_invitations set revoked_at=now()
    where circle_id=old.circle_id and accepted_at is null and revoked_at is null
      and (recipient_user_id=old.user_id or recipient_email=(select lower(u.email) from auth.users u where u.id=old.user_id));
  return old;
end $$;
create trigger revoke_removed_member_invites after delete on public.circle_members
for each row execute function private.revoke_removed_member_invites();
create function private.revoke_invite(i uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not exists(select 1 from public.circle_invitations where id=i and private.is_owner(circle_id)) then raise exception 'Denied' using errcode='42501'; end if;
  update public.circle_invitations set revoked_at=now() where id=i;
end $$;

create function public.create_circle(n text) returns uuid language sql security invoker set search_path = '' as $$ select private.create_circle(n) $$;
create function public.invite_member(c uuid,email text,r text) returns text language sql security invoker set search_path = '' as $$ select private.invite(c,email,r) $$;
create function public.accept_invite(token text) returns uuid language sql security invoker set search_path = '' as $$ select private.accept_invite(token) $$;
create function public.revoke_invite(i uuid) returns void language sql security invoker set search_path = '' as $$ select private.revoke_invite(i) $$;
create function public.my_role(c uuid) returns text language sql stable security invoker set search_path = '' as $$ select private.assigned_role(c) $$;
create function public.my_permissions(c uuid) returns table(kind text,can_read boolean,can_add boolean,can_edit boolean,can_delete boolean)
language sql stable security invoker set search_path = '' as $$
  select k,private.allowed(c,k,'read'),private.allowed(c,k,'add'),private.allowed(c,k,'edit'),private.allowed(c,k,'delete')
  from unnest(array['symptoms','observations','notes','attachments']) k where private.is_member(c)
$$;

-- Immutable identifiers prevent cross-circle moves, author spoofing and path reassignment.
create function private.protect_record() returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if new.id<>old.id or new.circle_id<>old.circle_id or new.kind<>old.kind or new.author_id<>old.author_id or new.created_at<>old.created_at or new.file_path is distinct from old.file_path or new.file_name is distinct from old.file_name then
    raise exception 'Entry identity and attachment path are immutable' using errcode='42501';
  end if;
  new.updated_at=now(); return new;
end $$;
create trigger protect_record before update on public.records for each row execute function private.protect_record();

-- A caregiver-recorded symptom-break check-in notifies the circle OWNER on their
-- other devices. Reading survivor tokens is authorized only here (definer), never
-- via RLS. In the hosted project this invokes the notify-symptom-break Edge
-- Function over the Supabase webhook helper (supabase_functions.http_request or
-- pg_net). Plain Postgres/PGlite has no such extension, so the net call is wrapped
-- in a guarded block that no-ops when the helper is absent: the migration still
-- applies and symptom-break check-ins still INSERT cleanly with no edge endpoint.
create function private.notify_symptom_break() returns trigger
language plpgsql security definer set search_path = '' as $$
declare owner uuid; payload jsonb;
begin
  if new.category is distinct from 'symptom_break' then return new; end if;
  select owner_id into owner from public.circles where id = new.circle_id;
  if owner is null then return new; end if;
  -- Server-side token lookup (never exposed to the caregiver through RLS).
  payload := jsonb_build_object(
    'check_in_id', new.id,
    'circle_id', new.circle_id,
    'owner_id', owner,
    'tokens', coalesce((select jsonb_agg(jsonb_build_object('token', t.token, 'environment', t.environment))
                        from public.device_tokens t where t.user_id = owner and t.platform = 'ios'), '[]'::jsonb));
  -- Degrade gracefully: only attempt the outbound webhook when the Supabase helper
  -- exists. Any failure here must NOT abort the check-in insert.
  begin
    if to_regprocedure('supabase_functions.http_request(text,text,jsonb,jsonb,integer)') is not null then
      perform supabase_functions.http_request(
        'notify-symptom-break', 'POST',
        jsonb_build_object('Content-Type','application/json'),
        payload, 5000);
    end if;
  exception when others then
    -- Notification is best-effort; swallow so the check-in always commits.
    null;
  end;
  return new;
end $$;
create trigger notify_symptom_break after insert on public.check_ins
for each row execute function private.notify_symptom_break();

alter table public.circles enable row level security;
alter table public.circle_members enable row level security;
alter table public.circle_permissions enable row level security;
alter table public.records enable row level security;
alter table public.circle_invitations enable row level security;
alter table public.check_ins enable row level security;
alter table public.device_tokens enable row level security;
revoke all on public.circles, public.circle_members, public.circle_permissions, public.records, public.circle_invitations, public.check_ins, public.device_tokens from anon, authenticated;
grant select on public.circles, public.circle_members, public.circle_permissions, public.circle_invitations to authenticated;
grant delete on public.circle_members to authenticated;
grant update(can_read,can_add,can_edit,can_delete) on public.circle_permissions to authenticated;
grant select,insert,update,delete on public.records to authenticated;
grant select,insert,delete on public.check_ins to authenticated;
grant select,insert,update,delete on public.device_tokens to authenticated;

create policy circles_read on public.circles for select to authenticated using(private.is_member(id));
create policy members_read on public.circle_members for select to authenticated using(private.is_owner(circle_id) or user_id=(select auth.uid()));
create policy members_delete on public.circle_members for delete to authenticated using(private.is_owner(circle_id));
create policy permissions_read on public.circle_permissions for select to authenticated using(private.is_owner(circle_id));
create policy permissions_edit on public.circle_permissions for update to authenticated using(private.is_owner(circle_id)) with check(private.is_owner(circle_id));
create policy invites_read on public.circle_invitations for select to authenticated using(private.is_owner(circle_id));
create policy records_read on public.records for select to authenticated using(private.allowed(circle_id,kind,'read'));
create policy records_add on public.records for insert to authenticated with check(private.allowed(circle_id,kind,'add') and author_id=(select auth.uid()));
create policy records_edit on public.records for update to authenticated using(private.allowed(circle_id,kind,'edit')) with check(private.allowed(circle_id,kind,'edit'));
create policy records_delete on public.records for delete to authenticated using(private.allowed(circle_id,kind,'delete'));
create policy check_ins_read on public.check_ins for select to authenticated using(private.is_owner(circle_id) or (sender_id=(select auth.uid()) and private.assigned_role(circle_id)='caregiver'));
create policy check_ins_add on public.check_ins for insert to authenticated with check(private.assigned_role(circle_id)='caregiver' and sender_id=(select auth.uid()));
create policy check_ins_delete on public.check_ins for delete to authenticated using(private.is_owner(circle_id));
-- A user may read/write ONLY their own device tokens. No cross-user access.
create policy device_tokens_own on public.device_tokens for all to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));

-- Private bucket. No signed/public URLs are used: authenticated downloads recheck access.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('steady-fictional','steady-fictional',false,15728640,array['image/png','image/jpeg','application/pdf'])
on conflict (id) do nothing;
create function private.storage_allowed(path text,a text) returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare c uuid;
begin
  if auth.uid() is null or path !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.(png|jpg|jpeg|pdf)$' then return false; end if;
  begin c:=split_part(path,'/',1)::uuid; exception when invalid_text_representation then return false; end;
  return private.allowed(c,'attachments',a);
end $$;
create policy steady_files_read on storage.objects for select to authenticated using(bucket_id='steady-fictional' and private.storage_allowed(name,'read'));
create policy steady_files_add on storage.objects for insert to authenticated with check(bucket_id='steady-fictional' and private.storage_allowed(name,'add') and owner_id=(select auth.uid())::text);
create policy steady_files_delete on storage.objects for delete to authenticated using(bucket_id='steady-fictional' and private.storage_allowed(name,'delete'));
-- No UPDATE policy: objects are immutable. Replacement is an explicit new upload.

revoke all on all functions in schema private from public, anon;
grant execute on all functions in schema private to authenticated;
revoke all on function public.create_circle(text), public.invite_member(uuid,text,text),public.accept_invite(text),public.revoke_invite(uuid),public.my_role(uuid),public.my_permissions(uuid) from public,anon;
grant execute on function public.create_circle(text),public.invite_member(uuid,text,text),public.accept_invite(text),public.revoke_invite(uuid),public.my_role(uuid),public.my_permissions(uuid) to authenticated;
