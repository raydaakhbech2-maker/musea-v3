-- Align profile visibility with the current follow graph and preserve block privacy.
drop policy if exists "profiles readable" on public.profiles;
create policy "profiles readable" on public.profiles
for select to authenticated using (
  is_private = false
  or id = (select auth.uid())
  or exists (
    select 1 from public.user_follows f
    where f.follower_id=(select auth.uid())
      and f.followed_id=profiles.id
      and f.status='accepted'
  )
  or exists (
    select 1 from public.follows f
    where f.follower_id=(select auth.uid()) and f.followed_id=profiles.id
  )
);

drop policy if exists stories_read_visible on public.stories;
create policy stories_read_visible on public.stories
for select to authenticated using (
  expires_at > now()
  and not exists (
    select 1 from public.direct_message_blocks b
    where (b.blocker_id=(select auth.uid()) and b.blocked_id=stories.user_id)
       or (b.blocked_id=(select auth.uid()) and b.blocker_id=stories.user_id)
  )
  and (
    user_id = (select auth.uid())
    or exists (select 1 from public.profiles p where p.id=stories.user_id and coalesce(p.is_private,false)=false)
    or exists (select 1 from public.user_follows f where f.follower_id=(select auth.uid()) and f.followed_id=stories.user_id and f.status='accepted')
  )
);
