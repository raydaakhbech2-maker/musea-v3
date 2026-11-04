-- MUSEA V3 — Filiations créatives : créditer l'inspiration sans réduire la création à un repost.
-- À exécuter une seule fois dans Supabase > SQL Editor.

create table if not exists public.creative_lineage (
  id uuid primary key default gen_random_uuid(),
  derived_post_id uuid not null unique references public.posts(id) on delete cascade,
  source_post_id uuid not null references public.posts(id) on delete cascade,
  creator_id uuid not null references auth.users(id) on delete cascade,
  relation_type text not null default 'inspired_by' check (relation_type in ('inspired_by','remix')),
  note text not null default '' check (char_length(note) <= 240),
  created_at timestamptz not null default now(),
  constraint creative_lineage_not_self check (derived_post_id <> source_post_id)
);

create index if not exists creative_lineage_source_idx on public.creative_lineage(source_post_id, created_at desc);
create index if not exists creative_lineage_creator_idx on public.creative_lineage(creator_id, created_at desc);

alter table public.creative_lineage enable row level security;
revoke all on public.creative_lineage from anon, authenticated;
grant select on public.creative_lineage to anon, authenticated;
grant insert, delete on public.creative_lineage to authenticated;

drop policy if exists "Public creative lineages are visible with both public works" on public.creative_lineage;
create policy "Public creative lineages are visible with both public works"
on public.creative_lineage for select to anon, authenticated
using (
  exists (select 1 from public.posts derived where derived.id = creative_lineage.derived_post_id and derived.visibility = 'public')
  and exists (select 1 from public.posts source where source.id = creative_lineage.source_post_id and source.visibility = 'public')
);

drop policy if exists "Creators link their own new public work to a public source" on public.creative_lineage;
create policy "Creators link their own new public work to a public source"
on public.creative_lineage for insert to authenticated
with check (
  creator_id = (select auth.uid())
  and derived_post_id <> source_post_id
  and exists (select 1 from public.posts derived where derived.id = creative_lineage.derived_post_id and derived.user_id = (select auth.uid()) and derived.visibility = 'public')
  and exists (select 1 from public.posts source where source.id = creative_lineage.source_post_id and source.visibility = 'public')
);

drop policy if exists "Creators remove the lineage attached to their own work" on public.creative_lineage;
create policy "Creators remove the lineage attached to their own work"
on public.creative_lineage for delete to authenticated
using (
  creator_id = (select auth.uid())
  and exists (select 1 from public.posts derived where derived.id = creative_lineage.derived_post_id and derived.user_id = (select auth.uid()))
);

comment on table public.creative_lineage is
  'Optional public attribution edge: a published work is inspired by or reinterprets another public MUSEA work. It does not transfer ownership.';
