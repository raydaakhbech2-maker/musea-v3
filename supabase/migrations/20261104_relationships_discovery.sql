-- MUSEA V3 — relations et intérêts créatifs
-- Étape 8 : abonnements persistants et passerelles de découverte.
create table if not exists public.follows (
  id uuid primary key default gen_random_uuid(),
  follower_id uuid not null references auth.users(id) on delete cascade,
  followed_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint follows_no_self check (follower_id <> followed_id),
  constraint follows_unique_pair unique (follower_id, followed_id)
);
create index if not exists follows_follower_created_idx on public.follows(follower_id, created_at desc);
create index if not exists follows_followed_created_idx on public.follows(followed_id, created_at desc);
create table if not exists public.profile_interests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  interest text not null check (char_length(trim(interest)) between 2 and 32),
  created_at timestamptz not null default now(),
  constraint profile_interests_unique unique(user_id, interest)
);
create index if not exists profile_interests_user_idx on public.profile_interests(user_id);

create or replace function public.musea_limit_profile_interests()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $
begin
  if not exists (
    select 1 from public.profile_interests
    where user_id = new.user_id and interest = new.interest
  ) and (
    select count(*) from public.profile_interests
    where user_id = new.user_id
  ) >= 5 then
    raise exception 'A maximum of five creative interests is allowed';
  end if;
  return new;
end;
$;

drop trigger if exists musea_profile_interests_limit on public.profile_interests;
create trigger musea_profile_interests_limit
before insert on public.profile_interests
for each row execute function public.musea_limit_profile_interests();
revoke all on function public.musea_limit_profile_interests() from public, anon, authenticated;
alter table public.follows enable row level security;
alter table public.profile_interests enable row level security;
drop policy if exists "Users see relationships involving them" on public.follows;
create policy "Users see relationships involving them" on public.follows for select to authenticated using (auth.uid() = follower_id or auth.uid() = followed_id);
drop policy if exists "Users follow other accounts" on public.follows;
create policy "Users follow other accounts" on public.follows for insert to authenticated with check (
  auth.uid() = follower_id and follower_id <> followed_id
  and not exists (select 1 from public.direct_message_blocks b where (b.blocker_id=follower_id and b.blocked_id=followed_id) or (b.blocker_id=followed_id and b.blocked_id=follower_id))
);
drop policy if exists "Users unfollow their own relationships" on public.follows;
create policy "Users unfollow their own relationships" on public.follows for delete to authenticated using (auth.uid() = follower_id);
drop policy if exists "Authenticated users read public creative interests" on public.profile_interests;
create policy "Authenticated users read public creative interests" on public.profile_interests for select to authenticated using (true);
drop policy if exists "Users add their own creative interests" on public.profile_interests;
create policy "Users add their own creative interests" on public.profile_interests for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "Users remove their own creative interests" on public.profile_interests;
create policy "Users remove their own creative interests" on public.profile_interests for delete to authenticated using (auth.uid() = user_id);
grant select, insert, delete on public.follows to authenticated;
grant select, insert, delete on public.profile_interests to authenticated;
do $$
begin
 if exists (select 1 from pg_publication where pubname='supabase_realtime') and not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='follows') then
  alter publication supabase_realtime add table public.follows;
 end if;
end $$;
