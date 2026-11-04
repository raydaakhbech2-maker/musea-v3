-- MUSEA V3 — Messagerie privée et ateliers collaboratifs
-- À exécuter une seule fois dans Supabase > SQL Editor.

alter table public.profiles
  add column if not exists allow_messages_from_non_followers boolean not null default false,
  add column if not exists allow_project_invites boolean not null default true;

create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('dm','project')),
  title text,
  project_description text not null default '',
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((kind = 'dm' and title is null) or (kind = 'project' and char_length(trim(title)) between 2 and 70)),
  check (char_length(project_description) <= 500)
);

create table if not exists public.conversation_members (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner','member')),
  status text not null default 'invited' check (status in ('invited','accepted','declined')),
  invited_by uuid references auth.users(id) on delete set null,
  joined_at timestamptz,
  last_read_at timestamptz,
  primary key (conversation_id,user_id)
);

create index if not exists conversation_members_user_status_idx
  on public.conversation_members(user_id,status,conversation_id);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  body text not null default '',
  shared_post_id uuid references public.posts(id) on delete set null,
  created_at timestamptz not null default now(),
  check (char_length(body) <= 4000),
  check (char_length(trim(body)) > 0 or shared_post_id is not null)
);

create index if not exists messages_conversation_created_idx
  on public.messages(conversation_id,created_at desc);

create table if not exists public.conversation_tasks (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  title text not null check (char_length(trim(title)) between 2 and 100),
  details text not null default '' check (char_length(details) <= 400),
  status text not null default 'todo' check (status in ('todo','doing','done')),
  assigned_to uuid references auth.users(id) on delete set null,
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists conversation_tasks_board_idx
  on public.conversation_tasks(conversation_id,status,created_at);

alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages enable row level security;
alter table public.conversation_tasks enable row level security;

revoke all on public.conversations,public.conversation_members,public.messages,public.conversation_tasks from anon,authenticated;
grant select on public.conversations,public.conversation_members,public.messages,public.conversation_tasks to authenticated;
grant insert on public.messages to authenticated;
grant update(last_read_at) on public.conversation_members to authenticated;
grant insert,update on public.conversation_tasks to authenticated;

drop policy if exists "Members can read their conversations" on public.conversations;
create policy "Members can read their conversations"
on public.conversations for select to authenticated
using (exists (
  select 1 from public.conversation_members cm
  where cm.conversation_id=conversations.id
    and cm.user_id=auth.uid()
    and cm.status in ('invited','accepted')
));

drop policy if exists "Members can read conversation membership" on public.conversation_members;
create policy "Members can read conversation membership"
on public.conversation_members for select to authenticated
using (exists (
  select 1 from public.conversation_members own
  where own.conversation_id=conversation_members.conversation_id
    and own.user_id=auth.uid()
    and own.status in ('invited','accepted')
));

drop policy if exists "Users update their own conversation read marker" on public.conversation_members;
create policy "Users update their own conversation read marker"
on public.conversation_members for update to authenticated
using (user_id=auth.uid() and status='accepted')
with check (user_id=auth.uid() and status='accepted');

drop policy if exists "Accepted members read conversation messages" on public.messages;
create policy "Accepted members read conversation messages"
on public.messages for select to authenticated
using (
  sender_id=auth.uid()
  or exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id=messages.conversation_id
      and cm.user_id=auth.uid()
      and cm.status='accepted'
  )
);

drop policy if exists "Accepted members send messages" on public.messages;
create policy "Accepted members send messages"
on public.messages for insert to authenticated
with check (
  sender_id=auth.uid()
  and exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id=messages.conversation_id
      and cm.user_id=auth.uid()
      and cm.status='accepted'
  )
  and (
    shared_post_id is null
    or exists (
      select 1 from public.posts p
      where p.id=messages.shared_post_id and p.visibility='public'
    )
  )
);

drop policy if exists "Accepted project members read tasks" on public.conversation_tasks;
create policy "Accepted project members read tasks"
on public.conversation_tasks for select to authenticated
using (
  exists (
    select 1 from public.conversations c
    join public.conversation_members cm on cm.conversation_id=c.id
    where c.id=conversation_tasks.conversation_id
      and c.kind='project'
      and cm.user_id=auth.uid()
      and cm.status='accepted'
  )
);

drop policy if exists "Accepted project members create tasks" on public.conversation_tasks;
create policy "Accepted project members create tasks"
on public.conversation_tasks for insert to authenticated
with check (
  created_by=auth.uid()
  and exists (
    select 1 from public.conversations c
    join public.conversation_members cm on cm.conversation_id=c.id
    where c.id=conversation_tasks.conversation_id
      and c.kind='project'
      and cm.user_id=auth.uid()
      and cm.status='accepted'
  )
  and (
    assigned_to is null
    or exists (
      select 1 from public.conversation_members assigned
      where assigned.conversation_id=conversation_tasks.conversation_id
        and assigned.user_id=conversation_tasks.assigned_to
        and assigned.status='accepted'
    )
  )
);

drop policy if exists "Accepted project members update tasks" on public.conversation_tasks;
create policy "Accepted project members update tasks"
on public.conversation_tasks for update to authenticated
using (
  exists (
    select 1 from public.conversations c
    join public.conversation_members cm on cm.conversation_id=c.id
    where c.id=conversation_tasks.conversation_id
      and c.kind='project'
      and cm.user_id=auth.uid()
      and cm.status='accepted'
  )
)
with check (
  exists (
    select 1 from public.conversations c
    join public.conversation_members cm on cm.conversation_id=c.id
    where c.id=conversation_tasks.conversation_id
      and c.kind='project'
      and cm.user_id=auth.uid()
      and cm.status='accepted'
  )
  and (
    assigned_to is null
    or exists (
      select 1 from public.conversation_members assigned
      where assigned.conversation_id=conversation_tasks.conversation_id
        and assigned.user_id=conversation_tasks.assigned_to
        and assigned.status='accepted'
    )
  )
);

create or replace function public.musea_create_conversation(
  p_kind text,
  p_title text,
  p_description text,
  p_participant_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path=public,auth,pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_id uuid;
  v_target uuid;
  v_count integer;
  v_profile record;
begin
  if v_user is null then raise exception 'Connexion nécessaire.'; end if;
  if p_kind not in ('dm','project') then raise exception 'Type de conversation invalide.'; end if;
  if p_participant_ids is null then raise exception 'Choisis au moins un participant.'; end if;
  select count(distinct x) into v_count from unnest(p_participant_ids) x where x is not null and x<>v_user;
  if v_count<1 or v_count>8 then raise exception 'Choisis entre 1 et 8 autres participants.'; end if;
  if p_kind='dm' and v_count<>1 then raise exception 'Une conversation privée nécessite exactement un destinataire.'; end if;
  if p_kind='project' and (char_length(trim(coalesce(p_title,'')))<2 or char_length(p_title)>70) then
    raise exception 'Le projet doit avoir un titre de 2 à 70 caractères.';
  end if;
  if char_length(coalesce(p_description,''))>500 then raise exception 'La description est trop longue.'; end if;

  for v_target in select distinct x from unnest(p_participant_ids) x where x is not null and x<>v_user loop
    select allow_messages_from_non_followers,allow_project_invites
      into v_profile from public.profiles where id=v_target;
    if not found then raise exception 'Un profil sélectionné est introuvable.'; end if;
    if p_kind='dm' and not coalesce(v_profile.allow_messages_from_non_followers,false) then
      raise exception 'Cette personne n’accepte pas les demandes de message pour le moment.';
    end if;
    if p_kind='project' and not coalesce(v_profile.allow_project_invites,true) then
      raise exception 'Un des créateurs sélectionnés n’accepte pas les invitations de projet.';
    end if;
  end loop;

  insert into public.conversations(kind,title,project_description,created_by)
  values(p_kind,case when p_kind='project' then trim(p_title) else null end,coalesce(p_description,''),v_user)
  returning id into v_id;

  insert into public.conversation_members(conversation_id,user_id,role,status,invited_by,joined_at)
  values(v_id,v_user,'owner','accepted',v_user,now());

  insert into public.conversation_members(conversation_id,user_id,role,status,invited_by)
  select v_id,x,'member','invited',v_user
  from (select distinct unnest(p_participant_ids) as x) ids
  where x is not null and x<>v_user;

  return v_id;
end;
$$;

create or replace function public.musea_respond_conversation_invite(
  p_conversation_id uuid,
  p_accept boolean
)
returns void
language plpgsql
security definer
set search_path=public,auth,pg_temp
as $$
begin
  if auth.uid() is null then raise exception 'Connexion nécessaire.'; end if;
  update public.conversation_members
  set status=case when p_accept then 'accepted' else 'declined' end,
      joined_at=case when p_accept then now() else null end
  where conversation_id=p_conversation_id
    and user_id=auth.uid()
    and status='invited';
  if not found then raise exception 'Cette invitation n’est plus disponible.'; end if;
end;
$$;

revoke all on function public.musea_create_conversation(text,text,text,uuid[]) from public,anon;
revoke all on function public.musea_respond_conversation_invite(uuid,boolean) from public,anon;
grant execute on function public.musea_create_conversation(text,text,text,uuid[]) to authenticated;
grant execute on function public.musea_respond_conversation_invite(uuid,boolean) to authenticated;

create or replace function public.musea_touch_conversation()
returns trigger language plpgsql set search_path=public,pg_temp as $$
begin
  update public.conversations set updated_at=now() where id=new.conversation_id;
  return new;
end;
$$;
drop trigger if exists musea_touch_conversation_after_message on public.messages;
create trigger musea_touch_conversation_after_message
after insert on public.messages for each row execute function public.musea_touch_conversation();

create or replace function public.musea_touch_conversation_task()
returns trigger language plpgsql set search_path=public,pg_temp as $$
begin
  new.updated_at=now();
  return new;
end;
$$;
drop trigger if exists musea_touch_conversation_task_before_update on public.conversation_tasks;
create trigger musea_touch_conversation_task_before_update
before update on public.conversation_tasks for each row execute function public.musea_touch_conversation_task();

-- Messages et invitations rejoignent le centre de notifications existant.
alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications add constraint notifications_type_check
  check (type in ('like','comment','reply','repost','message','message_request','project_invite'));

create or replace function public.musea_notify_conversation_invite()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare v_kind text; v_enabled boolean;
begin
  if new.status<>'invited' then return new; end if;
  select kind into v_kind from public.conversations where id=new.conversation_id;
  select messages into v_enabled from public.notification_preferences where user_id=new.user_id;
  if coalesce(v_enabled,true) then
    insert into public.notifications(recipient_id,actor_id,type)
    values(new.user_id,new.invited_by,case when v_kind='project' then 'project_invite' else 'message_request' end);
  end if;
  return new;
end;
$$;
drop trigger if exists musea_conversation_invite_notification on public.conversation_members;
create trigger musea_conversation_invite_notification
after insert on public.conversation_members
for each row execute function public.musea_notify_conversation_invite();

create or replace function public.musea_notify_conversation_message()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare v_member record; v_enabled boolean;
begin
  select messages into v_enabled from public.notification_preferences where user_id in (
    select user_id from public.conversation_members
    where conversation_id=new.conversation_id and user_id<>new.sender_id and status='accepted'
  ) limit 1;
  for v_member in
    select user_id from public.conversation_members
    where conversation_id=new.conversation_id and user_id<>new.sender_id and status='accepted'
  loop
    select messages into v_enabled from public.notification_preferences where user_id=v_member.user_id;
    if coalesce(v_enabled,true) then
      insert into public.notifications(recipient_id,actor_id,type)
      values(v_member.user_id,new.sender_id,'message');
    end if;
  end loop;
  return new;
end;
$$;
drop trigger if exists musea_message_notification on public.messages;
create trigger musea_message_notification
after insert on public.messages
for each row execute function public.musea_notify_conversation_message();

revoke all on function public.musea_notify_conversation_invite() from public,anon,authenticated;
revoke all on function public.musea_notify_conversation_message() from public,anon,authenticated;
revoke all on function public.musea_touch_conversation() from public,anon,authenticated;
revoke all on function public.musea_touch_conversation_task() from public,anon,authenticated;

-- Ajout Realtime idempotent : aucune table du schéma realtime n'est créée ou modifiée.
do $$
begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime') then
    if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='messages') then
      alter publication supabase_realtime add table public.messages;
    end if;
    if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='conversation_members') then
      alter publication supabase_realtime add table public.conversation_members;
    end if;
    if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='conversation_tasks') then
      alter publication supabase_realtime add table public.conversation_tasks;
    end if;
  end if;
end $$;
