import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luxury_app/admin_screen.dart';
import 'package:luxury_app/app_widgets.dart';
import 'package:luxury_app/models.dart';
import 'package:luxury_app/store.dart';

void main() {
  testWidgets('Gerente ve movimientos importantes y autores identificables', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = RestaurantStore();
    addTearDown(store.dispose);

    final date = DateTime(2026, 11, 9, 14, 8);
    store.auditEntries.addAll([
      AuditEntry(
        id: 1,
        createdAt: date,
        action: 'UPDATE',
        entity: 'pedidos',
        entityId: '32',
        actorName: 'Mesero',
      ),
      AuditEntry(
        id: 2,
        createdAt: date,
        action: 'INSERT',
        entity: 'mesas',
        entityId: '6',
        actorName: 'Administrador',
      ),
      AuditEntry(
        id: 3,
        createdAt: date,
        action: 'Reportar incidencia de cocina',
        entity: 'pedidos',
        entityId: '25',
        actorRole: 'COCINERO',
        actorName: 'Lucía Rojas',
      ),
      AuditEntry(
        id: 4,
        createdAt: date,
        action: 'Cancelar pedido',
        entity: 'pedidos',
        entityId: '26',
        actorRole: 'MESERO',
        actorName: 'Mesero',
        actorAccount: 'turno2@example.com',
      ),
      for (final (id, action) in [(5, 'Registrar pago'), (6, 'INSERT')])
        AuditEntry(
          id: id,
          createdAt: date,
          action: action,
          entity: 'pagos',
          entityId: '45',
          actorRole: 'CAJERO',
          actorName: 'Carlos Pérez',
        ),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: AdminScreen(store: store, managerOnly: true)),
    );
    tester
        .widget<LuxurySideMenu>(find.byType(LuxurySideMenu))
        .onDestinationSelected(5);
    await tester.pumpAndSettle();

    expect(find.textContaining('UPDATE'), findsNothing);
    expect(find.textContaining('INSERT'), findsNothing);
    expect(find.text('Incidencia de cocina reportada'), findsOneWidget);
    expect(find.textContaining('Lucía Rojas · Cocinero'), findsOneWidget);
    expect(find.text('Pedido cancelado'), findsOneWidget);
    expect(find.textContaining('turno2@example.com · Mesero'), findsOneWidget);
    expect(find.text('Pago registrado'), findsOneWidget);
    expect(find.textContaining('Carlos Pérez · Cajero'), findsOneWidget);
    expect(find.textContaining('09/11/2026 · 14:08'), findsNWidgets(3));
  });
}
