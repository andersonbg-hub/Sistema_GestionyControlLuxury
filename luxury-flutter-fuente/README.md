# Luxury · Restaurante Oriental

Aplicación de gestión del restaurante con Flutter y Supabase. La configuración pública de Supabase está en `config/supabase.public.json`.

## Organización de `lib/`

- `core/`: colores, componentes reutilizables y generación de comprobantes.
- `data/`: conexión HTTP y fachada `RestaurantStore`.
- `data/store/`: módulos de autenticación, sincronización remota, pedidos, catálogo, inventario, personal, caja y persistencia. Comparten estado y API de `RestaurantStore`.
- `models/`: entidades y tipos del dominio.
- `views/admin/dashboard_screen.dart`: contenedor y dashboard inicial del administrador y gerente. `views/admin/pages/` contiene catálogo, inventario, usuarios, mesas, reportes, incidencias, auditoría y control de caja.
- `views/waiter/`: contenedor del mesero y páginas separadas para mesas, creación de pedidos y pedidos/historial.
- `views/kitchen/`: contenedor de cocina y páginas separadas para comandas, tablero, inventario e historial.
- `views/cashier/`: contenedor de caja y páginas separadas para cuentas por cobrar, recibos, turno y actividad.
- `views/`: perfil del personal y cambio de contraseña, compartidos entre roles.
- `main.dart`: inicio de la aplicación y selección de pantalla según el rol.
