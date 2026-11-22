part of '../dashboard_screen.dart';

extension _AdminCashManagementView on _AdminScreenState {
  Future<void> _consultCashierShift(String cashierId) => _run(() async {
    final shift = store.cashierShift(cashierId);
    _setState(() {
      _cashierId = cashierId;
      _cashierShift = shift;
    });
    await shift;
  }, label: 'Consultando turno…');

  Widget _cashAdministration() {
    final cashiers = store.staff
        .where((member) => member.active && member.role == StaffRole.cashier)
        .toList();
    final cashier = cashiers
        .where((member) => member.id == _cashierId)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          title: 'Control de caja',
          subtitle: 'Apertura y cierre de turnos de los cajeros',
          trailing: cashier == null
              ? null
              : IconButton(
                  tooltip: 'Actualizar turno',
                  onPressed: _changingCashierShift
                      ? null
                      : () => _consultCashierShift(cashier.id),
                  icon: const Icon(Icons.refresh),
                ),
        ),
        if (cashiers.isEmpty)
          const EmptyState(
            message: 'No hay cajeros activos.',
            icon: Icons.point_of_sale,
          )
        else
          DropdownButtonFormField<String>(
            key: ValueKey(cashier?.id),
            initialValue: cashier?.id,
            decoration: const InputDecoration(labelText: 'Cajero'),
            isExpanded: true,
            items: [
              for (final member in cashiers)
                DropdownMenuItem(
                  value: member.id,
                  child: Text(member.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: _changingCashierShift
                ? null
                : (id) {
                    if (id != null) _consultCashierShift(id);
                  },
          ),
        if (cashier != null) ...[
          const SizedBox(height: 12),
          FutureBuilder<CashierShift>(
            future: _cashierShift,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LinearProgressIndicator();
              }
              final shift = snapshot.data;
              if (shift == null) {
                return OutlinedButton.icon(
                  onPressed: () => _consultCashierShift(cashier.id),
                  icon: const Icon(Icons.refresh),
                  label: const Text(
                    'No se pudo consultar el turno. Reintentar',
                  ),
                );
              }
              final openedAt = shift.openedAt;
              final previousOpen =
                  shift.open &&
                  openedAt != null &&
                  !isSameLimaBusinessDay(openedAt, DateTime.now());
              final openToday = shift.open && !previousOpen;
              final receipts = store.shiftReceipts(shift, cashier.id);
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StatusBadge(
                        label: previousOpen
                            ? 'Caja de hoy sin abrir'
                            : openToday
                            ? 'Turno abierto'
                            : 'Turno cerrado',
                        color: openToday ? luxuryGreen : luxuryRed,
                      ),
                      ResponsiveListTile(
                        title: const Text('Monto de apertura'),
                        trailing: Text(money(shift.openingCash)),
                      ),
                      if (shift.id != null) ...[
                        ResponsiveListTile(
                          title: Text(
                            previousOpen
                                ? 'Efectivo recaudado en el turno anterior'
                                : 'Efectivo recaudado',
                          ),
                          trailing: Text(money(receipts.cash)),
                        ),
                        ResponsiveListTile(
                          title: const Text('Total recaudado en el turno'),
                          trailing: Text(money(receipts.total)),
                        ),
                      ],
                      FilledButton.icon(
                        onPressed: _changingCashierShift
                            ? null
                            : () => _changeCashierShift(
                                cashier,
                                shift,
                                open: !openToday,
                                previousOpen: previousOpen,
                              ),
                        icon: Icon(
                          openToday ? Icons.lock_outline : Icons.lock_open,
                        ),
                        label: Text(openToday ? 'Cerrar caja' : 'Abrir caja'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  Future<void> _changeCashierShift(
    StaffMember cashier,
    CashierShift shift, {
    required bool open,
    required bool previousOpen,
  }) async {
    final title = open ? 'Abrir caja' : 'Cerrar caja';
    final confirmed = await confirmAction(
      context,
      title: '$title · ${cashier.name}',
      message: previousOpen
          ? 'Se cerrará el turno anterior con los cobros registrados y se abrirá la caja de hoy.'
          : open
          ? 'La caja empezará en S/ 0.00 y acumulará los pagos de los pedidos.'
          : 'El cierre se calculará con el efectivo de los pagos registrados en este turno.',
      actionLabel: 'Confirmar',
    );
    if (!confirmed || !mounted) return;
    _setState(() => _changingCashierShift = true);
    try {
      await _run(() async {
        await store.setShiftOpen(
          open,
          cashierId: cashier.id,
          shiftId: shift.id,
        );
        if (!mounted) return;
        final updatedShift = store.cashierShift(cashier.id);
        _setState(() {
          _cashierShift = updatedShift;
        });
        await updatedShift;
      }, label: open ? 'Abriendo turno…' : 'Cerrando turno…');
    } finally {
      if (mounted) _setState(() => _changingCashierShift = false);
    }
  }
}
