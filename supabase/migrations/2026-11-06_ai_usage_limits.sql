-- MUSEA V3 — quotas IA par compte et plafond global quotidien.
-- Les compteurs sont réservés par le serveur avant toute dépense fournisseur.

create table if not exists public.ai_usage_daily (
  user_id uuid not null references auth.users(id) on delete cascade,
  usage_date date not null default (now() at time zone 'utc')::date,
  text_requests integer not null default 0 check (text_requests >= 0),
  image_requests integer not null default 0 check (image_requests >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, usage_date)
);

create table if not exists public.ai_usage_global_daily (
  usage_date date primary key default (now() at time zone 'utc')::date,
  text_requests integer not null default 0 check (text_requests >= 0),
  image_requests integer not null default 0 check (image_requests >= 0),
  updated_at timestamptz not null default now()
);

alter table public.ai_usage_daily enable row level security;
alter table public.ai_usage_global_daily enable row level security;
revoke all on public.ai_usage_daily,public.ai_usage_global_daily from anon, authenticated;
grant all on public.ai_usage_daily,public.ai_usage_global_daily to service_role;

drop function if exists public.musea_claim_ai_usage(uuid,text,integer);
drop function if exists public.musea_claim_ai_usage(uuid,text,integer,integer);

create function public.musea_claim_ai_usage(
  p_user_id uuid,
  p_kind text,
  p_daily_limit integer,
  p_global_limit integer
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today date := (now() at time zone 'utc')::date;
  v_user_text integer := 0;
  v_user_image integer := 0;
  v_global_text integer := 0;
  v_global_image integer := 0;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'Accès serveur uniquement.';
  end if;
  if p_user_id is null
     or p_kind not in ('text','image')
     or p_daily_limit is null or p_daily_limit < 1 or p_daily_limit > 500
     or p_global_limit is null or p_global_limit < 1 or p_global_limit > 100000 then
    raise exception 'Paramètres de quota invalides.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('musea-ai-global:'||v_today::text,0));
  perform pg_advisory_xact_lock(hashtextextended('musea-ai-user:'||p_user_id::text||':'||v_today::text,1));

  select text_requests,image_requests into v_user_text,v_user_image
  from public.ai_usage_daily where user_id=p_user_id and usage_date=v_today;
  select text_requests,image_requests into v_global_text,v_global_image
  from public.ai_usage_global_daily where usage_date=v_today;

  if p_kind='text' then
    if coalesce(v_user_text,0)>=p_daily_limit or coalesce(v_global_text,0)>=p_global_limit then return false; end if;
  else
    if coalesce(v_user_image,0)>=p_daily_limit or coalesce(v_global_image,0)>=p_global_limit then return false; end if;
  end if;

  insert into public.ai_usage_daily(user_id,usage_date,text_requests,image_requests,updated_at)
  values(p_user_id,v_today,case when p_kind='text' then 1 else 0 end,case when p_kind='image' then 1 else 0 end,now())
  on conflict(user_id,usage_date) do update set
    text_requests=public.ai_usage_daily.text_requests+case when p_kind='text' then 1 else 0 end,
    image_requests=public.ai_usage_daily.image_requests+case when p_kind='image' then 1 else 0 end,
    updated_at=now();

  insert into public.ai_usage_global_daily(usage_date,text_requests,image_requests,updated_at)
  values(v_today,case when p_kind='text' then 1 else 0 end,case when p_kind='image' then 1 else 0 end,now())
  on conflict(usage_date) do update set
    text_requests=public.ai_usage_global_daily.text_requests+case when p_kind='text' then 1 else 0 end,
    image_requests=public.ai_usage_global_daily.image_requests+case when p_kind='image' then 1 else 0 end,
    updated_at=now();

  return true;
end;
$$;

revoke all on function public.musea_claim_ai_usage(uuid,text,integer,integer) from public,anon,authenticated;
grant execute on function public.musea_claim_ai_usage(uuid,text,integer,integer) to service_role;

comment on table public.ai_usage_daily is
  'Compteurs quotidiens privés pour limiter les dépenses IA par compte MUSEA.';
comment on table public.ai_usage_global_daily is
  'Plafond global quotidien de consommation IA, indépendant du nombre de comptes.';
