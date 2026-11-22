part of '../dashboard_screen.dart';

extension _AdminManagerFloorView on _AdminScreenState {
  Widget _managerFloorPage() {
    final tables = store.tables.where((table) => table.active).toList()
      ..sort((a, b) => a.number.compareTo(b.number));
    final occupied = tables
        .where((table) => table.status == TableStatus.occupied)
        .length;
    final available = tables
        .where((table) => table.status == TableStatus.available)
        .length;
    final due = tables
        .where((table) => table.status == TableStatus.payment)
        .length;
    final activeOrders = store.orders.where(
      (order) =>
          order.status != OrderStatus.cancelled &&
          order.status != OrderStatus.paid,
    );
    final selectedTable =
        tables
            .where((table) => table.id == _managerSelectedTable)
            .firstOrNull ??
        tables
            .where((table) => table.status != TableStatus.available)
            .firstOrNull ??
        tables.firstOrNull;
    final query = _managerTableQuery.trim().toLowerCase();
    final visibleTables = tables.where((table) {
      final label =
          'mesa ${table.number} ${store.tableLocationLabel(table)} ${table.status.label}'
              .toLowerCase();
      return query.isEmpty || label.contains(query);
    }).toList();
    final visibleOrders = activeOrders.where((order) {
      final label =
          '${order.id} ${order.locationLabel} ${order.waiterName} ${order.status.label}'
              .toLowerCase();
      return query.isEmpty || label.contains(query);
    }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(
          title: 'Salón y pedidos',
          subtitle: 'Supervisa tiempos, atención y cuentas del salón',
        ),
        StatGrid(
          children: [
            StatCard(
              label: 'Mesas activas',
              value: '${tables.length}',
              icon: Icons.table_restaurant,
            ),
            StatCard(
              label: 'Ocupadas',
              value: '$occupied',
              icon: Icons.people_outline,
              color: luxuryGold,
            ),
            StatCard(
              label: 'Libres',
              value: '$available',
              icon: Icons.event_seat_outlined,
              color: luxuryGreen,
            ),
            StatCard(
              label: 'Por cobrar',
              value: '$due',
              icon: Icons.point_of_sale_outlined,
              color: luxuryRed,
            ),
          ],
        ),
        const SizedBox(height: 16),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(
              value: 0,
              label: Text('Salón'),
              icon: Icon(Icons.table_restaurant),
            ),
            ButtonSegment(
              value: 1,
              label: Text('Pedidos'),
              icon: Icon(Icons.receipt_long_outlined),
            ),
          ],
          selected: {_managerFloorTab},
          onSelectionChanged: (selection) =>
              _setState(() => _managerFloorTab = selection.first),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('manager-floor-search'),
          onChanged: (value) => _setState(() => _managerTableQuery = value),
          decoration: const InputDecoration(
            hintText: 'Buscar mesa, pedido o responsable',
            prefixIcon: Icon(Icons.search),
            isDense: true,
          ),
        ),
        const SizedBox(height: 14),
        if (_managerFloorTab == 0)
          LayoutBuilder(
            builder: (context, constraints) {
              if (selectedTable == null || constraints.maxWidth < 900) {
                return Column(
                  children: [
                    _managerTableGrid(visibleTables, selectedTable),
                    if (selectedTable != null) ...[
                      const SizedBox(height: 12),
                      _managerTableDetail(selectedTable),
                    ],
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: _managerTableGrid(visibleTables, selectedTable),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: _managerTableDetail(selectedTable)),
                ],
              );
            },
          )
        else
          _managerOrderList(visibleOrders),
      ],
    );
  }

  Widget _managerTableGrid(
    List<RestaurantTable> tables,
    RestaurantTable? selected,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 1000
          ? 3
          : constraints.maxWidth >= 620
          ? 2
          : 1;
      const spacing = 12.0;
      final width = (constraints.maxWidth - (columns - 1) * spacing) / columns;
      if (tables.isEmpty) {
        return const EmptyState(message: 'No hay mesas que coincidan.');
      }
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final table in tables)
            SizedBox(
              width: width,
              child: _managerTableCard(table, selected?.id == table.id),
            ),
        ],
      );
    },
  );

  Widget _managerTableCard(RestaurantTable table, bool selected) {
    final service = store.serviceTableFor(table);
    final group = store.tableGroupFor(table);
    final capacity = store.tableServiceCapacity(table);
    final orders = store.orders.where(
      (order) =>
          order.tableId == service.id &&
          order.status != OrderStatus.cancelled &&
          order.status != OrderStatus.paid,
    );
    final order = orders.firstOrNull;
    final age = order == null
        ? null
        : DateTime.now().difference(order.createdAt).inMinutes.clamp(0, 999);
    final color = statusColor(table.status.databaseValue);
    return Card(
      color: selected ? const Color(0xFFFFF8F2) : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _setState(() => _managerSelectedTable = table.id),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.table_restaurant, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Mesa ${table.number.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  StatusBadge.table(table.status),
                ],
              ),
              const SizedBox(height: 8),
              if (group != null) Text(group.locationLabel),
              Text(
                order == null
                    ? 'Capacidad $capacity'
                    : '${order.diners}/$capacity personas',
              ),
              if (order != null) ...[
                const SizedBox(height: 4),
                Text('${age ?? 0} min · ${order.waiterName}'),
                if (order.status == OrderStatus.forPayment)
                  Text('Saldo ${money(order.balance)}'),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _managerTableDetail(RestaurantTable table) {
    final service = store.serviceTableFor(table);
    final group = store.tableGroupFor(table);
    final order = store.orders
        .where(
          (item) =>
              item.tableId == service.id &&
              item.status != OrderStatus.cancelled &&
              item.status != OrderStatus.paid,
        )
        .firstOrNull;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    group?.locationLabel ??
                        'Mesa ${table.number.toString().padLeft(2, '0')}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                StatusBadge.table(table.status),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              order == null
                  ? 'Capacidad ${store.tableServiceCapacity(table)}'
                  : '${order.diners} comensales · ${order.waiterName}',
            ),
            if (order != null) ...[
              const Divider(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Pedido #${order.id}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    'Abierto hace ${DateTime.now().difference(order.createdAt).inMinutes.clamp(0, 999)} min',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (final line in order.lines)
                ResponsiveListTile(
                  dense: true,
                  title: Text('${line.quantity}  ${line.name}'),
                  trailing: Text(money(line.subtotal)),
                ),
              const Divider(height: 20),
              ResponsiveListTile(
                title: const Text('Total'),
                trailing: Text(
                  money(order.total),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (order.balance > .001)
                ResponsiveListTile(
                  title: const Text('Saldo pendiente'),
                  trailing: Text(money(order.balance)),
                ),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Esta mesa no tiene pedidos abiertos.'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _managerOrderList(List<RestaurantOrder> orders) {
    if (orders.isEmpty) {
      return const EmptyState(message: 'No hay pedidos que coincidan.');
    }
    return Column(
      children: [
        for (final order in orders)
          Card(
            child: ResponsiveListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: Text('${order.locationLabel} · Pedido #${order.id}'),
              subtitle: Text(
                '${order.waiterName} · ${order.lines.length} productos · ${DateTime.now().difference(order.createdAt).inMinutes.clamp(0, 999)} min',
              ),
              trailing: Wrap(
                spacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StatusBadge.order(order.status),
                  Text(money(order.balance > 0 ? order.balance : order.total)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
