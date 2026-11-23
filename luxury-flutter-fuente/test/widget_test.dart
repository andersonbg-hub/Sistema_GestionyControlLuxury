import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luxury_app/main.dart';
import 'package:luxury_app/core/app_widgets.dart';
import 'package:luxury_app/data/restaurant_store.dart';
import 'package:luxury_app/models/models.dart';
import 'package:luxury_app/views/waiter/waiter_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Supabase exige acceso con cuenta y no ofrece roles demo', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final respondToLogin = Completer<void>();
    var loginAttempts = 0;
    late SupabaseClient client;
    await tester.runAsync(() async {
      client = SupabaseClient(
        'https://test.supabase.co',
        'sb_publishable_test',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((_) async {
          loginAttempts++;
          await respondToLogin.future;
          return http.Response(
            '{"error_code":"invalid_credentials","message":"Invalid login credentials"}',
            400,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
    });
    await tester.pumpWidget(LuxuryApp(client: client));
    await tester.pumpAndSettle();
    expect(find.text('Correo'), findsOneWidget);
    expect(find.text('Contraseña'), findsOneWidget);
    expect(
      find.text('Elige el espacio de trabajo para recorrer la demostración.'),
      findsNothing,
    );
    expect(find.textContaining('Modo local de demostración:'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Iniciar sesión').first).dx,
      greaterThan(550),
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/images/portada_restaurante.webp',
      ),
      findsOneWidget,
    );
    expect(
      tester.getCenter(find.byType(Image)).dx,
      closeTo(26 + (1280 - 52) * .2, 1),
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is ColoredBox && widget.color == Colors.white,
      ),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField).first, 'john');
    await tester.tap(find.widgetWithText(FilledButton, 'Iniciar sesión'));
    await tester.pumpAndSettle();
    expect(
      find.text('Usa un correo válido, como nombre@empresa.com'),
      findsOneWidget,
    );
    expect(find.byType(LoginFieldError), findsWidgets);
    expect(find.text('¿Olvidaste tu contraseña?'), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'john@example.com');
    await tester.enterText(find.byType(TextField).last, 'wrong-password');
    await tester.tap(find.widgetWithText(FilledButton, 'Iniciar sesión'));
    await tester.pump();
    expect(find.text('Conectando…'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    final button = find.widgetWithText(FilledButton, 'Iniciar sesión');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.tap(button);
    expect(loginAttempts, 1);
    respondToLogin.complete();
    await tester.pumpAndSettle();
    expect(
      find.text('El correo o la contraseña son incorrectos.'),
      findsOneWidget,
    );
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.textContaining('invalid_credentials'), findsNothing);
    expect(tester.takeException(), isNull);
    for (final size in const [
      Size(320, 600),
      Size(390, 844),
      Size(768, 1024),
      Size(844, 390),
      Size(1024, 360),
      Size(1920, 910),
      Size(2865, 1360),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      final button = find.widgetWithText(FilledButton, 'Iniciar sesión');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      expect(button.hitTestable(), findsOneWidget, reason: '$size');
      expect(tester.takeException(), isNull, reason: '$size');
    }
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(client.dispose);
  });

  testWidgets(
    'La campana confirma la recepción y retira los platos listos de Cocina',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const first = OrderLine(
        id: 7201,
        menuItemId: 1,
        name: 'Wantán',
        quantity: 1,
        unitPrice: 18,
        status: OrderStatus.ready,
      );
      const second = OrderLine(
        id: 7202,
        menuItemId: 2,
        name: 'Rollitos',
        quantity: 2,
        unitPrice: 15,
        status: OrderStatus.ready,
      );
      const newDish = OrderLine(
        id: 7203,
        menuItemId: 3,
        name: 'Sopa nueva',
        quantity: 1,
        unitPrice: 16,
        status: OrderStatus.ready,
      );
      RestaurantOrder order(int orderId, List<OrderLine> dishes) =>
          RestaurantOrder(
            id: orderId,
            tableId: 1,
            tableNumber: 1,
            createdAt: DateTime.now(),
            status: OrderStatus.ready,
            lines: dishes,
          );

      Future<RestaurantStore> openWaiter() async {
        await tester.pumpWidget(const LuxuryApp());
        await tester.pumpAndSettle();
        await tester.tap(find.text('Mesero').hitTestable().first);
        await tester.pumpAndSettle();
        return tester.widget<WaiterScreen>(find.byType(WaiterScreen)).store;
      }

      Future<void> showOrders(
        RestaurantStore store,
        List<RestaurantOrder> orders,
      ) async {
        store.orders
          ..clear()
          ..addAll(orders);
        await store.refresh();
        await tester.pumpAndSettle();
      }

      Finder bell(int count) =>
          find.byTooltip('Platos listos para servir ($count)');
      Finder notice(int id) => find.text('Mesa 1 · #$id');

      var store = await openWaiter();
      await showOrders(store, [
        order(72, [first, newDish.copyWith(status: OrderStatus.preparing)]),
        order(73, [second]),
      ]);
      await tester.tap(bell(2));
      await tester.pumpAndSettle();
      expect(notice(72), findsOneWidget);
      expect(notice(73), findsOneWidget);
      await tester.tap(notice(72));
      await tester.pumpAndSettle();
      expect(notice(72), findsNothing);
      expect(notice(73), findsOneWidget);
      expect(bell(1), findsOneWidget);
      expect(store.orders.first.lines.map((line) => line.status), [
        OrderStatus.delivered,
        OrderStatus.preparing,
      ]);
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();
      await store.loginDemo(StaffRole.kitchen);
      await tester.pumpAndSettle();
      expect(find.text('Listas (1)'), findsOneWidget);
      expect(find.text('En preparación (1)'), findsOneWidget);
      expect(notice(73), findsOneWidget);
      expect(find.text('Wantán'), findsNothing);

      await store.loginDemo(StaffRole.waiter);
      await tester.pumpAndSettle();
      await tester.tap(bell(1));
      await tester.pumpAndSettle();
      await showOrders(store, [
        store.orders.first.copyWith(
          lines: [store.orders.first.lines.first, newDish],
        ),
        store.orders.last,
      ]);
      expect(notice(72), findsOneWidget);
      expect(find.text('1× Sopa nueva'), findsOneWidget);
      expect(find.text('1× Wantán'), findsNothing);
      await tester.tap(notice(72));
      await tester.pumpAndSettle();
      await tester.tap(notice(73));
      await tester.pumpAndSettle();
      expect(find.text('No hay avisos nuevos.'), findsOneWidget);
      expect(bell(0), findsOneWidget);
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      store = await openWaiter();
      expect(
        store.orders.expand((order) => order.lines).map((line) => line.status),
        everyElement(OrderStatus.delivered),
      );
      expect(bell(0), findsOneWidget);
      await tester.tap(bell(0));
      await tester.pumpAndSettle();
      expect(find.text('No hay avisos nuevos.'), findsOneWidget);
    },
  );

  testWidgets('Mesero abre Mi perfil desde el menú de la cuenta', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const LuxuryApp());
    await tester.pumpAndSettle();
    final loginTheme = Theme.of(
      tester.element(find.text('Bienvenido a Luxury')),
    );
    expect(loginTheme.colorScheme.primary, luxuryGold);
    expect(loginTheme.colorScheme.error, luxuryRed);
    final waiter = find.text('Mesero');
    await tester.ensureVisible(waiter);
    await tester.tap(waiter);
    await tester.pumpAndSettle();
    final workTheme = Theme.of(tester.element(find.byType(LuxurySideMenu)));
    expect(workTheme.colorScheme.primary, luxuryPaletteOrange);
    expect(workTheme.colorScheme.secondary, luxuryPaletteGold);
    expect(workTheme.colorScheme.tertiary, luxuryPaletteGreen);
    expect(workTheme.colorScheme.error, luxuryPaletteRed);
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Supabase'), findsNothing);
    expect(workTheme.navigationRailTheme.backgroundColor, luxuryPaletteDark);
    expect(workTheme.popupMenuTheme.color, const Color(0xFFFFFEFB));
    expect(workTheme.popupMenuTheme.elevation, 14);
    expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Modo demostración'), findsOneWidget);
    expect(find.text('Reiniciar demostración'), findsOneWidget);
    expect(find.text('Actualizar información'), findsNothing);
    expect(find.text('Cerrar sesión'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Cerrar sesión')).style?.color,
      luxuryPaletteRed,
    );
    await tester.tap(find.text('Mi perfil'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AlertDialog, 'Mi perfil'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('los avisos de operaciones usan un diálogo de resultado', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => showResultDialog(
                  context,
                  success: true,
                  message: 'Pedido guardado.',
                ),
                child: const Text('Mostrar'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Mostrar'));
    await tester.pumpAndSettle();
    expect(find.text('¡Listo!'), findsOneWidget);
    expect(find.text('Pedido guardado.'), findsOneWidget);
    final barriers = tester.widgetList<ModalBarrier>(find.byType(ModalBarrier));
    expect(
      barriers.any((barrier) => barrier.color == const Color(0xB317181D)),
      isTrue,
    );
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.text('¡Listo!'), findsNothing);
  });
}
