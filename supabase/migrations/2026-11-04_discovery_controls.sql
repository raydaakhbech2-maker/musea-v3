-- MUSEA V3 — Réglages transparents de la Boussole créative
-- À exécuter après 2026-11-04_creative_discovery.sql.

alter table public.creative_preferences
  add column if not exists exploration_mode text not null default 'balanced',
  add column if not exists personalization_enabled boolean not null default true,
  add column if not exists emerging_enabled boolean not null default true;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.creative_preferences'::regclass
      and conname = 'creative_preferences_exploration_mode_check'
  ) then
    alter table public.creative_preferences
      add constraint creative_preferences_exploration_mode_check
      check (exploration_mode in ('familiar','balanced','curious'));
  end if;
end
$$;

-- Les préférences restent strictement privées et soumises aux politiques RLS
-- déjà définies dans la migration creative_discovery.
alter table public.creative_preferences enable row level security;
revoke all on public.creative_preferences from anon, authenticated;
grant select, insert, update on public.creative_preferences to authenticated;
