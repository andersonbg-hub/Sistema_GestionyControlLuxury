-- Campos opcionales. Las filas históricas conservan sus valores y permisos.
alter table public.platillos add column if not exists imagen_url text;
alter table public.insumos add column if not exists imagen_url text;
