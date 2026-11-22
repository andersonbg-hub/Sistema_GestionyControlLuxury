import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luxury_app/data/restaurant_store.dart';
import 'package:luxury_app/models/models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const waiter = '00000000-0000-4000-8000-000000000001';
const firstLine = OrderLine(
  menuItemId: 1,
  name: 'Wantán frito',
  quantity: 1,
  unitPrice: 18,
  status: OrderStatus.delivered,
);
const addedLine = OrderLine(
  menuItemId: 10,
  name: 'Chicha morada jarra',
  quantity: 1,
  unitPrice: 14,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'ordinary additions preserve delivered lines and legacy child orders',
    () async {
      final store = RestaurantStore()..role = StaffRole.waiter;
      addTearDown(store.dispose);
      final table = store.tables.first;
      await store.createOrder(
        table: table,
        diners: 2,
        lines: const [firstLine],
      );
      final account = store.orders.first;
      final legacyChild = account.copyWith(id: 900, parentOrderId: account.id);
      store.orders.add(legacyChild);
      await store.createOrder(
        table: table,
        diners: 2,
        lines: const [addedLine],
        parentOrderId: account.id,
      );
      final updated = store.orders.singleWhere(
        (order) => order.id == account.id,
      );
      expect(updated.total, 32);
      expect(updated.lines.first.status, OrderStatus.delivered);
      expect(updated.lines.last.status, OrderStatus.pending);
      expect(
        store.orders.singleWhere((order) => order.id == 900),
        same(legacyChild),
      );
      expect(
        store.orders.where((order) => order.tableId == table.id),
        hasLength(2),
      );

      final reloaded = RestaurantStore();
      addTearDown(reloaded.dispose);
      await reloaded.initialize();
      expect(
        reloaded.orders.singleWhere((order) => order.id == account.id).total,
        32,
      );
      final childIndex = store.orders.indexWhere((order) => order.id == 900);
      store.orders[childIndex] = legacyChild.copyWith(
        payments: [
          PaymentEntry(
            method: 'Efectivo',
            amount: 1,
            createdAt: DateTime.now(),
          ),
        ],
      );
      expect(store.canOrderAtTable(table), isFalse);
      await expectLater(
        store.createOrder(
          table: table,
          diners: 2,
          lines: const [addedLine],
          parentOrderId: account.id,
        ),
        throwsStateError,
      );
    },
  );

  test(
    'acknowledged append with failed refresh retains its retry token',
    () async {
      final requests = <Map<String, dynamic>>[];
      final client = SupabaseClient(
        'https://test.supabase.co',
        'sb_publishable_test',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
        httpClient: MockClient((request) async {
          if (request.url.path == '/auth/v1/token') {
            return http.Response(
              jsonEncode({
                'access_token': 'test-token',
                'refresh_token': 'test-refresh',
                'token_type': 'bearer',
                'expires_in': 3600,
                'user': {
                  'id': waiter,
                  'aud': 'authenticated',
                  'role': 'authenticated',
                  'email': 'test@example.com',
                  'created_at': '2026-01-01T00:00:00Z',
                  'app_metadata': <String, dynamic>{},
                  'user_metadata': <String, dynamic>{},
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          if (request.url.path.endsWith('/rpc/agregar_consumo_cuenta_mesa')) {
            requests.add(jsonDecode(request.body) as Map<String, dynamic>);
            return http.Response(
              '700',
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          return http.Response(
            '{"message":"temporarily unavailable"}',
            503,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      await client.auth.signInWithPassword(
        email: 'test@example.com',
        password: 'test-only',
      );
      final store = RestaurantStore(client: client)
        ..userId = waiter
        ..role = StaffRole.waiter;
      addTearDown(() async {
        store.dispose();
        await client.dispose();
      });
      const table = RestaurantTable(
        id: 1,
        number: 1,
        capacity: 4,
        status: TableStatus.occupied,
      );
      final account = RestaurantOrder(
        id: 700,
        tableId: 1,
        tableNumber: 1,
        createdAt: DateTime.now(),
        diners: 2,
        lines: const [firstLine],
        waiterId: waiter,
        status: OrderStatus.delivered,
      );
      store.tables.add(table);
      store.orders.add(account);
      await store.createOrder(
        table: table,
        diners: 2,
        lines: const [addedLine],
        parentOrderId: 700,
      );
      expect(store.pendingOrders.single.appendsToAccount, isTrue);
      final pending = RestaurantOrder.fromJson(
        store.pendingOrders.single.toJson(),
      );
      expect(pending.appendsToAccount, isTrue);
      expect(pending.parentOrderId, 700);
      await expectLater(store.syncPendingOrders(), throwsStateError);
      expect(requests, hasLength(2));
      expect(requests.first['p_solicitud_id'], requests.last['p_solicitud_id']);
      expect(requests.first['p_pedido_id'], 700);
      expect(store.pendingOrders, hasLength(1));
      expect(
        store.orders.singleWhere((order) => order.id == 700).lines,
        hasLength(1),
      );
      expect(store.additionalOrderParent(table), isNull);
      await expectLater(store.setOrderForPayment(account), throwsStateError);
    },
  );
}
