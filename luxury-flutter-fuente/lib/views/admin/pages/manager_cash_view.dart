part of '../dashboard_screen.dart';

extension _AdminManagerCashView on _AdminScreenState {
  void _selectManagerCashier(String cashierId) {
    _setState(() {
      _cashierId = cashierId;
      _cashierShift = store.cashierShiftForManager(cashierId);
    });
  }

  Widget _managerCashPage() {
    final cashiers = store.staff
        .where((member) => member.active && member.role == StaffRole.cashier)
        .toList();
    final selectedCashier = cashiers
        .where((member) => member.id == _cashierId)
        .firstOrNull;
    final businessDay = limaBusinessDay(DateTime.now());
    final todayPayments = [
      for (final order in store.orders)
        for (final payment in order.payments)
          if (limaBusinessDay(payment.createdAt) == businessDay)
            (order: order, payment: payment),
    ]..sort((a, b) => b.payment.createdAt.compareTo(a.payment.createdAt));
    final byMethod = <String, double>{};
    for (final row in todayPayments) {
      byMethod.update(
        row.payment.method,
        (amount) => amount + row.payment.amount,
        ifAbsent: () => row.payment.amount,
      );
    }
    final cashCollected = byMethod['Efectivo'] ?? 0;
    final otherCollected = byMethod.entries
        .where((entry) => entry.key != 'Efectivo')
        .fold<double>(0, (sum, entry) => sum + entry.value);
    final totalCollected = cashCollected + otherCollected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          title: 'Caja y cierres',
          subtitle: 'Supervisa el efectivo y consulta los cierres por turno',
          trailing: const StatusBadge(
            label: 'Consulta de gerencia',
            color: Color(0xFF3978A8),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                '${businessDay.day} ${_managerMonth(businessDay.month)} ${businessDay.year}',
              ),
            ),
            if (selectedCashier != null)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: DropdownButtonFormField<String>(
                  key: ValueKey('manager-cashier-${selectedCashier.id}'),
                  initialValue: selectedCashier.id,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.point_of_sale_outlined),
                    isDense: true,
                  ),
                  items: [
                    for (final cashier in cashiers)
                      DropdownMenuItem(
                        value: cashier.id,
                        child: Text(
                          cashier.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) _selectManagerCashier(value);
                  },
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        StatGrid(
          children: [
            StatCard(
              label: 'Cobros del local',
              value: money(totalCollected),
              icon: Icons.account_balance_wallet_outlined,
              color: luxuryGreen,
            ),
            StatCard(
              label: 'Efectivo registrado',
              value: money(cashCollected),
              icon: Icons.payments_outlined,
              color: const Color(0xFF3389C9),
            ),
            StatCard(
              label: 'Otros medios',
              value: money(otherCollected),
              icon: Icons.credit_card_outlined,
              color: const Color(0xFF7852C7),
            ),
            StatCard(
              label: 'Pagos registrados',
              value: '${todayPayments.length}',
              icon: Icons.receipt_long_outlined,
              color: luxuryGold,
            ),
          ],
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 800;
            final reconciliation = _managerCashReconciliation(selectedCashier);
            final methods = _managerCashMethods(byMethod, totalCollected);
            return narrow
                ? Column(
                    children: [
                      reconciliation,
                      const SizedBox(height: 14),
                      methods,
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: reconciliation),
                      const SizedBox(width: 14),
                      Expanded(flex: 2, child: methods),
                    ],
                  );
          },
        ),
        const SizedBox(height: 14),
        _managerCashMovements(todayPayments),
      ],
    );
  }

  Widget _managerCashReconciliation(StaffMember? cashier) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Conciliación de efectivo',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (cashier == null)
            const EmptyState(
              message: 'No hay cajeros activos para consultar.',
              icon: Icons.point_of_sale_outlined,
            )
          else ...[
            const SizedBox(height: 8),
            Text('Responsable · ${cashier.name}'),
            FutureBuilder<CashierShift>(
              future: _cashierShift,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: LinearProgressIndicator(),
                  );
                }
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: ErrorBanner(message: '${snapshot.error}'),
                  );
                }
                final shift = snapshot.data;
                if (shift == null || shift.id == null && !shift.open) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: EmptyState(
                      message: 'No hay un cierre registrado para este turno.',
                      icon: Icons.event_busy_outlined,
                    ),
                  );
                }
                return Column(
                  children: [
                    const Divider(height: 24),
                    ResponsiveListTile(
                      title: const Text('Estado del turno'),
                      trailing: StatusBadge(
                        label: shift.open ? 'Abierto' : 'Cerrado',
                        color: shift.open ? luxuryGold : luxuryGreen,
                      ),
                    ),
                    ResponsiveListTile(
                      title: const Text('Fondo inicial'),
                      trailing: Text(money(shift.openingCash)),
                    ),
                    if (shift.openedAt != null)
                      ResponsiveListTile(
                        title: const Text('Inicio del turno'),
                        trailing: Text(limaDateTime(shift.openedAt!)),
                      ),
                    if (!shift.open)
                      ResponsiveListTile(
                        title: const Text('Efectivo contado al cierre'),
                        trailing: Text(money(shift.closingCash)),
                      ),
                    const SizedBox(height: 8),
                    const Text(
                      'El detalle de cobros del local se muestra por método en el panel contiguo.',
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    ),
  );

  Widget _managerCashMethods(Map<String, double> byMethod, double total) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cobros por método',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (byMethod.isEmpty)
                const EmptyState(
                  message: 'Todavía no hay pagos registrados hoy.',
                  icon: Icons.payments_outlined,
                )
              else
                for (final method in byMethod.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        Expanded(child: Text(method.key)),
                        SizedBox(
                          width: 100,
                          child: LinearProgressIndicator(
                            value: total <= 0 ? 0 : method.value / total,
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(money(method.value)),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      );

  Widget _managerCashMovements(
    List<({RestaurantOrder order, PaymentEntry payment})> payments,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cobros registrados hoy',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          if (payments.isEmpty)
            const EmptyState(message: 'No hay movimientos del día.')
          else
            for (final row in payments.take(8))
              ResponsiveListTile(
                dense: true,
                leading: Icon(
                  row.payment.method == 'Efectivo'
                      ? Icons.payments_outlined
                      : Icons.credit_card_outlined,
                ),
                title: Text(
                  '${row.order.locationLabel} · Pedido #${row.order.id}',
                ),
                subtitle: Text(
                  '${row.payment.method} · ${limaDateTime(row.payment.createdAt)}',
                ),
                trailing: Text(
                  money(row.payment.amount),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
        ],
      ),
    ),
  );

  String _managerMonth(int month) => const [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ][month - 1];
}
