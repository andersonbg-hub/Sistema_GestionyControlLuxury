import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luxury_app/models/models.dart';
import 'package:luxury_app/views/waiter/waiter_screen.dart';
import 'package:luxury_app/views/kitchen/kitchen_screen.dart';
import 'package:luxury_app/data/restaurant_store.dart';

void main() {
  testWidgets('Mis pedidos usa el corte de Lima y conserva el historial', (
    tester,
  ) async {
    final store = _prepare(tester);
    await tester.pumpWidget(MaterialApp(home: WaiterScreen(store: store)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mis pedidos'));
    await tester.pumpAndSettle();
    expect(find.text('Pedido #901 · Mesa 1'), findsOneWidget);
    expect(find.text('Pedido #902 · Mesa 2'), findsNothing);

    await tester.tap(find.text('Historial').first);
    await tester.pumpAndSettle();
    expect(find.text('Pedido #902 · Mesa 2'), findsOneWidget);
    expect(find.text('Pedido #901 · Mesa 1'), findsNothing);
  });

  testWidgets('Comandas usa el corte de Lima y conserva el historial', (
    tester,
  ) async {
    final store = _prepare(tester);
    await tester.pumpWidget(MaterialApp(home: KitchenScreen(store: store)));
    await tester.pumpAndSettle();

    expect(find.text('Mesa 1 · #901'), findsOneWidget);
    expect(find.text('Mesa 2 · #902'), findsNothing);

    await tester.tap(find.text('Historial').first);
    await tester.pumpAndSettle();
    expect(find.text('Mesa 2 · #902'), findsOneWidget);
    expect(find.text('Mesa 1 · #901'), findsNothing);
  });
}

RestaurantStore _prepare(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final store = RestaurantStore();
  addTearDown(store.dispose);
  final midnightLima = limaBusinessDay(
    DateTime.now(),
  ).add(const Duration(hours: 5));
  const lines = [
    OrderLine(menuItemId: 1, name: 'Arroz', quantity: 1, unitPrice: 10),
  ];
  store.orders
    ..clear()
    ..addAll([
      RestaurantOrder(
        id: 901,
        tableId: 1,
        tableNumber: 1,
        createdAt: midnightLima,
        lines: lines,
      ),
      RestaurantOrder(
        id: 902,
        tableId: 2,
        tableNumber: 2,
        createdAt: midnightLima.subtract(const Duration(seconds: 1)),
        lines: lines,
      ),
    ]);
  return store;
}
