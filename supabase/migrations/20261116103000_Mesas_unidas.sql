alter table public.mesas
  add column if not exists pedido_grupo_id bigint references public.pedidos(id);

alter table public.pedidos
  add column if not exists mesas_unidas_ids bigint[],
  add column if not exists mesas_unidas_numeros integer[];

create index if not exists mesas_pedido_grupo_idx
  on public.mesas (pedido_grupo_id)
  where pedido_grupo_id is not null;

-- The existing single-table order RPCs also pass through this trigger.
create or replace function public.evitar_pedido_paralelo_en_mesas_unidas()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_grupo_id bigint;
begin
  if new.mesa_id is null or new.retirada_en is not null then
    return new;
  end if;

  select m.pedido_grupo_id into v_grupo_id
  from public.mesas m where m.id = new.mesa_id
  for update;
  if v_grupo_id is not null then
    raise sqlstate 'PT409' using message = 'La mesa pertenece a un grupo. Agrega el consumo a su pedido abierto.';
  end if;
  return new;
end;
$$;

drop trigger if exists evitar_pedido_paralelo_en_mesas_unidas on public.pedidos;
create trigger evitar_pedido_paralelo_en_mesas_unidas
before insert on public.pedidos
for each row execute function public.evitar_pedido_paralelo_en_mesas_unidas();

-- An older path may try to free the primary table before marking the order
-- retired. Group availability is reconciled by the order trigger below.
create or replace function public.proteger_mesas_unidas()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if old.pedido_grupo_id is not null then
      raise sqlstate 'PT409' using message = 'La mesa forma parte de un grupo en servicio.';
    end if;
    return old;
  elsif tg_op = 'INSERT' then
    if new.pedido_grupo_id is not null and current_user in ('anon', 'authenticated') then
      raise sqlstate 'PT403' using message = 'Registra la unión desde el pedido de las mesas.';
    end if;
    return new;
  end if;

  if new.pedido_grupo_id is distinct from old.pedido_grupo_id
      and current_user in ('anon', 'authenticated') then
    raise sqlstate 'PT403' using message = 'Actualiza la unión desde el pedido de las mesas.';
  end if;

  if old.pedido_grupo_id is not null then
    if new.numero is distinct from old.numero
        or new.capacidad is distinct from old.capacidad
        or new.activa is distinct from old.activa then
      raise sqlstate 'PT409' using message = 'Libera las mesas unidas antes de cambiar sus datos.';
    end if;
    if new.pedido_grupo_id is not null and (
        new.estado = 'DISPONIBLE'
        or (old.estado = 'POR_COBRAR' and new.estado = 'OCUPADA')
      ) then
      new.estado := old.estado;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists proteger_mesas_unidas on public.mesas;
create trigger proteger_mesas_unidas
before insert or update or delete on public.mesas
for each row execute function public.proteger_mesas_unidas();

create or replace function public.proteger_datos_pedido_mesas_unidas()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user in ('anon', 'authenticated') then
    if tg_op = 'INSERT' then
      if new.mesas_unidas_ids is not null or new.mesas_unidas_numeros is not null then
        raise sqlstate 'PT403' using message = 'Registra la unión desde el pedido de las mesas.';
      end if;
    elsif new.mesas_unidas_ids is distinct from old.mesas_unidas_ids
        or new.mesas_unidas_numeros is distinct from old.mesas_unidas_numeros then
      raise sqlstate 'PT403' using message = 'Actualiza la unión desde el pedido de las mesas.';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists proteger_datos_pedido_mesas_unidas on public.pedidos;
create trigger proteger_datos_pedido_mesas_unidas
before insert or update of mesas_unidas_ids, mesas_unidas_numeros on public.pedidos
for each row execute function public.proteger_datos_pedido_mesas_unidas();

create or replace function public.sincronizar_estado_mesas_unidas()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.mesas_unidas_ids is null then
    return new;
  end if;
  if new.retirada_en is not null and old.retirada_en is null then
    if new.estado not in ('PAGADO', 'CANCELADO') or (
        new.estado = 'PAGADO' and exists (
          select 1 from public.detalle_pedido d
          where d.pedido_id = new.id and d.estado <> 'ENTREGADO'
        )
      ) then
      raise sqlstate 'PT409' using message = 'Completa la entrega y el cobro antes de liberar las mesas.';
    end if;
    update public.mesas
    set pedido_grupo_id = null, estado = 'DISPONIBLE'
    where pedido_grupo_id = new.id;
  elsif new.retirada_en is null and new.estado in ('POR_COBRAR', 'PAGADO')
      and old.estado not in ('POR_COBRAR', 'PAGADO') then
    update public.mesas set estado = 'POR_COBRAR'
    where pedido_grupo_id = new.id and estado <> 'POR_COBRAR';
  end if;
  return new;
end;
$$;

drop trigger if exists sincronizar_estado_mesas_unidas on public.pedidos;
create trigger sincronizar_estado_mesas_unidas
after update of estado, retirada_en on public.pedidos
for each row execute function public.sincronizar_estado_mesas_unidas();

create or replace function public.rol_para_mesas_unidas()
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_rol text;
begin
  select u.rol into v_rol
  from public.usuarios u where u.id = auth.uid() and u.activo;
  if v_rol is null or v_rol not in ('MESERO', 'ADMINISTRADOR') then
    raise sqlstate 'PT403' using message = 'No tienes permiso para gestionar mesas unidas.';
  end if;
  return v_rol;
end;
$$;

-- Use the same request lock and ledger as regular synchronized orders.
create or replace function public.pedido_de_solicitud_mesas_unidas(p_solicitud_id uuid)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_solicitud public.solicitudes_pedido_sync%rowtype;
begin
  if v_actor_id is null or p_solicitud_id is null then
    raise exception 'Se requiere una sesión y un identificador de solicitud.';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(v_actor_id::text || ':' || p_solicitud_id::text, 0)
  );
  select * into v_solicitud
  from public.solicitudes_pedido_sync s where s.solicitud_id = p_solicitud_id;
  if v_solicitud.usuario_id is not null and v_solicitud.usuario_id <> v_actor_id then
    raise exception 'El identificador de solicitud ya pertenece a otro usuario.';
  end if;
  return v_solicitud.pedido_id;
end;
$$;

create or replace function public.crear_pedido_mesas_unidas(
  p_solicitud_id uuid,
  p_mesas_ids bigint[],
  p_comensales integer,
  p_items jsonb
)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_rol text := public.rol_para_mesas_unidas();
  v_pedido_id bigint := public.pedido_de_solicitud_mesas_unidas(p_solicitud_id);
  v_mesas_ids bigint[];
  v_numeros integer[];
  v_capacidad bigint;
  v_capacidad_principal integer;
  v_cantidad_bloqueada bigint;
begin
  if coalesce(array_ndims(p_mesas_ids), 0) <> 1 or cardinality(p_mesas_ids) < 2
      or cardinality(p_mesas_ids) <> (
        select count(distinct mesa_id) from unnest(p_mesas_ids) as elegidas(mesa_id)
      ) then
    raise exception 'Selecciona dos o más mesas diferentes.';
  end if;

  if v_pedido_id is not null then
    if not exists (
      select 1 from public.pedidos p
      where p.id = v_pedido_id and p.mesas_unidas_ids <@ p_mesas_ids
        and p.mesas_unidas_ids @> p_mesas_ids
    ) then
      raise sqlstate 'PT409' using message = 'La solicitud ya se usó con otro pedido.';
    end if;
    return v_pedido_id;
  end if;

  -- Lock in a stable order so concurrent selections serialize together.
  perform m.id from public.mesas m
  where m.id = any(p_mesas_ids) and m.activa and m.estado = 'DISPONIBLE'
    and m.pedido_grupo_id is null
  order by m.id
  for update;
  get diagnostics v_cantidad_bloqueada = row_count;
  if v_cantidad_bloqueada <> cardinality(p_mesas_ids) then
    raise sqlstate 'PT409' using message = 'Alguna de las mesas ya no está disponible.';
  end if;
  select array_agg(m.id order by m.numero, m.id),
         array_agg(m.numero::integer order by m.numero, m.id),
         sum(m.capacidad)
  into v_mesas_ids, v_numeros, v_capacidad
  from public.mesas m
  where m.id = any(p_mesas_ids) and m.activa and m.estado = 'DISPONIBLE'
    and m.pedido_grupo_id is null
    and not exists (
      select 1 from public.pedidos p where p.mesa_id = m.id and p.retirada_en is null
    );

  if coalesce(cardinality(v_mesas_ids), 0) <> cardinality(p_mesas_ids) then
    raise sqlstate 'PT409' using message = 'Alguna de las mesas ya no está disponible.';
  end if;
  if p_comensales is null or p_comensales < 1 or p_comensales > v_capacidad then
    raise exception 'Los comensales deben estar entre 1 y la capacidad de las mesas unidas.';
  end if;

  select m.capacidad into v_capacidad_principal
  from public.mesas m where m.id = v_mesas_ids[1];

  -- Keep the original checkout, inventory and order creation logic. Its seat
  -- validation knows the primary physical table only.
  v_pedido_id := public.crear_pedido(
    v_mesas_ids[1], least(p_comensales, v_capacidad_principal), p_items, null
  );
  update public.pedidos
  set comensales = p_comensales,
      mesas_unidas_ids = v_mesas_ids,
      mesas_unidas_numeros = v_numeros
  where id = v_pedido_id;

  update public.mesas
  set pedido_grupo_id = v_pedido_id, estado = 'OCUPADA'
  where id = any(v_mesas_ids);

  insert into public.solicitudes_pedido_sync (solicitud_id, usuario_id, pedido_id)
  values (p_solicitud_id, auth.uid(), v_pedido_id);

  insert into public.auditoria_movimientos (actor_id, actor_rol, accion, entidad, entidad_id)
  values (auth.uid(), v_rol, 'Juntar mesas', 'pedidos', v_pedido_id::text);
  return v_pedido_id;
end;
$$;

create or replace function public.pedido_para_cambiar_mesas_unidas(
  p_pedido_id bigint,
  p_rol text
)
returns public.pedidos
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pedido public.pedidos%rowtype;
begin
  select * into v_pedido
  from public.pedidos p
  where p.id = p_pedido_id and p.mesas_unidas_ids is not null
    and (p.mesero_id = auth.uid() or p_rol = 'ADMINISTRADOR')
  for update;
  if not found then
    raise sqlstate 'PT409' using message = 'No tienes un pedido de mesas unidas con ese número.';
  end if;
  return v_pedido;
end;
$$;

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
declare
  v_rol text := public.rol_para_mesas_unidas();
  v_solicitud_pedido bigint := public.pedido_de_solicitud_mesas_unidas(p_solicitud_id);
  v_pedido public.pedidos%rowtype;
  v_item jsonb;
  v_platillo_id bigint;
  v_cantidad integer;
  v_precio numeric;
begin
  if v_solicitud_pedido is not null then
    if v_solicitud_pedido is distinct from p_pedido_id then
      raise sqlstate 'PT409' using message = 'La solicitud ya se usó con otro pedido.';
    end if;
    return v_solicitud_pedido;
  end if;

  v_pedido := public.pedido_para_cambiar_mesas_unidas(p_pedido_id, v_rol);
  if v_pedido.retirada_en is not null
      or v_pedido.estado in ('POR_COBRAR', 'PAGADO', 'CANCELADO')
      or exists (select 1 from public.pagos p where p.pedido_id = p_pedido_id) then
    raise sqlstate 'PT409' using message = 'El pedido de estas mesas ya está cerrado o en cobro.';
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' then
    raise exception 'El pedido debe incluir al menos un platillo.';
  end if;
  if jsonb_array_length(p_items) = 0 then
    raise exception 'El pedido debe incluir al menos un platillo.';
  end if;

  -- Match the existing detail insertion path for additional consumption.
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
    values (p_pedido_id, v_platillo_id, v_cantidad, v_precio, coalesce(v_item ->> 'observaciones', ''));
  end loop;

  update public.pedidos set estado = 'PENDIENTE'
  where id = p_pedido_id and estado <> 'PENDIENTE';

  insert into public.solicitudes_pedido_sync (solicitud_id, usuario_id, pedido_id)
  values (p_solicitud_id, auth.uid(), p_pedido_id);

  insert into public.auditoria_movimientos (actor_id, actor_rol, accion, entidad, entidad_id)
  values (auth.uid(), v_rol, 'Agregar consumo a mesas unidas', 'pedidos', p_pedido_id::text);
  return p_pedido_id;
end;
$$;

create or replace function public.editar_pedido_mesas_unidas(
  p_pedido_id bigint,
  p_comensales integer,
  p_items jsonb
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_rol text := public.rol_para_mesas_unidas();
  v_pedido public.pedidos%rowtype := public.pedido_para_cambiar_mesas_unidas(p_pedido_id, v_rol);
  v_capacidad bigint;
  v_capacidad_principal integer;
begin
  if v_pedido.retirada_en is not null or v_pedido.estado <> 'PENDIENTE'
      or exists (select 1 from public.pagos p where p.pedido_id = p_pedido_id)
      or exists (
        select 1 from public.detalle_pedido d
        where d.pedido_id = p_pedido_id and d.estado <> 'PENDIENTE'
      ) then
    raise sqlstate 'PT409' using message = 'Solo se edita un pedido pendiente y sin abonos.';
  end if;

  select sum(m.capacidad), max(m.capacidad) filter (where m.id = v_pedido.mesa_id)
  into v_capacidad, v_capacidad_principal
  from public.mesas m where m.pedido_grupo_id = p_pedido_id;
  if v_capacidad_principal is null then
    raise sqlstate 'PT409' using message = 'Las mesas del pedido ya no están unidas.';
  end if;
  if p_comensales is null or p_comensales < 1 or p_comensales > v_capacidad then
    raise exception 'Los comensales deben estar entre 1 y la capacidad de las mesas unidas.';
  end if;

  perform public.editar_pedido(p_pedido_id, least(p_comensales, v_capacidad_principal), p_items);
  update public.pedidos set comensales = p_comensales where id = p_pedido_id;
end;
$$;

create or replace function public.confirmar_retiro_mesas_unidas(p_pedido_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rol text := public.rol_para_mesas_unidas();
  v_pedido public.pedidos%rowtype := public.pedido_para_cambiar_mesas_unidas(p_pedido_id, v_rol);
begin
  if v_pedido.retirada_en is not null then
    return;
  end if;
  if v_pedido.estado not in ('PAGADO', 'CANCELADO') or (
      v_pedido.estado = 'PAGADO' and exists (
        select 1 from public.detalle_pedido d
        where d.pedido_id = p_pedido_id and d.estado <> 'ENTREGADO'
      )
    ) then
    raise sqlstate 'PT409' using message = 'Completa la entrega y el cobro antes de liberar las mesas.';
  end if;
  if not exists (
    select 1 from public.mesas m where m.id = v_pedido.mesa_id and m.pedido_grupo_id = p_pedido_id
  ) then
    raise sqlstate 'PT409' using message = 'Las mesas del pedido ya no están unidas.';
  end if;

  perform public.confirmar_retiro_mesa(v_pedido.mesa_id);
  if not exists (
    select 1 from public.pedidos p where p.id = p_pedido_id and p.retirada_en is not null
  ) then
    raise sqlstate 'PT409' using message = 'El retiro de estas mesas quedó pendiente.';
  end if;
end;
$$;

revoke all on function public.evitar_pedido_paralelo_en_mesas_unidas() from public, anon, authenticated;
revoke all on function public.proteger_mesas_unidas() from public, anon, authenticated;
revoke all on function public.proteger_datos_pedido_mesas_unidas() from public, anon, authenticated;
revoke all on function public.sincronizar_estado_mesas_unidas() from public, anon, authenticated;
revoke all on function public.rol_para_mesas_unidas() from public, anon, authenticated;
revoke all on function public.pedido_de_solicitud_mesas_unidas(uuid) from public, anon, authenticated;
revoke all on function public.pedido_para_cambiar_mesas_unidas(bigint, text) from public, anon, authenticated;

revoke all on function public.crear_pedido_mesas_unidas(uuid, bigint[], integer, jsonb)
  from public, anon, authenticated;
grant execute on function public.crear_pedido_mesas_unidas(uuid, bigint[], integer, jsonb)
  to authenticated;
revoke all on function public.agregar_consumo_mesas_unidas(uuid, bigint, jsonb)
  from public, anon, authenticated;
grant execute on function public.agregar_consumo_mesas_unidas(uuid, bigint, jsonb)
  to authenticated;
revoke all on function public.editar_pedido_mesas_unidas(bigint, integer, jsonb)
  from public, anon, authenticated;
grant execute on function public.editar_pedido_mesas_unidas(bigint, integer, jsonb)
  to authenticated;
revoke all on function public.confirmar_retiro_mesas_unidas(bigint)
  from public, anon, authenticated;
grant execute on function public.confirmar_retiro_mesas_unidas(bigint)
  to authenticated;

