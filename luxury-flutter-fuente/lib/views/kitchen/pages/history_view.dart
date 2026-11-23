part of '../kitchen_screen.dart';

extension _KitchenHistoryView on _KitchenScreenState {
  Widget _kitchenHistory() {
    final today = limaBusinessDay(DateTime.now());
    final history =
        store.orders.where((order) {
          final lines = store.kitchenLines(order);
          return lines.isNotEmpty &&
              inBusinessRange(order.createdAt, historyRange) &&
              (limaBusinessDay(order.createdAt) != today ||
                  order.status == OrderStatus.cancelled ||
                  orderLineStage(lines) == OrderStatus.delivered);
        }).toList()..sort(
          (first, second) => second.createdAt.compareTo(first.createdAt),
        );
    final groupedHistory = <DateTime, List<RestaurantOrder>>{};
    for (final order in history) {
      groupedHistory
          .putIfAbsent(limaBusinessDay(order.createdAt), () => [])
          .add(order);
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SectionTitle(
          title: 'Historial de cocina',
          subtitle: 'Comandas de dÃ­as anteriores y comandas finalizadas',
        ),
        HistoryDateFilter(
          value: historyRange,
          onChanged: (value) => _setState(() => historyRange = value),
        ),
        const SizedBox(height: 12),
        if (history.isEmpty)
          const EmptyState(message: 'TodavÃ­a no hay comandas cerradas.')
        else
          for (final entry in groupedHistory.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 8),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_outlined, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    '${shortDate(entry.key)}/${entry.key.year}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(child: Divider()),
                ],
              ),
            ),
            for (final order in entry.value)
              Card(
                child: ResponsiveListTile(
                  leading: const Icon(Icons.done_all),
                  title: Text('${order.locationLabel} Â· #${order.id}'),
                  subtitle: Text(
                    store
                        .kitchenLines(order)
                        .map((line) => '${line.quantity}Ã— ${line.name}')
                        .join(', '),
                  ),
                  trailing: order.pendingSync
                      ? const StatusBadge(
                          label: 'Sin sincronizar',
                          color: luxuryGold,
                        )
                      : StatusBadge.order(order.status),
                ),
              ),
          ],
      ],
    );
  }
}
