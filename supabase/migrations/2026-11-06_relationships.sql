-- MUSEA V3 — Relations créatives et centres d'intérêt publics.
-- À appliquer après 2026-11-06_stories_live.sql (fonction de visibilité des comptes).

create table if not exists public.follows (
  id uuid primary key default gen_random_uuid(),
  follower_id uuid not null references auth.users(id) on delete cascade,
  followed_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint follows_no_self check (follower_id<>followed_id),
  constraint follows_unique_pair unique(follower_id,followed_id)
);
create index if not exists follows_follower_created_idx on public.follows(follower_id,created_at desc);
create index if not exists follows_followed_created_idx on public.follows(followed_id,created_at desc);

create table if not exists public.profile_interests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  interest text not null check (char_length(trim(interest)) between 2 and 32),
  created_at timestamptz not null default now(),
  constraint profile_interests_unique unique(user_id,interest)
);
create index if not exists profile_interests_user_idx on public.profile_interests(user_id);

alter table public.follows enable row level security;
alter table public.profile_interests enable row level security;

drop policy if exists "Members read visible follow relationships" on public.follows;
create policy "Members read visible follow relationships"
on public.follows for select to authenticated
using (
  public.musea_story_is_visible(follower_id)
  and public.musea_story_is_visible(followed_id)
);

drop policy if exists "Members follow visible accounts" on public.follows;
create policy "Members follow visible accounts"
on public.follows for insert to authenticated
with check (
  follower_id=(select auth.uid())
  and follower_id<>followed_id
  and public.musea_story_is_visible(followed_id)
);

drop policy if exists "Members unfollow their own relationships" on public.follows;
create policy "Members unfollow their own relationships"
on public.follows for delete to authenticated
using (follower_id=(select auth.uid()));

drop policy if exists "Members read visible profile interests" on public.profile_interests;
create policy "Members read visible profile interests"
on public.profile_interests for select to authenticated
using (public.musea_story_is_visible(user_id));

drop policy if exists "Members add their own profile interests" on public.profile_interests;
create policy "Members add their own profile interests"
on public.profile_interests for insert to authenticated
with check (user_id=(select auth.uid()));

drop policy if exists "Members remove their own profile interests" on public.profile_interests;
create policy "Members remove their own profile interests"
on public.profile_interests for delete to authenticated
using (user_id=(select auth.uid()));

create or replace function public.musea_limit_profile_interests()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform pg_advisory_xact_lock(hashtextextended(new.user_id::text,0));
  if not exists (
    select 1 from public.profile_interests
    where user_id=new.user_id and interest=new.interest
  ) and (
    select count(*) from public.profile_interests
    where user_id=new.user_id
  ) >= 5 then
    raise exception 'A maximum of five public profile interests is allowed';
  end if;
  return new;
end;
$$;

drop trigger if exists musea_profile_interests_limit on public.profile_interests;
create trigger musea_profile_interests_limit
before insert on public.profile_interests
for each row execute function public.musea_limit_profile_interests();

revoke all on function public.musea_limit_profile_interests() from public,anon,authenticated;
grant select,insert,delete on public.follows to authenticated;
grant select,insert,delete on public.profile_interests to authenticated;

do $$
begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime') then
    if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='follows') then
      alter publication supabase_realtime add table public.follows;
    end if;
    if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='profile_interests') then
      alter publication supabase_realtime add table public.profile_interests;
    end if;
  end if;
end $$;

create or replace function public.musea_search_creators(p_query text)
returns table(id uuid,username text,bio text)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id,p.username,p.bio
  from public.profiles p
  where (select auth.uid()) is not null
    and p.id<>(select auth.uid())
    and char_length(trim(coalesce(p_query,''))) between 2 and 40
    and p.username ilike ('%' || left(trim(p_query),40) || '%')
    and public.musea_story_is_visible(p.id)
  order by p.username
  limit 25;
$$;
revoke all on function public.musea_search_creators(text) from public,anon;
grant execute on function public.musea_search_creators(text) to authenticated;
