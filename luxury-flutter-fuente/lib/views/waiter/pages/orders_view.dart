part of '../waiter_screen.dart';

extension _WaiterOrdersView on _WaiterScreenState {
  List<RestaurantOrder> _tableBillOrders(int tableId) =>
      store.orders
          .where(
            (order) =>
                order.tableId == tableId &&
                !order.retirementConfirmed &&
                !(order.pendingSync && order.appendsToAccount) &&
                order.status != OrderStatus.cancelled,
          )
          .toList()
        ..sort((first, second) => first.createdAt.compareTo(second.createdAt));

  Future<void> _showOrderBill(RestaurantOrder order) async {
    final tableId = order.tableId;
    final tableOrders = tableId != null && !order.retirementConfirmed
        ? _tableBillOrders(tableId)
        : const <RestaurantOrder>[];
    await _showBill(tableOrders.isEmpty ? [order] : tableOrders);
  }

  Future<void> _showBill(List<RestaurantOrder> orders) async {
    final tableIds = orders
        .map((order) => order.tableId)
        .whereType<int>()
        .toSet();
    final awaitingConsumption = store.pendingOrders.any(
      (pending) =>
          pending.appendsToAccount && tableIds.contains(pending.tableId),
    );
    if (awaitingConsumption) {
      await showResultDialog(
        context,
        success: false,
        message:
            'Hay consumos pendientes de sincronización. Actualiza los pedidos antes de mostrar la cuenta al cliente.',
      );
      return;
    }
    await showLuxuryDialog<void>(
      context: context,
      builder: (context) => _WaiterBillDialog(orders: orders),
    );
  }

  Future<void> _requestBill(RestaurantOrder order) async {
    final confirmed = await confirmAction(
      context,
      title: '¿Solicitar la cuenta?',
      message: order.hasJoinedTables
          ? '${order.locationLabel} pasarán a Por cobrar. Caja recibirá una cuenta para el grupo.'
          : order.fulfillmentType == FulfillmentType.dineIn
          ? '${order.locationLabel} pasará a Por cobrar y se cerrará el ingreso de pedidos para esta mesa.'
          : 'La cuenta del pedido #${order.id} se enviará a Caja.',
      actionLabel: 'Solicitar cuenta',
    );
    if (!confirmed || !mounted) return;
    await _run(
      () => store.setOrderForPayment(order),
      label: 'Solicitando cuenta…',
    );
  }

  Future<void> _confirmTableRelease(RestaurantTable table) async {
    final group = store.tableGroupFor(table);
    final joined = group != null;
    final confirmed = await confirmAction(
      context,
      title: group != null
          ? '¿Liberar ${group.locationLabel.toLowerCase()}?'
          : '¿Liberar la mesa ${table.number}?',
      message: joined
          ? 'Confirma que los clientes se retiraron. Las mesas volverán a estar disponibles.'
          : 'Confirma que los clientes se retiraron. La mesa volverá a estar disponible.',
      actionLabel: joined ? 'Liberar mesas' : 'Liberar mesa',
    );
    if (!confirmed || !mounted) return;
    await _run(() {
      if (store.tableGroupFor(table)?.id != group?.id) {
        throw StateError('El servicio de esta mesa cambió. Vuelve a abrirlo.');
      }
      return store.confirmTableRelease(table);
    }, label: joined ? 'Liberando mesas…' : 'Liberando mesa…');
  }

  Future<void> _cancelOrder(RestaurantOrder order) async {
    final confirmed = await showLuxuryDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar pedido'),
        content: Text(
          '¿Cancelar el pedido #${order.id}? Solo se puede hacer antes de que cocina inicie y sin abonos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancelar pedido'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _run(() => store.cancelOrder(order));
  }

  Widget _historyDay(DateTime day) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 6),
    child: Row(
      children: [
        const Icon(
          Icons.calendar_today_outlined,
          size: 16,
          color: luxuryPaletteDark,
        ),
        const SizedBox(width: 8),
        Text(
          '${shortDate(day)}/${day.year}',
          style: const TextStyle(
            color: luxuryPaletteDark,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(child: Divider()),
      ],
    ),
  );

  Widget _orders({bool history = false}) {
    final today = limaBusinessDay(DateTime.now());
    final orders = store.orders.where((order) {
      final isToday = limaBusinessDay(order.createdAt) == today;
      final finished =
          order.status == OrderStatus.cancelled ||
          (order.balance <= .001 &&
              kitchenStage(order) == OrderStatus.delivered) ||
          (order.status == OrderStatus.delivered && order.balance <= .001);
      if (history) {
        return (finished || !isToday) &&
            inBusinessRange(order.createdAt, historyRange) &&
            searchText(
              [
                order.id,
                order.locationLabel,
                order.customerName,
                ...order.lines.map((line) => line.name),
              ].join(' '),
            ).contains(historyQuery);
      }
      return isToday && order.status != OrderStatus.cancelled && !finished;
    }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SectionTitle(
          title: history ? 'Historial' : 'Mis pedidos',
          subtitle: history
              ? 'Pedidos de días anteriores y pedidos finalizados'
              : 'Seguimiento de pedidos abiertos de hoy',
        ),
        if (history) ...[
          TextFormField(
            initialValue: historyQuery,
            decoration: const InputDecoration(
              labelText: 'Buscar pedido, mesa o plato',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) =>
                _setState(() => historyQuery = searchText(value)),
          ),
          const SizedBox(height: 10),
          HistoryDateFilter(
            value: historyRange,
            onChanged: (value) => _setState(() => historyRange = value),
          ),
          const SizedBox(height: 12),
        ],
        if (orders.isEmpty)
          EmptyState(
            message: history
                ? 'Aún no hay pedidos en el historial.'
                : 'No hay pedidos abiertos para hoy.',
            icon: Icons.receipt_long,
          )
        else
          for (final (index, order) in orders.indexed) ...[
            if (history &&
                (index == 0 ||
                    !isSameLimaBusinessDay(
                      orders[index - 1].createdAt,
                      order.createdAt,
                    )))
              _historyDay(limaBusinessDay(order.createdAt)),
            Card(
              key: ValueKey(order.id),
              child: ExpansionTile(
                key: PageStorageKey('waiter-order-${order.id}'),
                leading: CircleAvatar(
                  backgroundColor: luxuryGold.withValues(alpha: .14),
                  child: order.hasJoinedTables
                      ? const Icon(Icons.link, size: 19)
                      : Text(
                          order.fulfillmentType == FulfillmentType.dineIn
                              ? '${order.tableNumber}'
                              : order.fulfillmentType ==
                                    FulfillmentType.delivery
                              ? 'D'
                              : 'L',
                        ),
                ),
                title: Text('Pedido #${order.id} · ${order.locationLabel}'),
                subtitle: Text(
                  '${order.lines.fold<int>(0, (sum, line) => sum + line.quantity)} productos · ${money(order.total)}',
                ),
                trailing: order.pendingSync
                    ? const StatusBadge(
                        label: 'Sin sincronizar',
                        color: luxuryGold,
                      )
                    : StatusBadge.order(order.status),
                children: [
                  if (order.fulfillmentType != FulfillmentType.dineIn)
                    ResponsiveListTile(
                      dense: true,
                      leading: const Icon(Icons.person_outline),
                      title: Text(order.customerName),
                      subtitle: Text(
                        order.fulfillmentType == FulfillmentType.delivery
                            ? '${order.customerPhone} · ${order.deliveryAddress}'
                            : order.customerPhone,
                      ),
                    ),
                  for (final line in order.lines)
                    ResponsiveListTile(
                      dense: true,
                      title: Text('${line.quantity} × ${line.name}'),
                      subtitle: store.isWaiterService(line)
                          ? Text(
                              '${line.status == OrderStatus.delivered ? 'Entregado por el mesero' : 'Por entregar por el mesero'}'
                              '${line.note.isEmpty ? '' : '\n${line.note}'}',
                            )
                          : line.note.isEmpty
                          ? null
                          : Text(line.note),
                      trailing: Text(money(line.subtotal)),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (order.status != OrderStatus.cancelled)
                          OutlinedButton.icon(
                            onPressed: () => _showOrderBill(order),
                            icon: const Icon(Icons.receipt_long_outlined),
                            label: const Text('Mostrar cuenta'),
                          ),
                        if (order.fulfillmentType == FulfillmentType.dineIn &&
                            !order.retirementConfirmed &&
                            !order.pendingSync &&
                            order.status != OrderStatus.cancelled &&
                            store.tables.any(
                              (table) =>
                                  table.id == order.tableId &&
                                  store.canOrderAtTable(table) &&
                                  store.additionalOrderParent(table) != null,
                            ))
                          OutlinedButton.icon(
                            key: ValueKey('add-consumption-${order.id}'),
                            onPressed: () {
                              final table = store.tables.firstWhere(
                                (value) => value.id == order.tableId,
                              );
                              _openOrder(table);
                            },
                            icon: const Icon(Icons.add_shopping_cart),
                            label: const Text('Agregar consumo'),
                          ),
                        if (!order.pendingSync &&
                            order.status == OrderStatus.pending &&
                            order.payments.isEmpty &&
                            order.lines.every(
                              (line) => line.status == OrderStatus.pending,
                            )) ...[
                          if (order.lines
                                      .map((line) => line.menuItemId)
                                      .toSet()
                                      .length ==
                                  order.lines.length &&
                              store.tables.any(
                                (table) =>
                                    table.id == order.tableId &&
                                    store.canOrderAtTable(table),
                              ))
                            OutlinedButton.icon(
                              onPressed: () {
                                final table = store.tables.firstWhere(
                                  (value) => value.id == order.tableId,
                                );
                                _openOrder(table, editOrder: order);
                              },
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Editar pedido'),
                            ),
                          OutlinedButton.icon(
                            onPressed: () => _cancelOrder(order),
                            icon: const Icon(Icons.cancel_outlined),
                            label: const Text('Cancelar pedido'),
                          ),
                        ],
                        if (store.canConfirmWaiterService(order))
                          FilledButton.tonalIcon(
                            onPressed: () => _run(
                              () => store.confirmWaiterService(order),
                              label: 'Registrando entrega…',
                            ),
                            icon: const Icon(Icons.local_cafe_outlined),
                            label: const Text(
                              'Confirmar entrega de bebidas y postres',
                            ),
                          ),
                        if (!order.pendingSync &&
                            !order.retirementConfirmed &&
                            order.status != OrderStatus.cancelled &&
                            store
                                .kitchenLines(order)
                                .any(
                                  (line) => line.status == OrderStatus.ready,
                                ))
                          FilledButton.tonalIcon(
                            onPressed: () => _run(
                              () => store.advanceOrder(
                                order,
                                forStage: OrderStatus.ready,
                              ),
                            ),
                            icon: const Icon(Icons.done_all),
                            label: const Text('Confirmar entrega de cocina'),
                          ),
                        if (order.status == OrderStatus.ready ||
                            order.status == OrderStatus.delivered)
                          OutlinedButton.icon(
                            onPressed: () => _requestBill(order),
                            icon: const Icon(Icons.point_of_sale),
                            label: const Text('Solicitar cuenta'),
                          ),
                        if (order.balance > 0)
                          Text(
                            'Saldo ${money(order.balance)}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        if (order.fulfillmentType == FulfillmentType.dineIn &&
                            order.tableId != null &&
                            order.status == OrderStatus.paid &&
                            kitchenStage(order) == OrderStatus.delivered &&
                            !order.retirementConfirmed) ...[
                          OutlinedButton.icon(
                            onPressed: () {
                              final table = store.tables
                                  .where((value) => value.id == order.tableId)
                                  .firstOrNull;
                              if (table != null) {
                                _confirmTableRelease(table);
                              }
                            },
                            icon: const Icon(Icons.check_circle_outline),
                            label: Text(
                              order.hasJoinedTables
                                  ? 'Confirmar retiro de mesas'
                                  : 'Confirmar retiro de mesa',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
      ],
    );
  }
}

class _WaiterBillDialog extends StatelessWidget {
  const _WaiterBillDialog({required this.orders});

  final List<RestaurantOrder> orders;

  @override
  Widget build(BuildContext context) {
    final firstOrder = orders.first;
    final multipleOrders = orders.length > 1;
    final total = orders.fold<double>(0, (sum, order) => sum + order.total);
    final paid = orders.fold<double>(0, (sum, order) => sum + order.paid);
    final balance = orders.fold<double>(0, (sum, order) => sum + order.balance);
    final textTheme = Theme.of(context).textTheme;
    final totalStyle = textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
    );

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      scrollable: true,
      title: const Text('Precuenta'),
      content: SizedBox(
        width: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              multipleOrders
                  ? firstOrder.locationLabel
                  : '${firstOrder.locationLabel} · Pedido #${firstOrder.id}',
              style: textTheme.titleMedium,
            ),
            const Text('Documento informativo. El pago se registra en Caja.'),
            if (orders.any((order) => order.pendingSync)) ...[
              const SizedBox(height: 8),
              const Text('Incluye pedidos pendientes de sincronización.'),
            ],
            const Divider(height: 24),
            for (final order in orders) ...[
              if (multipleOrders)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    order.pendingSync
                        ? 'Pedido sin sincronizar'
                        : 'Pedido #${order.id}',
                    style: textTheme.titleSmall,
                  ),
                ),
              for (final line in order.lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${line.quantity} × ${line.name}'),
                            Text(
                              '${money(line.unitPrice)} por unidad',
                              style: textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(money(line.subtotal)),
                    ],
                  ),
                ),
            ],
            const Divider(height: 24),
            _amount('Total', total, style: totalStyle),
            if (paid > 0) ...[
              _amount('Abonado', paid),
              _amount('Saldo pendiente', balance, style: totalStyle),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }

  Widget _amount(String label, double amount, {TextStyle? style}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(label, style: style)),
        const SizedBox(width: 12),
        Text(money(amount), style: style),
      ],
    ),
  );
}
