-- MUSEA V3 — Les Atlas créatifs : collections éditorialisées et annotées.

create table if not exists public.creative_atlases (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(trim(title)) between 3 and 60),
  description text not null default '' check (char_length(description)<=240),
  visibility text not null default 'private' check (visibility in ('public','private')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists creative_atlases_owner_updated_idx on public.creative_atlases(owner_id,updated_at desc);
create index if not exists creative_atlases_public_updated_idx on public.creative_atlases(updated_at desc) where visibility='public';

create table if not exists public.creative_atlas_items (
  id uuid primary key default gen_random_uuid(),
  atlas_id uuid not null references public.creative_atlases(id) on delete cascade,
  post_id uuid not null references public.posts(id) on delete cascade,
  note text not null default '' check (char_length(note)<=240),
  position integer not null default 0 check (position between 0 and 9999),
  created_at timestamptz not null default now(),
  constraint creative_atlas_items_unique_post unique(atlas_id,post_id)
);
create index if not exists creative_atlas_items_order_idx on public.creative_atlas_items(atlas_id,position,created_at);

alter table public.creative_atlases enable row level security;
alter table public.creative_atlas_items enable row level security;
revoke all on public.creative_atlases,public.creative_atlas_items from anon,authenticated;
grant select,insert,update,delete on public.creative_atlases,public.creative_atlas_items to authenticated;

drop policy if exists "Atlas owners and visible members read atlases" on public.creative_atlases;
create policy "Atlas owners and visible members read atlases"
on public.creative_atlases for select to authenticated
using (owner_id=(select auth.uid()) or (visibility='public' and public.musea_story_is_visible(owner_id)));

drop policy if exists "Members create their own atlases" on public.creative_atlases;
create policy "Members create their own atlases"
on public.creative_atlases for insert to authenticated
with check(owner_id=(select auth.uid()));

drop policy if exists "Members update their own atlases" on public.creative_atlases;
create policy "Members update their own atlases"
on public.creative_atlases for update to authenticated
using(owner_id=(select auth.uid()))
with check(owner_id=(select auth.uid()));

drop policy if exists "Members delete their own atlases" on public.creative_atlases;
create policy "Members delete their own atlases"
on public.creative_atlases for delete to authenticated
using(owner_id=(select auth.uid()));

drop policy if exists "Atlas items follow atlas and post visibility" on public.creative_atlas_items;
create policy "Atlas items follow atlas and post visibility"
on public.creative_atlas_items for select to authenticated
using (
  exists (
    select 1 from public.creative_atlases a
    join public.posts p on p.id=creative_atlas_items.post_id
    where a.id=creative_atlas_items.atlas_id
      and p.visibility='public'
      and (a.owner_id=(select auth.uid()) or a.visibility='public')
      and public.musea_story_is_visible(a.owner_id)
      and public.musea_story_is_visible(p.user_id)
  )
);

drop policy if exists "Owners add visible public posts to their atlases" on public.creative_atlas_items;
create policy "Owners add visible public posts to their atlases"
on public.creative_atlas_items for insert to authenticated
with check (
  exists (
    select 1 from public.creative_atlases a
    join public.posts p on p.id=creative_atlas_items.post_id
    where a.id=creative_atlas_items.atlas_id
      and a.owner_id=(select auth.uid())
      and p.visibility='public'
      and public.musea_story_is_visible(p.user_id)
  )
);

drop policy if exists "Owners update their atlas items" on public.creative_atlas_items;
create policy "Owners update their atlas items"
on public.creative_atlas_items for update to authenticated
using (
  exists(select 1 from public.creative_atlases a where a.id=creative_atlas_items.atlas_id and a.owner_id=(select auth.uid()))
)
with check (
  exists (
    select 1 from public.creative_atlases a
    join public.posts p on p.id=creative_atlas_items.post_id
    where a.id=creative_atlas_items.atlas_id
      and a.owner_id=(select auth.uid())
      and p.visibility='public'
      and public.musea_story_is_visible(p.user_id)
  )
);

drop policy if exists "Owners remove their atlas items" on public.creative_atlas_items;
create policy "Owners remove their atlas items"
on public.creative_atlas_items for delete to authenticated
using(exists(select 1 from public.creative_atlases a where a.id=creative_atlas_items.atlas_id and a.owner_id=(select auth.uid())));

create or replace function public.musea_touch_atlas_updated_at()
returns trigger language plpgsql set search_path='' as $$
begin new.updated_at=now();return new;end;
$$;
drop trigger if exists musea_touch_atlas_updated_at on public.creative_atlases;
create trigger musea_touch_atlas_updated_at before update on public.creative_atlases
for each row execute function public.musea_touch_atlas_updated_at();
revoke all on function public.musea_touch_atlas_updated_at() from public,anon,authenticated;

create or replace function public.musea_limit_creative_atlases()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform pg_advisory_xact_lock(hashtextextended(new.owner_id::text,1));
  if (select count(*) from public.creative_atlases where owner_id=new.owner_id)>=50 then
    raise exception 'A creator can keep up to 50 Atlases';
  end if;
  return new;
end;
$$;
drop trigger if exists musea_limit_creative_atlases on public.creative_atlases;
create trigger musea_limit_creative_atlases before insert on public.creative_atlases
for each row execute function public.musea_limit_creative_atlases();
revoke all on function public.musea_limit_creative_atlases() from public,anon,authenticated;

create or replace function public.musea_limit_creative_atlas_items()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform pg_advisory_xact_lock(hashtextextended(new.atlas_id::text,2));
  if not exists(select 1 from public.creative_atlas_items where atlas_id=new.atlas_id and post_id=new.post_id)
     and (select count(*) from public.creative_atlas_items where atlas_id=new.atlas_id)>=100 then
    raise exception 'An Atlas can contain up to 100 creations';
  end if;
  return new;
end;
$$;
drop trigger if exists musea_limit_creative_atlas_items on public.creative_atlas_items;
create trigger musea_limit_creative_atlas_items before insert on public.creative_atlas_items
for each row execute function public.musea_limit_creative_atlas_items();
revoke all on function public.musea_limit_creative_atlas_items() from public,anon,authenticated;

create or replace function public.musea_touch_atlas_on_item_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_atlas_id uuid := coalesce(new.atlas_id,old.atlas_id);
begin
  update public.creative_atlases set updated_at=now() where id=v_atlas_id;
  return coalesce(new,old);
end;
$$;
drop trigger if exists musea_touch_atlas_on_item_change on public.creative_atlas_items;
create trigger musea_touch_atlas_on_item_change
after insert or update or delete on public.creative_atlas_items
for each row execute function public.musea_touch_atlas_on_item_change();
revoke all on function public.musea_touch_atlas_on_item_change() from public,anon,authenticated;
