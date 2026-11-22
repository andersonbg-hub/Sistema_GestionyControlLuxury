create or replace function public.administrar_turno_caja(
  p_cajero_id uuid, p_abrir boolean, p_monto numeric, p_turno_id bigint default null
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_turno_id bigint;
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
  if p_abrir is null or p_monto is null
     or p_monto::text in ('NaN', 'Infinity', '-Infinity')
     or p_monto < 0 or scale(p_monto) > 2 then
    raise exception 'Ingresa un importe válido de hasta dos decimales.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('luxury:turno:' || p_cajero_id::text, 0));
  if p_abrir then
    if exists (
      select 1 from public.turnos_caja
      where cajero_id = p_cajero_id and cerrado_en is null
    ) then
      return;
    end if;
    insert into public.turnos_caja (cajero_id, monto_apertura)
    values (p_cajero_id, p_monto)
    returning id into v_turno_id;
  else
    update public.turnos_caja
    set cerrado_en = now(), monto_cierre = p_monto
    where id = p_turno_id and cajero_id = p_cajero_id and cerrado_en is null
    returning id into v_turno_id;
    if v_turno_id is null then
      raise exception 'El turno cambió. Consulta su estado antes de volver a cerrar.';
    end if;
  end if;

  insert into public.auditoria_movimientos
    (actor_id, actor_rol, accion, entidad, entidad_id)
  values (
    auth.uid(), 'ADMINISTRADOR',
    case when p_abrir then 'Abrir turno de caja' else 'Cerrar turno de caja' end,
    'turnos_caja', v_turno_id::text
  );
end;
$$;

revoke all on function public.administrar_turno_caja(uuid, boolean, numeric, bigint)
  from public, anon, authenticated;
grant execute on function public.administrar_turno_caja(uuid, boolean, numeric, bigint)
  to authenticated;

revoke insert, update, delete on public.turnos_caja from public, anon, authenticated;

drop policy if exists turnos_lectura_administracion on public.turnos_caja;
create policy turnos_lectura_administracion on public.turnos_caja
  for select to authenticated using (public.es_administrador_activo());

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables where pubname = 'supabase_realtime'
       and schemaname = 'public' and tablename = 'turnos_caja'
     ) then
    alter publication supabase_realtime add table public.turnos_caja;
  end if;
end;
$$;
