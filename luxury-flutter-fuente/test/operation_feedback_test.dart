import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luxury_app/app_widgets.dart';

void main() {
  testWidgets(
    'Una operación pendiente muestra carga y evita un segundo envío',
    (tester) async {
      final complete = Completer<void>();
      var calls = 0;
      var outsideClicks = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: _OperationTestPage(
            onOutsideTap: () => outsideClicks++,
            action: () {
              calls++;
              return complete.future;
            },
          ),
        ),
      );

      final button = find.text('Enviar');
      final sideButton = find.byTooltip('Acción de la barra superior');
      final sidePosition = tester.getCenter(sideButton);
      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Enviando pedido…'), findsOneWidget);
      expect(find.text('Espera un momento.'), findsOneWidget);
      final progress = find.byType(LinearProgressIndicator);
      expect(progress, findsOneWidget);
      final center = tester.getCenter(find.byType(Dialog));
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(center, Offset(screen.width / 2, screen.height / 2));
      await tester.tapAt(sidePosition);
      await tester.tapAt(const Offset(12, 260));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(progress, findsOneWidget);
      expect(calls, 1);
      expect(outsideClicks, 0);

      complete.complete();
      await tester.pumpAndSettle();
      expect(progress, findsNothing);
      await tester.tap(sideButton);
      expect(outsideClicks, 1);
    },
  );

  testWidgets('Un error retira el bloqueo y permite cerrar el aviso', (
    tester,
  ) async {
    final complete = Completer<void>();
    var outsideClicks = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: _OperationTestPage(
          action: () => complete.future,
          onOutsideTap: () => outsideClicks++,
        ),
      ),
    );
    await tester.tap(find.text('Enviar'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    complete.completeError(StateError('No se pudo guardar el pedido.'));
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('No se pudo guardar el pedido.'), findsOneWidget);
      await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Acción de la barra superior'));
    expect(outsideClicks, 1);
  });

  testWidgets('Volver descarta y confirmar ejecuta la acción', (tester) async {
    var confirmed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                confirmed = await confirmAction(
                  context,
                  title: '¿Solicitar la cuenta?',
                  message: 'Se cerrará el ingreso de pedidos para esta mesa.',
                  actionLabel: 'Solicitar cuenta',
                );
              },
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Volver'));
    await tester.pumpAndSettle();
    expect(confirmed, isFalse);

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Solicitar cuenta'));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
  });
}

class _OperationTestPage extends StatefulWidget {
  const _OperationTestPage({required this.action, required this.onOutsideTap});

  final Future<void> Function() action;
  final VoidCallback onOutsideTap;

  @override
  State<_OperationTestPage> createState() => _OperationTestPageState();
}

class _OperationTestPageState extends State<_OperationTestPage>
    with OperationProgress<_OperationTestPage> {
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      actions: [
        IconButton(
          onPressed: widget.onOutsideTap,
          tooltip: 'Acción de la barra superior',
          icon: const Icon(Icons.menu),
        ),
      ],
    ),
    body: Center(
      child: FilledButton(
        onPressed: () => runOperation(widget.action, label: 'Enviando pedido…'),
        child: const Text('Enviar'),
      ),
    ),
  );
}
