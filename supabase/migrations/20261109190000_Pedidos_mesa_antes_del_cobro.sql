-- Keep new comandas and the start of billing serialized on the same mesa.
create or replace function public.validar_alta_pedido_mesa()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_estado_mesa text;
begin
  if new.mesa_id is null or new.retirada_en is not null then
    return new;
  end if;

  select m.estado::text into v_estado_mesa
  from public.mesas m
  where m.id = new.mesa_id and m.activa
  for update;
  if not found then
    raise sqlstate 'PT409' using message = 'La mesa ya no está disponible.';
  end if;

  if v_estado_mesa = 'POR_COBRAR' or exists (
    select 1 from public.pedidos p
    where p.mesa_id = new.mesa_id and p.retirada_en is null
      and p.estado <> 'CANCELADO'
      and (
        p.estado in ('POR_COBRAR', 'PAGADO')
        or exists (select 1 from public.pagos a where a.pedido_id = p.id)
      )
  ) then
    raise sqlstate 'PT409' using message = 'La mesa ya está en cobro y no admite más pedidos.';
  end if;

  if new.pedido_padre_id is not null then
    if not exists (
      select 1 from public.pedidos p
      where p.id = new.pedido_padre_id
        and p.mesa_id = new.mesa_id
        and p.retirada_en is null
        and p.estado not in ('POR_COBRAR', 'PAGADO', 'CANCELADO')
    ) then
      raise sqlstate 'PT409' using message = 'El pedido principal ya no está abierto en esta mesa.';
    end if;
  elsif exists (
    select 1 from public.pedidos p
    where p.mesa_id = new.mesa_id and p.retirada_en is null
  ) then
    raise sqlstate 'PT409' using message = 'Agrega el consumo al pedido abierto de esta mesa.';
  end if;
  return new;
end;
$$;

drop trigger if exists validar_alta_pedido_mesa on public.pedidos;
create trigger validar_alta_pedido_mesa before insert on public.pedidos
for each row execute function public.validar_alta_pedido_mesa();

create or replace function public.bloquear_mesa_al_iniciar_cobro()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.mesa_id is not null and new.estado is distinct from old.estado
      and new.estado in ('POR_COBRAR', 'PAGADO') then
    perform 1 from public.mesas where id = new.mesa_id for update;
  end if;
  return new;
end;
$$;

drop trigger if exists bloquear_mesa_al_iniciar_cobro on public.pedidos;
create trigger bloquear_mesa_al_iniciar_cobro before update of estado on public.pedidos
for each row execute function public.bloquear_mesa_al_iniciar_cobro();

create or replace function public.crear_consumo_mesa(
  p_mesa_id bigint,
  p_comensales integer,
  p_items jsonb,
  p_pedido_padre_id bigint
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_rol text;
  v_capacidad integer;
  v_pedido_id bigint;
  v_item jsonb;
  v_platillo_id bigint;
  v_cantidad integer;
  v_precio numeric;
begin
  select u.rol into v_rol
  from public.usuarios u
  where u.id = v_actor and u.activo;
  if v_rol is null or v_rol not in ('MESERO', 'ADMINISTRADOR') then
    raise exception 'No tienes permiso para registrar pedidos.';
  end if;

  select m.capacidad into v_capacidad
  from public.mesas m
  where m.id = p_mesa_id and m.activa
  for update;
  if not found then
    raise sqlstate 'PT409' using message = 'La mesa ya no está disponible.';
  end if;
  if p_comensales is null or p_comensales < 1 or p_comensales > v_capacidad then
    raise exception 'Los comensales deben estar entre 1 y la capacidad de la mesa.';
  end if;
  if p_pedido_padre_id is null then
    raise exception 'Selecciona el pedido principal del consumo.';
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' then
    raise exception 'El pedido debe incluir al menos un platillo.';
  end if;
  if jsonb_array_length(p_items) = 0 then
    raise exception 'El pedido debe incluir al menos un platillo.';
  end if;

  insert into public.pedidos (mesa_id, comensales, pedido_padre_id, mesero_id, tipo_pedido)
  values (p_mesa_id, p_comensales, p_pedido_padre_id, v_actor, 'MESA')
  returning id into v_pedido_id;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_platillo_id := (v_item ->> 'platillo_id')::bigint;
    v_cantidad := (v_item ->> 'cantidad')::integer;
    if v_cantidad is null or v_cantidad < 1 then
      raise exception 'La cantidad de cada platillo debe ser mayor que cero.';
    end if;
    select p.precio into v_precio from public.platillos p
    where p.id = v_platillo_id and p.activo and not p.agotado;
    if not found then
      raise exception 'Un platillo ya no está disponible.';
    end if;

    insert into public.detalle_pedido (pedido_id, platillo_id, cantidad, precio_unitario, observaciones)
    values (v_pedido_id, v_platillo_id, v_cantidad, v_precio, coalesce(v_item ->> 'observaciones', ''));
  end loop;

  update public.mesas set estado = 'OCUPADA'
  where id = p_mesa_id and estado = 'DISPONIBLE';

  insert into public.auditoria_movimientos (actor_id, actor_rol, accion, entidad, entidad_id)
  values (v_actor, v_rol, 'Agregar pedido a la mesa', 'pedidos', v_pedido_id::text);

  return v_pedido_id;
end;
$$;

revoke all on function public.validar_alta_pedido_mesa() from public, anon, authenticated;
revoke all on function public.bloquear_mesa_al_iniciar_cobro() from public, anon, authenticated;
revoke all on function public.crear_consumo_mesa(bigint, integer, jsonb, bigint) from public, anon, authenticated;

create or replace function public.crear_pedido_sincronizado(
  p_solicitud_id uuid,
  p_mesa_id bigint,
  p_comensales integer,
  p_pedido_padre_id bigint,
  p_tipo_pedido text,
  p_cliente_nombre text,
  p_cliente_telefono text,
  p_direccion_entrega text,
  p_items jsonb
)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_pedido_id bigint;
  v_usuario_id uuid := auth.uid();
begin
  if v_usuario_id is null or p_solicitud_id is null then
    raise exception 'Se requiere una sesión y un identificador de solicitud.';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(v_usuario_id::text || ':' || p_solicitud_id::text, 0)
  );
  select pedido_id into v_pedido_id
  from public.solicitudes_pedido_sync
  where solicitud_id = p_solicitud_id and usuario_id = v_usuario_id;
  if found then
    return v_pedido_id;
  end if;
  if exists (
    select 1
    from public.solicitudes_pedido_sync
    where solicitud_id = p_solicitud_id
  ) then
    raise exception 'El identificador de solicitud ya pertenece a otro usuario.';
  end if;

  if p_tipo_pedido = 'MESA' then
    if p_mesa_id is null then
      raise exception 'Selecciona una mesa para el pedido.';
    end if;
    if p_pedido_padre_id is null then
      v_pedido_id := public.crear_pedido(p_mesa_id, p_comensales, p_items, null);
    else
      v_pedido_id := public.crear_consumo_mesa(
        p_mesa_id, p_comensales, p_items, p_pedido_padre_id
      );
    end if;
  elsif p_tipo_pedido in ('PARA_LLEVAR', 'DELIVERY') then
    if p_pedido_padre_id is not null then
      raise exception 'El pedido adicional debe estar asociado a una mesa.';
    end if;
    v_pedido_id := public.crear_pedido_entrega(
      p_tipo_pedido,
      p_cliente_nombre,
      p_cliente_telefono,
      p_direccion_entrega,
      p_items
    );
  else
    raise exception 'El tipo de pedido no es válido.';
  end if;

  insert into public.solicitudes_pedido_sync (
    solicitud_id,
    usuario_id,
    pedido_id
  ) values (p_solicitud_id, v_usuario_id, v_pedido_id);
  return v_pedido_id;
end;
$$;

revoke all on function public.crear_pedido_sincronizado(
  uuid, bigint, integer, bigint, text, text, text, text, jsonb
) from public;
grant execute on function public.crear_pedido_sincronizado(
  uuid, bigint, integer, bigint, text, text, text, text, jsonb
) to authenticated;