part of '../cashier_screen.dart';

extension _CashierOutstandingAccountsView on _CashierScreenState {
  Widget _accounts(DateTime businessDay) {
    final showPrevious = _previousAccountsDay == businessDay;
    final search = _accountQuery.trim().toLowerCase();
    final active = store.orders.where((order) {
      if (order.balance <= .001 || order.status == OrderStatus.cancelled) {
        return false;
      }
      final orderDay = limaBusinessDay(order.createdAt);
      final matchesDay = showPrevious
          ? orderDay.isBefore(businessDay)
          : orderDay == businessDay;
      final searchable =
          '${order.locationLabel} ${order.id} ${order.customerName} ${order.customerPhone}'
              .toLowerCase();
      return matchesDay && (search.isEmpty || searchable.contains(search));
    }).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1080
            ? 3
            : constraints.maxWidth >= 700
            ? 2
            : 1;
        const spacing = 14.0;
        final cardWidth =
            (constraints.maxWidth - 40 - (columns - 1) * spacing) / columns;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          children: [
            SectionTitle(
              title: 'Cuentas por cobrar',
              subtitle: 'Abonos, pagos combinados y control del saldo.',
              trailing: StatusBadge(
                label: store.shiftOpen ? 'Turno abierto' : 'Turno cerrado',
                color: store.shiftOpen ? luxuryGreen : luxuryMuted,
              ),
            ),
            TextField(
              key: const ValueKey('cashier-account-search'),
              onChanged: (value) => _setState(() => _accountQuery = value),
              decoration: const InputDecoration(
                hintText: 'Buscar mesa o pedido',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Hoy'),
                  selected: !showPrevious,
                  onSelected: (_) =>
                      _setState(() => _previousAccountsDay = null),
                ),
                ChoiceChip(
                  label: const Text('Pendientes anteriores'),
                  selected: showPrevious,
                  onSelected: (_) =>
                      _setState(() => _previousAccountsDay = businessDay),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (active.isEmpty)
              EmptyState(
                message: showPrevious
                    ? 'No hay cuentas pendientes de días anteriores.'
                    : 'No hay cuentas pendientes que coincidan con la búsqueda.',
                icon: Icons.task_alt,
              )
            else
              Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final (index, order) in active.indexed)
                    SizedBox(
                      key: ValueKey(order.id),
                      width: cardWidth,
                      child: LuxuryReveal(
                        index: index,
                        child: _accountCard(order),
                      ),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }

  Widget _accountCard(RestaurantOrder order) {
    final elapsed = DateTime.now().difference(order.createdAt).inMinutes;
    final isNew =
        order.status == OrderStatus.forPayment &&
        !order.pendingSync &&
        !_reviewedAccounts.contains(order.id);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: AnimatedContainer(
        duration: luxuryDuration(context, 300),
        curve: Curves.easeOutCubic,
        color: isNew
            ? luxuryPaletteRed.withValues(alpha: .065)
            : Colors.transparent,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    order.locationLabel,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${elapsed.clamp(0, 999)} min',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              'Pedido #${order.id}${order.customerName.isEmpty ? '' : ' · ${order.customerName}'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                StatusBadge.order(order.status),
                if (isNew)
                  const StatusBadge(label: 'Cuenta nueva', color: luxuryRed),
                if (order.pendingSync)
                  const StatusBadge(
                    label: 'Pendiente de sincronizar',
                    color: luxuryMuted,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            for (final line in order.lines.take(4))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${line.quantity} × ${line.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            if (order.lines.length > 4)
              Text('+ ${order.lines.length - 4} productos más'),
            const Divider(height: 20),
            _accountTotal(order.total),
            const SizedBox(height: 12),
            if (order.pendingSync)
              const Text('El cobro estará disponible al sincronizar el pedido.')
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _collect(order),
                  icon: const Icon(Icons.point_of_sale),
                  label: Text(
                    order.paid > 0 ? 'Registrar abono' : 'Registrar pago',
                  ),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _printPreAccount(order),
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: const Text('Imprimir precuenta'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _accountTotal(double amount) => Row(
    children: [
      const Expanded(
        child: Text(
          'Total',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
      Text(
        money(amount),
        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
      ),
    ],
  );
  Future<void> _printPreAccount(RestaurantOrder order) async {
    await _run(() => printPreAccountPdf(order: order));
  }
}
