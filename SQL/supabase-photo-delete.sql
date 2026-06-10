-- =============================================================
--  Permitir ELIMINAR fotos al autor (o asignado), además del admin
--  Correr UNA vez en Supabase → SQL Editor → Run.
-- =============================================================

-- Tabla photos: borra si eres admin, o subiste la foto, o estás asignado a la parte
drop policy if exists "photos_delete_admin" on public.photos;
drop policy if exists "photos_delete"       on public.photos;
create policy "photos_delete" on public.photos
  for delete to authenticated
  using (public.is_admin() or uploaded_by = auth.uid() or public.is_assigned(part_id));

-- Storage: borra si eres admin o estás asignado a la parte (2do segmento de la ruta)
drop policy if exists "evidence_delete" on storage.objects;
create policy "evidence_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'evidence' and (public.is_admin() or public.is_assigned( nullif(split_part(name, '/', 2), '')::uuid )));
