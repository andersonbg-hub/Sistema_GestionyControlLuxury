part of '../kitchen_screen.dart';

extension _KitchenOrderBoardView on _KitchenScreenState {
  Widget _board() {
    final today = limaBusinessDay(DateTime.now());
    final byStage = {
      for (final stage in _KitchenScreenState.stages)
        stage.status: <RestaurantOrder>[],
    };
    var activeCount = 0;
    var matchingCount = 0;
    for (final order in store.orders) {
      if (order.status == OrderStatus.cancelled) continue;
      final stages = <OrderStatus, List<OrderLine>>{};
      for (final line in order.lines) {
        if (!byStage.containsKey(line.status) ||
            store.isWaiterService(line) ||
            limaBusinessDay(line.createdAt ?? order.createdAt) != today) {
          continue;
        }
        (stages[line.status] ??= []).add(line);
      }
      if (stages.isNotEmpty) activeCount++;
      var matched = false;
      for (final entry in stages.entries) {
        final lane = byStage[entry.key]!;
        final lines = entry.value;
        if (notesOnly &&
            order.incident.trim().isEmpty &&
            !lines.any((line) => line.note.trim().isNotEmpty)) {
          continue;
        }
        if (query.isNotEmpty) {
          final text = searchText(
            [
              order.locationLabel,
              order.customerName,
              order.customerPhone,
              order.deliveryAddress,
              order.id,
              order.incident,
              ...lines.expand((line) => [line.name, line.note]),
            ].join(' '),
          );
          if (!text.contains(query)) continue;
        }
        lane.add(order.copyWith(lines: lines));
        matched = true;
      }
      if (matched) matchingCount++;
    }
    for (final lane in byStage.values) {
      lane.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
    final shownStages = _KitchenScreenState.stages
        .where((stage) => stageFilter == null || stage.status == stageFilter)
        .toList();
    final shownCount = stageFilter == null
        ? matchingCount
        : byStage[stageFilter]!.length;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SectionTitle(
          title: 'Comandas de cocina',
          subtitle: 'Comandas de hoy · Actualización en vivo',
          trailing: Wrap(
            children: [
              if (store.isDemo)
                IconButton(
                  tooltip: 'Pedido de prueba',
                  onPressed: () async {
                    final table = store.tables
                        .where((value) => value.status == TableStatus.available)
                        .firstOrNull;
                    final item = store.menu
                        .where((value) => value.available)
                        .firstOrNull;
                    if (table == null || item == null) {
                      await showResultDialog(
                        context,
                        success: false,
                        message:
                            'No hay una mesa disponible o un plato habilitado.',
                      );
                      return;
                    }
                    _run(
                      () => store.createOrder(
                        table: table,
                        diners: 1,
                        lines: [
                          OrderLine(
                            menuItemId: item.id,
                            name: item.name,
                            quantity: 1,
                            unitPrice: item.price,
                          ),
                        ],
                      ),
                    );
                  },
                  icon: const Icon(Icons.add_box_outlined),
                ),
            ],
          ),
        ),
        TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Buscar mesa, pedido o plato',
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpiar búsqueda',
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _search.clear();
                      _setState(() => query = '');
                    },
                  ),
          ),
          onChanged: (value) => _setState(() => query = searchText(value)),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: Text('Todas ($matchingCount)'),
              selected: stageFilter == null,
              onSelected: (_) => _setState(() => stageFilter = null),
            ),
            for (final stage in _KitchenScreenState.stages)
              ChoiceChip(
                label: Text(
                  '${stage.filter} (${byStage[stage.status]!.length})',
                ),
                selected: stageFilter == stage.status,
                onSelected: (value) =>
                    _setState(() => stageFilter = value ? stage.status : null),
              ),
            FilterChip(
              label: const Text('Con observaciones'),
              selected: notesOnly,
              onSelected: (value) => _setState(() => notesOnly = value),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (activeCount == 0)
          const EmptyState(
            message: 'No hay comandas pendientes.',
            icon: Icons.check_circle_outline,
          )
        else if (shownCount == 0)
          EmptyState(
            message: notesOnly
                ? 'No hay comandas con observaciones o incidencias para este filtro.'
                : query.isNotEmpty
                ? 'No hay comandas que coincidan con la búsqueda.'
                : 'No hay comandas en esta etapa.',
            icon: Icons.search_off,
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = [
                for (final stage in shownStages)
                  _lane(
                    stage.status,
                    stage.title,
                    stage.icon,
                    byStage[stage.status]!,
                  ),
              ];
              if (columns.length > 1 && constraints.maxWidth >= 980) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final column in columns)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: column,
                        ),
                      ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: columns,
              );
            },
          ),
      ],
    );
  }

  Widget _lane(
    OrderStatus status,
    String title,
    IconData icon,
    List<RestaurantOrder> orders,
  ) => Card(
    key: ValueKey(status),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: orderColor(status), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              CircleAvatar(
                radius: 13,
                backgroundColor: orderColor(status).withValues(alpha: .16),
                child: Text(
                  '${orders.length}',
                  style: TextStyle(color: orderColor(status), fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (orders.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Sin pedidos',
                style: TextStyle(color: Colors.black45),
              ),
            )
          else
            for (final (index, order) in orders.indexed)
              _ticket(order, status, index),
        ],
      ),
    ),
  );

  Widget _ticket(RestaurantOrder order, OrderStatus stage, int index) {
    final (incidentDish, incidentReason) = order.kitchenIncident;
    final lines = order.lines;
    final firstLineAt = lines
        .map((line) => line.createdAt ?? order.createdAt)
        .reduce((first, next) => first.isBefore(next) ? first : next);
    final units = lines.fold(0, (total, line) => total + line.quantity);
    final nextAction = switch (stage) {
      OrderStatus.pending => 'Iniciar preparación',
      OrderStatus.preparing => 'Marcar listo',
      _ => '',
    };
    return LuxuryReveal(
      key: ValueKey(order.id),
      index: index,
      hover: true,
      child: Card(
        color: luxuryBone,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${order.locationLabel} · #${order.id}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ValueListenableBuilder(
                    valueListenable: clock,
                    builder: (context, now, _) {
                      final elapsed = now.difference(firstLineAt).inMinutes;
                      return StatusBadge(
                        label: '${elapsed < 0 ? 0 : elapsed} min',
                        color: elapsed >= 20 ? luxuryRed : luxuryBrown,
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${limaDateTime(firstLineAt)} · '
                '$units ${units == 1 ? 'porción' : 'porciones'}',
                style: const TextStyle(color: Colors.black54),
              ),
              if (order.pendingSync) ...[
                const SizedBox(height: 6),
                const StatusBadge(
                  label: 'PENDIENTE DE SINCRONIZACIÓN',
                  color: luxuryGold,
                ),
              ],
              if (order.fulfillmentType != FulfillmentType.dineIn)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${order.customerName} · ${order.customerPhone}'
                    '${order.deliveryAddress.isEmpty ? '' : ' · ${order.deliveryAddress}'}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              if (order.status == OrderStatus.paid)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: StatusBadge(
                    label: 'PAGADO · CONTINÚA EN COCINA',
                    color: luxuryGreen,
                  ),
                ),
              if (order.status == OrderStatus.forPayment)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: StatusBadge(
                    label: 'CUENTA SOLICITADA',
                    color: luxuryRed,
                  ),
                ),
              if (incidentReason.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: ErrorBanner(
                    message:
                        'Incidencia: $incidentReason\n'
                        'Platillo: ${incidentDish ?? 'Sin identificar'}',
                  ),
                ),
              const Divider(),
              ...lines.map(
                (line) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StatusBadge(
                        label: '${line.quantity}×',
                        color: luxuryBrown,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              line.name,
                              style: TextStyle(
                                color: line.name == incidentDish
                                    ? luxuryRed
                                    : null,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (line.createdAt case final created?)
                              ValueListenableBuilder(
                                valueListenable: clock,
                                builder: (context, now, _) => Text(
                                  '${now.difference(created).inMinutes.clamp(0, 1000000)} min desde el ingreso',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            if (line.note.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  line.note,
                                  style: const TextStyle(
                                    color: luxuryRed,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            if (line.status != stage)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: StatusBadge.order(line.status),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (stage == OrderStatus.ready)
                const StatusBadge(
                  label: 'LISTO · ESPERANDO AL MESERO',
                  color: luxuryGreen,
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: order.pendingSync
                        ? null
                        : () => _advanceKitchenOrder(order, stage),
                    child: Text(
                      order.pendingSync ? 'Esperando conexión' : nextAction,
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: order.pendingSync
                      ? null
                      : () => _reportIncident(order),
                  icon: const Icon(Icons.report_problem_outlined, size: 18),
                  label: const Text('Reportar incidencia'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
