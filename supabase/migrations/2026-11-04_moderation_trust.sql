-- MUSEA / Modération, signalements de contenu et traçabilité
-- À appliquer après les migrations sociales et messaging_collaboration.

create table if not exists public.content_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  target_type text not null check (target_type in ('post','comment')),
  target_id uuid not null,
  reason text not null check (reason in ('harassment','hate','sexual','violence','spam','copyright','privacy','other')),
  details text not null default '' check (char_length(details)<=500),
  status text not null default 'received' check (status in ('received','reviewing','resolved','dismissed')),
  moderator_note text not null default '',
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  unique(reporter_id,target_type,target_id)
);

create index if not exists content_reports_created_idx on public.content_reports(created_at desc);
create index if not exists content_reports_status_created_idx on public.content_reports(status,created_at desc);

alter table public.user_reports
  drop constraint if exists user_reports_status_check;
alter table public.user_reports
  add constraint user_reports_status_check check(status in ('received','reviewing','resolved','dismissed'));
alter table public.user_reports
  add column if not exists moderator_note text not null default '';
alter table public.user_reports
  add column if not exists reviewed_by uuid references auth.users(id) on delete set null;
alter table public.user_reports
  add column if not exists reviewed_at timestamptz;

create table if not exists public.moderation_audit_log (
  id uuid primary key default gen_random_uuid(),
  report_kind text not null check(report_kind in ('content','conversation')),
  report_id uuid not null,
  moderator_id uuid not null references auth.users(id) on delete restrict,
  previous_status text,
  new_status text not null,
  note text not null default '',
  created_at timestamptz not null default now()
);
create index if not exists moderation_audit_report_idx
  on public.moderation_audit_log(report_kind,report_id,created_at desc);

alter table public.content_reports enable row level security;
alter table public.moderation_audit_log enable row level security;
revoke all on public.content_reports,public.moderation_audit_log from anon,authenticated;
grant select,insert on public.content_reports to authenticated;

drop policy if exists "Members submit content reports" on public.content_reports;
create policy "Members submit content reports"
on public.content_reports for insert to authenticated
with check (
  reporter_id=(select auth.uid())
  and (
    (target_type='post' and exists(
      select 1 from public.posts p
      where p.id=target_id and p.visibility='public' and p.user_id<>(select auth.uid())
    ))
    or
    (target_type='comment' and exists(
      select 1 from public.post_comments pc
      join public.posts p on p.id=pc.post_id
      where pc.id=target_id and pc.user_id<>(select auth.uid()) and p.visibility='public'
    ))
  )
);

drop policy if exists "Members read their own content reports" on public.content_reports;
create policy "Members read their own content reports"
on public.content_reports for select to authenticated
using(reporter_id=(select auth.uid()));

create or replace function public.musea_is_moderator()
returns boolean
language sql
stable
set search_path=''
as $$
  select coalesce((auth.jwt()->'app_metadata'->>'role') in ('moderator','admin'),false);
$$;
revoke all on function public.musea_is_moderator() from public,anon;
grant execute on function public.musea_is_moderator() to authenticated;

drop policy if exists "Moderators read all content reports" on public.content_reports;
create policy "Moderators read all content reports"
on public.content_reports for select to authenticated
using((select public.musea_is_moderator()));

drop policy if exists "Moderators read all conversation reports" on public.user_reports;
create policy "Moderators read all conversation reports"
on public.user_reports for select to authenticated
using((select public.musea_is_moderator()));

create or replace function public.musea_moderation_queue()
returns table(
  report_kind text,
  report_id uuid,
  status text,
  reason text,
  reason_label text,
  details text,
  created_at timestamptz,
  target_label text,
  context_excerpt text
)
language plpgsql
stable
security definer
set search_path=''
as $$
begin
  if not public.musea_is_moderator() then
    raise exception 'Accès réservé à la modération.';
  end if;

  return query
  select
    'content'::text,
    cr.id,
    cr.status,
    cr.reason,
    case cr.reason
      when 'harassment' then 'Harcèlement ou intimidation'
      when 'hate' then 'Propos haineux'
      when 'sexual' then 'Contenu sexuel inapproprié'
      when 'violence' then 'Contenu violent'
      when 'spam' then 'Spam ou arnaque'
      when 'copyright' then 'Droits d’auteur'
      when 'privacy' then 'Atteinte à la vie privée'
      else 'Autre'
    end,
    cr.details,
    cr.created_at,
    case
      when cr.target_type='post' then 'Publication · '||left(coalesce(p.caption,'Sans description'),110)
      else 'Commentaire · '||left(coalesce(pc.content,'Contenu indisponible'),110)
    end,
    'Élément signalé : '||cr.target_type
  from public.content_reports cr
  left join public.posts p on cr.target_type='post' and p.id=cr.target_id
  left join public.post_comments pc on cr.target_type='comment' and pc.id=cr.target_id

  union all

  select
    'conversation'::text,
    ur.id,
    ur.status,
    ur.reason,
    case ur.reason
      when 'harassment' then 'Harcèlement'
      when 'spam' then 'Spam'
      when 'inappropriate' then 'Comportement inapproprié'
      when 'impersonation' then 'Usurpation d’identité'
      else 'Autre'
    end,
    ur.details,
    ur.created_at,
    '@'||coalesce(pr.username,'membre'),
    'Signalement lié à une conversation privée — contenu des messages non affiché'
  from public.user_reports ur
  left join public.profiles pr on pr.id=ur.target_user_id

  order by created_at desc;
end;
$$;
revoke all on function public.musea_moderation_queue() from public,anon;
grant execute on function public.musea_moderation_queue() to authenticated;

create or replace function public.musea_review_report(
  p_report_kind text,
  p_report_id uuid,
  p_status text,
  p_note text default ''
)
returns void
language plpgsql
security definer
set search_path=''
as $$
declare
  v_previous text;
  v_note text := left(coalesce(p_note,''),1000);
begin
  if not public.musea_is_moderator() then
    raise exception 'Accès réservé à la modération.';
  end if;
  if p_status not in ('reviewing','resolved','dismissed') then
    raise exception 'Statut de modération invalide.';
  end if;
  if p_report_kind='content' then
    select status into v_previous from public.content_reports where id=p_report_id for update;
    if not found then raise exception 'Signalement introuvable.'; end if;
    update public.content_reports
      set status=p_status,moderator_note=v_note,reviewed_by=auth.uid(),reviewed_at=now()
      where id=p_report_id;
  elsif p_report_kind='conversation' then
    select status into v_previous from public.user_reports where id=p_report_id for update;
    if not found then raise exception 'Signalement introuvable.'; end if;
    update public.user_reports
      set status=p_status,moderator_note=v_note,reviewed_by=auth.uid(),reviewed_at=now()
      where id=p_report_id;
  else
    raise exception 'Type de signalement invalide.';
  end if;

  insert into public.moderation_audit_log(report_kind,report_id,moderator_id,previous_status,new_status,note)
  values(p_report_kind,p_report_id,auth.uid(),v_previous,p_status,v_note);
end;
$$;
revoke all on function public.musea_review_report(text,uuid,text,text) from public,anon;
grant execute on function public.musea_review_report(text,uuid,text,text) to authenticated;

-- Aucun droit de modération n'est attribué par cette migration.
-- Le rôle doit être défini par le propriétaire du projet dans auth.users.raw_app_meta_data
-- (app_metadata côté client), jamais dans user_metadata ni depuis l'interface publique.
