create table public.survivor_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(btrim(display_name)) between 1 and 100),
  -- A survivor's local calendar day can be ahead of the database's day.
  injury_date date check (injury_date <= current_date + 1),
  injury_description text not null default '' check (char_length(injury_description) <= 300),
  injury_notes text not null default '' check (char_length(injury_notes) <= 1000),
  symptoms jsonb not null default '[]'::jsonb check (
    case when jsonb_typeof(symptoms) = 'array'
      then jsonb_array_length(symptoms) <= 50 and octet_length(symptoms::text) <= 24000
      else false
    end
  )
);

alter table public.survivor_profiles enable row level security;
revoke all on public.survivor_profiles from public, anon, authenticated;
grant select, insert, update on public.survivor_profiles to authenticated;

-- A circle invitation never grants access to these onboarding answers.
create policy survivor_profiles_read_own on public.survivor_profiles
  for select to authenticated using ((select auth.uid()) = user_id);
create policy survivor_profiles_insert_own on public.survivor_profiles
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy survivor_profiles_update_own on public.survivor_profiles
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
alter table public.circle_members
  add column shares_survivor_profile boolean not null default false;

grant update (shares_survivor_profile) on public.circle_members to authenticated;
create policy members_update_profile_sharing on public.circle_members
  for update to authenticated
  using (private.is_owner(circle_id))
  with check (private.is_owner(circle_id));

-- Keep the profile table owner-only. Return only the fields covered by the grant.
create function private.shared_survivor_profile(c uuid)
returns table (injury_date date, injury_description text, injury_notes text, symptoms jsonb)
language sql stable security definer set search_path = '' as $$
  select p.injury_date, p.injury_description, p.injury_notes, p.symptoms
  from public.circle_members m
  join public.circles s on s.id = m.circle_id
  join public.survivor_profiles p on p.user_id = s.owner_id
  where m.circle_id = c and m.user_id = (select auth.uid()) and m.shares_survivor_profile
$$;

create function public.shared_survivor_profile(c uuid)
returns table (injury_date date, injury_description text, injury_notes text, symptoms jsonb)
language sql stable security invoker set search_path = '' as $$
  select * from private.shared_survivor_profile(c)
$$;

revoke all on function private.shared_survivor_profile(uuid), public.shared_survivor_profile(uuid) from public, anon;
grant execute on function private.shared_survivor_profile(uuid), public.shared_survivor_profile(uuid) to authenticated;
create table public.activity_logs (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  activity text not null check (char_length(btrim(activity)) between 1 and 100),
  started_at timestamptz not null check (isfinite(started_at)),
  duration_minutes integer not null check (duration_minutes > 0),
  fatigue smallint not null check (fatigue between 0 and 5),
  symptoms text not null default '' check (char_length(symptoms) <= 1000)
);

create index activity_logs_user_start_idx on public.activity_logs (user_id, started_at desc, id desc);
alter table public.activity_logs enable row level security;
revoke all on public.activity_logs from public, anon, authenticated;
grant select, insert, delete on public.activity_logs to authenticated;
grant update (activity, started_at, duration_minutes, fatigue, symptoms) on public.activity_logs to authenticated;

create policy activity_logs_read_own on public.activity_logs
  for select to authenticated using ((select auth.uid()) = user_id);
create policy activity_logs_insert_own on public.activity_logs
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy activity_logs_update_own on public.activity_logs
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy activity_logs_delete_own on public.activity_logs
  for delete to authenticated using ((select auth.uid()) = user_id);
