import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luxury_app/models/models.dart';
import 'package:luxury_app/views/kitchen/kitchen_screen.dart';
import 'package:luxury_app/data/restaurant_store.dart';

void main() {
  testWidgets('Cocina combina los filtros de etapa y búsqueda', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = RestaurantStore()..role = StaffRole.kitchen;
    addTearDown(store.dispose);
    final now = DateTime.now();
    store.orders
      ..clear()
      ..addAll([
        RestaurantOrder(
          id: 31,
          tableId: 1,
          tableNumber: 1,
          createdAt: now,
          lines: const [
            OrderLine(menuItemId: 1, name: 'Arroz', quantity: 1, unitPrice: 8),
          ],
        ),
        RestaurantOrder(
          id: 32,
          tableId: 2,
          tableNumber: 2,
          createdAt: now,
          lines: const [
            OrderLine(
              menuItemId: 2,
              name: 'Tallarín',
              quantity: 2,
              unitPrice: 9,
              status: OrderStatus.ready,
            ),
          ],
        ),
      ]);
    await tester.pumpWidget(MaterialApp(home: KitchenScreen(store: store)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Listas (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Mesa 1 · #31'), findsNothing);
    expect(find.text('Mesa 2 · #32'), findsOneWidget);
    expect(find.textContaining('2 porciones'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'arroz');
    await tester.pumpAndSettle();
    expect(
      find.text('No hay comandas que coincidan con la búsqueda.'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Limpiar búsqueda'));
    await tester.pumpAndSettle();
    expect(find.text('Mesa 2 · #32'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Un consumo adicional conserva las etapas de cada plato', (
    tester,
  ) async {
    final now = DateTime.now();
    final store = RestaurantStore()..role = StaffRole.kitchen;
    addTearDown(store.dispose);
    store.orders
      ..clear()
      ..add(
        RestaurantOrder(
          id: 45,
          tableId: 1,
          tableNumber: 1,
          createdAt: now,
          lines: [
            OrderLine(
              menuItemId: 901,
              name: 'Min pao',
              quantity: 1,
              unitPrice: 3,
              createdAt: now,
            ),
            OrderLine(
              menuItemId: 902,
              name: 'Arroz',
              quantity: 1,
              unitPrice: 8,
              status: OrderStatus.preparing,
              createdAt: now,
            ),
            OrderLine(
              menuItemId: 903,
              name: 'Tallarín servido',
              quantity: 1,
              unitPrice: 9,
              status: OrderStatus.delivered,
              createdAt: now,
            ),
          ],
        ),
      );
    await tester.pumpWidget(MaterialApp(home: KitchenScreen(store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nuevas (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Min pao'), findsOneWidget);
    expect(find.text('Arroz'), findsNothing);
    expect(find.text('Tallarín servido'), findsNothing);
    await tester.tap(find.text('En preparación (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Arroz'), findsOneWidget);
    expect(find.text('Min pao'), findsNothing);
    expect(find.text('Tallarín servido'), findsNothing);
  });
}
