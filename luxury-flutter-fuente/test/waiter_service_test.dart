import 'package:flutter_test/flutter_test.dart';
import 'package:luxury_app/data/restaurant_store.dart';
import 'package:luxury_app/models/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

const food = OrderLine(
  menuItemId: 1,
  name: 'Wantán frito',
  quantity: 2,
  unitPrice: 18,
);
const drink = OrderLine(
  menuItemId: 10,
  name: 'Chicha morada jarra',
  quantity: 1,
  unitPrice: 14,
);
const dessert = OrderLine(
  menuItemId: 12,
  name: 'Helado frito',
  quantity: 1,
  unitPrice: 12,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final serveDirectFirst in [false, true]) {
    test(
      'mixed order: ${serveDirectFirst ? 'waiter' : 'kitchen'} serves first',
      () async {
        final store = RestaurantStore()..role = StaffRole.waiter;
        addTearDown(store.dispose);
        await store.createOrder(
          table: store.tables.first,
          diners: 2,
          lines: const [food, drink, dessert],
        );
        final order = store.orders.first;
        expect(store.kitchenLines(order).map((line) => line.menuItemId), [1]);
        expect(store.canConfirmWaiterService(order), isTrue);

        if (serveDirectFirst) {
          await store.confirmWaiterService(order);
        }
        await store.advanceOrder(store.orders.first);
        await store.advanceOrder(store.orders.first);
        await store.advanceOrder(store.orders.first);

        final afterKitchen = store.orders.first;
        expect(afterKitchen.lines.first.status, OrderStatus.delivered);
        expect(
          afterKitchen.lines.skip(1).map((line) => line.status),
          everyElement(
            serveDirectFirst ? OrderStatus.delivered : OrderStatus.pending,
          ),
        );
        if (!serveDirectFirst) {
          expect(afterKitchen.status, OrderStatus.ready);
          await store.confirmWaiterService(afterKitchen);
        }

        final delivered = store.orders.first;
        expect(delivered.status, OrderStatus.delivered);
        expect(store.canConfirmWaiterService(delivered), isFalse);
        expect(delivered.total, 62);
        await store.setOrderForPayment(delivered);
        expect(store.orders.first.status, OrderStatus.forPayment);
        expect(store.orders.first.balance, 62);
      },
    );
  }

  test(
    'an order of drinks and desserts skips kitchen and can be billed',
    () async {
      final store = RestaurantStore()..role = StaffRole.waiter;
      addTearDown(store.dispose);
      await store.createOrder(
        table: store.tables.first,
        diners: 2,
        lines: const [drink, dessert],
      );
      final order = store.orders.first;
      expect(store.kitchenLines(order), isEmpty);
      await expectLater(store.advanceOrder(order), throwsStateError);

      await store.confirmWaiterService(order);
      await store.confirmWaiterService(order);
      final delivered = store.orders.first;
      expect(delivered.status, OrderStatus.delivered);
      expect(
        delivered.lines.map((line) => line.status),
        everyElement(OrderStatus.delivered),
      );
      await store.setOrderForPayment(delivered);
      expect(store.orders.first.balance, 26);
    },
  );
}
