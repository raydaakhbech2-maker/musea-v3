-- MUSEA / Mesures proportionnées, transparence et recours
-- Prérequis : social_interactions, messaging_collaboration et moderation_trust.

create table if not exists public.moderation_content_actions (
  id uuid primary key default gen_random_uuid(),
  target_type text not null check(target_type in ('post','comment')),
  target_id uuid not null,
  active boolean not null default true,
  reason text not null check(char_length(reason)<=500),
  moderator_id uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(target_type,target_id)
);
create index if not exists moderation_content_active_idx
  on public.moderation_content_actions(target_type,target_id) where active;

create table if not exists public.moderation_user_sanctions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  sanction_type text not null check(sanction_type in ('warning','messaging_pause','publishing_pause','account_pause')),
  reason text not null check(char_length(reason) between 5 and 500),
  starts_at timestamptz not null default now(),
  expires_at timestamptz,
  revoked_at timestamptz,
  moderator_id uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  check(expires_at is null or expires_at>starts_at)
);
create index if not exists moderation_sanctions_active_idx
  on public.moderation_user_sanctions(user_id,sanction_type,expires_at)
  where revoked_at is null;

create table if not exists public.moderation_appeals (
  id uuid primary key default gen_random_uuid(),
  appellant_id uuid not null references auth.users(id) on delete cascade,
  target_type text not null check(target_type in ('content_action','sanction')),
  target_id uuid not null,
  explanation text not null check(char_length(explanation) between 20 and 1500),
  status text not null default 'received' check(status in ('received','reviewing','accepted','rejected')),
  moderator_note text not null default '',
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  unique(appellant_id,target_type,target_id)
);
create index if not exists moderation_appeals_status_idx
  on public.moderation_appeals(status,created_at desc);

create table if not exists public.moderation_decision_log (
  id uuid primary key default gen_random_uuid(),
  moderator_id uuid not null references auth.users(id) on delete restrict,
  decision_type text not null,
  target_type text not null,
  target_id uuid not null,
  reason text not null default '',
  created_at timestamptz not null default now()
);

alter table public.moderation_content_actions enable row level security;
alter table public.moderation_user_sanctions enable row level security;
alter table public.moderation_appeals enable row level security;
alter table public.moderation_decision_log enable row level security;

revoke all on public.moderation_content_actions,public.moderation_user_sanctions,public.moderation_appeals,public.moderation_decision_log from anon,authenticated;
grant select on public.moderation_appeals to authenticated;

drop policy if exists "Members read their own sanctions" on public.moderation_user_sanctions;
create policy "Members read their own sanctions" on public.moderation_user_sanctions
for select to authenticated using(user_id=(select auth.uid()));
drop policy if exists "Moderators read all sanctions" on public.moderation_user_sanctions;
create policy "Moderators read all sanctions" on public.moderation_user_sanctions
for select to authenticated using((select public.musea_is_moderator()));

drop policy if exists "Members read their own appeals" on public.moderation_appeals;
create policy "Members read their own appeals" on public.moderation_appeals
for select to authenticated using(appellant_id=(select auth.uid()));
drop policy if exists "Moderators read all appeals" on public.moderation_appeals;
create policy "Moderators read all appeals" on public.moderation_appeals
for select to authenticated using((select public.musea_is_moderator()));

create or replace function public.musea_user_is_restricted(p_user_id uuid,p_feature text)
returns boolean
language sql stable security definer set search_path=''
as $$
  select exists(
    select 1 from public.moderation_user_sanctions s
    where s.user_id=p_user_id and s.revoked_at is null
      and (s.expires_at is null or s.expires_at>now())
      and (s.sanction_type=p_feature or s.sanction_type='account_pause')
  );
$$;
revoke all on function public.musea_user_is_restricted(uuid,text) from public,anon;
grant execute on function public.musea_user_is_restricted(uuid,text) to authenticated;

-- Masquer le contenu sanctionné pour les autres membres, tout en le laissant
-- consultable par son auteur afin qu'il comprenne la mesure et puisse faire recours.
drop policy if exists "MUSEA hide moderated posts" on public.posts;
create policy "MUSEA hide moderated posts" on public.posts
as restrictive for select to anon,authenticated
using (
  user_id=(select auth.uid())
  or not exists(select 1 from public.moderation_content_actions a
    where a.target_type='post' and a.target_id=id and a.active)
);
drop policy if exists "MUSEA hide moderated comments" on public.post_comments;
create policy "MUSEA hide moderated comments" on public.post_comments
as restrictive for select to anon,authenticated
using (
  user_id=(select auth.uid())
  or not exists(select 1 from public.moderation_content_actions a
    where a.target_type='comment' and a.target_id=id and a.active)
);

-- Empêcher les actions nouvelles pendant une restriction active.
drop policy if exists "MUSEA publishing restrictions" on public.posts;
create policy "MUSEA publishing restrictions" on public.posts
as restrictive for insert to authenticated
with check(not public.musea_user_is_restricted((select auth.uid()),'publishing_pause'));
drop policy if exists "MUSEA comment restrictions" on public.post_comments;
create policy "MUSEA comment restrictions" on public.post_comments
as restrictive for insert to authenticated
with check(not public.musea_user_is_restricted((select auth.uid()),'publishing_pause'));
drop policy if exists "MUSEA messaging restrictions" on public.messages;
create policy "MUSEA messaging restrictions" on public.messages
as restrictive for insert to authenticated
with check(not public.musea_user_is_restricted((select auth.uid()),'messaging_pause'));

create or replace function public.musea_apply_content_action(
  p_target_type text,p_target_id uuid,p_hide boolean,p_reason text
) returns uuid
language plpgsql security definer set search_path=''
as $$
declare v_id uuid;
begin
  if not public.musea_is_moderator() then raise exception 'Accès réservé à la modération.'; end if;
  if p_target_type not in ('post','comment') then raise exception 'Type de contenu invalide.'; end if;
  if char_length(coalesce(p_reason,''))<5 or char_length(p_reason)>500 then raise exception 'La justification doit contenir entre 5 et 500 caractères.'; end if;
  if p_target_type='post' and not exists(select 1 from public.posts where id=p_target_id) then raise exception 'Publication introuvable.'; end if;
  if p_target_type='comment' and not exists(select 1 from public.post_comments where id=p_target_id) then raise exception 'Commentaire introuvable.'; end if;
  insert into public.moderation_content_actions(target_type,target_id,active,reason,moderator_id)
  values(p_target_type,p_target_id,p_hide,p_reason,auth.uid())
  on conflict(target_type,target_id) do update set active=excluded.active,reason=excluded.reason,
    moderator_id=excluded.moderator_id,updated_at=now()
  returning id into v_id;
  insert into public.moderation_decision_log(moderator_id,decision_type,target_type,target_id,reason)
  values(auth.uid(),case when p_hide then 'content_hidden' else 'content_restored' end,p_target_type,p_target_id,p_reason);
  return v_id;
end;
$$;
revoke all on function public.musea_apply_content_action(text,uuid,boolean,text) from public,anon;
grant execute on function public.musea_apply_content_action(text,uuid,boolean,text) to authenticated;

create or replace function public.musea_issue_sanction(
  p_user_id uuid,p_sanction_type text,p_reason text,p_duration_hours integer default 24
) returns uuid
language plpgsql security definer set search_path=''
as $$
declare v_id uuid; v_expiry timestamptz;
begin
  if not public.musea_is_moderator() then raise exception 'Accès réservé à la modération.'; end if;
  if p_user_id is null or p_user_id=auth.uid() then raise exception 'Cible invalide.'; end if;
  if p_sanction_type not in ('warning','messaging_pause','publishing_pause','account_pause') then raise exception 'Mesure invalide.'; end if;
  if char_length(coalesce(p_reason,''))<5 or char_length(p_reason)>500 then raise exception 'La justification doit contenir entre 5 et 500 caractères.'; end if;
  if p_sanction_type='warning' then v_expiry:=now()+interval '365 days';
  else
    if p_duration_hours is null or p_duration_hours<1 or p_duration_hours>720 then raise exception 'Durée autorisée : de 1 heure à 30 jours.'; end if;
    v_expiry:=now()+make_interval(hours=>p_duration_hours);
  end if;
  insert into public.moderation_user_sanctions(user_id,sanction_type,reason,expires_at,moderator_id)
  values(p_user_id,p_sanction_type,p_reason,v_expiry,auth.uid()) returning id into v_id;
  insert into public.moderation_decision_log(moderator_id,decision_type,target_type,target_id,reason)
  values(auth.uid(),'sanction_issued',p_sanction_type,p_user_id,p_reason);
  return v_id;
end;
$$;
revoke all on function public.musea_issue_sanction(uuid,text,text,integer) from public,anon;
grant execute on function public.musea_issue_sanction(uuid,text,text,integer) to authenticated;

create or replace function public.musea_submit_appeal(
  p_target_type text,p_target_id uuid,p_explanation text
) returns uuid
language plpgsql security definer set search_path=''
as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'Connexion nécessaire.'; end if;
  if p_target_type not in ('content_action','sanction') then raise exception 'Type de recours invalide.'; end if;
  if char_length(trim(coalesce(p_explanation,'')))<20 or char_length(p_explanation)>1500 then raise exception 'Explique ta contestation en 20 à 1500 caractères.'; end if;
  if p_target_type='content_action' and not exists(
    select 1 from public.moderation_content_actions a
    where a.id=p_target_id and a.active and (
      (a.target_type='post' and exists(select 1 from public.posts p where p.id=a.target_id and p.user_id=auth.uid()))
      or (a.target_type='comment' and exists(select 1 from public.post_comments c where c.id=a.target_id and c.user_id=auth.uid()))
    )
  ) then raise exception 'Cette mesure ne concerne pas ton contenu ou n’est plus active.'; end if;
  if p_target_type='sanction' and not exists(
    select 1 from public.moderation_user_sanctions s where s.id=p_target_id and s.user_id=auth.uid() and s.revoked_at is null
  ) then raise exception 'Cette mesure ne concerne pas ton compte.'; end if;
  insert into public.moderation_appeals(appellant_id,target_type,target_id,explanation)
  values(auth.uid(),p_target_type,p_target_id,trim(p_explanation)) returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.musea_submit_appeal(text,uuid,text) from public,anon;
grant execute on function public.musea_submit_appeal(text,uuid,text) to authenticated;

create or replace function public.musea_review_appeal(
  p_appeal_id uuid,p_status text,p_note text default ''
) returns void
language plpgsql security definer set search_path=''
as $$
declare v_appeal public.moderation_appeals%rowtype;
begin
  if not public.musea_is_moderator() then raise exception 'Accès réservé à la modération.'; end if;
  if p_status not in ('reviewing','accepted','rejected') then raise exception 'Décision invalide.'; end if;
  select * into v_appeal from public.moderation_appeals where id=p_appeal_id for update;
  if not found then raise exception 'Recours introuvable.'; end if;
  update public.moderation_appeals set status=p_status,moderator_note=left(coalesce(p_note,''),1000),
    reviewed_by=auth.uid(),reviewed_at=now() where id=p_appeal_id;
  if p_status='accepted' then
    if v_appeal.target_type='content_action' then
      update public.moderation_content_actions set active=false,updated_at=now() where id=v_appeal.target_id;
    else
      update public.moderation_user_sanctions set revoked_at=now() where id=v_appeal.target_id and revoked_at is null;
    end if;
  end if;
  insert into public.moderation_decision_log(moderator_id,decision_type,target_type,target_id,reason)
  values(auth.uid(),'appeal_'||p_status,v_appeal.target_type,v_appeal.target_id,left(coalesce(p_note,''),500));
end;
$$;
revoke all on function public.musea_review_appeal(uuid,text,text) from public,anon;
grant execute on function public.musea_review_appeal(uuid,text,text) to authenticated;

create or replace function public.musea_my_moderation_cases()
returns table(case_type text,case_id uuid,title text,reason text,expires_at timestamptz,appeal_id uuid,appeal_status text)
language plpgsql stable security definer set search_path=''
as $$
begin
  if auth.uid() is null then raise exception 'Connexion nécessaire.'; end if;
  return query
  select 'sanction'::text,s.id,
    case s.sanction_type when 'warning' then 'Avertissement' when 'messaging_pause' then 'Pause temporaire des messages' when 'publishing_pause' then 'Pause temporaire des publications' else 'Restriction temporaire du compte' end,
    s.reason,s.expires_at,a.id,a.status
  from public.moderation_user_sanctions s
  left join public.moderation_appeals a on a.target_type='sanction' and a.target_id=s.id and a.appellant_id=auth.uid()
  where s.user_id=auth.uid() and s.revoked_at is null and (s.expires_at is null or s.expires_at>now())
  union all
  select 'content_action'::text,c.id,'Contenu masqué',c.reason,null::timestamptz,a.id,a.status
  from public.moderation_content_actions c
  join public.posts p on c.target_type='post' and p.id=c.target_id and p.user_id=auth.uid()
  left join public.moderation_appeals a on a.target_type='content_action' and a.target_id=c.id and a.appellant_id=auth.uid()
  where c.active
  union all
  select 'content_action'::text,c.id,'Commentaire masqué',c.reason,null::timestamptz,a.id,a.status
  from public.moderation_content_actions c
  join public.post_comments pc on c.target_type='comment' and pc.id=c.target_id and pc.user_id=auth.uid()
  left join public.moderation_appeals a on a.target_type='content_action' and a.target_id=c.id and a.appellant_id=auth.uid()
  where c.active;
end;
$$;
revoke all on function public.musea_my_moderation_cases() from public,anon;
grant execute on function public.musea_my_moderation_cases() to authenticated;

drop function if exists public.musea_moderation_queue();
create function public.musea_moderation_queue()
returns table(
  report_kind text,report_id uuid,status text,reason text,reason_label text,details text,
  created_at timestamptz,target_label text,context_excerpt text,
  target_type text,target_id uuid,target_user_id uuid
)
language plpgsql stable security definer set search_path=''
as $$
begin
  if not public.musea_is_moderator() then raise exception 'Accès réservé à la modération.'; end if;
  return query
  select 'content'::text,cr.id,cr.status,cr.reason,
    case cr.reason when 'harassment' then 'Harcèlement ou intimidation' when 'hate' then 'Propos haineux'
      when 'sexual' then 'Contenu sexuel inapproprié' when 'violence' then 'Contenu violent'
      when 'spam' then 'Spam ou arnaque' when 'copyright' then 'Droits d’auteur'
      when 'privacy' then 'Atteinte à la vie privée' else 'Autre' end,
    cr.details,cr.created_at,
    case when cr.target_type='post' then 'Publication · '||left(coalesce(p.caption,'Sans description'),110)
      else 'Commentaire · '||left(coalesce(pc.content,'Contenu indisponible'),110) end,
    'Contenu signalé',cr.target_type,cr.target_id,
    case when cr.target_type='post' then p.user_id else pc.user_id end
  from public.content_reports cr
  left join public.posts p on cr.target_type='post' and p.id=cr.target_id
  left join public.post_comments pc on cr.target_type='comment' and pc.id=cr.target_id
  union all
  select 'conversation'::text,ur.id,ur.status,ur.reason,
    case ur.reason when 'harassment' then 'Harcèlement' when 'spam' then 'Spam'
      when 'inappropriate' then 'Comportement inapproprié' when 'impersonation' then 'Usurpation d’identité' else 'Autre' end,
    ur.details,ur.created_at,'@'||coalesce(pr.username,'membre'),
    'Signalement lié à une conversation privée — aucun message privé affiché',
    'user'::text,ur.target_user_id,ur.target_user_id
  from public.user_reports ur
  left join public.profiles pr on pr.id=ur.target_user_id
  union all
  select 'appeal'::text,a.id,a.status,'appeal','Contestation d’une mesure',
    a.explanation,a.created_at,a.target_type,'Recours envoyé par un membre',
    a.target_type,a.target_id,a.appellant_id
  from public.moderation_appeals a
  order by 7 desc;
end;
$$;
revoke all on function public.musea_moderation_queue() from public,anon;
grant execute on function public.musea_moderation_queue() to authenticated;
