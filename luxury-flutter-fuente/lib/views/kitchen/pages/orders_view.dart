part of '../kitchen_screen.dart';

extension _KitchenOrdersView on _KitchenScreenState {
  Future<void> _advanceKitchenOrder(
    RestaurantOrder order,
    OrderStatus stage,
  ) async {
    await _run(
      () => store.advanceOrder(order, forStage: stage),
      label: switch (stage) {
        OrderStatus.pending => 'Iniciando preparación…',
        OrderStatus.preparing => 'Marcando pedido listo…',
        _ => 'Registrando entrega…',
      },
    );
  }

  Future<void> _reportIncident(RestaurantOrder order) async {
    final (reportedDish, originalReason) = order.kitchenIncident;
    final formKey = GlobalKey<FormState>();
    var reason = originalReason;
    final lines = store.kitchenLines(order);
    var dish = lines.where((line) => line.name == reportedDish).firstOrNull;
    if (dish == null && lines.length == 1) dish = lines.single;

    final report = await showLuxuryDialog<(OrderLine?, String)>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text('Incidencia · Pedido #${order.id}'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (lines.isNotEmpty) ...[
                  DropdownButtonFormField<OrderLine>(
                    key: const ValueKey('incident-dish'),
                    initialValue: dish,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Platillo afectado',
                    ),
                    items: [
                      for (final line in lines)
                        DropdownMenuItem(
                          value: line,
                          child: Text(
                            '${line.quantity} × ${line.name}${line.note.isEmpty ? '' : ' · ${line.note}'}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) => dish = value,
                    validator: (value) => value == null
                        ? 'Selecciona el platillo afectado.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  key: const ValueKey('incident-reason'),
                  initialValue: reason,
                  onChanged: (value) => reason = value,
                  validator: (value) => (value?.trim().length ?? 0) < 5
                      ? 'Describe la incidencia con al menos cinco caracteres.'
                      : null,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 240,
                  decoration: const InputDecoration(
                    labelText: 'Motivo',
                    hintText: 'Describe el problema para administración y caja',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, (dish, reason.trim()));
              }
            },
            child: const Text('Registrar incidencia'),
          ),
        ],
      ),
    );
    if (report != null && mounted) {
      await _run(
        () => store.reportKitchenIncident(order, report.$2, dish: report.$1),
      );
    }
  }
}
