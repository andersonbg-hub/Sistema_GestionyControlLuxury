begin;

set local lock_timeout = '3s';
set local statement_timeout = '20s';

-- Called by the two service RPCs with the order row already locked.
create or replace function public.recalcular_estado_preparacion_comanda(p_pedido_id bigint)
returns void
language sql
security invoker
set search_path = ''
as $$
  with lineas as (
    select
      count(*) as total,
      bool_or(not atiende_mesero and estado = 'EN_PREPARACION') as preparando,
      bool_or(not atiende_mesero and estado = 'PENDIENTE') as pendiente_cocina,
      bool_or(not atiende_mesero) as tiene_cocina,
      bool_or(estado <> 'ENTREGADO') as pendiente_entrega
    from public.detalle_pedido
    where pedido_id = p_pedido_id
  ), preparacion as (
    select case
      when preparando then 'EN_PREPARACION'::public.estado_pedido
      when pendiente_cocina or (not tiene_cocina and pendiente_entrega)
        then 'PENDIENTE'::public.estado_pedido
      else 'LISTO'::public.estado_pedido
    end as estado
    from lineas
    where total > 0
  )
  update public.pedidos p
  set estado = preparacion.estado, actualizado_en = pg_catalog.now()
  from preparacion
  where p.id = p_pedido_id
    and p.retirada_en is null
    and p.estado in ('PENDIENTE', 'EN_PREPARACION', 'LISTO')
    and p.estado is distinct from preparacion.estado;
$$;

revoke all on function public.recalcular_estado_preparacion_comanda(bigint)
  from public, anon, authenticated;

create or replace function public.actualizar_estado_item(
  p_detalle_id bigint,
  p_estado public.estado_item
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_rol text;
  v_pedido_id bigint;
  v_pedido_estado public.estado_pedido;
  v_retirada_en boolean;
  v_detalle_estado public.estado_item;
  v_siguiente public.estado_item;
  v_atiende_mesero boolean;
begin
  select u.rol::text into v_rol
  from public.usuarios u
  where u.id = v_actor and u.activo;

  if v_rol is null or v_rol not in ('ADMINISTRADOR', 'MESERO', 'COCINERO', 'JEFE_COCINA') then
    raise sqlstate 'PT403' using message = 'No tienes permiso para actualizar la comanda.';
  end if;

  if p_estado is null or p_estado not in ('EN_PREPARACION', 'LISTO', 'ENTREGADO') then
    raise sqlstate 'PT422' using message = 'Ese estado no se puede asignar a un producto de la comanda.';
  end if;
  if (v_rol = 'MESERO' and p_estado <> 'ENTREGADO')
      or (v_rol in ('COCINERO', 'JEFE_COCINA') and p_estado = 'ENTREGADO') then
    raise sqlstate 'PT403' using message = 'Tu rol no puede confirmar ese estado.';
  end if;

  -- Billing, additional items and waiter delivery lock the order before its details.
  select p.id, p.estado, p.retirada_en is not null
  into v_pedido_id, v_pedido_estado, v_retirada_en
  from public.pedidos p
  join public.detalle_pedido d on d.pedido_id = p.id
  where d.id = p_detalle_id and (v_rol <> 'MESERO' or p.mesero_id = v_actor)
  for update of p;

  if not found then
    raise sqlstate 'PT404' using message = 'No se encontró un producto de la comanda al que tengas acceso.';
  end if;
  if v_retirada_en or v_pedido_estado = 'CANCELADO' then
    raise sqlstate 'PT409' using message = 'La comanda está cancelada o retirada.';
  end if;

  select d.estado, d.atiende_mesero into v_detalle_estado, v_atiende_mesero
  from public.detalle_pedido d
  where d.id = p_detalle_id and d.pedido_id = v_pedido_id
  for update;

  if not found then
    raise sqlstate 'PT404' using message = 'No se encontró el producto de la comanda.';
  end if;
  if v_atiende_mesero then
    raise sqlstate 'PT403' using message = 'Este producto se confirma desde la entrega de bebidas y postres.';
  end if;
  if v_detalle_estado = p_estado then
    return;
  end if;

  v_siguiente := case v_detalle_estado
    when 'PENDIENTE' then 'EN_PREPARACION'::public.estado_item
    when 'EN_PREPARACION' then 'LISTO'::public.estado_item
    when 'LISTO' then 'ENTREGADO'::public.estado_item
    else null
  end;
  if p_estado is distinct from v_siguiente then
    raise sqlstate 'PT409' using message = 'El producto cambió de estado. Actualiza la comanda e inténtalo de nuevo.';
  end if;

  update public.detalle_pedido
  set estado = p_estado
  where id = p_detalle_id;

  perform public.recalcular_estado_preparacion_comanda(v_pedido_id);
end;
$$;

revoke all on function public.actualizar_estado_item(bigint, public.estado_item)
  from public, anon, authenticated;
grant execute on function public.actualizar_estado_item(bigint, public.estado_item)
  to authenticated;

create or replace function public.entregar_productos_de_mesero(p_pedido_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
begin
  if not exists (
    select 1
    from public.usuarios u
    where u.id = v_actor and u.activo and u.rol = 'MESERO'
  ) then
    raise exception 'Solo un mesero activo puede confirmar esta entrega.';
  end if;

  perform 1
  from public.pedidos p
  where p.id = p_pedido_id
    and p.mesero_id = v_actor
    and p.retirada_en is null
    and p.estado <> 'CANCELADO'
  for update;
  if not found then
    raise exception 'No tienes un pedido abierto con ese número.';
  end if;

  update public.detalle_pedido
  set estado = 'ENTREGADO'
  where pedido_id = p_pedido_id
    and atiende_mesero
    and estado in ('PENDIENTE', 'EN_PREPARACION', 'LISTO');
  if not found then
    return;
  end if;

  perform public.recalcular_estado_preparacion_comanda(p_pedido_id);

  insert into public.auditoria_movimientos (actor_id, actor_rol, accion, entidad, entidad_id)
  values (v_actor, 'MESERO', 'Entregar bebidas y postres', 'pedidos', p_pedido_id::text);
end;
$$;

revoke all on function public.entregar_productos_de_mesero(bigint)
  from public, anon, authenticated;
grant execute on function public.entregar_productos_de_mesero(bigint)
  to authenticated;

commit;
