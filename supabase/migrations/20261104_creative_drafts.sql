-- MUSEA V3 — Les Pistes : espace privé de préparation des créations.
-- Étape 12 : brouillons persistants, image privée et progression créative.

create table if not exists public.creative_drafts (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(trim(title)) between 3 and 80),
  caption text not null default '' check (char_length(caption) <= 500),
  style text not null default 'Digital art' check (char_length(style) <= 40),
  format text not null default 'Carré' check (char_length(format) <= 30),
  status text not null default 'seed' check (status in ('seed','work','ready')),
  journal_intention text not null default '' check (char_length(journal_intention) <= 400),
  journal_choice text not null default '' check (char_length(journal_choice) <= 400),
  journal_discovery text not null default '' check (char_length(journal_discovery) <= 400),
  image_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint creative_drafts_image_owner_path check (
    image_path is null or image_path like (owner_id::text || '/%')
  )
);

create index if not exists creative_drafts_owner_updated_idx
  on public.creative_drafts(owner_id, updated_at desc);

alter table public.creative_drafts enable row level security;

drop policy if exists "Creators read their own drafts" on public.creative_drafts;
create policy "Creators read their own drafts"
on public.creative_drafts for select to authenticated
using (owner_id = auth.uid());

drop policy if exists "Creators create their own drafts" on public.creative_drafts;
create policy "Creators create their own drafts"
on public.creative_drafts for insert to authenticated
with check (owner_id = auth.uid());

drop policy if exists "Creators update their own drafts" on public.creative_drafts;
create policy "Creators update their own drafts"
on public.creative_drafts for update to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());

drop policy if exists "Creators delete their own drafts" on public.creative_drafts;
create policy "Creators delete their own drafts"
on public.creative_drafts for delete to authenticated
using (owner_id = auth.uid());

grant select, insert, update, delete on public.creative_drafts to authenticated;
revoke all on public.creative_drafts from anon;

create or replace function public.musea_touch_creative_draft_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $musea$
begin
  new.updated_at = now();
  return new;
end;
$musea$;

drop trigger if exists musea_touch_creative_draft_updated_at on public.creative_drafts;
create trigger musea_touch_creative_draft_updated_at
before update on public.creative_drafts
for each row execute function public.musea_touch_creative_draft_updated_at();

revoke all on function public.musea_touch_creative_draft_updated_at() from public, anon, authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'musea-drafts',
  'musea-drafts',
  false,
  5242880,
  array['image/jpeg','image/png','image/webp','image/gif']
)
on conflict (id) do update set
  public = false,
  file_size_limit = 5242880,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Creators upload private draft images" on storage.objects;
create policy "Creators upload private draft images"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'musea-drafts'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Creators read private draft images" on storage.objects;
create policy "Creators read private draft images"
on storage.objects for select to authenticated
using (
  bucket_id = 'musea-drafts'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Creators delete private draft images" on storage.objects;
create policy "Creators delete private draft images"
on storage.objects for delete to authenticated
using (
  bucket_id = 'musea-drafts'
  and (storage.foldername(name))[1] = auth.uid()::text
);
