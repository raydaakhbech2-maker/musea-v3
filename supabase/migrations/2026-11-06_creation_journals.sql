-- MUSEA V3 — Les Carnets : rendre visible la démarche, pas seulement le résultat.
-- Dépend de public.posts et de musea_story_is_visible().

create table if not exists public.post_creation_journals (
  post_id uuid primary key references public.posts(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade,
  intention text,
  choice text,
  discovery text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint creation_journal_has_content check (
    nullif(trim(coalesce(intention,'')), '') is not null
    or nullif(trim(coalesce(choice,'')), '') is not null
    or nullif(trim(coalesce(discovery,'')), '') is not null
  ),
  constraint creation_journal_lengths check (
    char_length(coalesce(intention,'')) <= 400
    and char_length(coalesce(choice,'')) <= 400
    and char_length(coalesce(discovery,'')) <= 400
  )
);

alter table public.post_creation_journals enable row level security;

drop policy if exists "Public creation journals are readable with their public post" on public.post_creation_journals;
create policy "Public creation journals are readable with their public post"
on public.post_creation_journals for select to anon,authenticated
using (
  exists (
    select 1 from public.posts p
    where p.id=post_creation_journals.post_id
      and p.visibility='public'
      and (auth.uid() is null or public.musea_story_is_visible(p.user_id))
  )
);

grant select on public.post_creation_journals to anon,authenticated;
revoke insert,update,delete on public.post_creation_journals from anon,authenticated;

create or replace function public.musea_save_creation_journal(
  p_post_id uuid,p_intention text,p_choice text,p_discovery text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_intention text := nullif(trim(coalesce(p_intention,'')),'');
  v_choice text := nullif(trim(coalesce(p_choice,'')),'');
  v_discovery text := nullif(trim(coalesce(p_discovery,'')),'');
begin
  if v_user_id is null then raise exception 'Authentication required'; end if;
  if p_post_id is null then raise exception 'A published creation is required'; end if;
  if v_intention is null and v_choice is null and v_discovery is null then raise exception 'Add at least one journal fragment'; end if;
  if char_length(coalesce(v_intention,''))>400 or char_length(coalesce(v_choice,''))>400 or char_length(coalesce(v_discovery,''))>400 then
    raise exception 'Each journal fragment must be 400 characters or less';
  end if;
  if not exists (
    select 1 from public.posts p
    where p.id=p_post_id and p.user_id=v_user_id and p.visibility='public'
  ) then raise exception 'You can only add a journal to your own public creation'; end if;

  insert into public.post_creation_journals(post_id,author_id,intention,choice,discovery,updated_at)
  values(p_post_id,v_user_id,v_intention,v_choice,v_discovery,now())
  on conflict(post_id) do update
    set intention=excluded.intention,choice=excluded.choice,discovery=excluded.discovery,updated_at=now()
    where public.post_creation_journals.author_id=v_user_id;
  if not found then raise exception 'This journal belongs to another creator'; end if;
end;
$$;

revoke all on function public.musea_save_creation_journal(uuid,text,text,text) from public,anon;
grant execute on function public.musea_save_creation_journal(uuid,text,text,text) to authenticated;

create or replace function public.musea_delete_creation_journal(p_post_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then raise exception 'Authentication required'; end if;
  delete from public.post_creation_journals
  where post_id=p_post_id and author_id=(select auth.uid());
end;
$$;
revoke all on function public.musea_delete_creation_journal(uuid) from public,anon;
grant execute on function public.musea_delete_creation_journal(uuid) to authenticated;
