-- MUSEA V3 — Les Regards : retours créatifs guidés, sans classement populaire.

create table if not exists public.creative_feedback_requests (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null unique references public.posts(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  question_kind text not null check (question_kind in ('impression','intention','exploration')),
  question text not null check (char_length(trim(question)) between 12 and 180),
  status text not null default 'open' check (status in ('open','closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists creative_feedback_requests_status_created_idx on public.creative_feedback_requests(status,created_at desc);

create table if not exists public.creative_feedback_responses (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.creative_feedback_requests(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade,
  perspective text not null check (perspective in ('emotion','clarity','possibility')),
  content text not null check (char_length(trim(content)) between 20 and 500),
  created_at timestamptz not null default now(),
  constraint creative_feedback_one_response_per_member unique(request_id,author_id)
);
create index if not exists creative_feedback_responses_request_created_idx on public.creative_feedback_responses(request_id,created_at asc);

alter table public.creative_feedback_requests enable row level security;
alter table public.creative_feedback_responses enable row level security;
revoke all on public.creative_feedback_requests,public.creative_feedback_responses from public,anon,authenticated;
grant select,insert,update,delete on public.creative_feedback_requests to authenticated;
grant select,insert,delete on public.creative_feedback_responses to authenticated;

drop policy if exists "Members read visible creative feedback requests" on public.creative_feedback_requests;
create policy "Members read visible creative feedback requests"
on public.creative_feedback_requests for select to authenticated
using (
  owner_id=(select auth.uid())
  or (
    status='open'
    and exists(select 1 from public.posts p where p.id=post_id and p.user_id=owner_id and p.visibility='public')
    and public.musea_story_is_visible(owner_id)
  )
);

drop policy if exists "Creators request feedback on their public posts" on public.creative_feedback_requests;
create policy "Creators request feedback on their public posts"
on public.creative_feedback_requests for insert to authenticated
with check (
  owner_id=(select auth.uid())
  and exists(select 1 from public.posts p where p.id=post_id and p.user_id=(select auth.uid()) and p.visibility='public')
);

drop policy if exists "Creators manage their feedback request" on public.creative_feedback_requests;
create policy "Creators manage their feedback request"
on public.creative_feedback_requests for update to authenticated
using(owner_id=(select auth.uid()))
with check (
  owner_id=(select auth.uid())
  and status in ('open','closed')
  and exists(
    select 1 from public.posts p
    where p.id=post_id and p.user_id=(select auth.uid())
      and (status='closed' or p.visibility='public')
  )
);

drop policy if exists "Creators delete their feedback request" on public.creative_feedback_requests;
create policy "Creators delete their feedback request"
on public.creative_feedback_requests for delete to authenticated
using(owner_id=(select auth.uid()));

drop policy if exists "Members read allowed creative feedback" on public.creative_feedback_responses;
create policy "Members read allowed creative feedback"
on public.creative_feedback_responses for select to authenticated
using (
  exists(
    select 1 from public.creative_feedback_requests r
    join public.posts p on p.id=r.post_id
    where r.id=request_id
      and (
        r.owner_id=(select auth.uid())
        or (r.status='open' and p.visibility='public' and public.musea_story_is_visible(r.owner_id))
      )
      and public.musea_story_is_visible(author_id)
  )
);

drop policy if exists "Members add one constructive creative response" on public.creative_feedback_responses;
create policy "Members add one constructive creative response"
on public.creative_feedback_responses for insert to authenticated
with check (
  author_id=(select auth.uid())
  and exists(
    select 1 from public.creative_feedback_requests r
    join public.posts p on p.id=r.post_id
    where r.id=request_id
      and r.status='open'
      and r.owner_id<>(select auth.uid())
      and p.visibility='public'
      and public.musea_story_is_visible(r.owner_id)
  )
);

drop policy if exists "Members delete their own creative response" on public.creative_feedback_responses;
create policy "Members delete their own creative response"
on public.creative_feedback_responses for delete to authenticated
using(author_id=(select auth.uid()));

create or replace function public.musea_touch_feedback_request_updated_at()
returns trigger language plpgsql set search_path='' as $$
begin new.updated_at=now();return new;end;
$$;
drop trigger if exists musea_touch_feedback_request_updated_at on public.creative_feedback_requests;
create trigger musea_touch_feedback_request_updated_at before update on public.creative_feedback_requests
for each row execute function public.musea_touch_feedback_request_updated_at();
revoke all on function public.musea_touch_feedback_request_updated_at() from public,anon,authenticated;
