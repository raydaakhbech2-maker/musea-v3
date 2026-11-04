-- MUSEA V3 — Les Échos : créations dérivées avec attribution
-- Étape 9 : une création publique peut inspirer une variation personnelle.
-- La publication de la variation et sa filiation sont enregistrées dans une
-- seule transaction via musea_publish_remix().

create table if not exists public.post_remixes (
  remix_post_id uuid primary key references public.posts(id) on delete cascade,
  source_post_id uuid not null references public.posts(id) on delete cascade,
  creator_id uuid not null references auth.users(id) on delete cascade,
  note text not null check (char_length(trim(note)) between 10 and 500),
  created_at timestamptz not null default now(),
  constraint post_remixes_distinct_posts check (remix_post_id <> source_post_id)
);

create index if not exists post_remixes_source_created_idx
  on public.post_remixes(source_post_id, created_at desc);

alter table public.post_remixes enable row level security;

drop policy if exists "Public remixes show public attribution" on public.post_remixes;
create policy "Public remixes show public attribution"
on public.post_remixes for select to anon, authenticated
using (
  exists (
    select 1
    from public.posts child
    join public.posts source on source.id = post_remixes.source_post_id
    where child.id = post_remixes.remix_post_id
      and child.visibility = 'public'
      and source.visibility = 'public'
  )
  and (
    auth.uid() is null
    or not exists (
      select 1 from public.direct_message_blocks b
      join public.posts child on child.id = post_remixes.remix_post_id
      join public.posts source on source.id = post_remixes.source_post_id
      where (b.blocker_id = auth.uid() and b.blocked_id in (child.user_id, source.user_id))
         or (b.blocked_id = auth.uid() and b.blocker_id in (child.user_id, source.user_id))
    )
  )
);

drop policy if exists "Creators add attribution to their own public remixes" on public.post_remixes;
create policy "Creators add attribution to their own public remixes"
on public.post_remixes for insert to authenticated
with check (
  auth.uid() = creator_id
  and exists (
    select 1 from public.posts child
    where child.id = remix_post_id
      and child.user_id = auth.uid()
      and child.visibility = 'public'
  )
  and exists (
    select 1 from public.posts source
    where source.id = source_post_id
      and source.visibility = 'public'
      and not exists (
        select 1 from public.direct_message_blocks b
        where (b.blocker_id = auth.uid() and b.blocked_id = source.user_id)
           or (b.blocked_id = auth.uid() and b.blocker_id = source.user_id)
      )
  )
);

grant select on public.post_remixes to anon, authenticated;
revoke insert, update, delete on public.post_remixes from anon, authenticated;

create or replace function public.musea_publish_remix(
  p_caption text,
  p_style text,
  p_image_url text,
  p_image_path text,
  p_source_post_id uuid,
  p_note text
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $musea$
declare
  v_user_id uuid := auth.uid();
  v_remix_post_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if nullif(trim(coalesce(p_caption, '')), '') is null
     or char_length(p_caption) > 500 then
    raise exception 'A remix needs a caption of 1 to 500 characters';
  end if;

  if nullif(trim(coalesce(p_style, '')), '') is null
     or char_length(p_style) > 80 then
    raise exception 'Invalid creative style';
  end if;

  if nullif(trim(coalesce(p_note, '')), '') is null
     or char_length(trim(p_note)) < 10
     or char_length(p_note) > 500 then
    raise exception 'Explain your personal interpretation in 10 to 500 characters';
  end if;

  if p_source_post_id is null then
    raise exception 'Source creation is required';
  end if;

  if not exists (
    select 1 from public.posts source
    where source.id = p_source_post_id
      and source.visibility = 'public'
      and not exists (
        select 1 from public.direct_message_blocks b
        where (b.blocker_id = v_user_id and b.blocked_id = source.user_id)
           or (b.blocked_id = v_user_id and b.blocker_id = source.user_id)
      )
  ) then
    raise exception 'This public creation is unavailable for remixing';
  end if;

  insert into public.posts (
    user_id, caption, style, visibility, image_url, image_path
  ) values (
    v_user_id, trim(p_caption), trim(p_style), 'public', p_image_url, p_image_path
  )
  returning id into v_remix_post_id;

  insert into public.post_remixes (
    remix_post_id, source_post_id, creator_id, note
  ) values (
    v_remix_post_id, p_source_post_id, v_user_id, trim(p_note)
  );

  return v_remix_post_id;
end;
$musea$;

revoke all on function public.musea_publish_remix(text, text, text, text, uuid, text)
  from public, anon;
grant execute on function public.musea_publish_remix(text, text, text, text, uuid, text)
  to authenticated;
