part of '../dashboard_screen.dart';

extension _AdminAuditView on _AdminScreenState {
  Widget _auditPage() {
    final paymentIds = <String>{};
    final movements = [
      for (final entry in store.auditEntries)
        if (entry.movement case final movement?)
          if (entry.entity != 'pagos' ||
              movement.$1 != 'Pago registrado' ||
              entry.entityId.isEmpty ||
              paymentIds.add(entry.entityId))
            (entry, movement),
    ];
    final peopleById = {for (final member in store.staff) member.id: member};

    String? reference(AuditEntry entry) {
      if (entry.entityId.isEmpty) return null;
      if (entry.entity == 'usuarios') {
        final member = peopleById[entry.entityId];
        if (member == null) return null;
        final name = AuditEntry.isGenericName(member.name)
            ? member.email
            : member.name;
        return name.isEmpty ? null : 'Cuenta de $name';
      }
      if (int.tryParse(entry.entityId) == null) return null;
      final label = switch (entry.entity) {
        'pedidos' => 'Pedido',
        'pagos' => 'Pago',
        'notas_venta' => 'Nota de venta',
        'turnos_caja' || 'caja_diaria' => 'Turno',
        'solicitudes_reabastecimiento' => 'Solicitud',
        'alertas_cocina' => 'Alerta',
        'insumos' => 'Insumo',
        _ => null,
      };
      return label == null ? null : '$label #${entry.entityId}';
    }

    String timestamp(DateTime value) {
      final date = limaWallTime(value);
      String two(int number) => number.toString().padLeft(2, '0');
      return '${two(date.day)}/${two(date.month)}/${date.year} · '
          '${two(date.hour)}:${two(date.minute)}';
    }

    final search = auditQuery.trim().toLowerCase();
    final visible = movements.where((record) {
      if (search.isEmpty) return true;
      final (entry, (title, category)) = record;
      final searchable =
          '${entry.actorLabel} ${entry.actorRoleLabel} $title $category ${reference(entry) ?? ''} ${timestamp(entry.createdAt)}'
              .toLowerCase();
      return searchable.contains(search);
    }).toList();

    if (managerOnly) {
      return _managerMovementHistory(visible, reference);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(
          title: 'Auditoría de movimientos',
          subtitle: 'Movimientos importantes y quién los realizó',
        ),
        if (visible.isEmpty)
          const EmptyState(
            message: 'Todavía no hay movimientos importantes registrados.',
            icon: Icons.history,
          )
        else
          for (final (entry, (title, category)) in visible)
            Card(
              child: ResponsiveListTile(
                leading: Icon(switch (category) {
                  'Caja' => Icons.point_of_sale_outlined,
                  'Cocina' => Icons.restaurant_outlined,
                  'Inventario' => Icons.inventory_2_outlined,
                  'Usuarios' => Icons.manage_accounts_outlined,
                  _ => Icons.receipt_long_outlined,
                }),
                title: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  [
                    ?reference(entry),
                    'Realizado por ${entry.actorLabel}${entry.actorRoleLabel.isEmpty || entry.actorRoleLabel == entry.actorLabel ? '' : ' · ${entry.actorRoleLabel}'}',
                    timestamp(entry.createdAt),
                  ].join('\n'),
                ),
                trailing: Chip(label: Text(category)),
              ),
            ),
      ],
    );
  }

  Widget _managerMovementHistory(
    List<(AuditEntry, (String, String))> movements,
    String? Function(AuditEntry) reference,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SectionTitle(
        title: 'Historial de movimientos',
        subtitle: 'Quién realizó cada operación y cuándo ocurrió',

        trailing: const Chip(
          avatar: Icon(Icons.visibility_outlined, size: 16),
          label: Text('Solo lectura'),
        ),
      ),
      TextField(
        key: const ValueKey('manager-movement-search'),
        onChanged: (value) => _setState(() => auditQuery = value),
        decoration: const InputDecoration(
          hintText: 'Buscar persona, acción o referencia',
          prefixIcon: Icon(Icons.search),
          isDense: true,
        ),
      ),
      const SizedBox(height: 14),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Actividad registrada',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (movements.isEmpty)
                const EmptyState(
                  message: 'No hay movimientos que coincidan con la búsqueda.',
                  icon: Icons.history,
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 680;
                    if (narrow) {
                      return Column(
                        children: [
                          for (final (entry, (action, _)) in movements)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(_managerActorLabel(entry)),
                              subtitle: Text(
                                '$action\n${reference(entry) ?? '—'}',
                              ),
                              isThreeLine: true,
                              trailing: Text(
                                _managerTimestamp(entry.createdAt),
                              ),
                            ),
                        ],
                      );
                    }
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('FECHA Y HORA')),
                          DataColumn(label: Text('PERSONA')),
                          DataColumn(label: Text('ACCIÓN')),
                          DataColumn(label: Text('REFERENCIA')),
                        ],
                        rows: [
                          for (final (entry, (action, _)) in movements)
                            DataRow(
                              cells: [
                                DataCell(
                                  Text(_managerTimestamp(entry.createdAt)),
                                ),
                                DataCell(Text(_managerActorLabel(entry))),
                                DataCell(Text(action)),
                                DataCell(Text(reference(entry) ?? '—')),
                              ],
                            ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    ],
  );

  String _managerActorLabel(AuditEntry entry) {
    final name = entry.actorLabel;
    final role = entry.actorRoleLabel;
    return role.isEmpty || role == name ? name : '$name · $role';
  }

  String _managerTimestamp(DateTime value) => limaDateTime(value);
}
