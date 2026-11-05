-- Social graph and stories for MUSEA.
-- Safe to re-run; existing profile privacy is respected by RLS.
create table if not exists public.user_follows (
  follower_id uuid not null references auth.users(id) on delete cascade,
  followed_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'accepted' check (status in ('pending','accepted')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (follower_id, followed_id),
  constraint user_follows_no_self check (follower_id <> followed_id)
);
create index if not exists user_follows_followed_status_idx
  on public.user_follows(followed_id,status,created_at desc);
create index if not exists user_follows_follower_status_idx
  on public.user_follows(follower_id,status,created_at desc);

create table if not exists public.stories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  content text not null check (char_length(btrim(content)) between 1 and 500),
  media_url text,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '24 hours'),
  constraint stories_expiry_window check (expires_at > created_at and expires_at <= created_at + interval '25 hours')
);
create index if not exists stories_active_idx on public.stories(expires_at desc,created_at desc);
create index if not exists stories_user_active_idx on public.stories(user_id,expires_at desc);

alter table public.user_follows enable row level security;
alter table public.stories enable row level security;

drop policy if exists "follows_read_participants" on public.user_follows;
create policy "follows_read_participants" on public.user_follows
for select to authenticated using (auth.uid() = follower_id or auth.uid() = followed_id);
drop policy if exists "follows_create_self" on public.user_follows;
create policy "follows_create_self" on public.user_follows
for insert to authenticated with check (
  auth.uid() = follower_id and follower_id <> followed_id
  and exists (select 1 from public.profiles p where p.id = followed_id)
);
drop policy if exists "follows_delete_self" on public.user_follows;
create policy "follows_delete_self" on public.user_follows
for delete to authenticated using (auth.uid() = follower_id or auth.uid() = followed_id);
drop policy if exists "stories_read_visible" on public.stories;
create policy "stories_read_visible" on public.stories
for select to authenticated using (
  expires_at > now() and (
    user_id = auth.uid()
    or exists (
      select 1 from public.profiles p
      where p.id = stories.user_id and coalesce(p.is_private,false) = false
    )
    or exists (
      select 1 from public.user_follows f
      where f.follower_id = auth.uid() and f.followed_id = stories.user_id and f.status = 'accepted'
    )
  )
);
drop policy if exists "stories_insert_self" on public.stories;
create policy "stories_insert_self" on public.stories
for insert to authenticated with check (auth.uid() = user_id and expires_at > now());
drop policy if exists "stories_delete_self" on public.stories;
create policy "stories_delete_self" on public.stories
for delete to authenticated using (auth.uid() = user_id);

create or replace function public.musea_follow_user(p_followed_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare private_profile boolean;
begin
  if auth.uid() is null then raise exception 'Authentification requise'; end if;
  if p_followed_id = auth.uid() then raise exception 'Impossible de se suivre soi-même'; end if;
  select coalesce(is_private,false) into private_profile from public.profiles where id=p_followed_id;
  if not found then raise exception 'Profil introuvable'; end if;
  insert into public.user_follows(follower_id,followed_id,status)
  values(auth.uid(),p_followed_id,case when private_profile then 'pending' else 'accepted' end)
  on conflict(follower_id,followed_id) do update set
    status=excluded.status, updated_at=now();
  return case when private_profile then 'pending' else 'accepted' end;
end;
$$;
revoke all on function public.musea_follow_user(uuid) from public;
grant execute on function public.musea_follow_user(uuid) to authenticated;

create or replace function public.musea_respond_follow_request(p_follower_id uuid,p_accept boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Authentification requise'; end if;
  if p_accept then
    update public.user_follows set status='accepted',updated_at=now()
    where follower_id=p_follower_id and followed_id=auth.uid() and status='pending';
  else
    delete from public.user_follows
    where follower_id=p_follower_id and followed_id=auth.uid() and status='pending';
  end if;
  if not found then raise exception 'Demande introuvable'; end if;
end;
$$;
revoke all on function public.musea_respond_follow_request(uuid,boolean) from public;
grant execute on function public.musea_respond_follow_request(uuid,boolean) to authenticated;
