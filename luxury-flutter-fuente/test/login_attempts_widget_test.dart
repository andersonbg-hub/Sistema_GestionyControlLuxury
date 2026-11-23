import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luxury_app/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets(
    'El tercer intento muestra un aviso y el cuarto bloquea el acceso',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var attempts = 0;
      late SupabaseClient client;
      await tester.runAsync(() async {
        client = SupabaseClient(
          'https://login-widget-test.supabase.co',
          'sb_publishable_test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient((_) async {
            attempts++;
            return http.Response(
              '{"error_code":"invalid_credentials","message":"Invalid login credentials"}',
              400,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
      });
      addTearDown(() => tester.runAsync(client.dispose));
      await tester.pumpWidget(LuxuryApp(client: client));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField).first,
        'prueba@example.com',
      );
      final submit = find.widgetWithText(FilledButton, 'Iniciar sesión');
      final warning = find.byType(AlertDialog);

      Future<void> tryPassword() async {
        await tester.enterText(find.byType(TextField).last, 'incorrecta');
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.pumpAndSettle();
      }

      for (var attempt = 1; attempt <= 2; attempt++) {
        await tryPassword();
        expect(attempts, attempt);
        expect(warning, findsNothing);
      }

      await tryPassword();
      expect(attempts, 3);
      expect(warning, findsOneWidget);
      expect(find.text('Te queda un último intento'), findsOneWidget);
      await tester.tap(find.text('Entendido'));
      await tester.pumpAndSettle();
      expect(warning, findsNothing);

      await tryPassword();
      expect(attempts, 4);
      expect(
        find.textContaining(RegExp('bloquead', caseSensitive: false)),
        findsWidgets,
      );
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(attempts, 4);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
