import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luxury_app/app_widgets.dart';
import 'package:luxury_app/models.dart';
import 'package:luxury_app/service_screen.dart';
import 'package:luxury_app/store.dart';

void main() {
  testWidgets('Caja separa cuentas anteriores y suma pagos del día de Lima', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = RestaurantStore();
    addTearDown(store.dispose);
    final businessDay = limaBusinessDay(DateTime.now());
    final beforeMidnight = businessDay.add(
      const Duration(hours: 4, minutes: 59),
    );
    final afterMidnight = businessDay.add(const Duration(hours: 5, minutes: 1));
    const lines = [
      OrderLine(
        menuItemId: 1,
        name: 'Plato de prueba',
        quantity: 1,
        unitPrice: 100,
      ),
    ];
    store.orders
      ..clear()
      ..addAll([
        RestaurantOrder(
          id: 301,
          tableId: 1,
          tableNumber: 1,
          createdAt: beforeMidnight,
          lines: lines,
          payments: [
            PaymentEntry(
              method: 'Efectivo',
              amount: 50,
              createdAt: beforeMidnight,
            ),
            PaymentEntry(
              method: 'Efectivo',
              amount: 10,
              createdAt: afterMidnight,
            ),
          ],
        ),
        RestaurantOrder(
          id: 302,
          tableId: 2,
          tableNumber: 2,
          createdAt: afterMidnight,
          lines: lines,
          payments: [
            PaymentEntry(
              method: 'Tarjeta',
              amount: 20,
              createdAt: afterMidnight,
            ),
          ],
        ),
      ]);

    await tester.pumpWidget(MaterialApp(home: CashierScreen(store: store)));
    await tester.pumpAndSettle();
    expect(find.text('Pedido #301 · Mesa 1'), findsNothing);
    expect(find.text('Pedido #302 · Mesa 2'), findsOneWidget);

    await tester.tap(find.text('Pendientes anteriores'));
    await tester.pumpAndSettle();
    expect(find.text('Pedido #301 · Mesa 1'), findsOneWidget);
    expect(find.text('Pedido #302 · Mesa 2'), findsNothing);

    tester
        .widget<LuxurySideMenu>(find.byType(LuxurySideMenu))
        .onDestinationSelected(2);
    await tester.pumpAndSettle();
    expect(find.text('S/ 10.00'), findsOneWidget);
    expect(find.text('S/ 30.00'), findsOneWidget);
    expect(find.text('S/ 50.00'), findsNothing);
  });
}
