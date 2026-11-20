drop trigger protect_steady_demo_identity on auth.users;
-- Reserve the synthetic email namespace for accounts created by the demo endpoint.
create or replace function private.protect_demo_identity() returns trigger
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
