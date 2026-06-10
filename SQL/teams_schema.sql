-- =========================================================
--  EQUIPOS (Teams) — esquema para "Bitácora de Lab"
--  Ejecútalo COMPLETO en Supabase  ->  SQL Editor  ->  New query  ->  Run.
--  Es idempotente: puedes correrlo más de una vez sin romper nada.
-- =========================================================

-- 1) Helper: ¿el usuario actual es admin?
--    SECURITY DEFINER para evitar recursión de RLS al leer profiles.
create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

-- 2) Tablas
create table if not exists public.teams (
  id             uuid primary key default gen_random_uuid(),
  element_symbol text not null,
  element_name   text not null,
  created_at     timestamptz not null default now()
);

-- Una persona pertenece como máximo a UN equipo -> user_id es la PK.
create table if not exists public.team_members (
  user_id    uuid primary key references public.profiles(id) on delete cascade,
  team_id    uuid not null references public.teams(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.join_requests (
  id         uuid primary key default gen_random_uuid(),
  team_id    uuid not null references public.teams(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  status     text not null default 'pending',
  created_at timestamptz not null default now()
);
create index if not exists join_requests_status_idx on public.join_requests(status);

-- 3) Row Level Security
alter table public.teams         enable row level security;
alter table public.team_members  enable row level security;
alter table public.join_requests enable row level security;

-- teams: todos leen, solo admin escribe
drop policy if exists teams_select on public.teams;
create policy teams_select on public.teams
  for select to authenticated using (true);
drop policy if exists teams_write on public.teams;
create policy teams_write on public.teams
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- team_members: todos leen, solo admin escribe
drop policy if exists tm_select on public.team_members;
create policy tm_select on public.team_members
  for select to authenticated using (true);
drop policy if exists tm_write on public.team_members;
create policy tm_write on public.team_members
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- join_requests: todos leen; cada quien crea/borra la suya; admin hace todo
drop policy if exists jr_select on public.join_requests;
create policy jr_select on public.join_requests
  for select to authenticated using (true);
drop policy if exists jr_insert_own on public.join_requests;
create policy jr_insert_own on public.join_requests
  for insert to authenticated with check (user_id = auth.uid());
drop policy if exists jr_delete_own_or_admin on public.join_requests;
create policy jr_delete_own_or_admin on public.join_requests
  for delete to authenticated using (user_id = auth.uid() or public.is_admin());
drop policy if exists jr_update_admin on public.join_requests;
create policy jr_update_admin on public.join_requests
  for update to authenticated using (public.is_admin()) with check (public.is_admin());

-- 4) Realtime: publica las tablas para que todos los dispositivos se sincronicen.
do $$
begin
  begin execute 'alter publication supabase_realtime add table public.teams';         exception when others then null; end;
  begin execute 'alter publication supabase_realtime add table public.team_members';  exception when others then null; end;
  begin execute 'alter publication supabase_realtime add table public.join_requests'; exception when others then null; end;
end $$;

-- Listo. Vuelve a la app y recarga.
