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

  test('La solución de una incidencia se guarda en el pedido local', () async {
    final store = RestaurantStore();
    final order = store.orders.first;
    await store.reportKitchenIncident(order, 'Faltó una guarnición');
    final incident = store.orders.firstWhere((item) => item.id == order.id);
    await store.resolveKitchenIncident(incident, 'Se entregó la guarnición');
    final resolved = store.orders.firstWhere((item) => item.id == order.id);
    expect(resolved.incident, 'Faltó una guarnición');
    expect(resolved.incidentSolution, 'Se entregó la guarnición');
    final restored = RestaurantOrder.fromJson(resolved.toJson());
    expect(restored.incidentSolution, resolved.incidentSolution);
    store.dispose();
  });

  test(
    'Una solicitud de reabastecimiento se puede procesar y cancelar',
    () async {
      final store = RestaurantStore();
      final request = store.requests.first;
      await store.advanceRequest(request);
      final processing = store.requests.firstWhere(
        (item) => item.id == request.id,
      );
      expect(processing.status, 'EN_PROCESO');
      await store.cancelRequest(processing);
      expect(
        store.requests.firstWhere((item) => item.id == request.id).status,
        'CANCELADA',
      );
      store.dispose();
    },
  );

  test(
    'El alta se conserva si el correo o la actualización de la lista fallan',
    () async {
      const id = '00000000-0000-4000-8000-000000000099';
      var attempts = 0;
      final client = SupabaseClient(
        'https://test.supabase.co',
        'sb_publishable_test',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          if (request.url.path == '/functions/v1/manage-staff') {
            attempts++;
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['action'], 'create');
            expect(body['email'], 'nuevo@example.com');
            expect(body['role'], 'MESERO');
            return http.Response(
              jsonEncode({'id': id, 'emailSent': false}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          expect(request.url.path, '/rest/v1/mesas');
          return http.Response(
            '{"message":"Servicio temporalmente no disponible"}',
            503,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      final store = RestaurantStore(client: client)
        ..role = StaffRole.administrator;
      addTearDown(() async {
        store.dispose();
        await client.dispose();
      });

      final emailSent = await store.addStaffMember(
        name: 'Empleado de prueba',
        email: ' Nuevo@example.com ',
        role: StaffRole.waiter,
        password: 'TemporalPrueba1!',
      );

      expect(emailSent, isFalse);
      expect(store.staff.single.id, id);
      await expectLater(
        store.addStaffMember(
          name: 'Duplicado',
          email: 'nuevo@example.com',
          role: StaffRole.waiter,
          password: 'TemporalPrueba2!',
        ),
        throwsStateError,
      );
      expect(attempts, 1);
    },
  );

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

  test('Un pedido confirmado se conserva si falla la recarga', () async {
    var creates = 0;
    final client = SupabaseClient(
      'https://test.supabase.co',
      'sb_publishable_test',
      postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
      httpClient: MockClient((request) async {
        final isCreate = request.url.path.endsWith(
          '/rpc/crear_pedido_sincronizado',
        );
        if (isCreate) {
          creates++;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['p_tipo_pedido'], 'PARA_LLEVAR');
          expect(body['p_solicitud_id'], isNotEmpty);
        }
        return http.Response(
          isCreate
              ? '402'
              : '{"code":"503","message":"Servicio temporalmente no disponible"}',
          isCreate ? 200 : 503,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    final store = RestaurantStore(client: client)..role = StaffRole.waiter;
    addTearDown(() async {
      store.dispose();
      await client.dispose();
    });

    await store.createOrder(
      table: null,
      lines: const [
        OrderLine(menuItemId: 1, name: 'Chaufa', quantity: 1, unitPrice: 20),
      ],
      diners: 1,
      fulfillmentType: FulfillmentType.takeaway,
      customerName: 'Cliente de prueba',
      customerPhone: '900000000',
    );

    expect(creates, 1);
    expect(store.orders.single.id, 402);
    expect(store.orders.single.pendingSync, isFalse);
    expect(store.errorMessage, contains('El cambio se guardó'));
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
      if (request.method == 'GET' && request.url.path.startsWith('/rest/v1/')) {
        return http.Response(
          '[]',
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
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
