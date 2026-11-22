part of '../cashier_screen.dart';

extension _CashierActivityView on _CashierScreenState {
  Widget _activity() {
    final recent =
        store.orders
            .where(
              (order) =>
                  inBusinessRange(order.createdAt, activityRange) ||
                  order.payments.any(
                    (payment) =>
                        inBusinessRange(payment.createdAt, activityRange),
                  ),
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SectionTitle(
          title: 'Actividad de caja',
          subtitle: 'Pedidos y pagos recientes',
        ),
        HistoryDateFilter(
          value: activityRange,
          presets: true,
          onChanged: (value) => _setState(() => activityRange = value),
        ),
        const SizedBox(height: 12),
        if (recent.isEmpty)
          const EmptyState(message: 'No hay actividad registrada.')
        else
          ...recent.map(
            (order) => Card(
              child: ResponsiveListTile(
                leading: Icon(
                  order.status == OrderStatus.paid
                      ? Icons.check_circle_outline
                      : Icons.receipt_long,
                  color: order.status == OrderStatus.paid
                      ? luxuryGreen
                      : luxuryBrown,
                ),
                title: Text('Pedido #${order.id} · ${order.locationLabel}'),
                subtitle: Text(
                  order.payments.isEmpty
                      ? '${limaDateTime(order.createdAt)} · Sin pagos registrados'
                      : order.payments
                            .map(
                              (payment) =>
                                  '${payment.method} ${money(payment.amount)}',
                            )
                            .join(' + '),
                ),
                trailing: Text(
                  money(order.paid),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
