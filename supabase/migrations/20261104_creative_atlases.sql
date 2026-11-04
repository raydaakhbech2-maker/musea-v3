-- MUSEA V3 — Atlas créatifs
-- Étape 11 : collections éditorialisées, publiques ou privées, avec ordre et annotations.

create table if not exists public.creative_atlases (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(trim(title)) between 3 and 60),
  description text not null default '' check (char_length(description) <= 240),
  visibility text not null default 'private' check (visibility in ('public','private')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists creative_atlases_owner_updated_idx
  on public.creative_atlases(owner_id, updated_at desc);
create index if not exists creative_atlases_public_updated_idx
  on public.creative_atlases(updated_at desc)
  where visibility = 'public';

create table if not exists public.creative_atlas_items (
  id uuid primary key default gen_random_uuid(),
  atlas_id uuid not null references public.creative_atlases(id) on delete cascade,
  post_id uuid not null references public.posts(id) on delete cascade,
  note text not null default '' check (char_length(note) <= 240),
  position integer not null default 0 check (position between 0 and 9999),
  created_at timestamptz not null default now(),
  constraint creative_atlas_items_unique_post unique(atlas_id, post_id)
);

create index if not exists creative_atlas_items_order_idx
  on public.creative_atlas_items(atlas_id, position, created_at);

alter table public.creative_atlases enable row level security;
alter table public.creative_atlas_items enable row level security;

drop policy if exists "Atlas owners and public visitors read atlases" on public.creative_atlases;
create policy "Atlas owners and public visitors read atlases"
on public.creative_atlases for select to anon, authenticated
using (
  owner_id = auth.uid()
  or visibility = 'public'
);

drop policy if exists "Users create their own atlases" on public.creative_atlases;
create policy "Users create their own atlases"
on public.creative_atlases for insert to authenticated
with check (owner_id = auth.uid());

drop policy if exists "Users update their own atlases" on public.creative_atlases;
create policy "Users update their own atlases"
on public.creative_atlases for update to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());

drop policy if exists "Users delete their own atlases" on public.creative_atlases;
create policy "Users delete their own atlases"
on public.creative_atlases for delete to authenticated
using (owner_id = auth.uid());

drop policy if exists "Atlas items follow atlas visibility" on public.creative_atlas_items;
create policy "Atlas items follow atlas visibility"
on public.creative_atlas_items for select to anon, authenticated
using (
  exists (
    select 1
    from public.creative_atlases a
    join public.posts p on p.id = creative_atlas_items.post_id
    where a.id = creative_atlas_items.atlas_id
      and p.visibility = 'public'
      and (a.owner_id = auth.uid() or a.visibility = 'public')
  )
);

drop policy if exists "Owners add public creations to their atlases" on public.creative_atlas_items;
create policy "Owners add public creations to their atlases"
on public.creative_atlas_items for insert to authenticated
with check (
  exists (
    select 1
    from public.creative_atlases a
    join public.posts p on p.id = creative_atlas_items.post_id
    where a.id = creative_atlas_items.atlas_id
      and a.owner_id = auth.uid()
      and p.visibility = 'public'
  )
);

drop policy if exists "Owners edit their atlas items" on public.creative_atlas_items;
create policy "Owners edit their atlas items"
on public.creative_atlas_items for update to authenticated
using (
  exists (
    select 1 from public.creative_atlases a
    where a.id = creative_atlas_items.atlas_id
      and a.owner_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.creative_atlases a
    join public.posts p on p.id = creative_atlas_items.post_id
    where a.id = creative_atlas_items.atlas_id
      and a.owner_id = auth.uid()
      and p.visibility = 'public'
  )
);

drop policy if exists "Owners remove their atlas items" on public.creative_atlas_items;
create policy "Owners remove their atlas items"
on public.creative_atlas_items for delete to authenticated
using (
  exists (
    select 1 from public.creative_atlases a
    where a.id = creative_atlas_items.atlas_id
      and a.owner_id = auth.uid()
  )
);

grant select on public.creative_atlases, public.creative_atlas_items to anon, authenticated;
grant insert, update, delete on public.creative_atlases to authenticated;
grant insert, update, delete on public.creative_atlas_items to authenticated;

create or replace function public.musea_touch_atlas_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $musea$
begin
  new.updated_at = now();
  return new;
end;
$musea$;

drop trigger if exists musea_touch_atlas_updated_at on public.creative_atlases;
create trigger musea_touch_atlas_updated_at
before update on public.creative_atlases
for each row execute function public.musea_touch_atlas_updated_at();

revoke all on function public.musea_touch_atlas_updated_at() from public, anon, authenticated;
