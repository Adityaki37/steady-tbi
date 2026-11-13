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
