import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luxury_app/main.dart';
import 'package:luxury_app/app_widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('Supabase exige acceso con cuenta y no ofrece roles demo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late SupabaseClient client;
    await tester.runAsync(() async {
      client = SupabaseClient(
        'https://test.supabase.co',
        'sb_publishable_test',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((_) async => http.Response('{}', 400)),
      );
    });
    await tester.pumpWidget(LuxuryApp(client: client));
    await tester.pumpAndSettle();
    expect(find.text('Correo'), findsOneWidget);
    expect(find.text('Contraseña'), findsOneWidget);
    expect(
      find.text('Elige el espacio de trabajo para recorrer la demostración.'),
      findsNothing,
    );
    expect(find.textContaining('Modo local de demostración:'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Iniciar sesión').first).dx,
      greaterThan(550),
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/images/portada_restaurante.png',
      ),
      findsOneWidget,
    );
    expect(
      tester.getCenter(find.byType(Image)).dx,
      closeTo(26 + (1280 - 52) * .2, 1),
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is ColoredBox && widget.color == Colors.white,
      ),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField).first, 'john');
    await tester.tap(find.widgetWithText(FilledButton, 'Iniciar sesión'));
    await tester.pumpAndSettle();
    expect(
      find.text('Usa un correo válido, como nombre@empresa.com'),
      findsOneWidget,
    );
    expect(find.byType(LoginFieldError), findsWidgets);
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.text('Iniciar sesión').first, findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(client.dispose);
  });

  testWidgets('los avisos de operaciones usan un diálogo de resultado', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => showResultDialog(
                  context,
                  success: true,
                  message: 'Pedido guardado.',
                ),
                child: const Text('Mostrar'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Mostrar'));
    await tester.pumpAndSettle();
    expect(find.text('¡Listo!'), findsOneWidget);
    expect(find.text('Pedido guardado.'), findsOneWidget);
    final barriers = tester.widgetList<ModalBarrier>(find.byType(ModalBarrier));
    expect(
      barriers.any((barrier) => barrier.color == const Color(0xB317181D)),
      isTrue,
    );
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.text('¡Listo!'), findsNothing);
  });
}
