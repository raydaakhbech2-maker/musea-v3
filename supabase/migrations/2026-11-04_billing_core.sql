-- MUSEA V3 — Encaissement sécurisé (étape 23)
-- À exécuter dans Supabase SQL Editor avant tout test Stripe.
-- Les écritures sont exclusivement réservées aux Edge Functions (clé serveur).

create table if not exists public.billing_customers (
  user_id uuid primary key references auth.users(id) on delete cascade,
  stripe_customer_id text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.billing_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  stripe_subscription_id text not null unique,
  stripe_customer_id text not null,
  price_id text,
  status text not null check (status in (
    'incomplete','incomplete_expired','trialing','active','past_due',
    'canceled','unpaid','paused'
  )),
  current_period_start timestamptz,
  current_period_end timestamptz,
  cancel_at_period_end boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists billing_subscriptions_user_status_idx
  on public.billing_subscriptions(user_id,status,current_period_end desc);

create table if not exists public.billing_invoices (
  stripe_invoice_id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  stripe_subscription_id text,
  status text,
  currency text not null default 'eur' check (char_length(currency)=3),
  amount_due bigint not null default 0,
  amount_paid bigint not null default 0,
  hosted_invoice_url text,
  invoice_pdf text,
  invoice_created_at timestamptz,
  updated_at timestamptz not null default now()
);

create index if not exists billing_invoices_user_created_idx
  on public.billing_invoices(user_id,invoice_created_at desc);

create table if not exists public.billing_webhook_events (
  stripe_event_id text primary key,
  event_type text not null,
  processed_at timestamptz not null default now()
);

alter table public.billing_customers enable row level security;
alter table public.billing_subscriptions enable row level security;
alter table public.billing_invoices enable row level security;
alter table public.billing_webhook_events enable row level security;

revoke all on public.billing_customers from anon, authenticated;
revoke all on public.billing_subscriptions from anon, authenticated;
revoke all on public.billing_invoices from anon, authenticated;
revoke all on public.billing_webhook_events from anon, authenticated;

grant all on public.billing_customers to service_role;
grant all on public.billing_subscriptions to service_role;
grant all on public.billing_invoices to service_role;
grant all on public.billing_webhook_events to service_role;

grant select on public.billing_subscriptions to authenticated;
grant select on public.billing_invoices to authenticated;

drop policy if exists "Users read own billing subscriptions" on public.billing_subscriptions;
create policy "Users read own billing subscriptions"
  on public.billing_subscriptions for select to authenticated
  using (user_id = auth.uid());

drop policy if exists "Users read own billing invoices" on public.billing_invoices;
create policy "Users read own billing invoices"
  on public.billing_invoices for select to authenticated
  using (user_id = auth.uid());

create or replace function public.musea_has_signature_access()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.billing_subscriptions s
    where s.user_id = auth.uid()
      and s.status in ('active','trialing')
      and (s.current_period_end is null or s.current_period_end > now())
  );
$$;

revoke all on function public.musea_has_signature_access() from public, anon;
grant execute on function public.musea_has_signature_access() to authenticated;

comment on table public.billing_customers is
  'Correspondance privée entre un compte MUSEA et son identifiant client Stripe. Écriture serveur uniquement.';
comment on table public.billing_subscriptions is
  'État des abonnements synchronisé par webhook Stripe signé. Jamais modifiable depuis le navigateur.';
comment on table public.billing_invoices is
  'Historique des factures et reçus synchronisé côté serveur. Lecture limitée au propriétaire.';
comment on table public.billing_webhook_events is
  'Journal anti-doublon des événements Stripe traités.';
