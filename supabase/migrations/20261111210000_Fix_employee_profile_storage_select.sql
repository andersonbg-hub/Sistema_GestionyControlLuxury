-- El cliente Flutter sube perfiles con upsert=true. Storage necesita permiso
-- de lectura para comprobar/reemplazar un archivo existente.
drop policy if exists employee_profile_read on storage.objects;
create policy employee_profile_read
on storage.objects for select to authenticated
using (
  bucket_id = 'employee-profiles'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.es_administrador_activo()
  )
);
