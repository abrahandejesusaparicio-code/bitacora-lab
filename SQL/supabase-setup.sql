-- =============================================================
--  Bitácora de Lab — Configuración de Supabase
--  Pega TODO este archivo en el SQL Editor de Supabase y dale "Run".
--  (Dashboard → SQL Editor → New query → pegar → Run)
--  Es seguro ejecutarlo más de una vez (usa IF NOT EXISTS / OR REPLACE).
-- =============================================================

-- ---------- Extensión para generar UUIDs ----------
create extension if not exists pgcrypto;

-- =============================================================
--  TABLAS
-- =============================================================

-- PERFILES: una fila por usuario registrado. role = 'member' | 'admin'
create table if not exists public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  full_name  text,
  email      text,
  role       text not null default 'member' check (role in ('member','admin')),
  created_at timestamptz not null default now()
);

-- LABORATORIOS: un "lab" por sesión (ej. "Lab 4 — Cambios Físicos y Químicos")
create table if not exists public.labs (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  description text,
  lab_date    date,
  archived    boolean not null default false,
  created_by  uuid references auth.users(id),
  created_at  timestamptz not null default now()
);

-- PARTES: cada lab se divide en varias partes (ordenadas por "position")
create table if not exists public.parts (
  id           uuid primary key default gen_random_uuid(),
  lab_id       uuid not null references public.labs(id) on delete cascade,
  title        text not null,
  description  text,
  position     int  not null default 0,
  equipment    text[] not null default '{}',
  completed_at timestamptz,
  completed_by uuid references auth.users(id),
  created_at   timestamptz not null default now()
);
create index if not exists parts_lab_id_idx on public.parts(lab_id);

-- ASIGNACIONES: qué usuarios están asignados a qué parte (el admin las gestiona)
create table if not exists public.assignments (
  id          uuid primary key default gen_random_uuid(),
  part_id     uuid not null references public.parts(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  assigned_by uuid references auth.users(id),
  created_at  timestamptz not null default now(),
  unique (part_id, user_id)
);
create index if not exists assignments_part_id_idx on public.assignments(part_id);
create index if not exists assignments_user_id_idx on public.assignments(user_id);

-- FOTOS: evidencia. Una parte puede tener una o varias fotos.
create table if not exists public.photos (
  id           uuid primary key default gen_random_uuid(),
  part_id      uuid not null references public.parts(id) on delete cascade,
  uploaded_by  uuid references auth.users(id),
  storage_path text not null,
  caption      text,
  created_at   timestamptz not null default now()
);
create index if not exists photos_part_id_idx on public.photos(part_id);

-- =============================================================
--  FUNCIONES AUXILIARES (security definer = ignoran RLS para evitar recursión)
-- =============================================================

-- ¿El usuario actual es admin?
create or replace function public.is_admin()
returns boolean
language sql security definer set search_path = public stable
as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

-- ¿El usuario actual está asignado a esta parte?
create or replace function public.is_assigned(p_part uuid)
returns boolean
language sql security definer set search_path = public stable
as $$
  select exists (select 1 from public.assignments where part_id = p_part and user_id = auth.uid());
$$;

-- Crear automáticamente un "profile" cuando alguien se registra
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, email)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', ''), new.email)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- =============================================================
--  ROW LEVEL SECURITY  (la seguridad real vive aquí, en el servidor)
-- =============================================================
alter table public.profiles    enable row level security;
alter table public.labs        enable row level security;
alter table public.parts       enable row level security;
alter table public.assignments enable row level security;
alter table public.photos      enable row level security;

-- ---------- PROFILES ----------
drop policy if exists "profiles_read"        on public.profiles;
drop policy if exists "profiles_update_own"  on public.profiles;
drop policy if exists "profiles_admin_update" on public.profiles;
create policy "profiles_read" on public.profiles
  for select to authenticated using (true);
create policy "profiles_update_own" on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy "profiles_admin_update" on public.profiles
  for update to authenticated using (public.is_admin()) with check (public.is_admin());

-- ---------- LABS ----------
drop policy if exists "labs_read"       on public.labs;
drop policy if exists "labs_admin_write" on public.labs;
create policy "labs_read" on public.labs
  for select to authenticated using (true);
create policy "labs_admin_write" on public.labs
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ---------- PARTS ----------
drop policy if exists "parts_read"            on public.parts;
drop policy if exists "parts_admin_write"     on public.parts;
drop policy if exists "parts_assigned_update" on public.parts;
create policy "parts_read" on public.parts
  for select to authenticated using (true);
create policy "parts_admin_write" on public.parts
  for all to authenticated using (public.is_admin()) with check (public.is_admin());
-- un miembro asignado puede actualizar la parte (marcarla completada)
create policy "parts_assigned_update" on public.parts
  for update to authenticated using (public.is_assigned(id)) with check (public.is_assigned(id));

-- ---------- ASSIGNMENTS ----------
drop policy if exists "assignments_read"        on public.assignments;
drop policy if exists "assignments_admin_write" on public.assignments;
create policy "assignments_read" on public.assignments
  for select to authenticated using (true);
create policy "assignments_admin_write" on public.assignments
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ---------- PHOTOS ----------
drop policy if exists "photos_read"          on public.photos;
drop policy if exists "photos_insert"        on public.photos;
drop policy if exists "photos_delete_admin"  on public.photos;
create policy "photos_read" on public.photos
  for select to authenticated using (true);
create policy "photos_insert" on public.photos
  for insert to authenticated
  with check (uploaded_by = auth.uid() and (public.is_assigned(part_id) or public.is_admin()));
create policy "photos_delete_admin" on public.photos
  for delete to authenticated using (public.is_admin());

-- =============================================================
--  STORAGE  (bucket privado "evidence" + políticas)
--  Las fotos se guardan con ruta:  lab_id/part_id/<archivo>.jpg
-- =============================================================
insert into storage.buckets (id, name, public)
values ('evidence', 'evidence', false)
on conflict (id) do nothing;

drop policy if exists "evidence_read"   on storage.objects;
drop policy if exists "evidence_insert" on storage.objects;
drop policy if exists "evidence_delete" on storage.objects;

create policy "evidence_read" on storage.objects
  for select to authenticated using (bucket_id = 'evidence');

-- subir: admin siempre; miembro solo si está asignado a la parte (2do segmento de la ruta)
create policy "evidence_insert" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'evidence'
    and (
      public.is_admin()
      or public.is_assigned( nullif(split_part(name, '/', 2), '')::uuid )
    )
  );

create policy "evidence_delete" on storage.objects
  for delete to authenticated using (bucket_id = 'evidence' and public.is_admin());

-- =============================================================
--  ¡LISTO!  Después de que TÚ (Abrahan) te registres en la app por
--  primera vez, ejecuta esta línea UNA VEZ para volverte admin:
--
--      update public.profiles set role = 'admin'
--      where email = 'abrahandejesusaparicio@gmail.com';
--
--  (cámbiala si te registras con otro correo)
-- =============================================================
