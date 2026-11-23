begin;

set local lock_timeout = '3s';
set local statement_timeout = '20s';
lock table public.platillos in access exclusive mode;

do $migration$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'platillos' and column_name = 'foto_url'
  ) then
    raise exception 'Falta la columna existente platillos.foto_url.';
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'platillos' and column_name = 'imagen_url'
  ) then
    return;
  end if;

  if exists (
    select 1 from public.platillos
    where nullif(btrim(imagen_url), '') is not null
      and nullif(btrim(foto_url), '') is not null
      and btrim(foto_url) <> btrim(imagen_url)
  ) then
    raise exception 'Hay platillos con dos fotos distintas. Resuelve las diferencias antes de retirar imagen_url.';
  end if;

  update public.platillos
     set foto_url = imagen_url
   where nullif(btrim(foto_url), '') is null
     and nullif(btrim(imagen_url), '') is not null;

  if exists (
    select 1 from public.platillos
    where nullif(btrim(imagen_url), '') is not null
      and btrim(foto_url) is distinct from btrim(imagen_url)
  ) then
    raise exception 'No se pudo conservar cada foto de platillo en foto_url.';
  end if;

  alter table public.platillos drop column imagen_url;
end
$migration$;

commit;
