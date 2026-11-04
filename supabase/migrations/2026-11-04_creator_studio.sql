-- MUSEA V3 — Studio créatif et projets privés
-- À exécuter dans Supabase > SQL Editor après les migrations de base.

create table if not exists public.creator_drafts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 80),
  caption text not null default '' check (char_length(caption) <= 500),
  creative_brief text not null default '' check (char_length(creative_brief) <= 1000),
  notes text not null default '' check (char_length(notes) <= 2000),
  style text not null default 'Digital art' check (char_length(style) <= 40),
  format text not null default 'Carré' check (format in ('Carré','Portrait','Paysage','Story 9:16')),
  status text not null default 'in_progress' check (status in ('idea','in_progress','ready')),
  image_path text,
  edit_settings jsonb not null default '{}'::jsonb
    check (jsonb_typeof(edit_settings) = 'object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint creator_drafts_image_owner_path_check
    check (image_path is null or split_part(image_path,'/',1) = user_id::text)
);

create index if not exists creator_drafts_owner_updated_idx
  on public.creator_drafts(user_id, updated_at desc);

alter table public.creator_drafts enable row level security;
revoke all on public.creator_drafts from anon, authenticated;
grant select, insert, update, delete on public.creator_drafts to authenticated;

drop policy if exists "Creators read their own private drafts" on public.creator_drafts;
create policy "Creators read their own private drafts"
on public.creator_drafts for select to authenticated
using (user_id = auth.uid());

drop policy if exists "Creators create their own private drafts" on public.creator_drafts;
create policy "Creators create their own private drafts"
on public.creator_drafts for insert to authenticated
with check (
  user_id = auth.uid()
  and (image_path is null or split_part(image_path,'/',1) = auth.uid()::text)
);

drop policy if exists "Creators update their own private drafts" on public.creator_drafts;
create policy "Creators update their own private drafts"
on public.creator_drafts for update to authenticated
using (user_id = auth.uid())
with check (
  user_id = auth.uid()
  and (image_path is null or split_part(image_path,'/',1) = auth.uid()::text)
);

drop policy if exists "Creators delete their own private drafts" on public.creator_drafts;
create policy "Creators delete their own private drafts"
on public.creator_drafts for delete to authenticated
using (user_id = auth.uid());

create or replace function public.musea_touch_creator_draft()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists creator_drafts_updated_at_trigger on public.creator_drafts;
create trigger creator_drafts_updated_at_trigger
before update on public.creator_drafts
for each row execute function public.musea_touch_creator_draft();

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('musea-drafts','musea-drafts',false,5242880,array['image/webp','image/jpeg','image/png']::text[])
on conflict (id) do update
set name = excluded.name, public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Creators read their own private studio assets" on storage.objects;
create policy "Creators read their own private studio assets"
on storage.objects for select to authenticated
using (bucket_id = 'musea-drafts' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "Creators upload their own private studio assets" on storage.objects;
create policy "Creators upload their own private studio assets"
on storage.objects for insert to authenticated
with check (bucket_id = 'musea-drafts' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "Creators update their own private studio assets" on storage.objects;
create policy "Creators update their own private studio assets"
on storage.objects for update to authenticated
using (bucket_id = 'musea-drafts' and (storage.foldername(name))[1] = auth.uid()::text)
with check (bucket_id = 'musea-drafts' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "Creators delete their own private studio assets" on storage.objects;
create policy "Creators delete their own private studio assets"
on storage.objects for delete to authenticated
using (bucket_id = 'musea-drafts' and (storage.foldername(name))[1] = auth.uid()::text);
