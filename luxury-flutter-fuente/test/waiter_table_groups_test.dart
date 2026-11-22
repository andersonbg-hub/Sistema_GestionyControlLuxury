import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luxury_app/data/restaurant_store.dart';
import 'package:luxury_app/models/models.dart';
import 'package:luxury_app/views/waiter/waiter_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('El mesero junta, cobra y libera las mesas desde el plano', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = RestaurantStore()..role = StaffRole.waiter;
    addTearDown(store.dispose);
    RestaurantTable table(int number) =>
        store.tables.firstWhere((table) => table.number == number);
    final product = store.menu.firstWhere((item) => item.available);

    Future<void> tap(Finder finder) async {
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Future<void> sendProduct({bool additional = false}) async {
      await tap(find.byKey(ValueKey('add-menu-item-${product.id}')));
      final action = additional ? 'Agregar consumo' : 'Registrar pedido';
      await tap(find.text(action));
      await tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(action),
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
    await tap(find.text('Juntar mesas'));
    final continueButton = find.widgetWithText(
      FilledButton,
      'Continuar al pedido',
    );
    expect(tester.widget<FilledButton>(continueButton).onPressed, isNull);
    expect(find.widgetWithText(CheckboxListTile, 'Mesa 2'), findsNothing);
    await tap(find.widgetWithText(CheckboxListTile, 'Mesa 3'));
    expect(tester.widget<FilledButton>(continueButton).onPressed, isNull);
    await tap(find.widgetWithText(CheckboxListTile, 'Mesa 1'));
    expect(find.text('Mesas 1 + 3 · 6 asientos en total'), findsOneWidget);
    await tap(continueButton);
    expect(find.text('Nueva comanda · Mesas 1 + 3'), findsOneWidget);
    expect(table(1).status, TableStatus.available);
    expect(table(3).status, TableStatus.available);
    await tap(find.byType(DropdownButton<int>));
    await tap(find.text('6').last);
    await sendProduct();

    final group = store.tableGroupFor(table(1))!;
    expect(group.diners, 6);
    expect(group.locationLabel, 'Mesas 1 + 3');
    expect(store.tableGroupFor(table(3))?.id, group.id);
    expect(table(1).status, TableStatus.occupied);
    expect(table(3).status, TableStatus.occupied);

    await tap(find.text('Mesas'));
    expect(find.text('Mesas 1 + 3'), findsNWidgets(2));
    await tap(find.text('Mesa 3'));
    await tap(find.text('Mostrar cuenta'));
    expect(find.text('Mesas 1 + 3 · Pedido #${group.id}'), findsOneWidget);
    expect(find.text('1 × ${product.name}'), findsOneWidget);
    await tap(find.text('Cerrar'));

    await tap(find.text('Mesa 3'));
    await tap(find.text('Agregar consumo'));
    expect(find.text('Consumo adicional · Mesas 1 + 3'), findsOneWidget);
    expect(find.text('6 / 6'), findsOneWidget);
    await sendProduct(additional: true);
    expect(store.tableGroupFor(table(1))?.id, group.id);
    expect(store.tableGroupFor(table(3))?.total, product.price * 2);

    await tester.runAsync(() async {
      RestaurantOrder current() =>
          store.orders.firstWhere((order) => order.id == group.id);
      await store.advanceOrder(current());
      await store.advanceOrder(current());
      await store.advanceOrder(current());
      await store.setOrderForPayment(current());
      store.role = StaffRole.administrator;
      await store.setShiftOpen(true, cashierId: 'demo-caja');
      store.role = StaffRole.cashier;
      final balance = current().balance;
      await store.recordPayment(
        order: current(),
        method: 'Efectivo',
        amount: balance,
        cashReceived: balance,
      );
      store.role = StaffRole.waiter;
    });
    await tester.pumpAndSettle();
    expect(table(1).status, isNot(TableStatus.available));
    expect(table(3).status, isNot(TableStatus.available));
    await tap(find.text('Mesas'));
    await tap(find.text('Mesa 3'));
    await tap(find.text('Confirmar retiro y liberar mesas'));
    await tap(find.text('Liberar mesas'));
    expect(table(1).status, TableStatus.available);
    expect(table(3).status, TableStatus.available);
    expect(find.text('Mesas 1 + 3'), findsNothing);
    expect(
      store.orders.firstWhere((order) => order.id == group.id).locationLabel,
      'Mesas 1 + 3',
    );
  });
}
