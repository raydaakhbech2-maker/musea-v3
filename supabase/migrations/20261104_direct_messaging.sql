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

alter table public.profiles
  add column if not exists allow_messages boolean not null default true;

create table if not exists public.direct_message_blocks (
  blocker_id uuid not null references auth.users(id) on delete cascade,
  blocked_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint direct_message_blocks_distinct_users check (blocker_id <> blocked_id)
);

alter table public.direct_message_blocks enable row level security;

drop policy if exists "Users can read blocks involving them" on public.direct_message_blocks;
create policy "Users can read blocks involving them"
on public.direct_message_blocks for select to authenticated
using (auth.uid() = blocker_id or auth.uid() = blocked_id);

drop policy if exists "Users can block others" on public.direct_message_blocks;
create policy "Users can block others"
on public.direct_message_blocks for insert to authenticated
with check (auth.uid() = blocker_id);

drop policy if exists "Users can unblock others" on public.direct_message_blocks;
create policy "Users can unblock others"
on public.direct_message_blocks for delete to authenticated
using (auth.uid() = blocker_id);

revoke insert on public.direct_message_blocks from authenticated;
grant select, delete on public.direct_message_blocks to authenticated;
grant insert (blocker_id, blocked_id) on public.direct_message_blocks to authenticated;
grant update (allow_messages) on public.profiles to authenticated;

drop policy if exists "Users can update their own messaging preference" on public.profiles;
create policy "Users can update their own messaging preference"
on public.profiles for update to authenticated
using (auth.uid() = id)
with check (auth.uid() = id);

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
  and exists (
    select 1 from public.profiles p
    where p.id = case when auth.uid() = user_one then user_two else user_one end
      and p.allow_messages = true
  )
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
  and read_at is null
  and exists (
    select 1 from public.direct_conversations c
    where c.id = conversation_id
      and (auth.uid() = c.user_one or auth.uid() = c.user_two)
      and exists (
        select 1 from public.profiles p
        where p.id = case when auth.uid() = c.user_one then c.user_two else c.user_one end
          and p.allow_messages = true
      )
      and not exists (
        select 1 from public.direct_message_blocks b
        where (b.blocker_id = auth.uid() and b.blocked_id =
          case when auth.uid() = c.user_one then c.user_two else c.user_one end)
           or (b.blocked_id = auth.uid() and b.blocker_id =
          case when auth.uid() = c.user_one then c.user_two else c.user_one end)
      )
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

revoke insert on public.direct_conversations from authenticated;
grant select on public.direct_conversations to authenticated;
grant insert (user_one, user_two) on public.direct_conversations to authenticated;
revoke insert on public.direct_messages from authenticated;
grant select on public.direct_messages to authenticated;
grant insert (conversation_id, sender_id, content) on public.direct_messages to authenticated;
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
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'direct_message_blocks'
    ) then
      alter publication supabase_realtime add table public.direct_message_blocks;
    end if;
  end if;
end $$;
