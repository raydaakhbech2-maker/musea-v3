-- MUSEA V3 — Notifications persistantes
-- À exécuter une seule fois dans Supabase > SQL Editor.

create table if not exists public.notification_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  likes boolean not null default true,
  comments boolean not null default true,
  replies boolean not null default true,
  reposts boolean not null default true,
  new_followers boolean not null default true,
  mentions boolean not null default true,
  messages boolean not null default true,
  recommendations boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table public.notification_preferences enable row level security;
revoke all on public.notification_preferences from anon, authenticated;
grant select, insert, update on public.notification_preferences to authenticated;

drop policy if exists "Users read their notification preferences" on public.notification_preferences;
create policy "Users read their notification preferences"
on public.notification_preferences for select to authenticated
using (user_id = auth.uid());

drop policy if exists "Users create their notification preferences" on public.notification_preferences;
create policy "Users create their notification preferences"
on public.notification_preferences for insert to authenticated
with check (user_id = auth.uid());

drop policy if exists "Users update their notification preferences" on public.notification_preferences;
create policy "Users update their notification preferences"
on public.notification_preferences for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references auth.users(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  type text not null check (type in ('like','comment','reply','repost')),
  post_id uuid references public.posts(id) on delete cascade,
  comment_id uuid references public.post_comments(id) on delete cascade,
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create index if not exists notifications_recipient_created_idx
on public.notifications(recipient_id, created_at desc);

create index if not exists notifications_unread_idx
on public.notifications(recipient_id, created_at desc)
where read_at is null;

alter table public.notifications enable row level security;
revoke all on public.notifications from anon, authenticated;
grant select, delete on public.notifications to authenticated;
grant update(read_at) on public.notifications to authenticated;

drop policy if exists "Users read their notifications" on public.notifications;
create policy "Users read their notifications"
on public.notifications for select to authenticated
using (recipient_id = auth.uid());

drop policy if exists "Users mark their notifications read" on public.notifications;
create policy "Users mark their notifications read"
on public.notifications for update to authenticated
using (recipient_id = auth.uid())
with check (recipient_id = auth.uid());

drop policy if exists "Users delete their notifications" on public.notifications;
create policy "Users delete their notifications"
on public.notifications for delete to authenticated
using (recipient_id = auth.uid());

-- Les insertions sont faites uniquement par les triggers sécurisés ci-dessous.
create or replace function public.musea_notify_like()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_recipient uuid;
  v_enabled boolean;
begin
  select p.user_id into v_recipient
  from public.posts p where p.id = new.post_id;

  if v_recipient is null or v_recipient = new.user_id then
    return new;
  end if;

  select np.likes into v_enabled
  from public.notification_preferences np
  where np.user_id = v_recipient;

  if coalesce(v_enabled, true) then
    insert into public.notifications(recipient_id, actor_id, type, post_id)
    values (v_recipient, new.user_id, 'like', new.post_id);
  end if;
  return new;
end;
$$;

create or replace function public.musea_notify_comment()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_post_owner uuid;
  v_parent_author uuid;
  v_enabled boolean;
begin
  select p.user_id into v_post_owner
  from public.posts p where p.id = new.post_id;

  if new.parent_comment_id is not null then
    select c.user_id into v_parent_author
    from public.post_comments c where c.id = new.parent_comment_id;

    if v_parent_author is not null and v_parent_author <> new.user_id then
      select np.replies into v_enabled
      from public.notification_preferences np where np.user_id = v_parent_author;

      if coalesce(v_enabled, true) then
        insert into public.notifications(recipient_id, actor_id, type, post_id, comment_id)
        values (v_parent_author, new.user_id, 'reply', new.post_id, new.id);
      end if;
    end if;
  end if;

  if v_post_owner is not null
     and v_post_owner <> new.user_id
     and v_post_owner is distinct from v_parent_author then
    select np.comments into v_enabled
    from public.notification_preferences np where np.user_id = v_post_owner;

    if coalesce(v_enabled, true) then
      insert into public.notifications(recipient_id, actor_id, type, post_id, comment_id)
      values (v_post_owner, new.user_id, 'comment', new.post_id, new.id);
    end if;
  end if;

  return new;
end;
$$;

create or replace function public.musea_notify_repost()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_recipient uuid;
  v_enabled boolean;
begin
  select p.user_id into v_recipient
  from public.posts p where p.id = new.post_id;

  if v_recipient is null or v_recipient = new.user_id then
    return new;
  end if;

  select np.reposts into v_enabled
  from public.notification_preferences np where np.user_id = v_recipient;

  if coalesce(v_enabled, true) then
    insert into public.notifications(recipient_id, actor_id, type, post_id)
    values (v_recipient, new.user_id, 'repost', new.post_id);
  end if;
  return new;
end;
$$;

drop trigger if exists musea_post_like_notification on public.post_likes;
create trigger musea_post_like_notification
after insert on public.post_likes
for each row execute function public.musea_notify_like();

drop trigger if exists musea_post_comment_notification on public.post_comments;
create trigger musea_post_comment_notification
after insert on public.post_comments
for each row execute function public.musea_notify_comment();

drop trigger if exists musea_post_repost_notification on public.post_reposts;
create trigger musea_post_repost_notification
after insert on public.post_reposts
for each row execute function public.musea_notify_repost();

revoke all on function public.musea_notify_like() from public, anon, authenticated;
revoke all on function public.musea_notify_comment() from public, anon, authenticated;
revoke all on function public.musea_notify_repost() from public, anon, authenticated;

-- Active les événements temps réel de la table des notifications, sans échec si déjà publiée.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'notifications'
     ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
end;
$$;
