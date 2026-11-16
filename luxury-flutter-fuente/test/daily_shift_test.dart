import 'package:flutter_test/flutter_test.dart';
import 'package:luxury_app/models.dart';
import 'package:luxury_app/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('La medianoche de Lima corresponde a las 05:00 UTC', () {
    final previous = DateTime.utc(2026, 11, 10, 4, 59, 59);
    final midnight = DateTime.utc(2026, 11, 10, 5);
    expect(limaBusinessDay(previous), DateTime.utc(2026, 11, 9));
    expect(limaBusinessDay(midnight), DateTime.utc(2026, 11, 10));
    expect(nextLimaMidnight(previous), midnight);
  });

  test(
    'Un turno anterior se conserva para el cierre y no permite cobrar hoy',
    () async {
      SharedPreferences.setMockInitialValues({});
      var now = DateTime.utc(2026, 11, 10, 4, 59);
      final store = RestaurantStore(now: () => now)
        ..role = StaffRole.administrator;
      addTearDown(store.dispose);
      const cashierId = 'local-cashier';

      await store.setShiftOpen(false, cashierId: cashierId, countedCash: 0);
      await store.setShiftOpen(true, cashierId: cashierId, countedCash: 90);
      expect(store.openingCash, 90);
      expect(store.shiftOpen, isTrue);

      now = DateTime.utc(2026, 11, 10, 5);
      expect(store.openingCash, 0);
      expect(store.closedCash, 0);
      expect(store.shiftOpen, isFalse);
      expect((await store.cashierShift(cashierId)).open, isTrue);
      await expectLater(
        store.setShiftOpen(true, cashierId: cashierId, countedCash: 15),
        throwsStateError,
      );
      await store.setShiftOpen(false, cashierId: cashierId, countedCash: 95);
      expect(store.closedCash, 0);

      await store.setShiftOpen(true, cashierId: cashierId, countedCash: 15);
      expect(store.shiftOpen, isTrue);
      expect(store.openingCash, 15);
      expect(store.closedCash, 0);
    },
  );
}
