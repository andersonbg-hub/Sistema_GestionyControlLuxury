part of '../waiter_screen.dart';

extension _WaiterFloorView on _WaiterScreenState {
  Future<void> _chooseTableGroup() async {
    final selectedIds = <int>{};
    final joined = await showLuxuryDialog<List<RestaurantTable>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final available = store.tables.where(store.canJoinTable).toList()
              ..sort((a, b) => a.number.compareTo(b.number));
            final selected = available
                .where((table) => selectedIds.contains(table.id))
                .toList();
            final capacity = selected.fold<int>(
              0,
              (total, table) => total + table.capacity,
            );
            return AlertDialog(
              scrollable: true,
              title: const Text('Juntar mesas'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Selecciona al menos dos mesas disponibles.'),
                    for (final table in available)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text('Mesa ${table.number}'),
                        subtitle: Text('${table.capacity} asientos'),
                        value: selectedIds.contains(table.id),
                        onChanged: (checked) => setDialogState(() {
                          if (checked == true) {
                            selectedIds.add(table.id);
                          } else {
                            selectedIds.remove(table.id);
                          }
                        }),
                      ),
                    if (available.length < 2)
                      const Text(
                        'Se necesitan dos mesas libres para continuar.',
                      ),
                    if (selected.length >= 2)
                      Text(
                        '${_joinedTablesLabel(selected)} · $capacity asientos en total',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: selected.length < 2
                      ? null
                      : () => Navigator.pop(context, selected),
                  child: const Text('Continuar al pedido'),
                ),
              ],
            );
          },
        ),
      ),
    );
    if (joined == null || !mounted) return;
    _openOrder(joined.first, joinedTables: joined);
  }

  Future<void> _tableActions(RestaurantTable table) async {
    final serviceTable = store.serviceTableFor(table);
    final group = store.tableGroupFor(table);
    final billOrders = _tableBillOrders(serviceTable.id);
    final activeOrders = billOrders.where(
      (order) => order.status != OrderStatus.paid,
    );
    final canOrder = store.canOrderAtTable(table);
    final parent = store.additionalOrderParent(table);
    final settledOrders = store.orders
        .where(
          (order) =>
              order.tableId == serviceTable.id &&
              (order.status == OrderStatus.paid ||
                  order.status == OrderStatus.cancelled) &&
              !order.retirementConfirmed,
        )
        .toList();
    final canRelease =
        settledOrders.isNotEmpty &&
        store.orders
            .where((order) => order.tableId == serviceTable.id)
            .every(
              (order) =>
                  order.status == OrderStatus.paid ||
                  order.status == OrderStatus.cancelled,
            ) &&
        settledOrders.every(
          (order) =>
              order.status != OrderStatus.paid ||
              kitchenStage(order) == OrderStatus.delivered,
        );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      sheetAnimationStyle: luxuryOverlayMotion(context),
      constraints: const BoxConstraints(maxWidth: 540),
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .72,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ResponsiveListTile(
                  leading: const Icon(
                    Icons.table_restaurant,
                    color: luxuryGold,
                  ),
                  title: Text(store.tableLocationLabel(table)),
                  subtitle: Text(
                    '${store.tableServiceCapacity(table)} personas · ${table.status.label}',
                  ),
                ),
                if (canOrder)
                  ResponsiveListTile(
                    leading: const Icon(Icons.add_shopping_cart),
                    title: Text(
                      parent == null ? 'Nuevo pedido' : 'Agregar consumo',
                    ),
                    subtitle: parent == null
                        ? null
                        : Text('Se suma a la cuenta del pedido #${parent.id}'),
                    onTap: () {
                      Navigator.pop(context);
                      _openOrder(table, parentOrder: parent);
                    },
                  )
                else if (store.tableBillingStarted(table))
                  ResponsiveListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: Text(
                      group == null
                          ? 'La mesa ya está en cobro'
                          : 'Las mesas unidas ya están en cobro',
                    ),
                    subtitle: Text(
                      group == null
                          ? 'Los pedidos se habilitan al liberar la mesa.'
                          : 'Los pedidos se habilitan al liberar las mesas.',
                    ),
                  ),
                if (billOrders.isNotEmpty)
                  ResponsiveListTile(
                    leading: const Icon(Icons.receipt_long),
                    title: const Text('Mostrar cuenta'),
                    onTap: () {
                      Navigator.pop(context);
                      final currentOrders = _tableBillOrders(serviceTable.id);
                      if (currentOrders.isNotEmpty) _showBill(currentOrders);
                    },
                  ),
                if (activeOrders.isNotEmpty)
                  ResponsiveListTile(
                    leading: const Icon(Icons.list_alt_outlined),
                    title: Text(
                      'Ver pedidos abiertos (${activeOrders.length})',
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _setState(() => page = 1);
                    },
                  ),
                if (canRelease)
                  ResponsiveListTile(
                    leading: const Icon(Icons.check_circle_outline),
                    title: Text(
                      group == null
                          ? 'Confirmar retiro y liberar mesa'
                          : 'Confirmar retiro y liberar mesas',
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _confirmTableRelease(table);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _floor() {
    final tables = store.tables.where((table) => table.active).toList();
    final firstAvailable = tables
        .where(
          (table) =>
              store.canOrderAtTable(table) &&
              store.additionalOrderParent(table) == null,
        )
        .firstOrNull;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SectionTitle(
          title: 'Mesas',
          subtitle: 'Toca una mesa para abrir el servicio',
          trailing: FilledButton.icon(
            onPressed: firstAvailable == null ? null : _chooseNewOrderTable,
            icon: const Icon(Icons.add),
            label: const Text('Nuevo pedido'),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (store.supportsTableGroups)
              OutlinedButton.icon(
                onPressed: tables.where(store.canJoinTable).length >= 2
                    ? _chooseTableGroup
                    : null,
                icon: const Icon(Icons.link),
                label: const Text('Juntar mesas'),
              ),
            OutlinedButton.icon(
              onPressed: () => _openOffPremiseOrder(FulfillmentType.takeaway),
              icon: const Icon(Icons.shopping_bag_outlined),
              label: const Text('Para llevar'),
            ),
            OutlinedButton.icon(
              onPressed: () => _openOffPremiseOrder(FulfillmentType.delivery),
              icon: const Icon(Icons.delivery_dining),
              label: const Text('Delivery'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 9,
          runSpacing: 9,
          children: [
            _legend('Disponible', luxuryGreen),
            _legend('Ocupada', luxuryGold),
            _legend('Por cobrar', luxuryRed),
          ],
        ),
        const SizedBox(height: 14),
        if (tables.isEmpty)
          const EmptyState(
            message: 'No hay mesas activas en el salón.',
            icon: Icons.table_restaurant,
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 850
                  ? 4
                  : constraints.maxWidth > 650
                  ? 3
                  : constraints.maxWidth > 360
                  ? 2
                  : 1;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: tables.length,
                findChildIndexCallback: (key) {
                  final index = tables.indexWhere(
                    (table) => ValueKey(table.id) == key,
                  );
                  return index < 0 ? null : index;
                },
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  mainAxisExtent:
                      205 * MediaQuery.textScalerOf(context).scale(1),
                ),
                itemBuilder: (context, index) {
                  final table = tables[index];
                  final group = store.tableGroupFor(table);
                  final tableId = store.serviceTableFor(table).id;
                  final orderCount = store.orders
                      .where(
                        (order) =>
                            order.tableId == tableId &&
                            !order.retirementConfirmed &&
                            order.status != OrderStatus.paid &&
                            order.status != OrderStatus.cancelled,
                      )
                      .length;
                  return LuxuryReveal(
                    key: ValueKey(table.id),
                    index: index,
                    hover: true,
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _tableActions(table),
                        child: AnimatedContainer(
                          duration: luxuryDuration(context, 220),
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(
                                color: statusColor(table.status.databaseValue),
                                width: 5,
                              ),
                            ),
                          ),
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _RectangularTableGraphic(table: table),
                              const Spacer(),
                              Text(
                                'Mesa ${table.number}',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 4),
                              if (group case final joined?)
                                Tooltip(
                                  message: joined.locationLabel,
                                  child: Text(
                                    joined.locationLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                )
                              else
                                Text(
                                  '${table.capacity} asientos · $orderCount ${orderCount == 1 ? 'pedido' : 'pedidos'}',
                                ),
                              const SizedBox(height: 8),
                              StatusBadge.table(table.status),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
      ],
    );
  }

  Widget _legend(String label, Color color) => Chip(
    avatar: CircleAvatar(radius: 6, backgroundColor: color),
    label: Text(label),
  );
}
