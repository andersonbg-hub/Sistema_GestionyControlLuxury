import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luxury_app/data/restaurant_store.dart';
import 'package:luxury_app/models/models.dart';
import 'package:luxury_app/views/waiter/waiter_screen.dart';

void main() {
  testWidgets('El mesero puede mostrar la precuenta de una mesa sin cobrar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = RestaurantStore();
    addTearDown(store.dispose);
    final table = store.tables.first;
    final otherTable = store.tables[1];
    final now = DateTime.now();
    final orders = [
      RestaurantOrder(
        id: 901,
        tableId: table.id,
        tableNumber: table.number,
        createdAt: now,
        status: OrderStatus.ready,
        lines: const [
          OrderLine(menuItemId: 1, name: 'Chaufa', quantity: 2, unitPrice: 18),
        ],
      ),
      RestaurantOrder(
        id: 902,
        tableId: table.id,
        tableNumber: table.number,
        createdAt: now,
        parentOrderId: 901,
        lines: const [
          OrderLine(menuItemId: 2, name: 'Limonada', quantity: 1, unitPrice: 6),
        ],
        payments: [
          PaymentEntry(method: 'Efectivo', amount: 4, createdAt: now),
        ],
      ),
      RestaurantOrder(
        id: 903,
        tableId: table.id,
        tableNumber: table.number,
        createdAt: now,
        status: OrderStatus.cancelled,
        lines: const [
          OrderLine(menuItemId: 3, name: 'Sopa', quantity: 1, unitPrice: 30),
        ],
      ),
      RestaurantOrder(
        id: 904,
        tableId: table.id,
        tableNumber: table.number,
        createdAt: now.subtract(const Duration(days: 1)),
        status: OrderStatus.paid,
        retirementConfirmed: true,
        lines: const [
          OrderLine(menuItemId: 4, name: 'Wontán', quantity: 1, unitPrice: 20),
        ],
      ),
      RestaurantOrder(
        id: 905,
        tableId: otherTable.id,
        tableNumber: otherTable.number,
        createdAt: now,
        lines: const [
          OrderLine(menuItemId: 5, name: 'Té', quantity: 1, unitPrice: 8),
        ],
      ),
    ];
    store.orders
      ..clear()
      ..addAll(orders);

    await tester.pumpWidget(MaterialApp(home: WaiterScreen(store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mesa ${table.number}'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mostrar cuenta'));
    await tester.pumpAndSettle();

    Finder billText(String text) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(text),
    );
    for (final text in [
      'Precuenta',
      '2 × Chaufa',
      'S/ 18.00 por unidad',
      'S/ 36.00',
      '1 × Limonada',
      'Total',
      'S/ 42.00',
      'Abonado',
      'S/ 4.00',
      'Saldo pendiente',
      'S/ 38.00',
    ]) {
      expect(billText(text), findsOneWidget);
    }
    for (final text in ['1 × Sopa', '1 × Wontán', '1 × Té']) {
      expect(billText(text), findsNothing);
    }
    await tester.tap(billText('Cerrar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mis pedidos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pedido #901 · Mesa ${table.number}'));
    await tester.pumpAndSettle();
    expect(find.text('Solicitar cuenta'), findsOneWidget);
    await tester.tap(find.text('Mostrar cuenta'));
    await tester.pumpAndSettle();
    expect(billText('S/ 42.00'), findsOneWidget);
    expect(store.orders, orders);
  });
}
