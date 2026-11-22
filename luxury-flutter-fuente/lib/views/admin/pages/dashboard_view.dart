part of '../dashboard_screen.dart';

extension _AdminDashboardView on _AdminScreenState {
  Widget _dashboard() {
    final today = limaBusinessDay(DateTime.now());
    final yesterday = today.subtract(const Duration(days: 1));
    final validReceipts = store.receipts.where(
      (receipt) => receipt['status'] == 'VIGENTE',
    );
    DateTime? receiptDate(Map<String, dynamic> receipt) =>
        DateTime.tryParse(receipt['createdAt'] as String? ?? '');
    final todayReceipts = validReceipts.where((receipt) {
      final date = receiptDate(receipt);
      return date != null && limaBusinessDay(date) == today;
    }).toList();
    final yesterdayReceipts = validReceipts.where((receipt) {
      final date = receiptDate(receipt);
      return date != null && limaBusinessDay(date) == yesterday;
    }).toList();
    final revenue = todayReceipts.fold<double>(
      0,
      (sum, receipt) => sum + (receipt['total'] as num).toDouble(),
    );
    final yesterdayRevenue = yesterdayReceipts.fold<double>(
      0,
      (sum, receipt) => sum + (receipt['total'] as num).toDouble(),
    );
    final activeOrders = store.orders.where(
      (order) =>
          order.status != OrderStatus.paid &&
          order.status != OrderStatus.cancelled &&
          order.status != OrderStatus.delivered,
    );
    final pendingAlerts = managerOnly
        ? <(InventoryItem?, List<StockAlert>)>[]
        : _pendingInventoryAlerts.toList();
    final occupied = store.tables
        .where((table) => table.status != TableStatus.available)
        .length;
    final weekStart = today.subtract(const Duration(days: 6));
    final bestSellers = <String, int>{};
    for (final order in store.orders.where(
      (order) =>
          order.status == OrderStatus.paid &&
          !limaBusinessDay(order.createdAt).isBefore(weekStart),
    )) {
      for (final line in order.lines) {
        bestSellers.update(
          line.name,
          (count) => count + line.quantity,
          ifAbsent: () => line.quantity,
        );
      }
    }
    final topItems = bestSellers.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final ordersByDay = <DateTime, int>{};
    for (final order in store.orders) {
      final day = limaBusinessDay(order.createdAt);
      if (order.status == OrderStatus.cancelled ||
          order.pendingSync ||
          day.isBefore(weekStart) ||
          day.isAfter(today)) {
        continue;
      }
      ordersByDay.update(day, (count) => count + 1, ifAbsent: () => 1);
    }
    final chartDays = [
      for (var index = 0; index < 7; index++)
        weekStart.add(Duration(days: index)),
    ];
    final trend = yesterdayRevenue == 0
        ? 0
        : ((revenue - yesterdayRevenue) / yesterdayRevenue * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          title: 'Resumen del día',
          subtitle: '${_summaryDate(today)} · Turno actual',
        ),
        StatGrid(
          children: [
            StatCard(
              label: 'Ventas netas',
              value: money(revenue),
              caption: '${trend >= 0 ? '+' : ''}$trend% vs. ayer',
              icon: Icons.bar_chart_rounded,
              color: luxuryGreen,
            ),
            StatCard(
              label: 'Cuentas cerradas',
              value: '${todayReceipts.length}',
              icon: Icons.receipt_long_outlined,
            ),
            StatCard(
              label: 'Ticket promedio',
              value: money(
                todayReceipts.isEmpty ? 0 : revenue / todayReceipts.length,
              ),
              icon: Icons.sell_outlined,
            ),
            StatCard(
              label: 'Mesas ocupadas',
              value: '$occupied de ${store.tables.length}',
              icon: Icons.groups_outlined,
              color: luxuryGold,
            ),
          ],
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final chart = managerOnly
                ? _ordersByDayChart(chartDays, ordersByDay)
                : _ordersTrendChart(chartDays, ordersByDay);
            final attention = _dashboardAttention(activeOrders, pendingAlerts);
            if (constraints.maxWidth < 840) {
              return Column(
                children: [chart, const SizedBox(height: 14), attention],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: chart),
                const SizedBox(width: 14),
                Expanded(flex: 2, child: attention),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final tables = _dashboardTables();
            final best = _dashboardBestSellers(topItems);
            if (constraints.maxWidth < 840) {
              return Column(
                children: [tables, const SizedBox(height: 14), best],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: tables),
                const SizedBox(width: 14),
                Expanded(flex: 2, child: best),
              ],
            );
          },
        ),
      ],
    );
  }

  String _summaryDate(DateTime day) {
    const weekdays = [
      'lunes',
      'martes',
      'miércoles',
      'jueves',
      'viernes',
      'sábado',
      'domingo',
    ];
    const months = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    return '${weekdays[day.weekday - 1]} ${day.day} de ${months[day.month - 1]}';
  }

  Widget _ordersTrendChart(List<DateTime> days, Map<DateTime, int> counts) {
    final values = [for (final day in days) counts[day] ?? 0];
    final maximum = values.fold(0, math.max);
    final step = math.max(1, (maximum / 3).ceil());
    final divisions = math.max(1, (maximum / step).ceil());
    final style = Theme.of(context).textTheme.labelSmall;
    const axisWidth = 30.0;
    const height = 112.0;
    String orderCount(int value) => value == 1 ? '1 pedido' : '$value pedidos';

    return _dashboardChart(
      icon: Icons.show_chart_rounded,
      title: 'Pedidos por día',
      description: 'Últimos 7 días · Hora de Lima',
      children: [
        Row(
          children: [
            SizedBox(
              width: axisWidth,
              height: height,
              child: Stack(
                children: [
                  for (var tick = divisions; tick >= 0; tick--)
                    Align(
                      alignment: Alignment(-1, 1 - 2 * tick / divisions),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${tick * step}',
                          style: style?.copyWith(color: luxuryMuted),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: SizedBox(
                height: height,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    TweenAnimationBuilder<double>(
                      duration: luxuryDuration(context, 520),
                      curve: Curves.easeOutCubic,
                      tween: Tween(begin: 0, end: 1),
                      builder: (context, progress, _) => CustomPaint(
                        painter: _OrdersTrendPainter(
                          values,
                          step * divisions,
                          divisions,
                          progress,
                        ),
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (index, day) in days.indexed)
                          Expanded(
                            child: Tooltip(
                              message:
                                  '${_summaryDate(day)} · ${orderCount(values[index])}',
                              excludeFromSemantics: true,
                              triggerMode: TooltipTriggerMode.tap,
                              child: const ColoredBox(
                                color: Colors.transparent,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            const SizedBox(width: axisWidth),
            for (final (index, day) in days.indexed)
              Expanded(
                child: Semantics(
                  label: '${_summaryDate(day)}, ${orderCount(values[index])}',
                  excludeSemantics: true,
                  child: Column(
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${values[index]}',
                          style: style?.copyWith(
                            color: index == days.length - 1
                                ? luxuryBrown
                                : luxuryInk,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${day.day}/${day.month}',
                          style: style?.copyWith(
                            color: index == days.length - 1
                                ? luxuryBrown
                                : luxuryMuted,
                            fontWeight: index == days.length - 1
                                ? FontWeight.w700
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _ordersByDayChart(List<DateTime> days, Map<DateTime, int> counts) {
    final maximum = counts.values.fold(1, math.max);
    final theme = Theme.of(context);
    final today = days.last;

    return _dashboardChart(
      icon: Icons.bar_chart_rounded,
      title: 'Pedidos por día',
      description: 'Últimos 7 días · Hora de Lima',
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: luxuryBone.withValues(alpha: .50),
            border: Border.all(color: luxuryBorder),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 10),
            child: Row(
              children: [
                for (final day in days)
                  Expanded(
                    child: Tooltip(
                      message:
                          '${_summaryDate(day)} · ${counts[day] ?? 0} pedidos',
                      excludeFromSemantics: true,
                      child: Semantics(
                        label:
                            '${_summaryDate(day)}, ${counts[day] ?? 0} pedidos',
                        excludeSemantics: true,
                        child: Column(
                          children: [
                            Text(
                              '${counts[day] ?? 0}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 5),
                            SizedBox(
                              height: 88,
                              width: 19,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: luxuryBorder,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: TweenAnimationBuilder<double>(
                                  tween: Tween(
                                    begin: 0,
                                    end: (counts[day] ?? 0) / maximum,
                                  ),
                                  duration: luxuryDuration(context, 580),
                                  curve: Curves.easeOutCubic,
                                  builder: (context, fraction, child) =>
                                      FractionallySizedBox(
                                        alignment: Alignment.bottomCenter,
                                        heightFactor: fraction,
                                        child: child,
                                      ),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: day == today
                                          ? luxuryPaletteOrange
                                          : luxuryPaletteGold,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 1,
                                ),
                                child: Text(
                                  '${day.day}/${day.month}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: day == today
                                        ? luxuryBrown
                                        : luxuryMuted,
                                    fontWeight: day == today
                                        ? FontWeight.w800
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _dashboardAttention(
    Iterable<RestaurantOrder> activeOrders,
    List<(InventoryItem?, List<StockAlert>)> pendingAlerts,
  ) {
    final delayed = activeOrders
        .where(
          (order) => DateTime.now().difference(order.createdAt).inMinutes >= 20,
        )
        .toList();
    final openIncidents = store.orders
        .where(
          (order) =>
              order.incident.trim().isNotEmpty &&
              order.incidentSolution.trim().isEmpty,
        )
        .toList();
    final items = <(IconData, String, String, VoidCallback)>[];
    if (delayed.isNotEmpty) {
      items.add((
        Icons.schedule_rounded,
        '${delayed.length} pedidos con demora',
        'Más de 20 minutos en preparación o entrega',
        () => _setState(() => page = _pages.indexOf(managerOnly ? 9 : 4)),
      ));
    }
    if (pendingAlerts.isNotEmpty) {
      items.add((
        Icons.inventory_2_outlined,
        '${pendingAlerts.length} alertas de inventario',
        'Hay insumos por revisar',
        () => _setState(() {
          page = _pages.indexOf(2);
          inventoryTab = 2;
        }),
      ));
    }
    if (openIncidents.isNotEmpty) {
      items.add((
        Icons.warning_amber_rounded,
        '${openIncidents.length} incidencias pendientes',
        'Requieren seguimiento',
        () => _setState(() => page = _pages.indexOf(6)),
      ));
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.notifications_active_outlined,
                  color: luxuryGold,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Requiere atención',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: EmptyState(
                  message: 'No hay alertas pendientes.',
                  icon: Icons.check_circle_outline,
                ),
              )
            else
              for (final item in items.take(4))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(item.$1, color: luxuryGold),
                  title: Text(item.$2),
                  subtitle: Text(item.$3),
                  trailing: TextButton(
                    onPressed: item.$4,
                    child: const Text('Revisar'),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _dashboardBestSellers(List<MapEntry<String, int>> topItems) {
    final theme = Theme.of(context);
    return _dashboardChart(
      icon: Icons.restaurant_menu_rounded,
      title: 'Platos más vendidos',
      description: 'Unidades vendidas en los últimos 7 días',
      children: [
        if (topItems.isEmpty)
          const EmptyState(message: 'Aún no hay ventas para mostrar.')
        else
          for (final (index, item) in topItems.take(5).indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 13),
              child: LuxuryReveal(
                key: ValueKey(item.key),
                index: index,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 13,
                      backgroundColor: luxuryBone,
                      foregroundColor: luxuryBrown,
                      child: Text(
                        '${index + 1}',
                        style: theme.textTheme.labelMedium,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  item.key,
                                  style: theme.textTheme.labelLarge,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${item.value}',
                                style: theme.textTheme.labelLarge,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          TweenAnimationBuilder<double>(
                            tween: Tween(
                              begin: 0,
                              end:
                                  item.value /
                                  math.max(1, topItems.first.value),
                            ),
                            duration: luxuryDuration(context, 560),
                            curve: Curves.easeOutCubic,
                            builder: (context, fraction, _) =>
                                LinearProgressIndicator(
                                  value: fraction,
                                  minHeight: 6,
                                  borderRadius: BorderRadius.circular(6),
                                  color: index == 0
                                      ? luxuryPaletteOrange
                                      : luxuryPaletteGold,
                                  backgroundColor: luxuryBone,
                                  semanticsLabel: item.key,
                                  semanticsValue: '${item.value} unidades',
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  Widget _dashboardChart({
    required IconData icon,
    required String title,
    required String description,
    required List<Widget> children,
  }) => LuxuryReveal(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: luxuryBone,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(icon, color: luxuryBrown, size: 19),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        description,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    ),
  );

  Widget _dashboardTables() {
    final available = store.tables
        .where((table) => table.status == TableStatus.available)
        .length;
    final occupied = store.tables
        .where((table) => table.status == TableStatus.occupied)
        .length;
    final payment = store.tables
        .where((table) => table.status == TableStatus.payment)
        .length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Estado del salón',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _countChip('Disponibles', available, luxuryPaletteGreen),
                _countChip('Ocupadas', occupied, luxuryPaletteGold),
                _countChip('Por cobrar', payment, luxuryPaletteRed),
              ],
            ),
            const SizedBox(height: 10),
            ...store.tables
                .take(8)
                .map(
                  (table) => ResponsiveListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.table_restaurant,
                      color: statusColor(table.status.databaseValue),
                    ),
                    title: Text('Mesa ${table.number}'),
                    subtitle: Text('${table.capacity} personas'),
                    trailing: StatusBadge.table(table.status),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _inventoryAlertTile(
    InventoryItem? item,
    List<StockAlert> notices, {
    bool dense = false,
  }) {
    final hasRequest = item != null && store.openStockRequestFor(item) != null;
    final title = item == null
        ? notices.single.message
        : item.lowStock
        ? 'Stock bajo: ${item.name}'
        : item.name;
    final details = [
      if (item != null)
        'Actual ${item.quantity} ${item.unit} · mínimo ${item.minimum}',
      if (item == null) 'Aviso de cocina · ${notices.single.priority}',
      if (item != null) ...notices.map((notice) => notice.message).toSet(),
      if (hasRequest) 'Reposición registrada',
    ];
    return ResponsiveListTile(
      dense: dense,
      contentPadding: dense ? EdgeInsets.zero : null,
      leading: Icon(
        item?.lowStock == true
            ? Icons.warning_amber
            : Icons.notifications_active_outlined,
        color: luxuryRed,
      ),
      title: Text(title),
      subtitle: Text(details.join('\n')),
      trailing: managerOnly
          ? null
          : TextButton(
              onPressed: _attendingAlert
                  ? null
                  : () => _attendInventoryAlert(item, notices),
              child: Text(
                hasRequest && notices.isEmpty ? 'Ver solicitud' : 'Atender',
              ),
            ),
    );
  }

  Widget _countChip(String label, int count, Color color) => Chip(
    avatar: CircleAvatar(radius: 7, backgroundColor: color),
    label: Text('$label · $count'),
  );
}

class _OrdersTrendPainter extends CustomPainter {
  const _OrdersTrendPainter(
    this.values,
    this.ceiling,
    this.divisions,
    this.progress,
  );

  final List<int> values;
  final int ceiling;
  final int divisions;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 7.0;
    final baseline = size.height - inset;
    final plotHeight = baseline - inset;
    final grid = Paint()..color = luxuryBorder;
    for (var index = 0; index <= divisions; index++) {
      final y = inset + plotHeight * index / divisions;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final interval = size.width / values.length;
    final points = [
      for (final (index, value) in values.indexed)
        Offset(
          (index + .5) * interval,
          baseline - plotHeight * progress * value / ceiling,
        ),
    ];
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      line.lineTo(point.dx, point.dy);
    }

    final area = Path.from(line)
      ..lineTo(points.last.dx, baseline)
      ..lineTo(points.first.dx, baseline)
      ..close();
    canvas.drawPath(area, Paint()..color = luxuryGold.withValues(alpha: .13));
    canvas.drawPath(
      line,
      Paint()
        ..color = luxuryPaletteOrange
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );

    for (final (index, point) in points.indexed) {
      final isToday = index == points.length - 1;
      canvas.drawCircle(
        point,
        isToday ? 5.5 : 4.5,
        Paint()..color = luxuryPaletteOrange,
      );
      if (!isToday) {
        canvas.drawCircle(point, 2.2, Paint()..color = const Color(0xFFFFFDFC));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _OrdersTrendPainter old) =>
      old.values != values ||
      old.ceiling != ceiling ||
      old.progress != progress;
}
