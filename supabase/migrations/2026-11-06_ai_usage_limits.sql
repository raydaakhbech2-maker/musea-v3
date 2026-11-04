-- MUSEA V3 — quotas serveur pour l'assistant créatif IA.
-- Les compteurs ne sont jamais modifiables depuis le navigateur.
-- Les appels sont réservés par compte et par jour UTC avant toute dépense API.

create table if not exists public.ai_usage_daily (
  user_id uuid not null references auth.users(id) on delete cascade,
  usage_date date not null default (now() at time zone 'utc')::date,
  text_requests integer not null default 0 check (text_requests >= 0),
  image_requests integer not null default 0 check (image_requests >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, usage_date)
);

alter table public.ai_usage_daily enable row level security;
revoke all on public.ai_usage_daily from anon, authenticated;
grant all on public.ai_usage_daily to service_role;

create or replace function public.musea_claim_ai_usage(
  p_user_id uuid,
  p_kind text,
  p_daily_limit integer
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claimed uuid;
  v_today date := (now() at time zone 'utc')::date;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'Accès serveur uniquement.';
  end if;
  if p_user_id is null
     or p_kind not in ('text','image')
     or p_daily_limit is null
     or p_daily_limit < 1
     or p_daily_limit > 500 then
    raise exception 'Paramètres de quota invalides.';
  end if;

  insert into public.ai_usage_daily(user_id,usage_date,text_requests,image_requests,updated_at)
  values (
    p_user_id,
    v_today,
    case when p_kind='text' then 1 else 0 end,
    case when p_kind='image' then 1 else 0 end,
    now()
  )
  on conflict (user_id,usage_date) do update
    set text_requests = public.ai_usage_daily.text_requests
          + case when p_kind='text' then 1 else 0 end,
        image_requests = public.ai_usage_daily.image_requests
          + case when p_kind='image' then 1 else 0 end,
        updated_at = now()
    where
      case when p_kind='text'
        then public.ai_usage_daily.text_requests < p_daily_limit
        else public.ai_usage_daily.image_requests < p_daily_limit
      end
  returning user_id into v_claimed;

  return v_claimed is not null;
end;
$$;

revoke all on function public.musea_claim_ai_usage(uuid,text,integer) from public,anon,authenticated;
grant execute on function public.musea_claim_ai_usage(uuid,text,integer) to service_role;

comment on table public.ai_usage_daily is
  'Compteurs quotidiens privés pour limiter les dépenses IA par compte MUSEA. Écriture et lecture réservées au serveur.';
