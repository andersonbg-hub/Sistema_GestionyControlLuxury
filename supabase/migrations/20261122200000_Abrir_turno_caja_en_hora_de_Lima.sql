-- SBLuxury · Apertura de caja con la fecha del servidor en hora de Lima.
-- Sustituye la función existente. Se ejecuta una vez en el SQL Editor.
-- La instalación no abre ni cierra turnos. Esas operaciones se hacen en Luxury.
begin;

create or replace function public.administrar_turno_caja(
  p_cajero_id uuid,
  p_abrir boolean,
  p_monto numeric,
  p_turno_id bigint default null
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_turno_id bigint;
  v_apertura timestamptz;
  v_movimiento timestamptz;
begin
  if not coalesce(public.es_administrador_activo(), false) then
    raise sqlstate 'PT403' using message = 'Solo Administración puede abrir o cerrar turnos.';
  end if;
  if not exists (
    select 1 from public.usuarios
    where id = p_cajero_id and activo and rol = 'CAJERO'
  ) then
    raise sqlstate 'PT400' using message = 'Selecciona un cajero activo.';
  end if;
  if p_abrir is null then
    raise sqlstate 'PT400' using message = 'Indica si vas a abrir o cerrar la caja.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('luxury:turno:' || p_cajero_id::text, 0));
  select id, abierto_en into v_turno_id, v_apertura
  from public.turnos_caja
  where cajero_id = p_cajero_id and cerrado_en is null
  order by abierto_en desc, id desc
  limit 1
  for update;

  v_movimiento := clock_timestamp();
  if v_apertura > v_movimiento then
    raise sqlstate 'PT409' using message = 'El turno tiene una hora de apertura futura. Revisa su fecha en Control de caja.';
  end if;
  if p_abrir and (v_apertura at time zone 'America/Lima')::date =
                 (v_movimiento at time zone 'America/Lima')::date then
    return;
  end if;
  if not p_abrir and (v_turno_id is null or v_turno_id is distinct from p_turno_id) then
    raise sqlstate 'PT409' using message = 'El turno cambió. Actualiza el turno antes de cerrar.';
  end if;

  if v_turno_id is not null then
    update public.turnos_caja t
    set cerrado_en = v_movimiento,
        monto_cierre = (
          select coalesce(sum(p.monto), 0)
          from public.pagos p
          where p.cajero_id = p_cajero_id
            and p.metodo = 'EFECTIVO'
            and (
              p.turno_id = v_turno_id
              or (p.turno_id is null and p.creado_en between v_apertura and v_movimiento)
            )
        )
    where t.id = v_turno_id;

    insert into public.auditoria_movimientos
      (actor_id, actor_rol, accion, entidad, entidad_id)
    values (auth.uid(), 'ADMINISTRADOR', 'Cerrar turno de caja', 'turnos_caja', v_turno_id::text);
  end if;

  if p_abrir then
    insert into public.turnos_caja (cajero_id, abierto_en, monto_apertura)
    values (p_cajero_id, v_movimiento, 0)
    returning id into v_turno_id;

    insert into public.auditoria_movimientos
      (actor_id, actor_rol, accion, entidad, entidad_id)
    values (auth.uid(), 'ADMINISTRADOR', 'Abrir turno de caja', 'turnos_caja', v_turno_id::text);
  end if;
end;
$$;

revoke all on function public.administrar_turno_caja(uuid, boolean, numeric, bigint)
  from public, anon, authenticated;
grant execute on function public.administrar_turno_caja(uuid, boolean, numeric, bigint)
  to authenticated;

commit;
