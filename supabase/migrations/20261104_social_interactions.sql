-- MUSEA V3 — interactions sociales persistantes
-- À exécuter une seule fois dans Supabase > SQL Editor.
-- Les utilisateurs ne peuvent agir qu'en leur propre nom.

create table if not exists public.post_likes (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint post_likes_one_per_user unique (post_id, user_id)
);

create table if not exists public.post_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  content text not null check (char_length(trim(content)) between 1 and 1000),
  created_at timestamptz not null default now()
);

create index if not exists post_comments_post_created_idx
  on public.post_comments(post_id, created_at asc);

create table if not exists public.post_reposts (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint post_reposts_one_per_user unique (post_id, user_id)
);

create index if not exists post_likes_post_idx on public.post_likes(post_id);
create index if not exists post_reposts_post_idx on public.post_reposts(post_id);

alter table public.post_likes enable row level security;
alter table public.post_comments enable row level security;
alter table public.post_reposts enable row level security;

drop policy if exists "Likes are visible to everyone" on public.post_likes;
create policy "Likes are visible to everyone"
  on public.post_likes for select to anon, authenticated using (true);
drop policy if exists "Users add their own likes" on public.post_likes;
create policy "Users add their own likes"
  on public.post_likes for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "Users remove their own likes" on public.post_likes;
create policy "Users remove their own likes"
  on public.post_likes for delete to authenticated using (auth.uid() = user_id);

drop policy if exists "Comments are visible to everyone" on public.post_comments;
create policy "Comments are visible to everyone"
  on public.post_comments for select to anon, authenticated using (true);
drop policy if exists "Authenticated users add their own comments" on public.post_comments;
create policy "Authenticated users add their own comments"
  on public.post_comments for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "Users edit their own comments" on public.post_comments;
create policy "Users edit their own comments"
  on public.post_comments for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "Users delete their own comments" on public.post_comments;
create policy "Users delete their own comments"
  on public.post_comments for delete to authenticated using (auth.uid() = user_id);

drop policy if exists "Reposts are visible to everyone" on public.post_reposts;
create policy "Reposts are visible to everyone"
  on public.post_reposts for select to anon, authenticated using (true);
drop policy if exists "Users add their own reposts" on public.post_reposts;
create policy "Users add their own reposts"
  on public.post_reposts for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "Users remove their own reposts" on public.post_reposts;
create policy "Users remove their own reposts"
  on public.post_reposts for delete to authenticated using (auth.uid() = user_id);

grant select on public.post_likes, public.post_comments, public.post_reposts to anon, authenticated;
grant insert, delete on public.post_likes, public.post_reposts to authenticated;
grant insert, update, delete on public.post_comments to authenticated;
