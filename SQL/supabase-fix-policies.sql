-- =============================================================
--  REPARACIÓN de políticas (RLS) — Bitácora de Lab
--  Pega TODO esto en Supabase → SQL Editor → Run.
--  Es seguro: vuelve a crear las reglas de seguridad de las tablas.
--  (No toca Storage; eso va aparte.)
-- =============================================================

-- Asegurar que RLS está activo
alter table public.profiles    enable row level security;
alter table public.labs        enable row level security;
alter table public.parts       enable row level security;
alter table public.assignments enable row level security;
alter table public.photos      enable row level security;

-- Funciones auxiliares (por si faltaban)
create or replace function public.is_admin()
returns boolean language sql security definer set search_path = public stable
as $$ select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin'); $$;

create or replace function public.is_assigned(p_part uuid)
returns boolean language sql security definer set search_path = public stable
as $$ select exists (select 1 from public.assignments where part_id = p_part and user_id = auth.uid()); $$;

-- ---------- PROFILES ----------
drop policy if exists "profiles_read"         on public.profiles;
drop policy if exists "profiles_update_own"   on public.profiles;
drop policy if exists "profiles_admin_update" on public.profiles;
create policy "profiles_read"         on public.profiles for select to authenticated using (true);
create policy "profiles_update_own"   on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy "profiles_admin_update" on public.profiles for update to authenticated using (public.is_admin()) with check (public.is_admin());

-- ---------- LABS ----------
drop policy if exists "labs_read"        on public.labs;
drop policy if exists "labs_admin_write" on public.labs;
create policy "labs_read"        on public.labs for select to authenticated using (true);
create policy "labs_admin_write" on public.labs for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ---------- PARTS ----------
drop policy if exists "parts_read"            on public.parts;
drop policy if exists "parts_admin_write"     on public.parts;
drop policy if exists "parts_assigned_update" on public.parts;
create policy "parts_read"            on public.parts for select to authenticated using (true);
create policy "parts_admin_write"     on public.parts for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "parts_assigned_update" on public.parts for update to authenticated using (public.is_assigned(id)) with check (public.is_assigned(id));

-- ---------- ASSIGNMENTS ----------
drop policy if exists "assignments_read"        on public.assignments;
drop policy if exists "assignments_admin_write" on public.assignments;
create policy "assignments_read"        on public.assignments for select to authenticated using (true);
create policy "assignments_admin_write" on public.assignments for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ---------- PHOTOS ----------
drop policy if exists "photos_read"         on public.photos;
drop policy if exists "photos_insert"       on public.photos;
drop policy if exists "photos_delete_admin" on public.photos;
create policy "photos_read"         on public.photos for select to authenticated using (true);
create policy "photos_insert"       on public.photos for insert to authenticated
  with check (uploaded_by = auth.uid() and (public.is_assigned(part_id) or public.is_admin()));
create policy "photos_delete_admin" on public.photos for delete to authenticated using (public.is_admin());

-- =============================================================
--  DIAGNÓSTICO: muestra todas las políticas que existen ahora.
--  Copia el resultado y mándamelo.
-- =============================================================
select tablename, policyname, cmd
from pg_policies
where schemaname = 'public'
order by tablename, policyname;
