create or replace function public.puede_editar_perfil_propio()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.usuarios
    where id = auth.uid() and activo
      and rol in ('ADMINISTRADOR', 'GERENTE', 'JEFE_COCINA')
  );
$$;

revoke all on function public.puede_editar_perfil_propio() from public, anon;
grant execute on function public.puede_editar_perfil_propio() to authenticated;

create or replace function public.actualizar_perfil_propio(
  p_correo_personal text,
  p_telefono text,
  p_direccion text,
  p_departamento text,
  p_foto_path text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Se requiere una sesión autenticada.';
  end if;
  if not exists (
    select 1 from public.usuarios
    where id = v_uid and activo = true
  ) then
    raise exception 'La cuenta no está activa.';
  end if;
  if not public.puede_editar_perfil_propio() then
    raise exception 'Tu perfil es de solo lectura.';
  end if;
  if nullif(trim(coalesce(p_correo_personal, '')), '') is not null
     and trim(p_correo_personal) !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'El correo personal no es válido.';
  end if;
  if p_foto_path is not null
     and split_part(p_foto_path, '/', 1) <> v_uid::text then
    raise exception 'La fotografía debe pertenecer al perfil autenticado.';
  end if;

  update public.usuarios
  set correo_personal = trim(coalesce(p_correo_personal, '')),
      telefono = trim(coalesce(p_telefono, '')),
      direccion = trim(coalesce(p_direccion, '')),
      departamento = trim(coalesce(p_departamento, '')),
      foto_path = coalesce(p_foto_path, foto_path)
  where id = v_uid and activo = true;
end;
$$;

drop policy if exists employee_profile_upload on storage.objects;
create policy employee_profile_upload
on storage.objects for insert to authenticated
with check (
  bucket_id = 'employee-profiles'
  and (
    ((storage.foldername(name))[1] = auth.uid()::text
      and public.puede_editar_perfil_propio())
    or public.es_administrador_activo()
  )
);

drop policy if exists employee_profile_update on storage.objects;
create policy employee_profile_update
on storage.objects for update to authenticated
using (
  bucket_id = 'employee-profiles'
  and (
    ((storage.foldername(name))[1] = auth.uid()::text
      and public.puede_editar_perfil_propio())
    or public.es_administrador_activo()
  )
)
with check (
  bucket_id = 'employee-profiles'
  and (
    ((storage.foldername(name))[1] = auth.uid()::text
      and public.puede_editar_perfil_propio())
    or public.es_administrador_activo()
  )
);

drop policy if exists employee_profile_delete on storage.objects;
create policy employee_profile_delete
on storage.objects for delete to authenticated
using (
  bucket_id = 'employee-profiles'
  and (
    ((storage.foldername(name))[1] = auth.uid()::text
      and public.puede_editar_perfil_propio())
    or public.es_administrador_activo()
  )
);
