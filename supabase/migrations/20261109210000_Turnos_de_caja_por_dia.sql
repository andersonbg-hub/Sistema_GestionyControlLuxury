-- A cashier needs an open shift for the current Lima day before taking payment.
create or replace function public.validar_turno_diario_al_cobrar()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cajero uuid := auth.uid();
  v_inicio timestamptz := date_trunc('day', now() at time zone 'America/Lima')
    at time zone 'America/Lima';
begin
  if new.monto > 0 and exists (
    select 1 from public.usuarios
    where id = v_cajero and activo and rol = 'CAJERO'
  ) then
    perform 1 from public.turnos_caja
    where cajero_id = v_cajero and cerrado_en is null
      and abierto_en >= v_inicio and abierto_en <= now()
    for share;
    if not found then
      raise exception 'Administración debe abrir el turno de caja de hoy.';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists validar_turno_diario_al_cobrar on public.pagos;
create trigger validar_turno_diario_al_cobrar
before insert on public.pagos
for each row execute function public.validar_turno_diario_al_cobrar();

revoke all on function public.validar_turno_diario_al_cobrar() from public, anon, authenticated;
