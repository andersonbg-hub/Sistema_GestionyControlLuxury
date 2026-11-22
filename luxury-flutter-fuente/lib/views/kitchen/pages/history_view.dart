part of '../kitchen_screen.dart';

extension _KitchenHistoryView on _KitchenScreenState {
  Widget _kitchenHistory() {
    final today = limaBusinessDay(DateTime.now());
    final history = store.orders.where((order) {
      final lines = store.kitchenLines(order);
      return lines.isNotEmpty &&
          inBusinessRange(order.createdAt, historyRange) &&
          (limaBusinessDay(order.createdAt) != today ||
              order.status == OrderStatus.cancelled ||
              orderLineStage(lines) == OrderStatus.delivered);
    }).toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SectionTitle(
          title: 'Historial de cocina',
          subtitle: 'Comandas de días anteriores y comandas finalizadas',
        ),
        HistoryDateFilter(
          value: historyRange,
          onChanged: (value) => _setState(() => historyRange = value),
        ),
        const SizedBox(height: 12),
        if (history.isEmpty)
          const EmptyState(message: 'Todavía no hay comandas cerradas.')
        else
          ...history.map(
            (order) => Card(
              child: ResponsiveListTile(
                leading: const Icon(Icons.done_all),
                title: Text('${order.locationLabel} · #${order.id}'),
                subtitle: Text(
                  store
                      .kitchenLines(order)
                      .map((line) => '${line.quantity}× ${line.name}')
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
          ),
      ],
    );
  }
}
