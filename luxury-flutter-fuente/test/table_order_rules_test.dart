import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luxury_app/models.dart';
import 'package:luxury_app/service_screen.dart';
import 'package:luxury_app/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const item = OrderLine(
  menuItemId: 1,
  name: 'Wantán frito',
  quantity: 1,
  unitPrice: 18,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'an occupied table accepts linked orders until billing starts',
    () async {
      final store = RestaurantStore();
      addTearDown(store.dispose);
      final table = store.tables.first;
      await store.createOrder(table: table, diners: 2, lines: const [item]);
      final mainOrder = store.orders.first;

      await store.advanceOrder(mainOrder);
      final preparing = store.orders.first;
      await store.createOrder(
        table: table,
        diners: 2,
        lines: const [item],
        parentOrderId: preparing.id,
      );
      final child = store.orders.first;
      expect(child.parentOrderId, mainOrder.id);
      expect(child.status, OrderStatus.pending);
      expect(preparing.status, OrderStatus.preparing);

      await store.setOrderForPayment(preparing);
      expect(store.tables.first.status, TableStatus.payment);
      expect(store.canOrderAtTable(table), isFalse);
      await expectLater(
        store.createOrder(
          table: table,
          diners: 2,
          lines: const [item],
          parentOrderId: child.id,
        ),
        throwsStateError,
      );
      await expectLater(
        store.editOrder(order: child, diners: 2, lines: const [item]),
        throwsStateError,
      );
    },
  );

  test('a paid table remains locked until guests have left', () async {
    final store = RestaurantStore();
    addTearDown(store.dispose);
    final table = store.tables.first;
    await store.createOrder(table: table, diners: 2, lines: const [item]);
    final order = store.orders.first;
    await store.recordPayment(
      order: order,
      method: 'Efectivo',
      amount: 18,
      cashReceived: 18,
      earlyPaymentConfirmed: true,
    );

    expect(store.canOrderAtTable(table), isFalse);
    final paid = store.orders.first;
    await store.advanceOrder(paid);
    await store.advanceOrder(store.orders.first);
    await store.advanceOrder(store.orders.first);
    await store.confirmTableRelease(table);
    expect(store.canOrderAtTable(table), isTrue);
  });

  testWidgets('red tables show the billing lock and occupied tables can add', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = RestaurantStore();
    addTearDown(store.dispose);

    await tester.pumpWidget(MaterialApp(home: WaiterScreen(store: store)));
    await tester.tap(find.text('Mesa 4'));
    await tester.pumpAndSettle();
    expect(find.text('La mesa ya está en cobro'), findsOneWidget);
    expect(find.text('Agregar pedido'), findsNothing);
    expect(find.text('Nuevo pedido').hitTestable(), findsNothing);

    final sheet = find.byType(BottomSheet);
    await tester.drag(sheet, const Offset(0, 700));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mesa 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agregar pedido'));
    await tester.pumpAndSettle();
    expect(find.text('Consumo adicional · Mesa 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
