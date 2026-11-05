-- MUSEA social graph compatibility migration.
-- The existing project was provisioned outside migration history; preserve its current stories schema.
create table if not exists public.user_follows (
  follower_id uuid not null references auth.users(id) on delete cascade,
  followed_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'accepted' check (status in ('pending','accepted')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (follower_id, followed_id),
  constraint user_follows_no_self check (follower_id <> followed_id)
);
create index if not exists user_follows_followed_status_idx on public.user_follows(followed_id,status,created_at desc);
create index if not exists user_follows_follower_status_idx on public.user_follows(follower_id,status,created_at desc);
alter table public.user_follows enable row level security;
grant select, insert, delete on public.user_follows to authenticated;

drop policy if exists user_follows_read_participants on public.user_follows;
create policy user_follows_read_participants on public.user_follows
for select to authenticated using ((select auth.uid())=follower_id or (select auth.uid())=followed_id);
drop policy if exists user_follows_insert_self on public.user_follows;
create policy user_follows_insert_self on public.user_follows
for insert to authenticated with check ((select auth.uid())=follower_id and follower_id<>followed_id);
drop policy if exists user_follows_delete_participants on public.user_follows;
create policy user_follows_delete_participants on public.user_follows
for delete to authenticated using ((select auth.uid())=follower_id or (select auth.uid())=followed_id);

create or replace function public.musea_follow_user(p_followed_id uuid)
returns text language plpgsql security definer set search_path = ''
as $$
declare v_private boolean; v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Authentification requise'; end if;
  if p_followed_id = v_user then raise exception 'Impossible de se suivre soi-même'; end if;
  select coalesce(p.is_private,false) into v_private from public.profiles p where p.id=p_followed_id;
  if not found then raise exception 'Profil introuvable'; end if;
  insert into public.user_follows(follower_id,followed_id,status)
  values(v_user,p_followed_id,case when v_private then 'pending' else 'accepted' end)
  on conflict(follower_id,followed_id) do update set status=excluded.status,updated_at=now();
  return case when v_private then 'pending' else 'accepted' end;
end $$;
revoke all on function public.musea_follow_user(uuid) from public, anon;
grant execute on function public.musea_follow_user(uuid) to authenticated;

create or replace function public.musea_respond_follow_request(p_follower_id uuid,p_accept boolean)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Authentification requise'; end if;
  if p_accept then
    update public.user_follows set status='accepted',updated_at=now()
    where follower_id=p_follower_id and followed_id=v_user and status='pending';
  else
    delete from public.user_follows
    where follower_id=p_follower_id and followed_id=v_user and status='pending';
  end if;
  if not found then raise exception 'Demande introuvable'; end if;
end $$;
revoke all on function public.musea_respond_follow_request(uuid,boolean) from public, anon;
grant execute on function public.musea_respond_follow_request(uuid,boolean) to authenticated;

-- Replace the overly broad legacy story policy with privacy-aware visibility.
drop policy if exists "Authenticated users see active unblocked stories" on public.stories;
drop policy if exists stories_read_visible on public.stories;
create policy stories_read_visible on public.stories
for select to authenticated using (
  expires_at > now() and (
    user_id = (select auth.uid())
    or exists (select 1 from public.profiles p where p.id=stories.user_id and coalesce(p.is_private,false)=false)
    or exists (select 1 from public.user_follows f where f.follower_id=(select auth.uid()) and f.followed_id=stories.user_id and f.status='accepted')
  )
);
grant select, insert, delete on public.stories to authenticated;
