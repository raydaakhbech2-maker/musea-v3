-- MUSEA V3 — notifications persistantes et préférences
-- Étape 6 : notifications sociales et nouveaux messages.

create table if not exists public.notification_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  likes boolean not null default true,
  comments boolean not null default true,
  reposts boolean not null default true,
  messages boolean not null default true,
  updated_at timestamptz not null default now()
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references auth.users(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  actor_username text,
  type text not null check (type in ('like','comment','repost','message')),
  target_type text not null check (target_type in ('post','conversation')),
  target_id uuid not null,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  constraint notifications_not_self check (actor_id is null or actor_id <> recipient_id)
);

create index if not exists notifications_recipient_created_idx
  on public.notifications(recipient_id, created_at desc);
create index if not exists notifications_unread_idx
  on public.notifications(recipient_id, created_at desc)
  where read_at is null;

alter table public.notification_preferences enable row level security;
alter table public.notifications enable row level security;

drop policy if exists "Users read their notification preferences" on public.notification_preferences;
create policy "Users read their notification preferences"
on public.notification_preferences for select to authenticated
using (auth.uid() = user_id);

drop policy if exists "Users create their notification preferences" on public.notification_preferences;
create policy "Users create their notification preferences"
on public.notification_preferences for insert to authenticated
with check (auth.uid() = user_id);

drop policy if exists "Users update their notification preferences" on public.notification_preferences;
create policy "Users update their notification preferences"
on public.notification_preferences for update to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Users read their own notifications" on public.notifications;
create policy "Users read their own notifications"
on public.notifications for select to authenticated
using (auth.uid() = recipient_id);

drop policy if exists "Users mark their own notifications as read" on public.notifications;
create policy "Users mark their own notifications as read"
on public.notifications for update to authenticated
using (auth.uid() = recipient_id)
with check (auth.uid() = recipient_id);

grant select, insert, update on public.notification_preferences to authenticated;
grant select, delete on public.notifications to authenticated;
grant update (read_at) on public.notifications to authenticated;
revoke insert, update, delete on public.notifications from anon, authenticated;
grant select on public.notifications to authenticated;

create or replace function public.musea_notification_is_enabled(
  p_user_id uuid,
  p_category text
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (
      select case p_category
        when 'likes' then np.likes
        when 'comments' then np.comments
        when 'reposts' then np.reposts
        when 'messages' then np.messages
        else false
      end
      from public.notification_preferences np
      where np.user_id = p_user_id
    ),
    true
  );
$$;

create or replace function public.musea_create_social_notification()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_recipient uuid;
  v_actor_username text;
  v_type text;
  v_category text;
begin
  if tg_table_name = 'post_likes' then
    v_type := 'like';
    v_category := 'likes';
  elsif tg_table_name = 'post_comments' then
    v_type := 'comment';
    v_category := 'comments';
  elsif tg_table_name = 'post_reposts' then
    v_type := 'repost';
    v_category := 'reposts';
  else
    return new;
  end if;

  select p.user_id into v_recipient
  from public.posts p
  where p.id = new.post_id;

  if v_recipient is null or v_recipient = new.user_id then
    return new;
  end if;

  if not public.musea_notification_is_enabled(v_recipient, v_category) then
    return new;
  end if;

  select pr.username into v_actor_username
  from public.profiles pr
  where pr.id = new.user_id;

  insert into public.notifications(
    recipient_id, actor_id, actor_username, type, target_type, target_id
  ) values (
    v_recipient, new.user_id, v_actor_username, v_type, 'post', new.post_id
  );

  return new;
end;
$$;

drop trigger if exists musea_notify_post_like on public.post_likes;
create trigger musea_notify_post_like
after insert on public.post_likes
for each row execute function public.musea_create_social_notification();

drop trigger if exists musea_notify_post_comment on public.post_comments;
create trigger musea_notify_post_comment
after insert on public.post_comments
for each row execute function public.musea_create_social_notification();

drop trigger if exists musea_notify_post_repost on public.post_reposts;
create trigger musea_notify_post_repost
after insert on public.post_reposts
for each row execute function public.musea_create_social_notification();

create or replace function public.musea_create_message_notification()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_recipient uuid;
  v_actor_username text;
begin
  select case
    when c.user_one = new.sender_id then c.user_two
    else c.user_one
  end
  into v_recipient
  from public.direct_conversations c
  where c.id = new.conversation_id
    and (c.user_one = new.sender_id or c.user_two = new.sender_id);

  if v_recipient is null or v_recipient = new.sender_id then
    return new;
  end if;

  if not public.musea_notification_is_enabled(v_recipient, 'messages') then
    return new;
  end if;

  select pr.username into v_actor_username
  from public.profiles pr
  where pr.id = new.sender_id;

  insert into public.notifications(
    recipient_id, actor_id, actor_username, type, target_type, target_id
  ) values (
    v_recipient, new.sender_id, v_actor_username, 'message', 'conversation', new.conversation_id
  );

  return new;
end;
$$;

drop trigger if exists musea_notify_direct_message on public.direct_messages;
create trigger musea_notify_direct_message
after insert on public.direct_messages
for each row execute function public.musea_create_message_notification();

revoke all on function public.musea_notification_is_enabled(uuid, text) from public, anon, authenticated;
revoke all on function public.musea_create_social_notification() from public, anon, authenticated;
revoke all on function public.musea_create_message_notification() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'notifications'
    ) then
      alter publication supabase_realtime add table public.notifications;
    end if;
  end if;
end $$;
