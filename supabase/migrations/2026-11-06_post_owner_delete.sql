-- MUSEA — suppression propriétaire des publications et nettoyage Storage.
-- À appliquer après les migrations sociales et créatives.
-- La migration refuse d'accorder DELETE si posts n'est pas déjà protégé par RLS.

do $$
declare
  v_rls_enabled boolean;
begin
  select c.relrowsecurity into v_rls_enabled
  from pg_class c
  join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relname='posts';
  if v_rls_enabled is distinct from true then
    raise exception 'Sécurité interrompue : active et vérifie d’abord RLS sur public.posts.';
  end if;
end $$;

grant delete on table public.posts to authenticated;

drop policy if exists "Creators delete their own posts" on public.posts;
create policy "Creators delete their own posts"
on public.posts for delete to authenticated
using (user_id = (select auth.uid()));

-- La règle restrictive protège aussi contre une éventuelle ancienne politique
-- permissive plus large qui autoriserait par erreur la suppression d'autrui.
drop policy if exists "Restrict post deletion to owner" on public.posts;
create policy "Restrict post deletion to owner"
on public.posts as restrictive for delete to authenticated
using (user_id = (select auth.uid()));

-- Les images de publications sont rangées sous le dossier UUID du propriétaire.
-- Le droit de suppression Storage ne couvre donc jamais les fichiers d'un autre membre.
grant delete on table storage.objects to authenticated;

drop policy if exists "Creators delete their own post images" on storage.objects;
create policy "Creators delete their own post images"
on storage.objects for delete to authenticated
using (
  bucket_id = 'musea-posts'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

-- Pour ce bucket, toute autre politique permissive est également limitée
-- au dossier propriétaire ; les autres buckets gardent leurs règles existantes.
drop policy if exists "Restrict MUSEA post image deletion to owner" on storage.objects;
create policy "Restrict MUSEA post image deletion to owner"
on storage.objects as restrictive for delete to authenticated
using (
  bucket_id <> 'musea-posts'
  or (storage.foldername(name))[1] = (select auth.uid())::text
);

comment on policy "Creators delete their own posts" on public.posts is
  'Un membre peut supprimer uniquement les publications dont user_id correspond à sa session authentifiée.';
comment on policy "Creators delete their own post images" on storage.objects is
  'Un membre peut supprimer uniquement les objets du bucket musea-posts situés dans son dossier UUID.';

comment on policy "Restrict post deletion to owner" on public.posts is
  'Règle restrictive : même une autre politique permissive ne peut autoriser la suppression d’une publication appartenant à un autre compte.';
comment on policy "Restrict MUSEA post image deletion to owner" on storage.objects is
  'Règle restrictive : le bucket musea-posts ne peut être supprimé que depuis le dossier UUID du propriétaire.';
