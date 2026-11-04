-- MUSEA V3 — Stories persistantes, éphémères et protégées
-- Étape 7 : Stories photo/vidéo/texte, 24 h, vues et stockage privé.

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
  constraint stories_media_pair check ((media_path is null and media_type is null) or (media_path is not null and media_type is not null))
);

create index if not exists stories_active_created_idx
  on public.stories(expires_at, created_at desc);
create index if not exists stories_user_active_idx
  on public.stories(user_id, expires_at desc);

create table if not exists public.story_views (
  id uuid primary key default gen_random_uuid(),
  story_id uuid not null references public.stories(id) on delete cascade,
  viewer_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint story_views_one_per_user unique(story_id, viewer_id)
);
create index if not exists story_views_story_idx on public.story_views(story_id);

alter table public.stories enable row level security;
alter table public.story_views enable row level security;

drop policy if exists "Authenticated users see active unblocked stories" on public.stories;
create policy "Authenticated users see active unblocked stories"
on public.stories for select to authenticated
using (
  expires_at > now()
  and not exists (
    select 1 from public.direct_message_blocks b
    where (b.blocker_id = auth.uid() and b.blocked_id = stories.user_id)
       or (b.blocker_id = stories.user_id and b.blocked_id = auth.uid())
  )
);

drop policy if exists "Users publish their own stories" on public.stories;
create policy "Users publish their own stories"
on public.stories for insert to authenticated
with check (
  auth.uid() = user_id
  and created_at <= now() + interval '1 minute'
  and expires_at > now()
  and expires_at <= now() + interval '24 hours' + interval '1 minute'
);

drop policy if exists "Users delete their own stories" on public.stories;
create policy "Users delete their own stories"
on public.stories for delete to authenticated
using (auth.uid() = user_id);

drop policy if exists "Story owners and viewers read view records" on public.story_views;
create policy "Story owners and viewers read view records"
on public.story_views for select to authenticated
using (
  viewer_id = auth.uid()
  or exists (select 1 from public.stories s where s.id = story_id and s.user_id = auth.uid())
);

drop policy if exists "Users record their own story views" on public.story_views;
create policy "Users record their own story views"
on public.story_views for insert to authenticated
with check (
  viewer_id = auth.uid()
  and exists (
    select 1 from public.stories s
    where s.id = story_id
      and s.user_id <> auth.uid()
      and s.expires_at > now()
      and not exists (
        select 1 from public.direct_message_blocks b
        where (b.blocker_id = auth.uid() and b.blocked_id = s.user_id)
           or (b.blocker_id = s.user_id and b.blocked_id = auth.uid())
      )
  )
);

grant select, insert, delete on public.stories to authenticated;
grant select, insert on public.story_views to authenticated;

-- Bucket privé dédié : les médias de Stories ne sont pas accessibles par URL publique.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'musea-stories',
  'musea-stories',
  false,
  20971520,
  array['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/webm']
)
on conflict (id) do update set
  public = false,
  file_size_limit = 20971520,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Users upload story media to own folder" on storage.objects;
create policy "Users upload story media to own folder"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'musea-stories'
  and (storage.foldername(name))[1] = 'stories'
  and (storage.foldername(name))[2] = auth.uid()::text
);

drop policy if exists "Users read active unblocked story media" on storage.objects;
create policy "Users read active unblocked story media"
on storage.objects for select to authenticated
using (
  bucket_id = 'musea-stories'
  and exists (
    select 1 from public.stories s
    where s.media_path = storage.objects.name
      and s.expires_at > now()
      and not exists (
        select 1 from public.direct_message_blocks b
        where (b.blocker_id = auth.uid() and b.blocked_id = s.user_id)
           or (b.blocker_id = s.user_id and b.blocked_id = auth.uid())
      )
  )
);

drop policy if exists "Users delete their own story media" on storage.objects;
create policy "Users delete their own story media"
on storage.objects for delete to authenticated
using (
  bucket_id = 'musea-stories'
  and (storage.foldername(name))[1] = 'stories'
  and (storage.foldername(name))[2] = auth.uid()::text
);

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'stories'
    ) then
      alter publication supabase_realtime add table public.stories;
    end if;
  end if;
end $$;
