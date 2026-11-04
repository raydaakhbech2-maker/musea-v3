-- MUSEA — verrou anti-double Checkout par compte.
-- Une seule session de paiement peut être préparée à la fois pour un membre.
-- Les verrous expirent après 30 minutes, durée de vie des sessions Checkout créées par MUSEA.

create table if not exists public.billing_checkout_locks (
  user_id uuid primary key references auth.users(id) on delete cascade,
  lock_token uuid not null,
  locked_until timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.billing_checkout_locks enable row level security;
revoke all on public.billing_checkout_locks from anon,authenticated;
grant all on public.billing_checkout_locks to service_role;

create or replace function public.musea_claim_billing_checkout(
  p_user_id uuid,
  p_lock_token uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claimed uuid;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'Accès serveur uniquement.';
  end if;
  if p_user_id is null or p_lock_token is null then
    raise exception 'Compte ou jeton de réservation manquant.';
  end if;

  insert into public.billing_checkout_locks(user_id,lock_token,locked_until,updated_at)
  values(p_user_id,p_lock_token,now()+interval '30 minutes',now())
  on conflict(user_id) do update
    set lock_token=excluded.lock_token,
        locked_until=excluded.locked_until,
        updated_at=now()
    where public.billing_checkout_locks.locked_until <= now()
  returning user_id into v_claimed;

  return v_claimed is not null;
end;
$$;

create or replace function public.musea_release_billing_checkout(
  p_user_id uuid,
  p_lock_token uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'Accès serveur uniquement.';
  end if;
  update public.billing_checkout_locks
  set locked_until=now(),updated_at=now()
  where user_id=p_user_id and lock_token=p_lock_token;
end;
$$;

revoke all on function public.musea_claim_billing_checkout(uuid,uuid) from public,anon,authenticated;
revoke all on function public.musea_release_billing_checkout(uuid,uuid) from public,anon,authenticated;
grant execute on function public.musea_claim_billing_checkout(uuid,uuid) to service_role;
grant execute on function public.musea_release_billing_checkout(uuid,uuid) to service_role;

comment on table public.billing_checkout_locks is
  'Verrou serveur temporaire empêchant la création concurrente de sessions Checkout pour un même compte MUSEA.';
