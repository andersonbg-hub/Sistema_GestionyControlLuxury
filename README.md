# Luxury · Sistema de Gestión y Control

Abre **Abrir Luxury.cmd** para ver la compilación conectada en Chrome. Entra con una cuenta de Luxury que tenga perfil activo en la base compartida de Supabase.

Para editar y ejecutar el proyecto, abre **Luxury-SIG.code-workspace** en Visual Studio Code y selecciona **Luxury en Chrome con Supabase**. La carpeta `luxury-flutter-fuente` contiene el proyecto Flutter. La carpeta `supabase` contiene las migraciones y la función de cuentas.

**Luxury.html**, en la carpeta de entrega, abre directamente en Chrome con los seis roles y datos de demostración.

## Diseño operativo

Las interfaces de los seis roles comparten una presentación minimalista para restaurante: navegación oscura, superficies cálidas y acentos controlados de la paleta Luxury (`#F20530`, `#93D92B`, `#F2BD1D`, `#F28907` y `#261603`). El login conserva su diseño independiente.

## Comparación por rol

| Rol | Main (3) | Completo y decisión |
| --- | --- | --- |
| Administrador | Permite solicitar varios insumos juntos y tiene módulos de carta, personal y reportes. | Se eligió Completo por la atención agrupada de alertas de inventario, el control de turnos por cajero y los reportes por cuenta de mesero. |
| Gerente | Ofrece reportes, consulta de usuarios y una lista general de auditoría. | Se eligió Completo por el filtro de movimientos relevantes, la identificación del responsable y el acceso a reportes e incidencias. |
| Cocina | Presenta el tablero de comandas y una vista gráfica de disponibilidad. | Se eligió Completo por los filtros por etapa y observaciones, la incidencia asociada a un platillo y la confirmación de entrega. |
| Jefe de cocina | Usa el tablero e inventario de Cocina para trabajar con faltantes. | Se eligió Completo por la misma gestión de comandas, con alertas y solicitudes en el inventario existente. |
| Mesero | El plano con sillas facilita reconocer la capacidad de cada mesa. | Se combinó ese dibujo con el flujo de Completo para consumos adicionales, delivery, pedidos para llevar y bloqueo de mesa cuando empieza el cobro. |
| Caja | Registra pagos y permite operar su turno en el módulo de caja. | Se eligió Completo por los abonos con saldo y vuelto visibles, las cuentas de días anteriores y el arqueo por turno de Lima que controla Administración. |

## Carga y sincronización

El acceso usa el espacio disponible en pantalla y permite desplazarse en ventanas bajas y en celular. Al pulsar **Iniciar sesión**, la barra dorada sigue visible mientras Supabase valida la cuenta y carga sus datos. El botón se habilita de nuevo si el acceso falla.

Al enviar un pedido, cobrar o guardar un cambio, la barra central indica la operación en curso. El fondo queda bloqueado hasta que se recibe un resultado. Las actualizaciones automáticas en segundo plano permiten seguir trabajando.

Las consultas independientes se cargan en paralelo. Los eventos seguidos de Realtime se agrupan para evitar recargar los mismos datos varias veces. Los pedidos pendientes reutilizan su identificador al reintentar. Si se pierde la confirmación de un cobro, Caja pide actualizar y revisar el saldo y los pagos antes de repetirlo.

La portada original se entrega en WebP y las fuentes principales se incluyen en el proyecto. La pantalla de carga usa el [arranque personalizado de Flutter Web](https://docs.flutter.dev/platform-integration/web/initialization).

## Supabase

La compilación usa `luxury-flutter-fuente/config/supabase.public.json`, con la configuración pública que compartían ambos ZIP. El servicio respondió en la comprobación de lectura y los 21 endpoints RPC que invoca Flutter estaban registrados. Los flujos con datos de prueba se comprueban aparte de los registros reales del restaurante.

- **Gestión de cuentas.** El endpoint de `manage-staff` devuelve 404. La función está en `supabase/functions/manage-staff` y requiere publicarse desde una cuenta con acceso al proyecto. El envío de correos de esa función usa los secretos de Resend en Supabase.
- **Auditoría de gerencia.** La base responde con las columnas básicas y la app muestra el autor a partir de `usuarios` cuando está disponible. Para guardar el nombre y la cuenta como parte de cada movimiento, aplica `supabase/migrations/20261109200000_Auditoria_para_gerencia.sql`.
- **Fotos de perfil.** Se incluyó la corrección de acceso de Storage que venía en Main (3). Su aplicación se verifica desde el proyecto de Supabase.

## Volver a compilar

Ejecuta desde `luxury-flutter-fuente`.

```powershell
flutter pub get
flutter analyze
flutter test
flutter build web --release --no-web-resources-cdn --dart-define-from-file=config/supabase.public.json --output=../web-conectado
```
