create table private.demo_signup_quota (
  singleton boolean primary key default true check (singleton),
  window_start timestamptz not null,
  attempts integer not null
);
alter table private.demo_signup_quota enable row level security;
revoke all on private.demo_signup_quota from public, anon, authenticated;

create function private.reserve_demo_signup() returns boolean
language sql security definer set search_path = '' as $$
  insert into private.demo_signup_quota as quota (window_start, attempts)
  values (date_trunc('hour', now()), 1)
  on conflict (singleton) do update set
    window_start = excluded.window_start,
    attempts = case when quota.window_start = excluded.window_start then quota.attempts + 1 else 1 end
  where quota.window_start <> excluded.window_start or quota.attempts < 60
  returning true
$$;

create function public.reserve_demo_signup() returns boolean
language sql security invoker set search_path = '' as $$
  select coalesce(private.reserve_demo_signup(), false)
$$;

revoke all on function private.reserve_demo_signup(), public.reserve_demo_signup() from public, anon, authenticated;
grant usage on schema private to service_role;
grant execute on function private.reserve_demo_signup(), public.reserve_demo_signup() to service_role;

-- Reserve the synthetic email namespace for accounts created by the demo endpoint.
create function private.protect_demo_identity() returns trigger
language plpgsql set search_path = '' as $$
begin
  if lower(new.email) like '%@steady-demo.example'
    and not exists (
      select 1 from auth.users where id = new.id and raw_app_meta_data ->> 'steady_demo' = 'true'
    ) then
    raise exception 'Use the Steady demo signup screen to create this account';
  end if;
  if tg_op = 'UPDATE' and (old.raw_app_meta_data ->> 'steady_demo') = 'true'
    and new.email is distinct from old.email then
    raise exception 'The demo username cannot be changed';
  end if;
  return new;
end
$$;

-- Auth Admin sets app metadata after the initial INSERT within its transaction.
create constraint trigger protect_steady_demo_identity after insert or update of email on auth.users
deferrable initially deferred for each row execute function private.protect_demo_identity();
revoke all on function private.protect_demo_identity() from public, anon, authenticated;

alter table public.circle_invitations add constraint demo_invites_require_existing_account
  check (recipient_email not like '%@steady-demo.example' or recipient_user_id is not null);
