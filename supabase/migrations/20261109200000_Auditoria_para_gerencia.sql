-- Capture a human-readable name at the time of the event.
alter table public.auditoria_movimientos
  add column if not exists actor_nombre text,
  add column if not exists actor_cuenta text;

create or replace function public.identificar_autor_auditoria()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  select nullif(btrim(u.nombre_completo), ''), nullif(btrim(u.correo), '')
    into new.actor_nombre, new.actor_cuenta
  from public.usuarios u
  where u.id::text = new.actor_id::text;
  return new;
end;
$$;

drop trigger if exists identificar_autor_auditoria on public.auditoria_movimientos;
create trigger identificar_autor_auditoria
before insert on public.auditoria_movimientos
for each row execute function public.identificar_autor_auditoria();

-- Register operational changes that otherwise appear only as generic UPDATE entries.
create or replace function public.registrar_movimiento_gerencial()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_rol text;
  v_accion text;
begin
  if v_actor is null then
    return new;
  end if;
  select u.rol::text into v_rol from public.usuarios u where u.id = v_actor;
  if not found then return new; end if;

  case tg_table_name
    when 'pedidos' then
      if new.estado is distinct from old.estado and new.estado::text = 'CANCELADO' then
        v_accion := 'Cancelar pedido';
      elsif new.incidencia_cocina is distinct from old.incidencia_cocina
          and nullif(btrim(new.incidencia_cocina), '') is not null then
        v_accion := 'Reportar incidencia de cocina';
      elsif new.solucion_incidencia_cocina is distinct from old.solucion_incidencia_cocina
          and nullif(btrim(new.solucion_incidencia_cocina), '') is not null then
        v_accion := 'Resolver incidencia de cocina';
      elsif new.estado is distinct from old.estado and new.estado::text = 'POR_COBRAR'
          and v_rol in ('MESERO', 'ADMINISTRADOR')
          and not exists (select 1 from public.pagos where pedido_id = new.id) then
        v_accion := 'Solicitar cuenta';
      end if;
    when 'pagos' then
      v_accion := 'Registrar pago';
    when 'notas_venta' then
      if new.estado is distinct from old.estado and new.estado::text = 'ANULADO' then
        v_accion := 'Anular nota de venta';
      end if;
    when 'alertas_cocina' then
      v_accion := 'Crear alerta de cocina';
    when 'insumos' then
      if old.activo and not new.activo then
        v_accion := 'Archivar insumo';
      end if;
    when 'usuarios' then
      if new.activo is distinct from old.activo then
        v_accion := case when new.activo then 'Activar usuario' else 'Desactivar usuario' end;
      elsif new.rol is distinct from old.rol then
        v_accion := 'Cambiar rol de usuario';
      end if;
  end case;

  if v_accion is not null then
    insert into public.auditoria_movimientos
      (actor_id, actor_rol, accion, entidad, entidad_id)
    values (v_actor, v_rol, v_accion, tg_table_name, new.id::text);
  end if;
  return new;
end;
$$;

drop trigger if exists auditoria_gerencial_pedidos on public.pedidos;
create trigger auditoria_gerencial_pedidos
after update of estado, incidencia_cocina, solucion_incidencia_cocina on public.pedidos
for each row execute function public.registrar_movimiento_gerencial();

drop trigger if exists auditoria_gerencial_pagos on public.pagos;
create trigger auditoria_gerencial_pagos
after insert on public.pagos
for each row execute function public.registrar_movimiento_gerencial();

drop trigger if exists auditoria_gerencial_notas on public.notas_venta;
create trigger auditoria_gerencial_notas
after update of estado on public.notas_venta
for each row execute function public.registrar_movimiento_gerencial();

drop trigger if exists auditoria_gerencial_alertas on public.alertas_cocina;
create trigger auditoria_gerencial_alertas
after insert on public.alertas_cocina
for each row execute function public.registrar_movimiento_gerencial();

drop trigger if exists auditoria_gerencial_insumos on public.insumos;
create trigger auditoria_gerencial_insumos
after update of activo on public.insumos
for each row execute function public.registrar_movimiento_gerencial();

drop trigger if exists auditoria_gerencial_usuarios on public.usuarios;
create trigger auditoria_gerencial_usuarios
after update of activo, rol on public.usuarios
for each row execute function public.registrar_movimiento_gerencial();

revoke all on function public.identificar_autor_auditoria() from public, anon, authenticated;
revoke all on function public.registrar_movimiento_gerencial() from public, anon, authenticated;
