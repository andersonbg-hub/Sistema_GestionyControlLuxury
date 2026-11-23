import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luxury_app/data/restaurant_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'Advierte al tercero y bloquea el cuarto por correo durante 15 minutos',
    () async {
      const email = 'mesero@example.com';
      var now = DateTime.utc(2026, 11, 22, 18);
      final submittedEmails = <String>[];
      final client = _client((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        submittedEmails.add(body['email'] as String);
        if (body['password'] == 'esperar') {
          return _authError(
            code: 'over_request_rate_limit',
            message: 'Too many requests',
            status: 429,
          );
        }
        return _authError();
      });
      addTearDown(client.dispose);
      final store = RestaurantStore(client: client, now: () => now);
      addTearDown(store.dispose);

      for (var count = 1; count <= 3; count++) {
        await expectLater(
          store.signIn(' Mesero@Example.com ', 'incorrecta'),
          throwsA(
            isA<LoginAttemptException>()
                .having((error) => error.isLastAttempt, 'último', count == 3)
                .having((error) => error.lockedUntil, 'desbloqueo', isNull),
          ),
        );
        if (count == 1) {
          await expectLater(
            store.signIn(email, 'esperar'),
            throwsA(
              isA<AuthException>().having(
                (error) => error.code,
                'código',
                'over_request_rate_limit',
              ),
            ),
          );
        }
      }

      final unlock = now.add(const Duration(minutes: 15));
      final locked = throwsA(
        isA<LoginAttemptException>()
            .having((error) => error.isLastAttempt, 'último', isFalse)
            .having((error) => error.lockedUntil, 'desbloqueo', unlock)
            .having(
              (error) => error.message,
              'mensaje',
              contains('15 minutos'),
            ),
      );
      await expectLater(store.signIn(email, 'incorrecta'), locked);
      expect(submittedEmails, List.filled(5, email));

      final reopened = RestaurantStore(client: client, now: () => now);
      addTearDown(reopened.dispose);
      expect(await reopened.loginLockedUntil(email), unlock);
      await expectLater(reopened.signIn(email, 'correcta'), locked);
      expect(submittedEmails, hasLength(5));
      await expectLater(
        reopened.signIn('caja@example.com', 'incorrecta'),
        throwsA(isA<LoginAttemptException>()),
      );
      expect(submittedEmails.last, 'caja@example.com');

      now = unlock;
      expect(await reopened.loginLockedUntil(email), isNull);
      await expectLater(
        reopened.signIn(email, 'incorrecta'),
        throwsA(
          isA<LoginAttemptException>()
              .having((error) => error.isLastAttempt, 'último', isFalse)
              .having((error) => error.lockedUntil, 'desbloqueo', isNull),
        ),
      );
      expect(submittedEmails, hasLength(7));
    },
  );

  test('Respeta el vencimiento devuelto por el hook de Supabase', () async {
    final now = DateTime.utc(2026, 11, 22, 18);
    final unlock = now.add(const Duration(minutes: 5));
    var requests = 0;
    final client = _client((_) async {
      requests++;
      return _authError(
        message: 'luxury_login_locked_until:${unlock.millisecondsSinceEpoch}',
      );
    });
    addTearDown(client.dispose);
    final store = RestaurantStore(client: client, now: () => now);
    addTearDown(store.dispose);

    final locked = throwsA(
      isA<LoginAttemptException>().having(
        (error) => error.lockedUntil,
        'desbloqueo',
        unlock,
      ),
    );
    await expectLater(store.signIn('mesero@example.com', 'correcta'), locked);
    await expectLater(store.signIn('mesero@example.com', 'correcta'), locked);
    expect(requests, 1);
  });

  test(
    'Acepta una contraseña correcta al cuarto intento y reinicia el contador',
    () async {
      final client = _client((request) async {
        switch (request.url.path) {
          case '/auth/v1/token':
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            if (body['password'] != 'correcta') return _authError();
            return http.Response(
              jsonEncode({
                'access_token': 'test-token',
                'token_type': 'bearer',
                'expires_in': 3600,
                'refresh_token': 'test-refresh',
                'user': {
                  'id': '00000000-0000-4000-8000-000000000001',
                  'aud': 'authenticated',
                  'created_at': '2026-11-22T00:00:00Z',
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          case '/rest/v1/usuarios':
            return http.Response(
              '[]',
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          case '/auth/v1/logout':
            return http.Response('', 204);
        }
        throw StateError('Solicitud inesperada: ${request.url.path}');
      });
      addTearDown(client.dispose);
      final store = RestaurantStore(client: client);
      addTearDown(store.dispose);
      const email = 'mesero@example.com';

      for (var count = 1; count <= 3; count++) {
        await expectLater(
          store.signIn(email, 'incorrecta'),
          throwsA(isA<LoginAttemptException>()),
        );
      }
      await expectLater(
        store.signIn(email, 'correcta'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'mensaje',
            contains('No existe un perfil activo'),
          ),
        ),
      );
      for (var count = 1; count <= 3; count++) {
        await expectLater(
          store.signIn(email, 'incorrecta'),
          throwsA(
            isA<LoginAttemptException>()
                .having((error) => error.isLastAttempt, 'último', count == 3)
                .having((error) => error.lockedUntil, 'desbloqueo', isNull),
          ),
        );
      }
    },
  );
}

SupabaseClient _client(Future<http.Response> Function(http.Request) respond) =>
    SupabaseClient(
      'https://test.supabase.co',
      'sb_publishable_test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(respond),
    );

http.Response _authError({
  String code = 'invalid_credentials',
  String message = 'Invalid login credentials',
  int status = 400,
}) => http.Response(
  jsonEncode({'error_code': code, 'msg': message}),
  status,
  headers: {'content-type': 'application/json'},
);
