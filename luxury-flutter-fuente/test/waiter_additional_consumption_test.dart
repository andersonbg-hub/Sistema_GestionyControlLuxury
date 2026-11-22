import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luxury_app/data/restaurant_store.dart';
import 'package:luxury_app/models/models.dart';
import 'package:luxury_app/views/waiter/waiter_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'El mesero agrega consumos desde la mesa y el pedido a una cuenta',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = RestaurantStore()..role = StaffRole.waiter;
      addTearDown(store.dispose);
      final table = store.tables.singleWhere((table) => table.number == 1);
      final originalProduct = store.menu.firstWhere(
        (item) => item.name == 'Wantán frito',
      );
      final addedProduct = store.menu.firstWhere(
        (item) => item.name == 'Rollitos primavera',
      );
      await store.createOrder(
        table: table,
        diners: 3,
        lines: [
          OrderLine(
            menuItemId: originalProduct.id,
            name: originalProduct.name,
            quantity: 1,
            unitPrice: originalProduct.price,
          ),
        ],
      );
      final orderId = store.additionalOrderParent(table)!.id;
      await store.advanceOrder(
        store.orders.firstWhere((order) => order.id == orderId),
      );
      RestaurantOrder current() =>
          store.orders.firstWhere((order) => order.id == orderId);
      Future<void> tap(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      Future<void> addConsumption() async {
        expect(find.text('Consumo adicional · Mesa 1'), findsOneWidget);
        expect(find.text('3 / 4'), findsOneWidget);
        expect(find.byType(DropdownButton<int>), findsNothing);
        expect(find.text('0 productos'), findsOneWidget);
        await tap(find.byKey(ValueKey('add-menu-item-${addedProduct.id}')));
        await tap(find.text('Agregar consumo'));
        expect(
          find.text(
            'Mesa 1 · S/ 15.00. Se sumará a la cuenta del pedido #$orderId.',
          ),
          findsOneWidget,
        );
        await tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Agregar consumo'),
          ),
        );
      }

      await tester.pumpWidget(
        MaterialApp(
          home: ListenableBuilder(
            listenable: store,
            builder: (context, _) => WaiterScreen(store: store),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tap(find.text('Mesa 1'));
      await tap(find.text('Agregar consumo'));
      await addConsumption();
      expect(current().lines.length, 2);
      expect(current().lines.first.status, OrderStatus.preparing);
      expect(current().total, originalProduct.price + addedProduct.price);
      expect(
        store.orders.where(
          (order) => order.tableId == table.id && !order.retirementConfirmed,
        ),
        hasLength(1),
      );

      await tap(find.text('Pedido #$orderId · Mesa 1'));
      await tap(find.byKey(ValueKey('add-consumption-$orderId')));
      await addConsumption();
      expect(current().lines.length, 3);
      expect(current().lines.first.status, OrderStatus.preparing);
      expect(current().total, originalProduct.price + addedProduct.price * 2);
      expect(current().diners, 3);
      expect(
        store.orders.where((order) => order.parentOrderId == orderId),
        isEmpty,
      );

      if (find.text('Mostrar cuenta').evaluate().isEmpty) {
        await tap(find.text('Pedido #$orderId · Mesa 1'));
      }
      await tap(find.text('Mostrar cuenta'));
      Finder billText(String value) => find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(value),
      );
      expect(billText('Mesa 1 · Pedido #$orderId'), findsOneWidget);
      expect(billText('1 × ${originalProduct.name}'), findsOneWidget);
      expect(billText('1 × ${addedProduct.name}'), findsNWidgets(2));
      expect(billText('S/ 48.00'), findsOneWidget);
      await tap(find.text('Cerrar'));

      store.pendingOrders.add(
        RestaurantOrder(
          id: -1,
          tableId: table.id,
          tableNumber: table.number,
          createdAt: DateTime.now(),
          diners: 3,
          parentOrderId: orderId,
          pendingSync: true,
          appendsToAccount: true,
          lines: [
            OrderLine(
              menuItemId: addedProduct.id,
              name: addedProduct.name,
              quantity: 1,
              unitPrice: addedProduct.price,
            ),
          ],
        ),
      );
      await tap(find.text('Mostrar cuenta'));
      expect(find.text('Precuenta'), findsNothing);
      expect(
        find.text(
          'Hay consumos pendientes de sincronización. Actualiza los pedidos antes de mostrar la cuenta al cliente.',
        ),
        findsOneWidget,
      );
      await tap(find.text('Continuar'));
      store.pendingOrders.clear();

      await tester.runAsync(() => store.setOrderForPayment(current()));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('add-consumption-$orderId')), findsNothing);
    },
  );
}
