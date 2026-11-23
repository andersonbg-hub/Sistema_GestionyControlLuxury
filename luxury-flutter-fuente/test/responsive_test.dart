import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luxury_app/views/admin/dashboard_screen.dart';
import 'package:luxury_app/core/app_widgets.dart';
import 'package:luxury_app/models/models.dart';
import 'package:luxury_app/views/cashier/cashier_screen.dart';
import 'package:luxury_app/views/kitchen/kitchen_screen.dart';
import 'package:luxury_app/views/staff_profile_dialog.dart';
import 'package:luxury_app/views/waiter/waiter_screen.dart';
import 'package:luxury_app/data/restaurant_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  for (final size in [
    (320.0, 1.0),
    (390.0, 1.0),
    (600.0, 1.0),
    (768.0, 1.0),
    (844.0, 1.0),
    (1280.0, 1.0),
    (390.0, 1.5),
  ]) {
    testWidgets('Administración: ancho ${size.$1}, texto ${size.$2}', (
      tester,
    ) async {
      tester.view.physicalSize = Size(size.$1, size.$1 == 844 ? 390 : 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = RestaurantStore();
      store.menu.insert(
        0,
        const MenuItem(
          id: 9999,
          name: 'Arroz chaufa especial',
          category: 'Chifas',
          price: 15,
          description: 'Con verduras y pollo, preparado al momento',
        ),
      );
      store.inventory.insert(
        0,
        const InventoryItem(
          id: 9999,
          name: 'Ajo para cocina',
          description: 'Insumo fresco para la preparación del día',
          unit: 'UNIDAD',
          quantity: 1,
          minimum: 1,
        ),
      );
      addTearDown(store.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(size.$2)),
            child: child!,
          ),
          home: Scaffold(body: AdminScreen(store: store)),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Resumen');
      for (var page = 1; page < 7; page++) {
        if (size.$1 < 760) {
          await tester.tap(find.byType(DropdownButtonFormField<int>));
          await tester.pumpAndSettle();
          final label = [
            'Resumen',
            'Menú y catálogo',
            'Inventario',
            'Usuarios y roles',
            'Mesas',
            'Reportes',
            'Incidencias',
          ][page];
          await tester.tap(find.text(label).last);
        } else {
          tester
              .widget<LuxurySideMenu>(find.byType(LuxurySideMenu))
              .onDestinationSelected(page);
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Sección $page');
        if (page == 1 || page == 2 || page == 4) {
          final name = page == 1
              ? 'Arroz chaufa especial'
              : page == 2
              ? 'Ajo para cocina'
              : 'Mesa ${store.tables.first.number}';
          final record = find
              .descendant(
                of: find.byType(ResponsiveListTile),
                matching: find.text(name),
              )
              .first;
          expect(
            tester.renderObject<RenderBox>(record).constraints.maxWidth,
            greaterThan(150),
          );
          if (page == 1 && size.$1 < 760) {
            expect(
              tester.getTopLeft(find.text('Nuevo plato')).dy,
              greaterThan(
                tester.getBottomLeft(find.text('Menú y catálogo').last).dy,
              ),
            );
          }
        }
        if (page == 2) {
          final segments = tester.widget<SegmentedButton<int>>(
            find.byType(SegmentedButton<int>),
          );
          for (final tab in [1, 2, 0]) {
            segments.onSelectionChanged!({tab});
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: 'Inventario $tab');
          }
        }
      }
    });
  }

  for (final viewport in [
    Size(320, 900),
    Size(390, 900),
    Size(768, 900),
    Size(1280, 900),
    Size(1920, 1000),
    Size(844, 390),
    Size(640, 360),
  ]) {
    final width = viewport.width;
    testWidgets('Mesero, cocina y caja: $viewport', (tester) async {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = RestaurantStore();
      addTearDown(store.dispose);
      for (final screen in [
        (WaiterScreen(store: store), 3),
        (KitchenScreen(store: store), 3),
        (CashierScreen(store: store), 5),
      ]) {
        await tester.pumpWidget(MaterialApp(home: screen.$1));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (screen.$1 is WaiterScreen) {
          await tester.tap(find.widgetWithText(FilledButton, 'Nuevo pedido'));
          await tester.pumpAndSettle();
          expect(find.text('Elegir mesa'), findsOneWidget);
          await tester.tap(
            find
                .descendant(
                  of: find.byType(AlertDialog),
                  matching: find.byType(ListTile),
                )
                .first,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'Nueva comanda');
          await tester.scrollUntilVisible(
            find.byKey(ValueKey('add-menu-item-${store.menu.first.id}')),
            100,
            scrollable: find
                .descendant(
                  of: find.byKey(const ValueKey('order-form-scroll')),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(ValueKey('add-menu-item-${store.menu.first.id}')),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: 'Comanda con productos',
          );
          final compactOrder = find.widgetWithText(TextButton, 'Ver orden (1)');
          if (compactOrder.evaluate().isNotEmpty) {
            await tester.tap(compactOrder);
            await tester.pumpAndSettle();
            await tester.scrollUntilVisible(
              find.byKey(const ValueKey('order-cart-panel')),
              120,
              scrollable: find
                  .descendant(
                    of: find.byKey(const ValueKey('order-form-scroll')),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            await tester.pumpAndSettle();
          }
          expect(
            find.byKey(const ValueKey('order-cart-panel')),
            findsOneWidget,
          );
          expect(find.text('Enviar a cocina'), findsOneWidget);
          expect(find.byIcon(Icons.remove), findsOneWidget);
          if (width >= 1920) {
            expect(find.text('Carta'), findsOneWidget);
            expect(find.text('Orden #1 · Mesa 1'), findsOneWidget);
            expect(
              tester
                  .getTopLeft(find.byKey(const ValueKey('menu-panel-title')))
                  .dy,
              closeTo(
                tester
                    .getTopLeft(find.byKey(const ValueKey('cart-panel-title')))
                    .dy,
                2,
              ),
            );
            expect(
              tester
                  .getTopLeft(find.byKey(const ValueKey('order-menu-panel')))
                  .dy,
              closeTo(
                tester
                    .getTopLeft(find.byKey(const ValueKey('order-cart-panel')))
                    .dy,
                2,
              ),
            );
            expect(
              tester
                  .getRect(find.byKey(const ValueKey('order-cart-panel')))
                  .right,
              lessThan(tester.view.physicalSize.width - 8),
            );
          }
        }
        for (var page = 1; page < screen.$2; page++) {
          if (width < 760) {
            final nav = tester.widget<NavigationBar>(
              find.byType(NavigationBar),
            );
            if (page >= nav.destinations.length) break;
            nav.onDestinationSelected!(page);
          } else {
            final nav = tester.widget<LuxurySideMenu>(
              find.byType(LuxurySideMenu),
            );
            final destination = screen.$1 is WaiterScreen && page > 0
                ? page + 1
                : page;
            if (destination >= nav.entries.length) break;
            nav.onDestinationSelected(destination);
          }
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '${screen.$1.runtimeType}, sección $page',
          );
        }
      }
    });
  }

  testWidgets(
    'La comanda alinea la carta y la orden y conserva las fotos del catálogo',
    (tester) async {
      tester.view.physicalSize = const Size(1536, 840);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = RestaurantStore()..role = StaffRole.waiter;
      addTearDown(store.dispose);
      const photo = 'https://restaurant.example.test/platillo.png';
      store.menu.insert(
        0,
        const MenuItem(
          id: 90007,
          name: 'Plato con foto',
          category: 'Entradas',
          price: 28,
          imageUrl: photo,
        ),
      );
      await tester.pumpWidget(MaterialApp(home: WaiterScreen(store: store)));
      await tester.tap(find.text('Delivery'));
      await tester.pumpAndSettle();
      expect(find.text('Dirección de entrega'), findsOneWidget);
      final catalog = find.byKey(const ValueKey('order-menu-panel'));
      final cart = find.byKey(const ValueKey('order-cart-panel'));
      expect(tester.getTopLeft(catalog).dy, tester.getTopLeft(cart).dy);
      expect(
        tester.getRect(catalog).right,
        lessThan(tester.getRect(cart).left),
      );
      final configuredImage = find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is NetworkImage &&
            (widget.image as NetworkImage).url == photo,
      );
      expect(
        find.descendant(of: catalog, matching: configuredImage),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('add-menu-item-90007')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: cart, matching: find.text('S/ 28.00')),
        findsNWidgets(2),
      );
      expect(
        find.descendant(of: cart, matching: find.text('Agregar observación')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'El resumen de Administración grafica los pedidos por fecha de Lima',
    (tester) async {
      tester.view.physicalSize = const Size(1240, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = RestaurantStore()..role = StaffRole.administrator;
      addTearDown(store.dispose);
      final now = DateTime.now();
      store.orders
        ..clear()
        ..addAll([
          for (final (id, timestamp, status) in [
            (1, now, OrderStatus.pending),
            (2, now.subtract(const Duration(days: 1)), OrderStatus.pending),
            (3, now, OrderStatus.ready),
            (4, now, OrderStatus.cancelled),
          ])
            RestaurantOrder(
              id: id,
              tableId: null,
              tableNumber: 0,
              createdAt: timestamp,
              status: status,
              lines: const [],
            ),
        ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AdminScreen(store: store)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.show_chart_rounded), findsOneWidget);
      final dayCounts = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((widget) => widget.message)
          .whereType<String>()
          .where((message) => RegExp(r' pedidos?$').hasMatch(message))
          .map((message) => message.split(' · ').last);
      expect(dayCounts.toList(), [
        '0 pedidos',
        '0 pedidos',
        '0 pedidos',
        '0 pedidos',
        '0 pedidos',
        '1 pedido',
        '2 pedidos',
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Cocina filtra incidencias y muestra el platillo afectado', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = RestaurantStore()..role = StaffRole.kitchen;
    addTearDown(store.dispose);
    const arroz = OrderLine(
      menuItemId: 1,
      name: 'Arroz',
      quantity: 1,
      unitPrice: 8,
    );
    const tallarin = OrderLine(
      menuItemId: 2,
      name: 'Tallarín',
      quantity: 1,
      unitPrice: 9,
    );
    final now = DateTime.now();
    final legacy = RestaurantOrder(
      id: 31,
      tableId: 1,
      tableNumber: 1,
      createdAt: now,
      lines: const [arroz, tallarin],
      incident: 'Se pasó de cocción',
    );
    final newOrder = RestaurantOrder(
      id: 32,
      tableId: 2,
      tableNumber: 2,
      createdAt: now,
      lines: const [arroz, tallarin],
    );
    store.orders
      ..clear()
      ..addAll([legacy, newOrder]);
    await tester.pumpWidget(
      MaterialApp(
        home: ListenableBuilder(
          listenable: store,
          builder: (context, _) => KitchenScreen(store: store),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final filter = find.text('Con observaciones');
    await tester.tap(filter);
    await tester.pumpAndSettle();
    expect(find.text('Mesa 1 · #31'), findsOneWidget);
    expect(find.textContaining('Platillo: Sin identificar'), findsOneWidget);
    expect(find.text('Mesa 2 · #32'), findsNothing);

    await tester.tap(filter);
    await tester.pumpAndSettle();
    final card = find
        .ancestor(of: find.text('Mesa 2 · #32'), matching: find.byType(Card))
        .first;
    final report = find
        .descendant(of: card, matching: find.text('Reportar incidencia'))
        .last;
    await tester.ensureVisible(report);
    await tester.pumpAndSettle();
    await tester.tap(report);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('incident-dish')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 × Tallarín').hitTestable());
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('incident-reason')),
      'Llegó frío',
    );
    await tester.tap(find.text('Registrar incidencia'));
    await tester.pumpAndSettle();

    expect(store.orders.last.kitchenIncident, ('Tallarín', 'Llegó frío'));
    await tester.scrollUntilVisible(
      filter,
      -220,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(filter);
    await tester.pumpAndSettle();
    expect(find.text('Mesa 2 · #32'), findsOneWidget);
    expect(find.textContaining('Platillo: Tallarín'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Delivery de Mesero acepta hasta nueve dígitos', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = RestaurantStore()..role = StaffRole.waiter;
    addTearDown(store.dispose);
    await tester.pumpWidget(MaterialApp(home: WaiterScreen(store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delivery'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nombre del cliente'),
      'Ana3 Peña24',
    );
    expect(find.text('Ana Peña'), findsOneWidget);
    expect(RestaurantStore.isValidDeliveryName('Álvaro Muñoz'), isTrue);
    expect(RestaurantStore.isValidDeliveryName('Ana 3'), isFalse);
    final phone = find.byKey(const ValueKey('customer-phone'));
    await tester.enterText(phone, '987-654 abc321012');
    await tester.pumpAndSettle();
    final editable = find.descendant(
      of: phone,
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(editable).controller.text, '987654321');
    expect(RestaurantStore.isValidCustomerPhone('987654321'), isTrue);
    expect(RestaurantStore.isValidCustomerPhone('98765432'), isFalse);
    expect(RestaurantStore.isValidCustomerPhone('9876543210'), isFalse);
  });

  testWidgets('Para llevar retira los números del nombre', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = RestaurantStore()..role = StaffRole.waiter;
    addTearDown(store.dispose);
    await tester.pumpWidget(MaterialApp(home: WaiterScreen(store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Para llevar').hitTestable().first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nombre del cliente'),
      'Ana3 Peña24',
    );
    expect(find.text('Ana Peña'), findsOneWidget);
  });

  testWidgets('El rango compacto aplica y cancela fechas en español', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    DateTimeRange? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => HistoryDateFilter(
              value: selected,
              onChanged: (range) => setState(() => selected = range),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Rango de fechas'));
    await tester.pumpAndSettle();
    expect(find.text('Desde'), findsOneWidget);
    expect(find.text('Hasta'), findsOneWidget);
    await tester.tap(find.byTooltip('Mes anterior'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '6'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();
    expect(selected?.start.day, 3);
    expect(selected?.end.day, 6);
    await tester.tap(
      find.text(
        '03/${selected!.start.month.toString().padLeft(2, '0')} – 06/${selected!.end.month.toString().padLeft(2, '0')}',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '8'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(selected?.start.day, 3);
    await tester.tap(find.byTooltip('Restablecer fechas'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Historial de Mesero agrupa y filtra por la fecha de Lima', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = limaBusinessDay(DateTime.now());
    final first = DateTime.utc(now.year, now.month - 1, 8);
    final last = first.add(const Duration(days: 4));
    final store = RestaurantStore()..role = StaffRole.waiter;
    addTearDown(store.dispose);
    store.orders
      ..clear()
      ..addAll([
        for (final (id, instant) in [
          (701, first.add(const Duration(hours: 21))),
          (702, first.add(const Duration(hours: 26))),
          (703, last.add(const Duration(hours: 12))),
        ])
          RestaurantOrder(
            id: id,
            tableNumber: 1,
            tableId: 1,
            createdAt: instant,
            lines: const [],
            status: OrderStatus.cancelled,
          ),
      ]);
    await tester.pumpWidget(MaterialApp(home: WaiterScreen(store: store)));
    final menu = tester.widget<LuxurySideMenu>(find.byType(LuxurySideMenu));
    menu.onDestinationSelected(2);
    await tester.pumpAndSettle();
    expect(find.text('${shortDate(first)}/${first.year}'), findsOneWidget);
    expect(find.text('${shortDate(last)}/${last.year}'), findsOneWidget);
    expect(find.textContaining('Pedido #702'), findsOneWidget);
    await tester.tap(find.text('Rango de fechas'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Mes anterior'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '8'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Pedido #701'), findsOneWidget);
    expect(find.textContaining('Pedido #702'), findsOneWidget);
    expect(find.textContaining('Pedido #703'), findsNothing);
  });

  testWidgets('Mesero, Cocina y Caja consultan su perfil sin editarlo', (
    tester,
  ) async {
    final store = RestaurantStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showOwnStaffProfile(context, store),
              child: const Text('Consultar mi perfil'),
            ),
          ),
        ),
      ),
    );
    for (final role in [
      StaffRole.waiter,
      StaffRole.kitchen,
      StaffRole.cashier,
    ]) {
      store.role = role;
      await tester.tap(find.text('Consultar mi perfil'));
      await tester.pumpAndSettle();
      expect(find.text('Mi perfil'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Cambiar fotografía'), findsNothing);
      expect(find.text('Guardar perfil'), findsNothing);
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('Caja conserva el diálogo tras el abono y calcula el vuelto', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = RestaurantStore()..role = StaffRole.administrator;
    addTearDown(store.dispose);
    final cashierId = store.staff
        .firstWhere((member) => member.role == StaffRole.cashier)
        .id;
    await store.setShiftOpen(true, cashierId: cashierId);
    store.role = StaffRole.cashier;
    await tester.pumpWidget(MaterialApp(home: CashierScreen(store: store)));
    await tester.pumpAndSettle();

    expect(find.text('Pedido #405'), findsOneWidget);
    final account = find.ancestor(
      of: find.text('Pedido #405'),
      matching: find.byType(Card),
    );
    final newNotice = find.descendant(
      of: account,
      matching: find.text('Cuenta nueva'),
    );
    expect(newNotice, findsOneWidget);
    await tester.tap(
      find.descendant(of: account, matching: find.text('Registrar pago')),
    );
    await tester.pumpAndSettle();

    final amountField = find.byKey(const ValueKey('payment-amount-field'));
    final receivedField = find.byKey(const ValueKey('payment-received-field'));
    expect(tester.widget<TextField>(amountField).readOnly, isTrue);
    expect(tester.widget<TextField>(amountField).controller!.text, '85.00');
    await tester.enterText(receivedField, '10');
    await tester.pumpAndSettle();
    expect(find.text('Saldo después del pago: S/ 75.00'), findsOneWidget);
    await tester.tap(find.text('Registrar abono'));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(amountField).controller!.text, '75.00');
    expect(store.orders.firstWhere((order) => order.id == 405).paid, 10);
    expect(newNotice, findsNothing);
    expect(
      find.descendant(of: account, matching: find.text('Abonado')),
      findsNothing,
    );
    await tester.enterText(receivedField, '100');
    await tester.pumpAndSettle();
    expect(find.text('Vuelto: S/ 25.00'), findsOneWidget);
    await tester.tap(find.text('Confirmar pago'));
    await tester.pumpAndSettle();

    expect(amountField, findsNothing);
    final order = store.orders.firstWhere((order) => order.id == 405);
    expect(order.paid, 85);
    expect(order.payments.last.cashReceived, 100);
    expect(
      store.receipts.where((receipt) => receipt['orderId'] == 405),
      hasLength(1),
    );
    store.role = StaffRole.administrator;
    await store.setShiftOpen(false, cashierId: cashierId);
    expect(store.closedCash, 85);
  });

  testWidgets('Administración controla turnos y Caja solo los consulta', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = RestaurantStore()..role = StaffRole.cashier;
    addTearDown(store.dispose);
    final cashier = store.staff.firstWhere(
      (member) => member.role == StaffRole.cashier,
    );
    await expectLater(
      store.setShiftOpen(false, cashierId: cashier.id),
      throwsStateError,
    );

    await tester.pumpWidget(MaterialApp(home: CashierScreen(store: store)));
    tester
        .widget<LuxurySideMenu>(find.byType(LuxurySideMenu))
        .onDestinationSelected(2);
    await tester.pumpAndSettle();
    expect(find.text('Turno cerrado'), findsOneWidget);
    expect(find.text('Cerrar caja'), findsNothing);

    store.role = StaffRole.administrator;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AdminScreen(store: store)),
      ),
    );
    tester
        .widget<LuxurySideMenu>(find.byType(LuxurySideMenu))
        .onDestinationSelected(7);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(cashier.name).hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abrir caja'));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNothing);
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(store.shiftOpen, isTrue);
    expect(find.text('Cerrar caja').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Cerrar caja'));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNothing);
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(store.shiftOpen, isFalse);
    expect(store.closedCash, 0);
    expect(find.text('Abrir caja'), findsOneWidget);
  });

  testWidgets('administración puede registrar la solución de una incidencia', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = RestaurantStore();
    addTearDown(store.dispose);
    final order = store.orders.first;
    await store.reportKitchenIncident(order, 'Faltó una guarnición');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AdminScreen(store: store)),
      ),
    );
    await tester.pumpAndSettle();
    tester
        .widget<LuxurySideMenu>(find.byType(LuxurySideMenu))
        .onDestinationSelected(6);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pedido #${order.id} · ${order.locationLabel}'));
    await tester.pumpAndSettle();

    expect(find.text('Reporte'), findsOneWidget);
    expect(find.text('Faltó una guarnición'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('incident-solution-field')),
      'Se entregó la guarnición faltante',
    );
    await tester.tap(find.text('Guardar solución'));
    await tester.pumpAndSettle();

    expect(
      store.orders.firstWhere((item) => item.id == order.id).incidentSolution,
      'Se entregó la guarnición faltante',
    );
    expect(find.text('Solucionada'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Atender reúne los avisos y registra una sola reposición', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = RestaurantStore();
    addTearDown(store.dispose);
    final initialRequestCount = store.requests.length;
    final cebolla = store.inventory.firstWhere((item) => item.id == 4);
    await store.createKitchenAlert(item: cebolla, message: 'Falta cebolla');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AdminScreen(store: store)),
      ),
    );
    await tester.pumpAndSettle();
    tester
        .widget<LuxurySideMenu>(find.byType(LuxurySideMenu))
        .onDestinationSelected(2);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alertas'));
    await tester.pumpAndSettle();
    final cebollaAlert = find.ancestor(
      of: find.text('Stock bajo: Cebolla china'),
      matching: find.byType(ResponsiveListTile),
    );
    expect(cebollaAlert, findsOneWidget);
    expect(
      find.descendant(
        of: cebollaAlert,
        matching: find.textContaining('Falta cebolla'),
      ),
      findsOneWidget,
    );
    expect(find.text('Solicitar'), findsNothing);
    await tester.ensureVisible(cebollaAlert);
    await tester.tap(
      find.descendant(of: cebollaAlert, matching: find.text('Atender')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('stock-request-quantity')),
      '0',
    );
    await tester.tap(find.text('Registrar reposición'));
    await tester.pumpAndSettle();
    expect(find.text('Ingresa una cantidad mayor a cero.'), findsOneWidget);
    expect(store.requests.length, initialRequestCount);

    await tester.enterText(
      find.byKey(const ValueKey('stock-request-quantity')),
      '4',
    );
    await tester.tap(find.text('Registrar reposición'));
    await tester.pumpAndSettle();
    expect(store.requests.length, initialRequestCount + 1);
    final newRequestId = store.requests.first.id;
    expect(
      store.alerts
          .where((alert) => alert.inventoryId == cebolla.id)
          .every((alert) => alert.status == 'REVISADA'),
      isTrue,
    );
    expect(
      store.inventory.firstWhere((item) => item.id == cebolla.id).quantity,
      cebolla.quantity,
    );

    await tester.tap(find.text('Alertas'));
    await tester.pumpAndSettle();
    final cebollaCard = find.ancestor(
      of: find.text('Stock bajo: Cebolla china'),
      matching: find.byType(Card),
    );
    await tester.tap(
      find.descendant(of: cebollaCard, matching: find.text('Ver solicitud')),
    );
    await tester.pumpAndSettle();
    expect(store.requests.length, initialRequestCount + 1);
    final requestCard = find.ancestor(
      of: find.text('Cebolla china · 4.0 KG'),
      matching: find.byType(Card),
    );
    await tester.tap(
      find.descendant(of: requestCard, matching: find.text('Procesar')),
    );
    await tester.pumpAndSettle();
    final processingRequest = store.requests.firstWhere(
      (item) => item.id == newRequestId,
    );
    expect(processingRequest.status, 'EN_PROCESO');
    await tester.tap(
      find.descendant(
        of: requestCard,
        matching: find.text('Confirmar recepción'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      store.inventory.firstWhere((item) => item.id == cebolla.id).quantity,
      cebolla.quantity + 4,
    );
    expect(
      store.requests.firstWhere((item) => item.id == newRequestId).status,
      'ATENDIDO',
    );
    await expectLater(
      store.fulfillStockRequest(processingRequest),
      throwsStateError,
    );
    expect(
      store.inventory.firstWhere((item) => item.id == cebolla.id).quantity,
      cebolla.quantity + 4,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reportes muestra meseros registrados y filtra por cuenta', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = RestaurantStore();
    addTearDown(store.dispose);
    store.staff
      ..clear()
      ..addAll(const [
        StaffMember(
          id: 'mesera-a',
          name: 'Ana Pérez',
          email: 'ana1@example.com',
          role: StaffRole.waiter,
        ),
        StaffMember(
          id: 'mesera-b',
          name: 'Ana Pérez',
          email: 'ana2@example.com',
          role: StaffRole.waiter,
        ),
        StaffMember(
          id: 'mesero-c',
          name: 'Luis Ramos',
          email: 'luis@example.com',
          role: StaffRole.waiter,
        ),
        StaffMember(
          id: 'admin',
          name: 'Usuario administrador',
          email: 'admin@example.com',
          role: StaffRole.administrator,
        ),
      ]);
    final now = DateTime.now();
    store.orders
      ..clear()
      ..addAll([
        for (final (id, waiter) in [
          (101, 'mesera-a'),
          (102, 'mesera-b'),
          (103, null),
        ])
          RestaurantOrder(
            id: id,
            tableId: 1,
            tableNumber: 1,
            createdAt: now,
            lines: const [],
            waiterId: waiter,
            waiterName: 'Mesero',
          ),
      ]);
    store.receipts
      ..clear()
      ..addAll([
        for (final (id, amount) in [(101, 35), (102, 50), (103, 80)])
          {
            'id': id,
            'orderId': id,
            'code': 'NV-$id',
            'tableNumber': 1,
            'total': amount,
            'createdAt': now.toIso8601String(),
            'status': 'VIGENTE',
          },
      ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AdminScreen(store: store)),
      ),
    );
    await tester.pumpAndSettle();
    tester
        .widget<LuxurySideMenu>(find.byType(LuxurySideMenu))
        .onDestinationSelected(5);
    await tester.pumpAndSettle();
    final dropdown = find.byKey(const ValueKey('report-waiter'));
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    expect(find.text('Luis Ramos').hitTestable(), findsOneWidget);
    expect(find.text('Usuario administrador'), findsNothing);
    await tester.tap(find.text('Ana Pérez (ana2@example.com)').hitTestable());
    await tester.pumpAndSettle();
    expect(find.textContaining('NV-102'), findsWidgets);
    expect(find.textContaining('NV-101'), findsNothing);
    expect(find.textContaining('NV-103'), findsNothing);
    expect(find.text('S/ 50.00'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la auditoría está disponible para gerente, no administrador', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = RestaurantStore();
    addTearDown(store.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AdminScreen(store: store)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Historial'), findsNothing);
    store.role = StaffRole.manager;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AdminScreen(store: store, managerOnly: true)),
      ),
    );
    await tester.pumpAndSettle();
    final menu = tester.widget<LuxurySideMenu>(find.byType(LuxurySideMenu));
    expect(
      menu.entries.any((entry) => entry.label.startsWith('Usuarios')),
      isFalse,
    );
    menu.onDestinationSelected(
      menu.entries.indexWhere((entry) => entry.label == 'Historial'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Historial de movimientos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
