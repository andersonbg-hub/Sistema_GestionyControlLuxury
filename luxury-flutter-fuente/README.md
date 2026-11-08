# Sistema de Gestión y Control Luxury

Aplicación Flutter conectada al proyecto **SBLuxury** de Supabase.

**Abrir aplicación:** https://andersonbg-hub.github.io/Sistema_GestionyControlLuxury/

## Archivos del repositorio de publicación

- `luxury-web.zip`: versión web compilada con la configuración de Supabase.
- `luxury-flutter-fuente.zip`: proyecto Flutter editable, con `lib/`, `pubspec.yaml`, dependencias fijadas, configuración pública y pruebas.
- `.github/workflows/publicar.yml`: publica automáticamente el contenido de `luxury-web.zip` en GitHub Pages cuando se actualiza `main`.

Los siete archivos Dart originales se recuperaron de la tabla de fuentes de la caché Dart Kernel que acompañaba a la compilación. Se reconstruyeron los archivos de proyecto y la plataforma web. No se reemplazó la interfaz por otra aplicación.

## Conexión y acceso

El archivo `config/supabase.public.json` contiene la URL y la clave **publishable** del proyecto. Flutter recibe esos valores al compilar; copiar un `.env` a la web publicada no configura por sí solo la aplicación.

En modo conectado, ingresar con una cuenta de **Supabase Auth** que tenga un perfil activo en `public.usuarios`, con el mismo UUID. El campo `rol` controla el espacio de trabajo: `ADMINISTRADOR`, `GERENTE`, `COCINERO`, `JEFE_COCINA`, `MESERO` o `CAJERO`.

La sesión del panel de administración de Supabase es distinta de una cuenta de acceso a Luxury. La clave pública no es la contraseña de un usuario. Los botones de roles de demostración dejan de aparecer al configurar Supabase.

Se verificó que existen las 14 tablas usadas por la aplicación, las 15 funciones RPC que invoca y las seis tablas de su suscripción Realtime. Las tablas tienen RLS habilitado. No se desactivaron esas protecciones ni se incluyeron claves secretas o `service_role` en la web.

La aplicación conectada no carga los datos de ejemplo del navegador. Si falla la carga de datos al iniciar sesión, vuelve al acceso en lugar de mostrar un panel con datos de demostración.

## Crear un acceso de Luxury si fuera necesario

La persona que administra SBLuxury debe:

1. Crear o comprobar la cuenta en **Authentication → Users** y que su correo esté confirmado.
2. Comprobar en **Table Editor → usuarios** que existe el perfil con el mismo `id` de Auth, `nombre_completo`, `correo`, el `rol` correspondiente y `activo = true`.
3. Facilitar las credenciales al integrante por un canal privado. No publicar contraseñas en este repositorio.

## Administración de cuentas y correo

La app incluye creación de cuentas con contraseña temporal, edición del nombre/correo/rol, restablecimiento administrativo, cambio obligatorio de contraseña temporal y recuperación de contraseña propia. Las operaciones administrativas se realizan en `supabase/functions/manage-staff`; nunca se usa `service_role` desde Flutter.

Para habilitarlo en el proyecto Supabase:

1. Revisa y aplica las migraciones del directorio `../supabase/migrations` después de confirmar que corresponden al esquema desplegado.
2. Configura SMTP en **Authentication → SMTP Settings** y agrega la URL publicada en **Authentication → URL Configuration → Redirect URLs** para el correo de recuperación.
3. Configura en Resend un dominio remitente verificado y define los secretos de la función:

   ```sh
   supabase secrets set RESEND_API_KEY=... EMAIL_FROM="Luxury <cuentas@tu-dominio>"
   supabase functions deploy manage-staff
   ```

   Supabase proporciona `SUPABASE_URL`, `SUPABASE_ANON_KEY` y `SUPABASE_SERVICE_ROLE_KEY` al runtime de Edge Functions. No los copies a archivos Flutter, al ZIP web ni al repositorio.

La contraseña inicial o restablecida es temporal y se envía al correo ingresado; el sistema obliga a cambiarla al iniciar sesión. La función elimina la cuenta recién creada si el perfil o el correo de bienvenida no pueden completarse. El botón «Olvidaste tu contraseña» usa el correo de recuperación de Supabase Auth y requiere SMTP configurado.

## Pedidos y trabajo sin conexión

La migración `20261103151304_Delivery_takeaway.sql` agrega pedidos «Para llevar» y «Delivery», con contacto/dirección, y una función idempotente para sincronizar pedidos en cola sin duplicarlos si se pierde la respuesta de red.

Después de cargar datos online, la app conserva una caché local por usuario durante hasta 12 horas desde la última sincronización. Si se corta la conexión mientras se registra un pedido, lo guarda en el dispositivo y lo reintenta al recuperar Supabase; también se puede solicitar «Sincronizar pedidos» desde el menú de usuario. Los pedidos pendientes se identifican en cocina y caja. No se guardan pagos offline: se deben registrar cuando Supabase vuelva a estar disponible, para evitar cobros duplicados.

Supabase Auth mantiene una sola sesión por origen del navegador y la comparte entre pestañas; al cambiar de cuenta en otra pestaña, la app vuelve a validar el perfil. Perfiles de navegador distintos o dispositivos diferentes tienen almacenamiento separado y requieren una solución adicional de registro de dispositivos para imponer un bloqueo físico.

## Terminal de pago

El terminal disponible es un **Kobile P3**. La app admite registrar pagos con tarjeta y su número de operación, pero todavía no ejecuta ni confirma cobros en ese terminal. No se debe simular un cobro como si estuviera aprobado. Para integrar el equipo se necesita identificar el adquirente/proveedor que procesa los pagos, obtener su SDK/API y confirmar el método de comunicación y el sistema operativo habilitado en el terminal. El número de serie del equipo no se guarda en el repositorio.

## Compilar y actualizar

Descomprimir `luxury-flutter-fuente.zip` y abrir la carpeta que contiene `pubspec.yaml`. Con Flutter instalado:

```sh
flutter pub get
flutter analyze
flutter test
flutter build web --release --base-href /Sistema_GestionyControlLuxury/ --dart-define-from-file=config/supabase.public.json
```

Comprimir **el contenido** de `build/web/` como `luxury-web.zip`: `index.html`, `main.dart.js`, `assets/` y `canvaskit/` deben quedar en la raíz del ZIP. Reemplazar ese archivo en GitHub mediante **Add file → Upload files → Commit changes**. La pestaña **Actions** muestra el resultado de la publicación.

Mantener **Settings → Pages → Source → GitHub Actions**. El repositorio es público para utilizar GitHub Pages con el plan gratuito.

Para desarrollar en local con Supabase:

```sh
flutter run -d chrome --dart-define-from-file=config/supabase.public.json
```

Compilar sin configuración abre el modo local de demostración; no usar esa compilación para reemplazar la versión conectada.

## Verificación

La versión 0.1.2 adapta encabezados y registros al ancho disponible. En pantallas pequeñas, las acciones aparecen debajo de la información; el selector «Sección» permite abrir todos los módulos de administración. Las estadísticas utilizan alturas naturales y las tarjetas del salón conservan espacio para el estado y la capacidad. También se adaptaron las listas de mesero, cocina y caja.

Las pruebas de interfaz recorren las ocho secciones de administración, las tres pestañas de inventario y los espacios de mesero, cocina y caja. Se comprueban anchos de 320, 390, 600, 640, 768, 844 y 1280 píxeles, orientación vertical y horizontal, texto ampliado al 150 %, ausencia de errores de distribución y espacio suficiente para los nombres de los registros. También se abre una comanda y se agrega un producto para comprobar sus controles y desplazamiento. Se ejecutan con datos de demostración locales y no escriben en Supabase.

Se mantienen las tres pruebas de conexión y acceso. Consultar tablas y funciones confirma la estructura; la prueba completa de escritura desde la aplicación requiere iniciar sesión con una cuenta autorizada y autorización para utilizar datos de prueba. La actualización del diseño no cambia datos, tablas, cuentas, funciones ni permisos de Supabase.
