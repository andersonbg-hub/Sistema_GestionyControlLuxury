alter table public.detalle_pedido
  add column if not exists atiende_mesero boolean not null default false;

-- Route drinks and desserts for service still in progress.
update public.detalle_pedido d
set atiende_mesero = true
from public.platillos pl
join public.categorias c on c.id = pl.categoria_id,
public.pedidos p
where d.platillo_id = pl.id
  and d.pedido_id = p.id
  and p.retirada_en is null
  and p.estado <> 'CANCELADO'
  and d.estado in ('PENDIENTE', 'EN_PREPARACION', 'LISTO')
  and lower(btrim(c.nombre)) in ('bebida', 'bebidas', 'postre', 'postres');

create or replace function public.asignar_servicio_detalle_pedido()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if new.platillo_id is not distinct from old.platillo_id then
      new.atiende_mesero := old.atiende_mesero;
      return new;
    end if;
  end if;

  new.atiende_mesero := exists (
    select 1
    from public.platillos pl
    join public.categorias c on c.id = pl.categoria_id
    where pl.id = new.platillo_id
      and lower(btrim(c.nombre)) in ('bebida', 'bebidas', 'postre', 'postres')
  );
  return new;
end;
$$;

revoke all on function public.asignar_servicio_detalle_pedido()
  from public, anon, authenticated;

drop trigger if exists asignar_servicio_detalle_pedido on public.detalle_pedido;
create trigger asignar_servicio_detalle_pedido
before insert or update of platillo_id, atiende_mesero on public.detalle_pedido
for each row execute function public.asignar_servicio_detalle_pedido();

create or replace function public.entregar_productos_de_mesero(p_pedido_id bigint)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
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

  update public.pedidos p
  set estado = 'LISTO'
  where p.id = p_pedido_id
    and p.estado in ('PENDIENTE', 'EN_PREPARACION')
    and not exists (
      select 1
      from public.detalle_pedido d
      where d.pedido_id = p.id and d.estado <> 'ENTREGADO'
    );

  insert into public.auditoria_movimientos (actor_id, actor_rol, accion, entidad, entidad_id)
  values (v_actor, 'MESERO', 'Entregar bebidas y postres', 'pedidos', p_pedido_id::text);
end;
$$;

revoke all on function public.entregar_productos_de_mesero(bigint)
  from public, anon, authenticated;
grant execute on function public.entregar_productos_de_mesero(bigint)
  to authenticated;
