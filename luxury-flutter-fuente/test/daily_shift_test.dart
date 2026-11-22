import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luxury_app/models/models.dart';
import 'package:luxury_app/data/restaurant_store.dart';
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
    'Abrir la caja de hoy reemplaza el turno anterior en la vista',
    () async {
      SharedPreferences.setMockInitialValues({});
      var now = DateTime.utc(2026, 11, 10, 4, 59);
      final store = RestaurantStore(now: () => now)
        ..role = StaffRole.administrator;
      addTearDown(store.dispose);
      const cashierId = 'local-cashier';

      expect(store.shiftOpen, isFalse);
      await store.setShiftOpen(true, cashierId: cashierId);
      expect(store.openingCash, 0);
      expect(store.shiftOpen, isTrue);

      now = DateTime.utc(2026, 11, 10, 5);
      expect(store.openingCash, 0);
      expect(store.closedCash, 0);
      expect(store.shiftOpen, isFalse);
      expect((await store.cashierShift(cashierId)).open, isTrue);
      await store.setShiftOpen(true, cashierId: cashierId);
      expect(store.shiftOpen, isTrue);
      expect((await store.cashierShift(cashierId)).openedAt, now);
      expect(store.openingCash, 0);
      expect(store.closedCash, 0);
    },
  );

  test('Solo se confirma la apertura si hay un turno abierto de hoy', () async {
    final now = DateTime.utc(2026, 11, 10, 5, 30);
    var openedAt = DateTime.utc(2026, 11, 10, 4, 59);
    String? closedAt;
    var operations = 0;
    final client = SupabaseClient(
      'https://test.supabase.co',
      'sb_publishable_test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        Object? body;
        if (request.url.path.endsWith('/rpc/administrar_turno_caja')) {
          operations++;
          expect(jsonDecode(request.body)['p_abrir'], true);
        } else {
          expect(request.url.path, '/rest/v1/turnos_caja');
          body = [
            {
              'id': 10,
              'abierto_en': openedAt.toIso8601String(),
              'cerrado_en': closedAt,
              'monto_apertura': 0,
              'monto_cierre': 0,
            },
          ];
        }
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    final store = RestaurantStore(client: client, now: () => now)
      ..role = StaffRole.administrator;
    addTearDown(() async {
      store.dispose();
      await client.dispose();
    });

    Future<void> open() => store.setShiftOpen(true, cashierId: 'cashier-test');
    await expectLater(
      open(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'detalle',
          contains('turno de otro día'),
        ),
      ),
    );
    openedAt = now;
    closedAt = now.toIso8601String();
    await expectLater(open(), throwsStateError);
    closedAt = null;
    await open();
    expect(operations, 3);
  });
}
