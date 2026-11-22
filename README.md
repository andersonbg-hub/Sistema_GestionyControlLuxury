# Luxury · Sistema de gestión del restaurante

**Abrir Luxury.cmd** inicia la compilación web conectada al Supabase existente. Requiere Python 3 y un navegador. Usa una cuenta activa del restaurante.

Para editar el código en Visual Studio Code, abre **Luxury-SIG.code-workspace**. Selecciona **Luxury en Chrome con Supabase** en Ejecutar y depurar. Este proyecto se verificó con Flutter 3.44.4 y Dart 3.12.2. Si tienes varias instalaciones de Flutter, usa la versión indicada.

## Flujos de trabajo

- **Mesero** elige una mesa de forma explícita, filtra la carta sin perder la comanda y consulta desde la campana qué platos de sus pedidos están listos. Al pulsar un aviso, lo marca como recibido y desaparece de la campana. La lectura se guarda por mesero en ese navegador. Puede conservar los flujos existentes de para llevar y delivery desde Mesas.
- **Cocina y Jefatura de cocina** ven en cada columna los productos de esa etapa. Los consumos nuevos conservan su hora de ingreso y los productos entregados se consultan en el historial.
- **Caja** valida importes con dos decimales, conserva los códigos de operación como texto y muestra la confirmación después de registrar el cobro. La actividad y los recibos internos admiten filtros de fecha en hora de Lima.
- **Administración y Gerencia** consultan pedidos de los últimos siete días. Administración guarda las fotos de los platillos en `platillos.foto_url` y las fotos de los insumos en `insumos.imagen_url`.
- La aplicación conserva los colores, tipografías y recursos visuales de Luxury. Las entradas de sección, tarjetas, menús y avisos tienen movimiento y respetan la preferencia de movimiento reducido.

`Luxury.html` es la demostración independiente que venía en el ZIP original. Los cambios de esta versión están en la aplicación Flutter y su compilación web.

## Supabase

La distribución de las comandas y el gráfico del resumen de Administración usan el esquema existente. La corrección de apertura de caja usa la migración `supabase/migrations/20261122200000_Abrir_turno_caja_en_hora_de_Lima.sql`. Si vas a aplicarla manualmente, copia solo ese archivo al SQL Editor del proyecto SBLuxury y ejecútalo completo. La instalación actualiza la función de turnos. Luego vuelve a **Administración → Control de caja**, selecciona el cajero y abre el turno desde Luxury.

La configuración pública existente está en `luxury-flutter-fuente/config/supabase.public.json`. Las migraciones están en `supabase/migrations` y la función de cuentas en `supabase/functions/manage-staff`.

- La API de autenticación respondió a la revisión de solo lectura. Varias tablas y columnas se verificaron con consultas de cero filas.
- Los cambios de nombre y datos personales usan los permisos existentes de `usuarios`. El alta y los cambios de acceso siguen dependiendo de la Edge Function `manage-staff`.
- Publica el contenido de `supabase/functions/manage-staff/index.ts` como una Edge Function llamada `manage-staff`. Supabase proporciona las variables de conexión reservadas `SUPABASE_*`. La gestión de perfiles y contraseñas no requiere un proveedor de correo.
- En **Administración → Usuarios y roles**, un administrador activo edita los perfiles y asigna contraseñas iniciales o de reemplazo al personal operativo. El empleado entra con la contraseña asignada y debe cambiarla en su siguiente inicio. Gerencia conserva sus pantallas de operación y auditoría.
- La migración de imágenes inicial ya se aplicó en SBLuxury. La migración posterior conserva las fotos de platillos en `foto_url` y retira `platillos.imagen_url` después de verificar que las fotos estén a salvo. Usa esta compilación antes de ejecutar esa migración SQL.
- La recepción de inventario usa `recibir_solicitud_reabastecimiento`. El SQL incluido valida el rol y bloquea la solicitud durante la recepción. La prueba con una cuenta real queda pendiente.

## Reconstruir y verificar

Desde `luxury-flutter-fuente`, con el Flutter compatible en el PATH.

```powershell
flutter pub get
flutter analyze
flutter test
flutter build web --release --no-web-resources-cdn --dart-define-from-file=config/supabase.public.json --output=../web-conectado
```

Para ejecutar la compilación sin abrir una ventana desde el script, usa `python servidor_local.py --sin-abrir` en la carpeta raíz.
