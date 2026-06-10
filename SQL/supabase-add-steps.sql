-- =============================================================
--  Agregar instrucciones detalladas (pasos) a las partes
--  Correr UNA vez en Supabase → SQL Editor → Run.
-- =============================================================
alter table public.parts
  add column if not exists steps jsonb not null default '[]'::jsonb;
