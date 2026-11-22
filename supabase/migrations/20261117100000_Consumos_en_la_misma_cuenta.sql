create or replace function public.agregar_consumo_cuenta_mesa(
  p_solicitud_id uuid,
  p_pedido_id bigint,
  p_items jsonb
)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_rol text;
  v_solicitud_pedido bigint;
  v_pedido public.pedidos%rowtype;
  v_mesa public.mesas%rowtype;
  v_item jsonb;
  v_platillo_id bigint;
  v_cantidad integer;
  v_precio numeric;
begin
  select u.rol into v_rol
  from public.usuarios u
  where u.id = v_actor and u.activo;
  if v_rol is null or v_rol not in ('MESERO', 'ADMINISTRADOR') then
    raise sqlstate 'PT403' using message = 'No tienes permiso para agregar consumos a la cuenta.';
  end if;

  v_solicitud_pedido := public.pedido_de_solicitud_mesas_unidas(p_solicitud_id);
  if v_solicitud_pedido is not null then
    if v_solicitud_pedido is distinct from p_pedido_id then
      raise sqlstate 'PT409' using message = 'La solicitud ya se usó con otro pedido.';
    end if;
    return v_solicitud_pedido;
  end if;

  -- Billing locks the order before updating the table. Keep that lock order.
  select * into v_pedido
  from public.pedidos p
  where p.id = p_pedido_id
    and p.tipo_pedido = 'MESA'
    and p.mesa_id is not null
    and (p.mesero_id = v_actor or v_rol = 'ADMINISTRADOR')
  for update;
  if not found then
    raise sqlstate 'PT409' using message = 'No tienes una cuenta de mesa con ese número.';
  end if;

  select * into v_mesa
  from public.mesas m
  where m.id = v_pedido.mesa_id and m.activa
  for update;
  if not found then
    raise sqlstate 'PT409' using message = 'La mesa de esta cuenta ya no está disponible.';
  end if;
  if v_mesa.pedido_grupo_id is not null
      and v_mesa.pedido_grupo_id is distinct from p_pedido_id then
    raise sqlstate 'PT409' using message = 'La mesa pertenece a otra cuenta de mesas unidas.';
  end if;
  if v_pedido.mesas_unidas_ids is not null
      and v_mesa.pedido_grupo_id is distinct from p_pedido_id then
    raise sqlstate 'PT409' using message = 'Las mesas de esta cuenta ya no están unidas.';
  end if;
  if v_pedido.retirada_en is not null
      or v_pedido.estado in ('POR_COBRAR', 'PAGADO', 'CANCELADO')
      or v_mesa.estado = 'POR_COBRAR'
      or exists (
        select 1
        from public.pedidos p
        where p.mesa_id = v_pedido.mesa_id
          and p.retirada_en is null
          and p.estado <> 'CANCELADO'
          and (
            p.estado in ('POR_COBRAR', 'PAGADO')
            or exists (select 1 from public.pagos a where a.pedido_id = p.id)
          )
      ) then
    raise sqlstate 'PT409' using message = 'La cuenta de esta mesa ya está cerrada o en cobro.';
  end if;

  if jsonb_typeof(p_items) is distinct from 'array' then
    raise exception 'El consumo debe incluir al menos un producto.';
  end if;
  if jsonb_array_length(p_items) = 0 then
    raise exception 'El consumo debe incluir al menos un producto.';
  end if;

  -- Each later round has new details. Already prepared or delivered details
  -- retain their quantities, recorded prices and delivery states.
  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_platillo_id := (v_item ->> 'platillo_id')::bigint;
    v_cantidad := (v_item ->> 'cantidad')::integer;
    if v_cantidad is null or v_cantidad < 1 then
      raise exception 'La cantidad de cada producto debe ser mayor que cero.';
    end if;
    select p.precio into v_precio
    from public.platillos p
    where p.id = v_platillo_id and p.activo and not p.agotado;
    if not found then
      raise exception 'Un producto ya no está disponible.';
    end if;

    insert into public.detalle_pedido (
      pedido_id, platillo_id, cantidad, precio_unitario, observaciones
    )
    values (
      p_pedido_id, v_platillo_id, v_cantidad, v_precio,
      coalesce(v_item ->> 'observaciones', '')
    );
  end loop;

  update public.pedidos
  set estado = 'PENDIENTE'
  where id = p_pedido_id and estado <> 'PENDIENTE';

  insert into public.solicitudes_pedido_sync (solicitud_id, usuario_id, pedido_id)
  values (p_solicitud_id, v_actor, p_pedido_id);

  insert into public.auditoria_movimientos (
    actor_id, actor_rol, accion, entidad, entidad_id
  )
  values (
    v_actor, v_rol, 'Agregar consumo a la cuenta', 'pedidos', p_pedido_id::text
  );
  return p_pedido_id;
end;
$$;

-- Preserve the existing RPC for installations that still use its group name.
create or replace function public.agregar_consumo_mesas_unidas(
  p_solicitud_id uuid,
  p_pedido_id bigint,
  p_items jsonb
)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not exists (
    select 1 from public.pedidos p
    where p.id = p_pedido_id and p.mesas_unidas_ids is not null
  ) then
    raise sqlstate 'PT409' using message = 'Selecciona una cuenta de mesas unidas.';
  end if;
  return public.agregar_consumo_cuenta_mesa(
    p_solicitud_id, p_pedido_id, p_items
  );
end;
$$;

revoke all on function public.agregar_consumo_cuenta_mesa(uuid, bigint, jsonb)
  from public, anon, authenticated;
grant execute on function public.agregar_consumo_cuenta_mesa(uuid, bigint, jsonb)
  to authenticated;

revoke all on function public.agregar_consumo_mesas_unidas(uuid, bigint, jsonb)
  from public, anon, authenticated;
grant execute on function public.agregar_consumo_mesas_unidas(uuid, bigint, jsonb)
  to authenticated;
