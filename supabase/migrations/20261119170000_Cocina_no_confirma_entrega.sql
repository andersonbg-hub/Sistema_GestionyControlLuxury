-- Cocina no puede marcar un platillo como ENTREGADO: la entrega final la confirma el mesero.
-- Se valida en la base de datos para que aplique aunque se llame a actualizar_estado_item
-- (o se actualice detalle_pedido) desde cualquier cliente.

create or replace function public.bloquear_entrega_por_cocina()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
begin
  if new.estado = 'ENTREGADO' and new.estado is distinct from old.estado then
    if exists (
      select 1
      from public.usuarios u
      where u.id = v_actor
        and u.rol in ('COCINERO', 'JEFE_COCINA')
    ) then
      raise exception 'La entrega la confirma el mesero.';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function public.bloquear_entrega_por_cocina()
  from public, anon, authenticated;

drop trigger if exists bloquear_entrega_por_cocina on public.detalle_pedido;
create trigger bloquear_entrega_por_cocina
before update of estado on public.detalle_pedido
for each row execute function public.bloquear_entrega_por_cocina();
