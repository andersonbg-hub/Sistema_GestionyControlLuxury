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
