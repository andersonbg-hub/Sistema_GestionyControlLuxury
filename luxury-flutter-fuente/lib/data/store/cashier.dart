part of '../restaurant_store.dart';

extension RestaurantStoreCashier on RestaurantStore {
  void _requireCashAdministration() {
    if (role != StaffRole.administrator) {
      throw StateError('Solo Administración puede abrir o cerrar turnos.');
    }
  }

  Future<PostgrestList> _cashierShiftRows(
    SupabaseClient client,
    String cashierId,
  ) => client
      .from('turnos_caja')
      .select('id, abierto_en, cerrado_en, monto_apertura, monto_cierre')
      .eq('cajero_id', cashierId)
      .order('cerrado_en', ascending: false, nullsFirst: true)
      .order('abierto_en', ascending: false)
      .order('id', ascending: false)
      .limit(1);

  Future<CashierShift> _readCashierShift(
    SupabaseClient client,
    String cashierId,
  ) async =>
      _shiftFromRow((await _cashierShiftRows(client, cashierId)).firstOrNull);

  CashierShift _shiftFromRow(Map<String, dynamic>? row) {
    if (row == null) return _noCashierShift;
    return (
      id: row['id'] as int,
      openedAt: DateTime.tryParse(row['abierto_en'] as String? ?? ''),
      closedAt: DateTime.tryParse(row['cerrado_en'] as String? ?? ''),
      open: row['cerrado_en'] == null,
      openingCash: (row['monto_apertura'] as num?)?.toDouble() ?? 0,
      closingCash: (row['monto_cierre'] as num?)?.toDouble() ?? 0,
    );
  }

  Future<CashierShift> cashierShift(String cashierId) async {
    _requireCashAdministration();
    final shift = _client == null
        ? _shift
        : await _readCashierShift(_client, cashierId);
    return shift.open || _shiftIsToday(shift) ? shift : _noCashierShift;
  }

  Future<CashierShift> cashierShiftForManager(String cashierId) async {
    if (role != StaffRole.manager) {
      throw StateError('Solo Gerencia puede consultar cierres de caja.');
    }
    final shift = _client == null
        ? _shift
        : await _readCashierShift(_client, cashierId);
    return shift.open || _shiftIsToday(shift) ? shift : _noCashierShift;
  }

  Future<void> setShiftOpen(
    bool open, {
    required String cashierId,
    int? shiftId,
  }) async {
    _requireCashAdministration();
    final client = _client;
    if (client != null) {
      final current = await _readCashierShift(client, cashierId);
      if (!open && (!current.open || current.id != shiftId)) {
        throw StateError('El turno cambió. Actualiza antes de cerrar la caja.');
      }
      final countedCash = open
          ? 0.0
          : (shiftReceipts(current, cashierId).cash * 100).round() / 100;
      await client.rpc(
        'administrar_turno_caja',
        params: {
          'p_cajero_id': cashierId,
          'p_abrir': open,
          'p_monto': countedCash,
          'p_turno_id': shiftId,
        },
      );
      if (open) {
        final confirmed = await _readCashierShift(client, cashierId);
        if (confirmed.open && _shiftIsToday(confirmed)) return;
        if (confirmed.open) {
          throw StateError(
            'Sigue abierto un turno de otro día. Aplica la migración 20261122200000 de turnos de caja en Supabase y vuelve a intentar.',
          );
        }
        throw StateError(
          'Supabase no confirmó un turno abierto para hoy. Actualiza el turno y verifica la función y los permisos de lectura de Administración.',
        );
      }
      return;
    }

    if (open ? shiftOpen : !_shift.open) return;
    final closedAt = _now();
    _shift = open
        ? _newDemoShift()
        : (
            id: _shift.id,
            openedAt: _shift.openedAt,
            closedAt: closedAt,
            open: false,
            openingCash: _shift.openingCash,
            closingCash: shiftReceipts(_shift, cashierId).cash,
          );
    await _persist();
    _recordLocalAudit(
      open ? 'Abrir turno de caja' : 'Cerrar turno de caja',
      'turnos_caja',
      cashierId,
    );
    _publish();
  }

  ({double cash, double total}) shiftReceipts(
    CashierShift shift,
    String cashierId,
  ) {
    final start = shift.openedAt;
    final end = shift.closedAt;
    var cash = 0.0;
    var total = 0.0;
    if (start == null) return (cash: cash, total: total);
    for (final payment in orders.expand((order) => order.payments)) {
      if (!isDemo && payment.cashierId != cashierId) continue;
      if (payment.shiftId != null) {
        if (payment.shiftId != shift.id) continue;
      } else if (payment.createdAt.isBefore(start) ||
          (end != null && payment.createdAt.isAfter(end))) {
        continue;
      }
      total += payment.amount;
      if (payment.method == 'Efectivo') cash += payment.amount;
    }
    return (cash: cash, total: total);
  }

  Iterable<PaymentEntry> cashierPaymentsForDay(DateTime businessDay) => orders
      .expand((order) => order.payments)
      .where(
        (payment) =>
            (isDemo || payment.cashierId == userId) &&
            limaBusinessDay(payment.createdAt) == businessDay,
      );

  Future<void> setOrderForPayment(RestaurantOrder order) async {
    final index = orders.indexWhere((item) => item.id == order.id);
    if (index < 0) throw StateError('No se encontró el pedido.');
    final current = orders[index];
    if (current.pendingSync || _hasPendingConsumption(current)) {
      throw StateError('Sincroniza el pedido antes de solicitar la cuenta.');
    }
    if (current.status == OrderStatus.forPayment) return;
    if (current.retirementConfirmed ||
        current.status == OrderStatus.cancelled ||
        current.status == OrderStatus.paid ||
        current.balance <= .001) {
      throw StateError('El pedido ya no tiene un saldo pendiente.');
    }
    if (_client != null) {
      await _client.rpc('solicitar_cuenta', params: {'p_pedido_id': order.id});
      await _loadRemoteData();
    } else {
      orders[index] = current.copyWith(status: OrderStatus.forPayment);
      _recalculateTable(order.tableId);
      await _persist();
    }
    _recordLocalAudit('Solicitar cuenta', 'pedidos', order.id.toString());
    _publish();
  }
}
