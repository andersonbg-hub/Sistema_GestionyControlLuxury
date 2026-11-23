part of '../dashboard_screen.dart';

extension _AdminTablesView on _AdminScreenState {
  Widget _tablesPage() {
    final tables = store.tables
        .where((table) => 'mesa ${table.number}'.contains(query))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          title: 'Mesas',
          subtitle:
              '${store.tables.fold<int>(0, (sum, table) => sum + table.capacity)} asientos disponibles en el salón',
        ),
        if (!managerOnly)
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => _editTable(),
              icon: const Icon(Icons.add),
              label: const Text('Nueva mesa'),
            ),
          ),
        const SizedBox(height: 12),
        _searchField(),
        const SizedBox(height: 12),
        if (tables.isEmpty)
          const EmptyState(message: 'No hay mesas registradas.')
        else
          ...tables.map(
            (table) => Card(
              child: ResponsiveListTile(
                leading: const Icon(Icons.table_restaurant),
                title: Text('Mesa ${table.number}'),
                subtitle: Text('${table.capacity} personas'),
                trailing: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusBadge.table(table.status),
                    if (!managerOnly) ...[
                      IconButton(
                        tooltip: 'Editar mesa',
                        onPressed:
                            table.status == TableStatus.available &&
                                table.groupOrderId == null
                            ? () => _editTable(table)
                            : null,
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Eliminar mesa',
                        onPressed: () async {
                          final confirm = await showLuxuryDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Eliminar mesa'),
                              content: Text(
                                '¿Eliminar la mesa ${table.number}?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancelar'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Eliminar'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await _run(() => store.removeTable(table));
                          }
                        },
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  List<PaymentEntry> _receiptPayments(Map<String, dynamic> receipt) =>
      (receipt['payments'] as List<dynamic>? ?? const [])
          .map(
            (payment) => payment is PaymentEntry
                ? payment
                : PaymentEntry.fromJson(
                    Map<String, dynamic>.from(payment as Map),
                  ),
          )
          .toList(growable: false);
}
