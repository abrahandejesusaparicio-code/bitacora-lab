-- =============================================================
--  Habilitar TIEMPO REAL — Bitácora de Lab  (correr UNA vez)
--  Supabase → SQL Editor → New query → pegar → Run.
--  Agrega las tablas a la publicación de realtime para que la
--  app reciba los cambios al instante. Es seguro re-ejecutarlo.
-- =============================================================
do $$
begin
  begin alter publication supabase_realtime add table public.labs;        exception when others then null; end;
  begin alter publication supabase_realtime add table public.parts;       exception when others then null; end;
  begin alter publication supabase_realtime add table public.assignments; exception when others then null; end;
  begin alter publication supabase_realtime add table public.photos;      exception when others then null; end;
end $$;

-- Diagnóstico: muestra qué tablas tienen tiempo real activo.
select tablename
from pg_publication_tables
where pubname = 'supabase_realtime' and schemaname = 'public'
order by tablename;
