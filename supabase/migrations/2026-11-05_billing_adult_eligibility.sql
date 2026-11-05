-- Checkout is fail-closed until an adult account holder has approved the account.
create table if not exists public.billing_checkout_eligibility (
  user_id uuid primary key references auth.users(id) on delete cascade,
  adult_verified boolean not null default false,
  verified_at timestamptz,
  verified_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint billing_checkout_eligibility_consistent check (
    (adult_verified = false and verified_at is null)
    or (adult_verified = true and verified_at is not null)
  )
);
alter table public.billing_checkout_eligibility enable row level security;
revoke all on public.billing_checkout_eligibility from public, anon, authenticated;
grant all on public.billing_checkout_eligibility to service_role;
comment on table public.billing_checkout_eligibility is
  'Server-managed eligibility gate. Checkout is refused unless an authorized adult account holder has verified eligibility.';
