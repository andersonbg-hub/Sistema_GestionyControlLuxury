-- Preserve the existing RPC signature for clients already in use.
create or replace function public.administrar_turno_caja(
  p_cajero_id uuid, p_abrir boolean, p_monto numeric, p_turno_id bigint default null
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inicio_hoy timestamptz := date_trunc('day', now() at time zone 'America/Lima')
    at time zone 'America/Lima';
  v_turno_id bigint;
  v_apertura timestamptz;
  v_cierre timestamptz;
begin
  if not public.es_administrador_activo() then
    raise exception 'Solo Administración puede abrir o cerrar turnos.';
  end if;
  if not exists (
    select 1 from public.usuarios
    where id = p_cajero_id and activo and rol = 'CAJERO'
  ) then
    raise exception 'Selecciona un cajero activo.';
  end if;
  if p_abrir is null then
    raise exception 'Indica si se va a abrir o cerrar la caja.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('luxury:turno:' || p_cajero_id::text, 0));
  select id, abierto_en into v_turno_id, v_apertura
  from public.turnos_caja
  where cajero_id = p_cajero_id and cerrado_en is null
  order by abierto_en desc, id desc
  limit 1
  for update;

  if p_abrir and v_apertura >= v_inicio_hoy then
    return;
  end if;
  if not p_abrir and (v_turno_id is null or v_turno_id is distinct from p_turno_id) then
    raise sqlstate 'PT409' using message = 'El turno cambió. Consulta su estado antes de volver a cerrar.';
  end if;

  if v_turno_id is not null then
    v_cierre := clock_timestamp();
    update public.turnos_caja t
    set cerrado_en = v_cierre,
        monto_cierre = (
          select coalesce(sum(p.monto), 0)
          from public.pagos p
          where p.cajero_id = p_cajero_id
            and p.metodo = 'EFECTIVO'
            and (
              p.turno_id = v_turno_id
              or (p.turno_id is null and p.creado_en between v_apertura and v_cierre)
            )
        )
    where t.id = v_turno_id;

    insert into public.auditoria_movimientos
      (actor_id, actor_rol, accion, entidad, entidad_id)
    values (auth.uid(), 'ADMINISTRADOR', 'Cerrar turno de caja', 'turnos_caja', v_turno_id::text);
  end if;

  if p_abrir then
    insert into public.turnos_caja (cajero_id, monto_apertura)
    values (p_cajero_id, 0)
    returning id into v_turno_id;

    insert into public.auditoria_movimientos
      (actor_id, actor_rol, accion, entidad, entidad_id)
    values (auth.uid(), 'ADMINISTRADOR', 'Abrir turno de caja', 'turnos_caja', v_turno_id::text);
  end if;
end;
$$;
