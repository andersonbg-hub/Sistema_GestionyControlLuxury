import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luxury_app/data/restaurant_store.dart';
import 'package:luxury_app/models/models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const userId = '00000000-0000-4000-8000-000000000001';
final now = DateTime.utc(2026, 11, 23, 16);

http.Response jsonResponse(Object? payload, [int status = 200]) =>
    http.Response(
      jsonEncode(payload),
      status,
      headers: {'content-type': 'application/json'},
    );

Future<RestaurantStore> connectedStore(
  StaffRole role,
  Future<http.Response> Function(http.Request) respond,
) async {
  final client = SupabaseClient(
    'https://test.supabase.co',
    'sb_publishable_test',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
    httpClient: MockClient((request) async {
      if (request.url.path != '/auth/v1/token') {
        final response = await respond(request);
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      }
      return jsonResponse({
        'access_token': 'test-token',
        'refresh_token': 'test-refresh',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': userId,
          'aud': 'authenticated',
          'role': 'authenticated',
          'email': 'test@example.com',
          'created_at': now.toIso8601String(),
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
        },
      });
    }),
  );
  await client.auth.signInWithPassword(
    email: 'test@example.com',
    password: 'test-only',
  );
  final store = RestaurantStore(client: client, now: () => now)
    ..userId = userId
    ..role = role;
  addTearDown(() async {
    store.dispose();
    await client.dispose();
  });
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'Waiter receipt updates only the selected ready lines for both roles',
    () async {
      const orderId = 81;
      final lineStates = {101: 'LISTO', 102: 'LISTO', 103: 'EN_PREPARACION'};
      final deliveries = <int>[];

      Future<http.Response> serve(http.Request request) async {
        final path = request.url.path;
        if (path.endsWith('/rpc/actualizar_estado_item')) {
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          final id = payload['p_detalle_id'] as int;
          expect(payload['p_estado'], 'ENTREGADO');
          expect(lineStates[id], 'LISTO');
          deliveries.add(id);
          lineStates[id] = 'ENTREGADO';
          return jsonResponse(null);
        }
        if (path.endsWith('/pedidos')) {
          return jsonResponse([
            {
              'id': orderId,
              'creado_en': now.toIso8601String(),
              'mesero_id': userId,
              'estado': 'PAGADO',
            },
          ]);
        }
        if (path.endsWith('/detalle_pedido')) {
          return jsonResponse([
            for (final entry in lineStates.entries)
              {
                'id': entry.key,
                'pedido_id': orderId,
                'platillo_id': 1,
                'cantidad': 1,
                'precio_unitario': 15,
                'estado': entry.value,
              },
          ]);
        }
        return jsonResponse([]);
      }

      final waiter = await connectedStore(StaffRole.waiter, serve);
      final kitchen = await connectedStore(StaffRole.kitchen, serve);
      await waiter.refresh();
      final order = waiter.orders.single;
      await waiter.advanceOrder(
        order.copyWith(lines: [order.lines.first]),
        forStage: OrderStatus.ready,
      );
      expect(deliveries, [101]);
      expect(waiter.orders.single.lines.first.status, OrderStatus.delivered);
      await kitchen.refresh(reconcilePayments: false);
      expect(kitchen.orders.single.lines.map((line) => line.status), [
        OrderStatus.delivered,
        OrderStatus.ready,
        OrderStatus.preparing,
      ]);
      expect(kitchen.orders.single.status, OrderStatus.paid);
    },
  );

  test('A rejected offline order does not block the next order', () async {
    final requests = <String>[];
    final store = await connectedStore(StaffRole.waiter, (request) async {
      if (request.url.path.endsWith('/rpc/crear_pedido_sincronizado')) {
        final id = jsonDecode(request.body)['p_solicitud_id'] as String;
        requests.add(id);
        if (id == 'rejected') {
          return jsonResponse({
            'code': 'P0001',
            'message': 'Platillo desactivado',
          }, 400);
        }
        return jsonResponse(80);
      }
      return jsonResponse({'code': '503', 'message': 'Sin conexión'}, 503);
    });
    const line = OrderLine(
      menuItemId: 1,
      name: 'Arroz',
      quantity: 1,
      unitPrice: 10,
    );
    final rejected = RestaurantOrder(
      id: -1,
      tableId: null,
      tableNumber: 0,
      createdAt: now,
      lines: const [line],
      pendingSync: true,
      clientRequestId: 'rejected',
      fulfillmentType: FulfillmentType.takeaway,
    );
    final accepted = RestaurantOrder.fromJson({
      ...rejected.toJson(),
      'id': -2,
      'clientRequestId': 'accepted',
    });
    store.pendingOrders.addAll([rejected, accepted]);
    store.orders.addAll([rejected, accepted]);

    await expectLater(store.syncPendingOrders(), throwsStateError);
    expect(requests, ['rejected', 'accepted']);
    expect(store.pendingOrders, [rejected]);
    expect(
      store.orders.singleWhere((order) => order.id == 80).pendingSync,
      isFalse,
    );
    await store.discardPendingOrder(rejected);
    expect(store.pendingOrders, isEmpty);
    expect(store.orders.map((order) => order.id), [80]);
  });

  test(
    'A confirmed payment with failed refresh stays out of the local ledger',
    () async {
      var payments = 0;
      final store = await connectedStore(StaffRole.cashier, (request) async {
        if (request.url.path.endsWith('/rpc/registrar_pago')) {
          expect(
            jsonDecode(request.body)['p_cobro_anticipado_confirmado'],
            isFalse,
          );
          payments++;
          return jsonResponse(301);
        }
        if (payments != 0) {
          return jsonResponse({'code': '503', 'message': 'Sin conexión'}, 503);
        }
        if (request.url.path.endsWith('/turnos_caja')) {
          return jsonResponse([
            {'id': 20, 'abierto_en': now.toIso8601String()},
          ]);
        }
        return jsonResponse([]);
      });
      await store.refresh();
      expect(store.shiftOpen, isTrue);
      final order = RestaurantOrder(
        id: 901,
        tableId: null,
        tableNumber: 0,
        createdAt: now,
        status: OrderStatus.ready,
        lines: const [
          OrderLine(
            menuItemId: 1,
            name: 'Arroz',
            quantity: 1,
            unitPrice: 10,
            status: OrderStatus.ready,
          ),
          OrderLine(
            menuItemId: 2,
            name: 'Jugo',
            quantity: 1,
            unitPrice: 5,
            waiterService: true,
          ),
        ],
      );
      store.orders.add(order);
      Future<void> pay() => store.recordPayment(
        order: order,
        method: 'Efectivo',
        amount: 15,
        cashReceived: 15,
      );

      await expectLater(
        pay(),
        throwsA(
          isA<PaymentNotConfirmed>().having(
            (error) => error.saved,
            'saved',
            true,
          ),
        ),
      );
      expect(store.orders.single.payments, isEmpty);
      await expectLater(pay(), throwsA(isA<PaymentNotConfirmed>()));
      expect(payments, 1);
    },
  );
}
