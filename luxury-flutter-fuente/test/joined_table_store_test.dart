import 'package:flutter_test/flutter_test.dart';
import 'package:luxury_app/data/restaurant_store.dart';
import 'package:luxury_app/models/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

const food = OrderLine(
  menuItemId: 1,
  name: 'Wantán frito',
  quantity: 1,
  unitPrice: 18,
);
const drink = OrderLine(
  menuItemId: 10,
  name: 'Chicha morada jarra',
  quantity: 1,
  unitPrice: 14,
);

RestaurantTable table(RestaurantStore store, int number) =>
    store.tables.singleWhere((item) => item.number == number);

Future<void> join(RestaurantStore store, {int diners = 6}) {
  final first = table(store, 1);
  final third = table(store, 3);
  return store.createOrder(
    table: third,
    joinedTables: [third, first],
    diners: diners,
    lines: const [food],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('joined tables share the same order, payment and retirement', () async {
    final store = RestaurantStore();
    addTearDown(store.dispose);
    await join(store);
    final first = table(store, 1);
    final third = table(store, 3);
    final group = store.tableGroupFor(third)!;
    expect(group.locationLabel, 'Mesas 1 + 3');
    expect(group.groupTableIds, [first.id, third.id]);
    expect(group.groupTableNumbers, [1, 3]);
    expect(store.serviceTableFor(third).id, first.id);
    expect(store.tableServiceCapacity(third), 6);
    expect(store.canJoinTable(first), isFalse);
    expect(first.status, TableStatus.occupied);
    expect(third.status, TableStatus.occupied);

    await store.advanceOrder(group);
    await store.createOrder(
      table: third,
      lines: const [drink],
      diners: 6,
      parentOrderId: group.id,
    );
    final combined = store.tableGroupFor(first)!;
    expect(combined.id, group.id);
    expect(
      store.orders.where((entry) => entry.parentOrderId == group.id),
      isEmpty,
    );
    expect(combined.lines.map((line) => line.status), [
      OrderStatus.preparing,
      OrderStatus.pending,
    ]);
    expect(combined.balance, 32);

    await store.setOrderForPayment(combined);
    expect(table(store, 1).status, TableStatus.payment);
    expect(table(store, 3).status, TableStatus.payment);
    expect(store.canOrderAtTable(third), isFalse);
    await expectLater(
      store.createOrder(
        table: third,
        lines: const [drink],
        diners: 6,
        parentOrderId: group.id,
      ),
      throwsStateError,
    );
    await expectLater(store.confirmTableRelease(third), throwsStateError);

    expect(store.canConfirmWaiterService(combined), isTrue);
    await store.confirmWaiterService(combined);
    await store.advanceOrder(combined);
    await store.advanceOrder(combined);
    store.role = StaffRole.administrator;
    await store.setShiftOpen(true, cashierId: 'demo-caja');
    store.role = StaffRole.cashier;
    await store.recordPayment(
      order: combined,
      method: 'Efectivo',
      amount: 32,
      cashReceived: 32,
    );
    store.role = StaffRole.waiter;
    expect(table(store, 1).status, TableStatus.payment);
    expect(table(store, 3).status, TableStatus.payment);

    await store.confirmTableRelease(table(store, 3));
    for (final number in [1, 3]) {
      final released = table(store, number);
      expect(released.status, TableStatus.available);
      expect(released.groupOrderId, isNull);
      expect(store.canJoinTable(released), isTrue);
    }
    final receiptOrder = store.orders.singleWhere(
      (entry) => entry.id == group.id,
    );
    expect(receiptOrder.locationLabel, 'Mesas 1 + 3');
    expect(receiptOrder.balance, 0);
    expect(receiptOrder.retirementConfirmed, isTrue);
  });

  test(
    'group capacity and membership survive reloading and stale release',
    () async {
      final store = RestaurantStore();
      addTearDown(store.dispose);
      final first = table(store, 1);
      final occupied = table(store, 2);
      await expectLater(
        store.createOrder(
          table: first,
          joinedTables: [first, occupied],
          diners: 2,
          lines: const [food],
        ),
        throwsStateError,
      );
      await expectLater(join(store, diners: 7), throwsStateError);
      await join(store);

      final reloaded = RestaurantStore();
      addTearDown(reloaded.dispose);
      await reloaded.initialize();
      final oldThird = table(reloaded, 3);
      final oldGroup = reloaded.tableGroupFor(oldThird)!;
      expect(oldGroup.locationLabel, 'Mesas 1 + 3');
      expect(reloaded.tableServiceCapacity(oldThird), 6);
      await reloaded.editOrder(order: oldGroup, lines: const [food], diners: 5);
      expect(reloaded.tableGroupFor(oldThird)!.diners, 5);
      await reloaded.cancelOrder(oldGroup);
      await reloaded.confirmTableRelease(oldThird);
      await join(reloaded);
      final newThird = table(reloaded, 3);
      expect(newThird.groupOrderId, isNot(oldThird.groupOrderId));
      await expectLater(
        reloaded.confirmTableRelease(oldThird),
        throwsStateError,
      );
      expect(newThird.status, TableStatus.occupied);
    },
  );
}
