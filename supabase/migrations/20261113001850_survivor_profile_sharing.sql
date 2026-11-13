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
