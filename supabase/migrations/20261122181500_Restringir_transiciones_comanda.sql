begin;

set local lock_timeout = '3s';
set local statement_timeout = '20s';

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
  v_estado_agregado public.estado_pedido;
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

  select d.estado into v_detalle_estado
  from public.detalle_pedido d
  where d.id = p_detalle_id and d.pedido_id = v_pedido_id
  for update;

  if not found then
    raise sqlstate 'PT404' using message = 'No se encontró el producto de la comanda.';
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

  if exists (
    select 1 from public.detalle_pedido
    where pedido_id = v_pedido_id and estado = 'EN_PREPARACION'
  ) then
    v_estado_agregado := 'EN_PREPARACION';
  elsif exists (
    select 1 from public.detalle_pedido
    where pedido_id = v_pedido_id and estado = 'PENDIENTE'
  ) then
    v_estado_agregado := 'PENDIENTE';
  else
    v_estado_agregado := 'LISTO';
  end if;

  update public.pedidos
  set estado = v_estado_agregado, actualizado_en = pg_catalog.now()
  where id = v_pedido_id and estado not in ('PAGADO', 'POR_COBRAR', 'CANCELADO');
end;
$$;

revoke all on function public.actualizar_estado_item(bigint, public.estado_item)
  from public, anon, authenticated;
grant execute on function public.actualizar_estado_item(bigint, public.estado_item)
  to authenticated;

commit;
