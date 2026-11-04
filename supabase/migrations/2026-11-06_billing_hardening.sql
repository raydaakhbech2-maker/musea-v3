-- MUSEA — durcissement du traitement des événements Stripe.
-- Les anciens événements déjà inscrits sont considérés comme traités.
-- Les nouveaux événements sont réservés atomiquement, puis marqués traités ou échoués.

alter table public.billing_webhook_events
  add column if not exists processing_status text not null default 'processed'
    check (processing_status in ('processing','processed','failed')),
  add column if not exists attempts integer not null default 1 check (attempts >= 1),
  add column if not exists last_error text,
  add column if not exists updated_at timestamptz not null default now();

create or replace function public.musea_claim_billing_event(
  p_stripe_event_id text,
  p_event_type text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claimed text;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'Accès serveur uniquement.';
  end if;
  if p_stripe_event_id is null or char_length(p_stripe_event_id) not between 1 and 255
     or p_event_type is null or char_length(p_event_type) not between 1 and 255 then
    raise exception 'Identifiant ou type d’événement invalide.';
  end if;

  insert into public.billing_webhook_events(
    stripe_event_id,event_type,processing_status,attempts,updated_at
  ) values (p_stripe_event_id,p_event_type,'processing',1,now())
  on conflict (stripe_event_id) do update
    set event_type=excluded.event_type,
        processing_status='processing',
        attempts=public.billing_webhook_events.attempts+1,
        last_error=null,
        updated_at=now()
    where public.billing_webhook_events.processing_status='failed'
       or (
         public.billing_webhook_events.processing_status='processing'
         and public.billing_webhook_events.updated_at < now()-interval '15 minutes'
       )
  returning stripe_event_id into v_claimed;

  return v_claimed is not null;
end;
$$;

create or replace function public.musea_complete_billing_event(
  p_stripe_event_id text,
  p_error text default null
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
  update public.billing_webhook_events
  set processing_status=case when p_error is null then 'processed' else 'failed' end,
      processed_at=case when p_error is null then now() else processed_at end,
      last_error=case when p_error is null then null else left(p_error,1000) end,
      updated_at=now()
  where stripe_event_id=p_stripe_event_id
    and processing_status='processing';

  if not found then
    raise exception 'Événement non réservé ou déjà clôturé.';
  end if;
end;
$$;

revoke all on function public.musea_claim_billing_event(text,text) from public,anon,authenticated;
revoke all on function public.musea_complete_billing_event(text,text) from public,anon,authenticated;
grant execute on function public.musea_claim_billing_event(text,text) to service_role;
grant execute on function public.musea_complete_billing_event(text,text) to service_role;

comment on column public.billing_webhook_events.processing_status is
  'État du verrou idempotent : processing, processed ou failed. Réservation et clôture uniquement côté serveur.';
