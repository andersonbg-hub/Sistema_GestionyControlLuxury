alter table public.pedidos
  alter column mesa_id drop not null,
  add column if not exists tipo_pedido text not null default 'MESA',
  add column if not exists cliente_nombre text not null default '',
  add column if not exists cliente_telefono text not null default '',
  add column if not exists direccion_entrega text not null default '';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'pedidos_tipo_pedido_check'
      and conrelid = 'public.pedidos'::regclass
  ) then
    alter table public.pedidos
      add constraint pedidos_tipo_pedido_check
      check (tipo_pedido in ('MESA', 'PARA_LLEVAR', 'DELIVERY'));
  end if;
end
$$;

create or replace function public.crear_pedido_entrega(
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
  v_item jsonb;
  v_platillo_id bigint;
  v_cantidad integer;
  v_precio numeric;
  v_rol text;
begin
  if auth.uid() is null then
    raise exception 'Se requiere una sesión autenticada.';
  end if;

  select rol into v_rol
  from public.usuarios
  where id = auth.uid() and activo = true;
  if v_rol is null or v_rol not in ('MESERO', 'ADMINISTRADOR') then
    raise exception 'No tienes permiso para registrar pedidos.';
  end if;

  if p_tipo_pedido not in ('PARA_LLEVAR', 'DELIVERY') then
    raise exception 'El tipo de pedido no es válido.';
  end if;
  if nullif(trim(p_cliente_nombre), '') is null
      or nullif(trim(p_cliente_telefono), '') is null then
    raise exception 'Indica el nombre y teléfono del cliente.';
  end if;
  if p_tipo_pedido = 'DELIVERY'
      and nullif(trim(p_direccion_entrega), '') is null then
    raise exception 'Indica la dirección de entrega.';
  end if;
  if p_items is null
      or jsonb_typeof(p_items) <> 'array'
      or jsonb_array_length(p_items) = 0 then
    raise exception 'El pedido debe incluir al menos un platillo.';
  end if;

  insert into public.pedidos (
    mesa_id,
    comensales,
    pedido_padre_id,
    mesero_id,
    tipo_pedido,
    cliente_nombre,
    cliente_telefono,
    direccion_entrega
  ) values (
    null,
    1,
    null,
    auth.uid(),
    p_tipo_pedido,
    trim(p_cliente_nombre),
    trim(p_cliente_telefono),
    case when p_tipo_pedido = 'DELIVERY' then trim(p_direccion_entrega) else '' end
  )
  returning id into v_pedido_id;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_platillo_id := (v_item ->> 'platillo_id')::bigint;
    v_cantidad := (v_item ->> 'cantidad')::integer;
    if v_cantidad < 1 then
      raise exception 'La cantidad de cada platillo debe ser mayor que cero.';
    end if;

    select precio into v_precio
    from public.platillos
    where id = v_platillo_id and agotado = false;
    if not found then
      raise exception 'Un platillo ya no está disponible.';
    end if;

    insert into public.detalle_pedido (
      pedido_id,
      platillo_id,
      cantidad,
      precio_unitario,
      observaciones
    ) values (
      v_pedido_id,
      v_platillo_id,
      v_cantidad,
      v_precio,
      coalesce(v_item ->> 'observaciones', '')
    );
  end loop;

  return v_pedido_id;
end;
$$;

create table if not exists public.solicitudes_pedido_sync (
  solicitud_id uuid primary key,
  usuario_id uuid not null references auth.users(id) on delete cascade,
  pedido_id bigint not null references public.pedidos(id) on delete cascade,
  creado_en timestamptz not null default now()
);

alter table public.solicitudes_pedido_sync enable row level security;

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
    v_pedido_id := public.crear_pedido(
      p_mesa_id,
      p_comensales,
      p_items,
      p_pedido_padre_id
    );
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

revoke all on function public.crear_pedido_entrega(text, text, text, text, jsonb)
  from public;
grant execute on function public.crear_pedido_entrega(text, text, text, text, jsonb)
  to authenticated;
revoke all on function public.crear_pedido_sincronizado(
  uuid, bigint, integer, bigint, text, text, text, text, jsonb
) from public;
grant execute on function public.crear_pedido_sincronizado(
  uuid, bigint, integer, bigint, text, text, text, text, jsonb
) to authenticated;