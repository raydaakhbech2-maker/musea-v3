-- MUSEA V3 — Stories synchronisées, privées et éphémères (24 h).
-- Cette version utilise public.user_blocks, présent dans la migration messaging_collaboration.

create table if not exists public.stories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  caption text check (caption is null or char_length(caption) <= 240),
  media_path text,
  media_type text check (media_type is null or media_type in ('image','video')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  constraint stories_expiry_after_creation check (expires_at > created_at),
  constraint stories_max_24h check (expires_at <= created_at + interval '24 hours' + interval '1 minute'),
  constraint stories_content_required check (nullif(trim(coalesce(caption,'')),'') is not null or media_path is not null),
  constraint stories_media_pair check ((media_path is null and media_type is null) or (media_path is not null and media_type is not null)),
  constraint stories_media_owner_path check (media_path is null or media_path like ('stories/' || user_id::text || '/%'))
);

create index if not exists stories_active_created_idx on public.stories(expires_at,created_at desc);
create index if not exists stories_user_active_idx on public.stories(user_id,expires_at desc);

create table if not exists public.story_views (
  id uuid primary key default gen_random_uuid(),
  story_id uuid not null references public.stories(id) on delete cascade,
  viewer_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint story_views_one_per_user unique(story_id,viewer_id)
);
create index if not exists story_views_story_idx on public.story_views(story_id);

alter table public.stories enable row level security;
alter table public.story_views enable row level security;

create or replace function public.musea_story_is_visible(p_owner_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    (select auth.uid()) is not null
    and p_owner_id is not null
    and not exists (
      select 1 from public.user_blocks b
      where (b.blocker_id = (select auth.uid()) and b.blocked_id = p_owner_id)
         or (b.blocker_id = p_owner_id and b.blocked_id = (select auth.uid()))
    );
$$;

revoke all on function public.musea_story_is_visible(uuid) from public;
grant execute on function public.musea_story_is_visible(uuid) to anon,authenticated;

drop policy if exists "Members read active unblocked stories" on public.stories;
create policy "Members read active unblocked stories"
on public.stories for select to authenticated
using (expires_at > now() and public.musea_story_is_visible(user_id));

drop policy if exists "Members publish their own stories" on public.stories;
create policy "Members publish their own stories"
on public.stories for insert to authenticated
with check (
  user_id = (select auth.uid())
  and expires_at > now()
  and expires_at <= now() + interval '24 hours' + interval '1 minute'
  and (media_path is null or media_path like ('stories/' || (select auth.uid())::text || '/%'))
);

drop policy if exists "Members delete their own stories" on public.stories;
create policy "Members delete their own stories"
on public.stories for delete to authenticated
using (user_id = (select auth.uid()));

drop policy if exists "Story owners and viewers read view records" on public.story_views;
create policy "Story owners and viewers read view records"
on public.story_views for select to authenticated
using (
  viewer_id = (select auth.uid())
  or exists (select 1 from public.stories s where s.id = story_id and s.user_id = (select auth.uid()))
);

drop policy if exists "Members record their own story views" on public.story_views;
create policy "Members record their own story views"
on public.story_views for insert to authenticated
with check (
  viewer_id = (select auth.uid())
  and exists (
    select 1 from public.stories s
    where s.id = story_id
      and s.user_id <> (select auth.uid())
      and s.expires_at > now()
      and public.musea_story_is_visible(s.user_id)
  )
);

grant select,insert,delete on public.stories to authenticated;
grant select,insert on public.story_views to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values (
  'musea-stories','musea-stories',false,20971520,
  array['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/webm']::text[]
)
on conflict(id) do update set
  name=excluded.name,
  public=false,
  file_size_limit=excluded.file_size_limit,
  allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists "Members upload their own story media" on storage.objects;
create policy "Members upload their own story media"
on storage.objects for insert to authenticated
with check (
  bucket_id='musea-stories'
  and (storage.foldername(name))[1]='stories'
  and (storage.foldername(name))[2]=(select auth.uid())::text
);

drop policy if exists "Members read active unblocked story media" on storage.objects;
create policy "Members read active unblocked story media"
on storage.objects for select to authenticated
using (
  bucket_id='musea-stories'
  and exists (
    select 1 from public.stories s
    where s.media_path=storage.objects.name
      and s.expires_at>now()
      and public.musea_story_is_visible(s.user_id)
  )
);

drop policy if exists "Members delete their own story media" on storage.objects;
create policy "Members delete their own story media"
on storage.objects for delete to authenticated
using (
  bucket_id='musea-stories'
  and (storage.foldername(name))[1]='stories'
  and (storage.foldername(name))[2]=(select auth.uid())::text
);
drop policy if exists "Restrict story media uploads to owner" on storage.objects;
create policy "Restrict story media uploads to owner"
on storage.objects as restrictive for insert to authenticated
with check (
  bucket_id<>'musea-stories'
  or ((storage.foldername(name))[1]='stories' and (storage.foldername(name))[2]=(select auth.uid())::text)
);

drop policy if exists "Restrict story media reads to visible active stories" on storage.objects;
create policy "Restrict story media reads to visible active stories"
on storage.objects as restrictive for select to authenticated
using (
  bucket_id<>'musea-stories'
  or exists (
    select 1 from public.stories s
    where s.media_path=storage.objects.name
      and s.expires_at>now()
      and public.musea_story_is_visible(s.user_id)
  )
);

drop policy if exists "Restrict story media deletion to owner" on storage.objects;
create policy "Restrict story media deletion to owner"
on storage.objects as restrictive for delete to authenticated
using (
  bucket_id<>'musea-stories'
  or ((storage.foldername(name))[1]='stories' and (storage.foldername(name))[2]=(select auth.uid())::text)
);

do $$
begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime')
     and not exists(
       select 1 from pg_publication_tables
       where pubname='supabase_realtime' and schemaname='public' and tablename='stories'
     ) then
    alter publication supabase_realtime add table public.stories;
  end if;
end $$;

comment on table public.stories is
  'Stories visibles aux membres connectés non bloqués, avec expiration serveur à 24 h.';
comment on table public.story_views is
  'Une vue par membre et par Story ; seuls le propriétaire et le spectateur voient la ligne.';
