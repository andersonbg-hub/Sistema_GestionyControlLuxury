part of '../dashboard_screen.dart';

extension _AdminReportsView on _AdminScreenState {
  Widget _reportsPage() {
    final waiters =
        store.staff.where((member) => member.role == StaffRole.waiter).toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    final waitersById = {for (final waiter in waiters) waiter.id: waiter};
    final waitersByName = <String, List<StaffMember>>{};
    for (final waiter in waiters) {
      waitersByName
          .putIfAbsent(waiter.name.trim().toLowerCase(), () => [])
          .add(waiter);
    }
    final selectedWaiterId = waitersById.containsKey(reportWaiterId)
        ? reportWaiterId
        : '';
    final ordersById = {for (final order in store.orders) order.id: order};

    StaffMember? waiterFor(RestaurantOrder? order) {
      if (order == null) return null;
      if (order.waiterId != null) return waitersById[order.waiterId];
      final name = order.waiterName.trim().toLowerCase();
      if (name.isEmpty || name == 'mesero' || name == 'equipo luxury') {
        return null;
      }
      final matches = waitersByName[name];
      return matches?.length == 1 ? matches!.single : null;
    }

    String waiterLabel(RestaurantOrder? order) {
      final waiter = waiterFor(order);
      if (waiter != null) return waiter.name;
      final name = order?.waiterName.trim() ?? '';
      return name.isEmpty ||
              name.toLowerCase() == 'mesero' ||
              name == 'Equipo Luxury'
          ? 'Sin mesero identificado'
          : name;
    }

    bool matchesWaiter(Map<String, dynamic> receipt) =>
        selectedWaiterId.isEmpty ||
        waiterFor(ordersById[receipt['orderId']])?.id == selectedWaiterId;

    String receiptTime(Map<String, dynamic> receipt) {
      final timestamp = DateTime.tryParse(
        receipt['createdAt'] as String? ?? '',
      );
      return timestamp == null ? 'Sin fecha' : limaDateTime(timestamp);
    }

    final receiptHistory = store.receipts.where(matchesWaiter).toList();
    final today = limaBusinessDay(DateTime.now());
    final cutoff = switch (reportRange) {
      'Hoy' => today,
      '7 días' => today.subtract(const Duration(days: 6)),
      _ => DateTime.fromMillisecondsSinceEpoch(0),
    };
    final allValidReceipts = receiptHistory.where(
      (receipt) => receipt['status'] == 'VIGENTE',
    );
    final receipts =
        allValidReceipts.where((receipt) {
          final issued = DateTime.tryParse(
            receipt['createdAt'] as String? ?? '',
          );
          if (issued == null || limaBusinessDay(issued).isBefore(cutoff)) {
            return false;
          }
          if (reportMethod != 'Todos' &&
              !_receiptPayments(
                receipt,
              ).any((payment) => payment.method == reportMethod)) {
            return false;
          }
          return true;
        }).toList()..sort(
          (a, b) => DateTime.parse(
            b['createdAt'] as String,
          ).compareTo(DateTime.parse(a['createdAt'] as String)),
        );
    final total = receipts.fold<double>(
      0,
      (sum, receipt) => sum + (receipt['total'] as num).toDouble(),
    );
    final methods = <String, double>{};
    for (final receipt in receipts) {
      for (final payment in _receiptPayments(receipt)) {
        methods.update(
          payment.method,
          (value) => value + payment.amount,
          ifAbsent: () => payment.amount,
        );
      }
    }
    String csvCell(Object? value) =>
        '"${(value ?? '').toString().replaceAll('"', '""')}"';
    final csvRows = [
      ['Nota', 'Fecha', 'Mesa', 'Mesero', 'Métodos de pago', 'Total'],
      ...receipts.map((receipt) {
        final order = ordersById[receipt['orderId']];
        final payments = _receiptPayments(receipt)
            .map(
              (payment) =>
                  '${payment.method} ${payment.amount.toStringAsFixed(2)}',
            )
            .join(' + ');
        return [
          receipt['code'],
          receipt['createdAt'],
          receipt['tableNumber'],
          waiterLabel(order),
          payments,
          (receipt['total'] as num).toStringAsFixed(2),
        ];
      }),
    ].map((row) => row.map(csvCell).join(';')).join('\r\n');
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            title: 'Reportes',
            subtitle: 'Ventas, cobros y actividad',
            /* trailing: OutlinedButton.icon(
              onPressed: receipts.isEmpty
                  ? null
                  : () async {
                      Clipboard.setData(ClipboardData(text: csvRows));
                      await showResultDialog(
                        context,
                        success: true,
                        message:
                            'CSV copiado · ${receipts.length} comprobantes',
                      );
                    },
              icon: const Icon(Icons.content_copy),
              label: const Text('Copiar CSV'),
            ), */
          ),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: receipts.isEmpty
                  ? null
                  : () async {
                      Clipboard.setData(ClipboardData(text: csvRows));
                      await showResultDialog(
                        context,
                        success: true,
                        message:
                            'CSV copiado Â· ${receipts.length} comprobantes',
                      );
                    },
              icon: const Icon(Icons.content_copy),
              label: const Text('Copiar CSV'),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: ['Hoy', '7 días', 'Todo']
                .map(
                  (range) => ChoiceChip(
                    label: Text(range),
                    selected: reportRange == range,
                    onSelected: (_) => _setState(() => reportRange = range),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Método'),
              DropdownButton<String>(
                value: reportMethod,
                items: const ['Todos', 'Efectivo', 'Yape / Plin', 'Tarjeta']
                    .map(
                      (method) =>
                          DropdownMenuItem(value: method, child: Text(method)),
                    )
                    .toList(),
                onChanged: (value) =>
                    _setState(() => reportMethod = value ?? 'Todos'),
              ),
              const Text('Mesero'),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: DropdownButton<String>(
                  key: const ValueKey('report-waiter'),
                  isExpanded: true,
                  value: selectedWaiterId,
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Todos')),
                    for (final waiter in waiters)
                      DropdownMenuItem(
                        value: waiter.id,
                        child: Text(
                          waitersByName[waiter.name.trim().toLowerCase()]!
                                      .length >
                                  1
                              ? '${waiter.name} (${waiter.email})'
                              : waiter.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) =>
                      _setState(() => reportWaiterId = value ?? ''),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          StatGrid(
            maxColumns: 3,
            children: [
              StatCard(
                label: 'Total cobrado',
                value: money(total),
                icon: Icons.payments,
                color: luxuryGold,
              ),
              StatCard(
                label: 'Notas de venta',
                value: '${receipts.length}',
                icon: Icons.receipt_long,
              ),
              StatCard(
                label: 'Ticket promedio',
                value: money(receipts.isEmpty ? 0 : total / receipts.length),
                icon: Icons.show_chart,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cobros por método',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  if (methods.isEmpty)
                    const Text('No hay pagos en el periodo seleccionado.')
                  else
                    ...methods.entries.map(
                      (entry) => ResponsiveListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.account_balance_wallet_outlined,
                        ),
                        title: Text(entry.key),
                        trailing: Text(
                          money(entry.value),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (receipts.isEmpty)
            const EmptyState(
              message: 'No hay notas vigentes con estos filtros.',
              icon: Icons.receipt_long,
            )
          else
            ...receipts.map((receipt) {
              final order = ordersById[receipt['orderId']];
              return Card(
                child: ResponsiveListTile(
                  title: Text(
                    '${receipt['code']} · ${receipt['locationLabel'] ?? 'Mesa ${receipt['tableNumber']}'}',
                  ),
                  subtitle: Text(
                    '${waiterLabel(order)} · ${receiptTime(receipt)}',
                  ),
                  trailing: Text(money((receipt['total'] as num).toDouble())),
                ),
              );
            }),
          const SizedBox(height: 18),
          Text(
            'Notas de venta',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (receiptHistory.isEmpty)
            const Text('No hay notas de venta para esta selección.')
          else
            ...receiptHistory.map(
              (receipt) => Card(
                child: ResponsiveListTile(
                  leading: const Icon(Icons.receipt_long),
                  title: Text(
                    '${receipt['code']} · ${receipt['locationLabel'] ?? 'Mesa ${receipt['tableNumber']}'}',
                  ),
                  subtitle: Text(
                    'Pedido #${receipt['orderId']} · ${receiptTime(receipt)}',
                  ),
                  trailing: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(money((receipt['total'] as num).toDouble())),
                      IconButton(
                        tooltip: 'Imprimir nota',
                        onPressed: () => _printReceipt(receipt),
                        icon: const Icon(Icons.print_outlined),
                      ),
                      if (receipt['status'] == 'ANULADO')
                        const StatusBadge(label: 'Anulada', color: luxuryRed)
                      else
                        IconButton(
                          tooltip: 'Anular nota',
                          onPressed: () => _voidReceipt(receipt),
                          icon: const Icon(Icons.undo, color: luxuryRed),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
