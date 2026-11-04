-- MUSEA V3 — Profils créateurs et portfolios sélectionnés
-- À exécuter une seule fois dans Supabase > SQL Editor.

alter table public.profiles
  add column if not exists display_name text not null default '',
  add column if not exists headline text not null default '',
  add column if not exists creative_signature text not null default '',
  add column if not exists specialties text[] not null default '{}';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'profiles_headline_length_check'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles add constraint profiles_headline_length_check
      check (char_length(headline) <= 90);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'profiles_signature_length_check'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles add constraint profiles_signature_length_check
      check (char_length(creative_signature) <= 180);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'profiles_specialties_limit_check'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles add constraint profiles_specialties_limit_check
      check (cardinality(specialties) <= 5);
  end if;
end $$;

create table if not exists public.creator_portfolio_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  post_id uuid not null references public.posts(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 70),
  context text not null default '' check (char_length(context) <= 240),
  contribution text not null default '' check (char_length(contribution) <= 100),
  process_note text not null default '' check (char_length(process_note) <= 180),
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(user_id, post_id)
);

create index if not exists creator_portfolio_user_order_idx
  on public.creator_portfolio_items(user_id, sort_order, created_at desc);

alter table public.creator_portfolio_items enable row level security;
revoke all on public.creator_portfolio_items from anon, authenticated;
grant select, insert, update, delete on public.creator_portfolio_items to authenticated;

drop policy if exists "Portfolio items visible to their owner or public profile visitors"
  on public.creator_portfolio_items;
create policy "Portfolio items visible to their owner or public profile visitors"
on public.creator_portfolio_items for select to anon, authenticated
using (
  user_id = auth.uid()
  or exists (
    select 1 from public.profiles p
    where p.id = creator_portfolio_items.user_id
      and coalesce(p.is_private, false) = false
  )
);

drop policy if exists "Creators add portfolio items linked to their own public posts"
  on public.creator_portfolio_items;
create policy "Creators add portfolio items linked to their own public posts"
on public.creator_portfolio_items for insert to authenticated
with check (
  user_id = auth.uid()
  and exists (
    select 1 from public.posts p
    where p.id = creator_portfolio_items.post_id
      and p.user_id = auth.uid()
      and p.visibility = 'public'
  )
);

drop policy if exists "Creators update their portfolio items"
  on public.creator_portfolio_items;
create policy "Creators update their portfolio items"
on public.creator_portfolio_items for update to authenticated
using (user_id = auth.uid())
with check (
  user_id = auth.uid()
  and exists (
    select 1 from public.posts p
    where p.id = creator_portfolio_items.post_id
      and p.user_id = auth.uid()
      and p.visibility = 'public'
  )
);

drop policy if exists "Creators delete their portfolio items"
  on public.creator_portfolio_items;
create policy "Creators delete their portfolio items"
on public.creator_portfolio_items for delete to authenticated
using (user_id = auth.uid());

create or replace function public.musea_limit_creator_portfolio_items()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  current_count integer;
begin
  if tg_op = 'UPDATE' and old.user_id = new.user_id then
    return new;
  end if;
  select count(*) into current_count
  from public.creator_portfolio_items
  where user_id = new.user_id;
  if current_count >= 6 then
    raise exception 'Un portfolio MUSEA peut contenir au maximum 6 pièces.';
  end if;
  return new;
end;
$$;

drop trigger if exists creator_portfolio_limit_trigger
  on public.creator_portfolio_items;
create trigger creator_portfolio_limit_trigger
before insert or update of user_id on public.creator_portfolio_items
for each row execute function public.musea_limit_creator_portfolio_items();

create or replace function public.musea_touch_creator_portfolio_item()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists creator_portfolio_updated_at_trigger
  on public.creator_portfolio_items;
create trigger creator_portfolio_updated_at_trigger
before update on public.creator_portfolio_items
for each row execute function public.musea_touch_creator_portfolio_item();
