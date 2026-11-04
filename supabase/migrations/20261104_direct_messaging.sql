-- MUSEA V3 — messagerie privée 1-à-1
-- À exécuter une seule fois dans Supabase > SQL Editor.

create table if not exists public.direct_conversations (
  id uuid primary key default gen_random_uuid(),
  user_one uuid not null references auth.users(id) on delete cascade,
  user_two uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint direct_conversations_distinct_users check (user_one <> user_two),
  constraint direct_conversations_canonical_pair check (user_one < user_two),
  constraint direct_conversations_unique_pair unique (user_one, user_two)
);

create index if not exists direct_conversations_user_one_updated_idx
  on public.direct_conversations(user_one, updated_at desc);
create index if not exists direct_conversations_user_two_updated_idx
  on public.direct_conversations(user_two, updated_at desc);

create table if not exists public.direct_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.direct_conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  content text not null check (char_length(trim(content)) between 1 and 4000),
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create index if not exists direct_messages_conversation_created_idx
  on public.direct_messages(conversation_id, created_at asc);
create index if not exists direct_messages_unread_idx
  on public.direct_messages(conversation_id, read_at)
  where read_at is null;

create or replace function public.musea_touch_conversation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.direct_conversations
     set updated_at = new.created_at
   where id = new.conversation_id;
  return new;
end;
$$;

drop trigger if exists musea_touch_conversation_after_message on public.direct_messages;
create trigger musea_touch_conversation_after_message
after insert on public.direct_messages
for each row execute function public.musea_touch_conversation();

alter table public.direct_conversations enable row level security;
alter table public.direct_messages enable row level security;

drop policy if exists "Participants can read their conversations" on public.direct_conversations;
create policy "Participants can read their conversations"
on public.direct_conversations for select to authenticated
using (auth.uid() = user_one or auth.uid() = user_two);

drop policy if exists "Users can create their own conversations" on public.direct_conversations;
create policy "Users can create their own conversations"
on public.direct_conversations for insert to authenticated
with check (
  user_one < user_two
  and (auth.uid() = user_one or auth.uid() = user_two)
);

drop policy if exists "Participants can read messages" on public.direct_messages;
create policy "Participants can read messages"
on public.direct_messages for select to authenticated
using (
  exists (
    select 1 from public.direct_conversations c
    where c.id = conversation_id
      and (auth.uid() = c.user_one or auth.uid() = c.user_two)
  )
);

drop policy if exists "Participants can send as themselves" on public.direct_messages;
create policy "Participants can send as themselves"
on public.direct_messages for insert to authenticated
with check (
  auth.uid() = sender_id
  and exists (
    select 1 from public.direct_conversations c
    where c.id = conversation_id
      and (auth.uid() = c.user_one or auth.uid() = c.user_two)
  )
);

drop policy if exists "Recipients can mark messages as read" on public.direct_messages;
create policy "Recipients can mark messages as read"
on public.direct_messages for update to authenticated
using (
  sender_id <> auth.uid()
  and exists (
    select 1 from public.direct_conversations c
    where c.id = conversation_id
      and (auth.uid() = c.user_one or auth.uid() = c.user_two)
  )
)
with check (
  sender_id <> auth.uid()
  and read_at is not null
  and exists (
    select 1 from public.direct_conversations c
    where c.id = conversation_id
      and (auth.uid() = c.user_one or auth.uid() = c.user_two)
  )
);

grant select, insert on public.direct_conversations to authenticated;
grant select, insert on public.direct_messages to authenticated;
grant update (read_at) on public.direct_messages to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'direct_messages'
    ) then
      alter publication supabase_realtime add table public.direct_messages;
    end if;
  end if;
end $$;
