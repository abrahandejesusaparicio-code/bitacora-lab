-- =========================================================
--  SECCIONES (asignación de partes a equipos) — "Bitácora de Lab"
--  Ejecútalo COMPLETO en Supabase -> SQL Editor -> New query -> Run.
--  Idempotente: puedes correrlo más de una vez.
--  Requiere haber corrido antes teams_schema.sql (usa is_admin(), teams, team_members).
-- =========================================================

-- 1) Tablas ------------------------------------------------
-- Una parte tiene como máximo UN equipo asignado -> part_id es la PK.
create table if not exists public.part_assignments (
  part_id    uuid primary key references public.parts(id) on delete cascade,
  team_id    uuid references public.teams(id) on delete cascade,
  created_at timestamptz not null default now()
);

-- Solicitudes de intercambio de sección entre equipos (a nivel de parte).
create table if not exists public.swap_requests (
  id           uuid primary key default gen_random_uuid(),
  from_part_id uuid not null references public.parts(id) on delete cascade,
  to_part_id   uuid not null references public.parts(id) on delete cascade,
  status       text not null default 'pending',
  created_at   timestamptz not null default now()
);
create index if not exists swap_requests_status_idx on public.swap_requests(status);

-- 2) Sincronización con la tabla 'assignments' (personas responsables por parte)
--    Cuando una parte recibe equipo, sus integrantes pasan a ser los responsables.
create or replace function public.rebuild_team_parts(p_team uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_team is null then return; end if;
  delete from assignments a using part_assignments pa
    where a.part_id = pa.part_id and pa.team_id = p_team;
  insert into assignments(part_id, user_id)
    select pa.part_id, tm.user_id
    from part_assignments pa
    join team_members tm on tm.team_id = pa.team_id
    where pa.team_id = p_team;
end $$;

create or replace function public.sync_part_team()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (TG_OP = 'DELETE') then
    delete from assignments where part_id = OLD.part_id;
    return OLD;
  end if;
  delete from assignments where part_id = NEW.part_id;
  if NEW.team_id is not null then
    insert into assignments(part_id, user_id)
      select NEW.part_id, tm.user_id from team_members tm where tm.team_id = NEW.team_id;
  end if;
  return NEW;
end $$;
drop trigger if exists trg_sync_part_team on public.part_assignments;
create trigger trg_sync_part_team
  after insert or update or delete on public.part_assignments
  for each row execute function public.sync_part_team();

-- Si cambian los integrantes de un equipo, refresca las partes de ese equipo.
create or replace function public.sync_team_member()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (TG_OP = 'INSERT') then perform rebuild_team_parts(NEW.team_id);
  elsif (TG_OP = 'DELETE') then perform rebuild_team_parts(OLD.team_id);
  else
    perform rebuild_team_parts(OLD.team_id);
    if NEW.team_id is distinct from OLD.team_id then perform rebuild_team_parts(NEW.team_id); end if;
  end if;
  return null;
end $$;
drop trigger if exists trg_sync_team_member on public.team_members;
create trigger trg_sync_team_member
  after insert or update or delete on public.team_members
  for each row execute function public.sync_team_member();

-- 3) Funciones de intercambio (las usan los equipos, sin admin) -----
create or replace function public.request_section_swap(p_from uuid, p_to uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_from_team uuid;
begin
  select team_id into v_from_team from part_assignments where part_id = p_from;
  if v_from_team is null then raise exception 'La parte de origen no tiene equipo'; end if;
  if not exists (select 1 from team_members where team_id = v_from_team and user_id = auth.uid()) then
    raise exception 'No eres integrante del equipo de la parte de origen';
  end if;
  delete from swap_requests where from_part_id = p_from and to_part_id = p_to and status = 'pending';
  insert into swap_requests(from_part_id, to_part_id) values (p_from, p_to) returning id into v_id;
  return v_id;
end $$;

create or replace function public.accept_section_swap(p_req uuid)
returns void language plpgsql security definer set search_path = public as $$
declare r record; t_from uuid; t_to uuid;
begin
  select * into r from swap_requests where id = p_req and status = 'pending';
  if not found then raise exception 'Solicitud no encontrada'; end if;
  select team_id into t_from from part_assignments where part_id = r.from_part_id;
  select team_id into t_to   from part_assignments where part_id = r.to_part_id;
  if not exists (select 1 from team_members where team_id = t_to and user_id = auth.uid()) then
    raise exception 'Solo el equipo solicitado puede aceptar';
  end if;
  update part_assignments set team_id = t_to   where part_id = r.from_part_id;
  update part_assignments set team_id = t_from where part_id = r.to_part_id;
  delete from swap_requests
    where from_part_id in (r.from_part_id, r.to_part_id)
       or to_part_id   in (r.from_part_id, r.to_part_id);
end $$;

create or replace function public.decline_section_swap(p_req uuid)
returns void language plpgsql security definer set search_path = public as $$
declare r record; t_from uuid; t_to uuid;
begin
  select * into r from swap_requests where id = p_req;
  if not found then return; end if;
  select team_id into t_from from part_assignments where part_id = r.from_part_id;
  select team_id into t_to   from part_assignments where part_id = r.to_part_id;
  if not (exists (select 1 from team_members where team_id = t_from and user_id = auth.uid())
       or exists (select 1 from team_members where team_id = t_to   and user_id = auth.uid())
       or public.is_admin()) then
    raise exception 'No autorizado';
  end if;
  delete from swap_requests where id = p_req;
end $$;

grant execute on function public.request_section_swap(uuid, uuid) to authenticated;
grant execute on function public.accept_section_swap(uuid)        to authenticated;
grant execute on function public.decline_section_swap(uuid)       to authenticated;

-- 4) RLS ---------------------------------------------------
alter table public.part_assignments enable row level security;
alter table public.swap_requests    enable row level security;

-- part_assignments: todos leen; solo admin escribe directo (randomizar / reasignar).
--   (los intercambios de equipos pasan por las funciones SECURITY DEFINER de arriba)
drop policy if exists pa_select on public.part_assignments;
create policy pa_select on public.part_assignments for select to authenticated using (true);
drop policy if exists pa_write on public.part_assignments;
create policy pa_write on public.part_assignments for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- swap_requests: todos leen (ambos equipos las ven). Crear/aceptar/rechazar va por funciones.
drop policy if exists sr_select on public.swap_requests;
create policy sr_select on public.swap_requests for select to authenticated using (true);
-- el admin puede borrarlas (p. ej. al re-randomizar las secciones)
drop policy if exists sr_admin_del on public.swap_requests;
create policy sr_admin_del on public.swap_requests for delete to authenticated using (public.is_admin());

-- 5) Realtime ----------------------------------------------
do $$
begin
  begin execute 'alter publication supabase_realtime add table public.part_assignments'; exception when others then null; end;
  begin execute 'alter publication supabase_realtime add table public.swap_requests';    exception when others then null; end;
end $$;

-- Listo. Vuelve a la app y recarga.
