alter table public.usuarios
  add column if not exists documento_identidad text not null default '',
  add column if not exists correo_personal text not null default '',
  add column if not exists telefono text not null default '',
  add column if not exists direccion text not null default '',
  add column if not exists departamento text not null default '',
  add column if not exists foto_path text not null default '',
  add column if not exists estado_laboral text not null default 'ACTIVO';

update public.usuarios
set estado_laboral = case when activo then 'ACTIVO' else 'INACTIVO' end
where estado_laboral not in ('ACTIVO', 'VACACIONES', 'LICENCIA', 'INACTIVO')
   or (not activo and estado_laboral <> 'INACTIVO');

alter table public.usuarios
  drop constraint if exists usuarios_estado_laboral_check;
alter table public.usuarios
  add constraint usuarios_estado_laboral_check
  check (estado_laboral in ('ACTIVO', 'VACACIONES', 'LICENCIA', 'INACTIVO'));

create or replace function public.puede_ver_perfiles_empleados()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.usuarios
    where id = auth.uid()
      and activo = true
      and rol in ('ADMINISTRADOR', 'GERENTE')
  );
$$;

create or replace function public.es_administrador_activo()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.usuarios
    where id = auth.uid()
      and activo = true
      and rol = 'ADMINISTRADOR'
  );
$$;

revoke all on function public.puede_ver_perfiles_empleados() from public;
grant execute on function public.puede_ver_perfiles_empleados() to authenticated;
revoke all on function public.es_administrador_activo() from public;
grant execute on function public.es_administrador_activo() to authenticated;

alter table public.usuarios enable row level security;
drop policy if exists staff_profile_scope on public.usuarios;
create policy staff_profile_scope
on public.usuarios as restrictive
for select to authenticated
using (id = auth.uid() or public.puede_ver_perfiles_empleados());

drop policy if exists staff_profile_read on public.usuarios;
create policy staff_profile_read
on public.usuarios as permissive
for select to authenticated
using (id = auth.uid() or public.puede_ver_perfiles_empleados());

drop policy if exists staff_profile_update_scope on public.usuarios;
create policy staff_profile_update_scope
on public.usuarios as restrictive
for update to authenticated
using (public.es_administrador_activo())
with check (public.es_administrador_activo());

drop policy if exists staff_profile_admin_update on public.usuarios;
create policy staff_profile_admin_update
on public.usuarios as permissive
for update to authenticated
using (public.es_administrador_activo())
with check (public.es_administrador_activo());

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

revoke all on function public.actualizar_perfil_propio(
  text, text, text, text, text
) from public;
grant execute on function public.actualizar_perfil_propio(
  text, text, text, text, text
) to authenticated;

insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
) values (
  'employee-profiles',
  'employee-profiles',
  true,
  2097152,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists employee_profile_upload on storage.objects;
create policy employee_profile_upload
on storage.objects for insert to authenticated
with check (
  bucket_id = 'employee-profiles'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.es_administrador_activo()
  )
);

drop policy if exists employee_profile_update on storage.objects;
create policy employee_profile_update
on storage.objects for update to authenticated
using (
  bucket_id = 'employee-profiles'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.es_administrador_activo()
  )
)
with check (
  bucket_id = 'employee-profiles'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.es_administrador_activo()
  )
);

drop policy if exists employee_profile_delete on storage.objects;
create policy employee_profile_delete
on storage.objects for delete to authenticated
using (
  bucket_id = 'employee-profiles'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.es_administrador_activo()
  )
);
