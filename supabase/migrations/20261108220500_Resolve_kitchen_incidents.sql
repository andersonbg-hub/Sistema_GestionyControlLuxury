alter table public.pedidos
  add column if not exists solucion_incidencia_cocina text not null default '';

create or replace function public.limpiar_solucion_incidencia_cocina()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.incidencia_cocina is distinct from old.incidencia_cocina then
    new.solucion_incidencia_cocina := '';
  end if;
  return new;
end;
$$;

drop trigger if exists limpiar_solucion_incidencia_cocina
  on public.pedidos;
create trigger limpiar_solucion_incidencia_cocina
before update of incidencia_cocina on public.pedidos
for each row
execute function public.limpiar_solucion_incidencia_cocina();

create or replace function public.resolver_incidencia_cocina(
  p_pedido_id bigint,
  p_solucion text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_rol text;
  v_solucion text := trim(coalesce(p_solucion, ''));
begin
  if auth.uid() is null then
    raise exception 'Se requiere una sesión autenticada.';
  end if;

  select rol into v_rol
  from public.usuarios
  where id = auth.uid() and activo = true;

  if v_rol is null or v_rol not in ('ADMINISTRADOR', 'GERENTE') then
    raise exception 'No tienes permiso para registrar soluciones de incidencias.';
  end if;
  if length(v_solucion) < 5 then
    raise exception 'Describe la solución con al menos cinco caracteres.';
  end if;

  update public.pedidos
  set solucion_incidencia_cocina = v_solucion
  where id = p_pedido_id
    and nullif(trim(incidencia_cocina), '') is not null;

  if not found then
    raise exception 'No se encontró una incidencia para el pedido indicado.';
  end if;
end;
$$;

revoke all on function public.resolver_incidencia_cocina(bigint, text)
  from public;
grant execute on function public.resolver_incidencia_cocina(bigint, text)
  to authenticated;
