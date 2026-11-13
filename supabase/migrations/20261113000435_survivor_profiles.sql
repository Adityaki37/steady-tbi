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
