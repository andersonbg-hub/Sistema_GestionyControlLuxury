import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luxury_app/models.dart';
import 'package:luxury_app/store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test('La caja no agrega un fondo de apertura automático', () {
    final store = RestaurantStore();
    expect(store.openingCash, 0);
    store.dispose();
  });

  test('Un pedido delivery conserva su tipo y datos para sincronización', () {
    final order = RestaurantOrder(
      id: -1,
      tableId: null,
      tableNumber: 0,
      createdAt: DateTime.utc(2026, 1, 1),
      lines: const [
        OrderLine(menuItemId: 7, name: 'Chaufa', quantity: 2, unitPrice: 28),
      ],
      fulfillmentType: FulfillmentType.delivery,
      customerName: 'Cliente',
      customerPhone: '999111222',
      deliveryAddress: 'Calle 1',
      pendingSync: true,
      clientRequestId: '4c918db9-c2e8-40b6-aad8-dc15ee136e3c',
    );
    final restored = RestaurantOrder.fromJson(order.toJson());
    expect(restored.locationLabel, 'Delivery');
    expect(restored.tableId, isNull);
    expect(restored.customerName, 'Cliente');
    expect(restored.deliveryAddress, 'Calle 1');
    expect(restored.pendingSync, isTrue);
    expect(restored.clientRequestId, order.clientRequestId);
  });

  test('La conexion remota no incorpora datos de demostracion', () async {
    final client = SupabaseClient(
      'https://test.supabase.co',
      'sb_publishable_test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final store = RestaurantStore(client: client);
    expect(store.tables, isEmpty);
    expect(store.orders, isEmpty);
    expect(store.menu, isEmpty);
    expect(store.openingCash, 0);
    expect(store.shiftOpen, isFalse);
    await expectLater(
      store.loginDemo(StaffRole.administrator),
      throwsStateError,
    );
    expect(store.role, isNull);
    store.dispose();
    await client.dispose();
  });

  test('Un fallo al leer la base no deja un rol autorizado ni datos', () async {
    final requests = <String>[];
    const id = '00000000-0000-4000-8000-000000000001';
    final httpClient = MockClient((request) async {
      requests.add(request.url.path);
      if (request.url.path == '/auth/v1/token') {
        return http.Response(
          jsonEncode({
            'access_token': 'test-token',
            'token_type': 'bearer',
            'expires_in': 3600,
            'refresh_token': 'test-refresh',
            'user': {
              'id': id,
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
      if (request.url.path == '/rest/v1/usuarios') {
        return http.Response(
          jsonEncode([
            {
              'id': id,
              'activo': true,
              'rol': 'ADMINISTRADOR',
              'nombre_completo': 'Prueba',
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }
      if (request.url.path == '/rest/v1/mesas') {
        return http.Response(
          jsonEncode({
            'code': '42501',
            'message': 'permission denied for table mesas',
          }),
          403,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }
      if (request.url.path == '/auth/v1/logout') {
        return http.Response('', 204);
      }
      throw StateError('Unexpected request: ${request.url.path}');
    });
    final client = SupabaseClient(
      'https://test.supabase.co',
      'sb_publishable_test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: httpClient,
    );
    final store = RestaurantStore(client: client);
    await expectLater(
      store.signIn('test@example.com', 'test-only'),
      throwsA(isA<PostgrestException>()),
    );
    expect(requests, contains('/rest/v1/mesas'));
    expect(store.role, isNull);
    expect(store.userId, isNull);
    expect(store.tables, isEmpty);
    expect(client.auth.currentUser, isNull);
    store.dispose();
    await client.dispose();
  });
}
