# Sistema de Gestión y Control Luxury

Versión web de la aplicación Flutter Luxury, recuperada de la compilación disponible en `Sistema_GestionyControlLuxury-main/luxury_app/build/web`.

## Qué contiene

El archivo `luxury-web.zip` contiene la aplicación web compilada y sus recursos, conservando su estructura de carpetas. La copia encontrada en Descargas no incluía `lib/` ni `pubspec.yaml`; por eso este repositorio conserva la versión ejecutable web, no el proyecto fuente completo de Flutter.

## Abrir la aplicación

La dirección de la aplicación en GitHub Pages es:

https://andersonbg-hub.github.io/Sistema_GestionyControlLuxury/

En **Settings → Pages**, seleccionar **GitHub Actions** como fuente. El flujo `.github/workflows/publicar.yml` descomprime la aplicación y la publica automáticamente cuando hay cambios en `main`. En GitHub Free el repositorio debe ser público.

La aplicación se presenta como una demostración local: los cambios se conservan en cada navegador y no se envían a Supabase.

## Cómo se preparó

1. Se copiaron los archivos de `build/web` sin modificar los originales de Descargas.
2. Se ajustó `<base href>` de `index.html` a `/Sistema_GestionyControlLuxury/`.
3. Se agregó `.nojekyll` y se comprimió el contenido como `luxury-web.zip`.
4. Se subieron el archivo, esta guía y el flujo de publicación a un nuevo repositorio.
5. Se activó GitHub Pages con GitHub Actions.

## Actualizar desde el código Flutter completo

Ejecutar desde la carpeta que contiene `pubspec.yaml`:

```sh
flutter pub get
flutter build web --release --base-href /Sistema_GestionyControlLuxury/
```

Después comprimir el contenido de `build/web/` en un nuevo `luxury-web.zip`. Al abrir el ZIP, `index.html`, `main.dart.js`, `assets/` y `canvaskit/` deben estar en su raíz. Reemplazar el ZIP en GitHub mediante **Add file → Upload files → Commit changes** y esperar a que termine el flujo de la pestaña **Actions**.

Abrir la aplicación mediante un servidor web; no basta con hacer doble clic en `index.html`.

La publicación web no comprueba por sí sola las funciones del sistema ni la conexión a sus servicios externos.
