part of '../cashier_screen.dart';

extension _CashierReceiptsView on _CashierScreenState {
  Widget _receipts() {
    final receipts = store.receipts.where((receipt) {
      final date = DateTime.tryParse('${receipt['createdAt']}');
      return receiptRange == null ||
          (date != null && inBusinessRange(date, receiptRange));
    }).toList();
    final recordedOrderIds = store.receipts
        .map((receipt) => receipt['orderId'])
        .toSet();
    final paidOrders = store.orders
        .where(
          (order) =>
              order.status == OrderStatus.paid &&
              !recordedOrderIds.contains(order.id) &&
              inBusinessRange(
                order.payments.lastOrNull?.createdAt ?? order.createdAt,
                receiptRange,
              ),
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SectionTitle(
          title: 'Notas de venta',
          subtitle: 'Recibos internos registrados en caja',
        ),
        HistoryDateFilter(
          value: receiptRange,
          presets: true,
          onChanged: (value) => _setState(() => receiptRange = value),
        ),
        const SizedBox(height: 12),
        if (receipts.isEmpty && paidOrders.isEmpty)
          const EmptyState(
            message: 'Todavía no hay notas de venta emitidas.',
            icon: Icons.receipt_long,
          )
        else ...[
          ...receipts.map(
            (receipt) => Card(
              child: ResponsiveListTile(
                leading: const Icon(Icons.receipt_long),
                title: Text(
                  '${receipt['code']} · ${receipt['locationLabel'] ?? 'Mesa ${receipt['tableNumber']}'}',
                ),
                subtitle: Text(
                  'Pedido #${receipt['orderId']} · '
                  '${switch (DateTime.tryParse('${receipt['createdAt']}')) {
                    DateTime date => limaDateTime(date),
                    null => 'Sin fecha',
                  }}',
                ),
                trailing: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      money((receipt['total'] as num).toDouble()),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    IconButton(
                      tooltip: 'Imprimir nota',
                      onPressed: () => _printReceipt(receipt),
                      icon: const Icon(Icons.print_outlined),
                    ),
                    if (receipt['status'] == 'ANULADO')
                      const StatusBadge(label: 'Anulada', color: luxuryRed),
                  ],
                ),
              ),
            ),
          ),
          ...paidOrders.map(
            (order) => Card(
              child: ResponsiveListTile(
                leading: const Icon(Icons.receipt_long),
                title: Text('Nota de venta · Pedido #${order.id}'),
                subtitle: Text(
                  '${order.locationLabel} · ${order.payments.map((payment) => payment.method).toSet().join(', ')}',
                ),
                trailing: Text(
                  money(order.total),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _printReceipt(Map<String, dynamic> receipt) async {
    await _run(() async {
      final order = store.orders
          .where((value) => value.id == receipt['orderId'])
          .firstOrNull;
      if (order == null) {
        throw StateError('No se encontró el pedido de esta nota.');
      }
      await printReceiptPdf(
        order: order,
        code: receipt['code'] as String,
        status: receipt['status'] as String? ?? 'VIGENTE',
        issuedAt: DateTime.tryParse(receipt['createdAt'] as String? ?? ''),
      );
      if (receipt['id'] is int) {
        await store.recordReceiptPrint(receipt['id'] as int);
      }
    });
  }
}
