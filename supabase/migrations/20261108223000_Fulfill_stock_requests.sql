create or replace function public.procesar_solicitud_reabastecimiento(
  p_solicitud_id bigint
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_rol text;
begin
  if auth.uid() is null then
    raise exception 'Se requiere una sesión autenticada.';
  end if;

  select rol into v_rol
  from public.usuarios
  where id = auth.uid() and activo = true;

  if v_rol is distinct from 'ADMINISTRADOR' then
    raise exception 'Solo un administrador puede procesar solicitudes.';
  end if;

  update public.solicitudes_reabastecimiento
  set estado = 'EN_PROCESO'
  where id = p_solicitud_id and estado = 'PENDIENTE';

  if not found then
    raise exception 'La solicitud no existe o ya no está pendiente.';
  end if;

  insert into public.auditoria_movimientos (
    actor_id, actor_rol, accion, entidad, entidad_id
  ) values (
    auth.uid(),
    v_rol,
    'Procesar solicitud de reabastecimiento',
    'solicitudes_reabastecimiento',
    p_solicitud_id::text
  );
end;
$$;

create or replace function public.cancelar_solicitud_reabastecimiento(
  p_solicitud_id bigint
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_rol text;
begin
  if auth.uid() is null then
    raise exception 'Se requiere una sesión autenticada.';
  end if;

  select rol into v_rol
  from public.usuarios
  where id = auth.uid() and activo = true;

  if v_rol is distinct from 'ADMINISTRADOR' then
    raise exception 'Solo un administrador puede cancelar solicitudes.';
  end if;

  update public.solicitudes_reabastecimiento
  set estado = 'CANCELADA'
  where id = p_solicitud_id
    and estado in ('PENDIENTE', 'EN_PROCESO');

  if not found then
    raise exception 'La solicitud no existe o ya no puede cancelarse.';
  end if;

  insert into public.auditoria_movimientos (
    actor_id, actor_rol, accion, entidad, entidad_id
  ) values (
    auth.uid(),
    v_rol,
    'Cancelar solicitud de reabastecimiento',
    'solicitudes_reabastecimiento',
    p_solicitud_id::text
  );
end;
$$;

create or replace function public.recibir_solicitud_reabastecimiento(
  p_solicitud_id bigint
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_rol text;
  v_estado text;
  v_item record;
  v_lineas integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Se requiere una sesión autenticada.';
  end if;

  select rol into v_rol
  from public.usuarios
  where id = auth.uid() and activo = true;

  if v_rol is distinct from 'ADMINISTRADOR' then
    raise exception 'Solo un administrador puede recibir reabastecimientos.';
  end if;

  select estado into v_estado
  from public.solicitudes_reabastecimiento
  where id = p_solicitud_id
  for update;

  if not found then
    raise exception 'No se encontró la solicitud de reabastecimiento.';
  end if;
  if v_estado <> 'EN_PROCESO' then
    raise exception 'La solicitud debe estar en proceso para recibir stock.';
  end if;

  for v_item in
    select insumo_id, cantidad
    from public.solicitud_items
    where solicitud_id = p_solicitud_id
  loop
    if v_item.cantidad is null or v_item.cantidad <= 0 then
      raise exception 'La cantidad recibida debe ser mayor a cero.';
    end if;

    update public.insumos
    set stock_actual = stock_actual + v_item.cantidad
    where id = v_item.insumo_id and activo = true;

    if not found then
      raise exception 'No se encontró un insumo activo de la solicitud.';
    end if;
    v_lineas := v_lineas + 1;
  end loop;

  if v_lineas = 0 then
    raise exception 'La solicitud no contiene insumos para recibir.';
  end if;

  update public.solicitudes_reabastecimiento
  set estado = 'ATENDIDO',
      atendido_en = now()
  where id = p_solicitud_id;

  insert into public.auditoria_movimientos (
    actor_id,
    actor_rol,
    accion,
    entidad,
    entidad_id
  ) values (
    auth.uid(),
    v_rol,
    'Recibir reabastecimiento',
    'solicitudes_reabastecimiento',
    p_solicitud_id::text
  );
end;
$$;

revoke all on function public.recibir_solicitud_reabastecimiento(bigint)
  from public;
grant execute on function public.recibir_solicitud_reabastecimiento(bigint)
  to authenticated;
revoke all on function public.procesar_solicitud_reabastecimiento(bigint)
  from public;
grant execute on function public.procesar_solicitud_reabastecimiento(bigint)
  to authenticated;
revoke all on function public.cancelar_solicitud_reabastecimiento(bigint)
  from public;
grant execute on function public.cancelar_solicitud_reabastecimiento(bigint)
  to authenticated;
