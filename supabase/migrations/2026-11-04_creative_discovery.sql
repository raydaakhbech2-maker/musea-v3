-- MUSEA V3 — Boussole créative et réglages de découverte
-- À exécuter une seule fois dans Supabase > SQL Editor.

create table if not exists public.creative_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  styles text[] not null default '{}',
  updated_at timestamptz not null default now(),
  constraint creative_preferences_styles_limit check (cardinality(styles) <= 12)
);

alter table public.creative_preferences enable row level security;
revoke all on public.creative_preferences from anon, authenticated;
grant select, insert, update on public.creative_preferences to authenticated;

drop policy if exists "Users read their creative preferences" on public.creative_preferences;
create policy "Users read their creative preferences"
on public.creative_preferences for select to authenticated
using (user_id = auth.uid());

drop policy if exists "Users create their creative preferences" on public.creative_preferences;
create policy "Users create their creative preferences"
on public.creative_preferences for insert to authenticated
with check (user_id = auth.uid());

drop policy if exists "Users update their creative preferences" on public.creative_preferences;
create policy "Users update their creative preferences"
on public.creative_preferences for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create table if not exists public.discovery_feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  post_id uuid not null references public.posts(id) on delete cascade,
  action text not null check (action in ('less_like_this','hide')),
  created_at timestamptz not null default now(),
  unique(user_id, post_id)
);

create index if not exists discovery_feedback_user_idx
on public.discovery_feedback(user_id, action);

alter table public.discovery_feedback enable row level security;
revoke all on public.discovery_feedback from anon, authenticated;
grant select, insert, update, delete on public.discovery_feedback to authenticated;

drop policy if exists "Users manage their discovery feedback" on public.discovery_feedback;
create policy "Users manage their discovery feedback"
on public.discovery_feedback for all to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());
