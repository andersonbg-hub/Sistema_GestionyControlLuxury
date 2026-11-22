part of '../restaurant_store.dart';

extension RestaurantStoreTableGroups on RestaurantStore {
  bool get supportsTableGroups => isDemo || _remoteSupportsTableGroups;

  RestaurantTable? _tableById(int? id) =>
      tables.where((table) => table.id == id).firstOrNull;

  RestaurantOrder? tableGroupFor(RestaurantTable table) {
    final groupId = _tableById(table.id)?.groupOrderId;
    if (groupId == null) return null;
    return orders
        .where(
          (order) =>
              order.id == groupId &&
              order.hasJoinedTables &&
              !order.retirementConfirmed &&
              order.parentOrderId == null &&
              order.groupTableIds.contains(table.id),
        )
        .firstOrNull;
  }

  RestaurantTable serviceTableFor(RestaurantTable table) =>
      _tableById(tableGroupFor(table)?.tableId) ??
      _tableById(table.id) ??
      table;

  String tableLocationLabel(RestaurantTable table) =>
      tableGroupFor(table)?.locationLabel ??
      'Mesa ${serviceTableFor(table).number}';

  int tableServiceCapacity(RestaurantTable table) {
    final group = tableGroupFor(table);
    if (group == null) return serviceTableFor(table).capacity;
    return tables
        .where((entry) => group.groupTableIds.contains(entry.id))
        .fold(0, (capacity, entry) => capacity + entry.capacity);
  }

  bool _hasOpenOrderAtTable(int tableId) => orders.any(
    (order) =>
        !order.retirementConfirmed &&
        (order.tableId == tableId || order.groupTableIds.contains(tableId)),
  );

  bool canJoinTable(RestaurantTable table) {
    final current = _tableById(table.id);
    return supportsTableGroups &&
        current != null &&
        current.active &&
        current.groupOrderId == null &&
        current.status == TableStatus.available &&
        !_hasOpenOrderAtTable(current.id);
  }

  List<RestaurantTable> _availableJoinedTables(
    RestaurantTable? selectedTable,
    List<RestaurantTable> joinedTables,
  ) {
    final ids = joinedTables.map((table) => table.id).toSet();
    if (ids.length < 2 ||
        ids.length != joinedTables.length ||
        !ids.contains(selectedTable?.id)) {
      throw StateError('Selecciona al menos dos mesas libres distintas.');
    }
    final selected = tables.where((table) => ids.contains(table.id)).toList()
      ..sort((a, b) {
        final byNumber = a.number.compareTo(b.number);
        return byNumber == 0 ? a.id.compareTo(b.id) : byNumber;
      });
    if (selected.length != ids.length || !selected.every(canJoinTable)) {
      throw StateError('Alguna de las mesas seleccionadas ya no está libre.');
    }
    return selected;
  }

  bool _canManageJoinedOrder(RestaurantOrder order) =>
      isDemo ||
      role == StaffRole.administrator ||
      (userId != null && order.waiterId == userId);

  bool _groupBillingStarted(RestaurantOrder group) =>
      group.status == OrderStatus.forPayment ||
      group.status == OrderStatus.paid ||
      group.payments.isNotEmpty;

  void _setJoinedTableStatuses(RestaurantOrder group) {
    final status = group.retirementConfirmed
        ? TableStatus.available
        : _groupBillingStarted(group)
        ? TableStatus.payment
        : TableStatus.occupied;
    for (var i = 0; i < tables.length; i++) {
      final table = tables[i];
      if (!group.groupTableIds.contains(table.id)) continue;
      if (table.groupOrderId != null && table.groupOrderId != group.id) {
        continue;
      }
      tables[i] = table.copyWith(
        status: status,
        groupOrderId: group.id,
        clearGroup: group.retirementConfirmed,
      );
    }
  }

  void _showPendingOrderQueue(Iterable<RestaurantOrder> queue) {
    orders.addAll(queue);
    queue.forEach(_showPendingJoinedTableMembership);
  }

  void _showPendingJoinedTableMembership(RestaurantOrder order) {
    if (!order.hasJoinedTables || order.parentOrderId != null) return;
    final members = tables.where(
      (table) => order.groupTableIds.contains(table.id),
    );
    if (members.length == order.groupTableIds.length &&
        members.every(
          (table) =>
              table.active &&
              (table.groupOrderId == order.id ||
                  (table.groupOrderId == null &&
                      table.status == TableStatus.available)),
        )) {
      _setJoinedTableStatuses(order);
    }
  }

  Future<dynamic> _sendJoinedTableOrder(
    SupabaseClient client, {
    required String requestId,
    required List<int> tableIds,
    required int diners,
    required int? parentOrderId,
    required List<OrderLine> lines,
  }) async {
    if (parentOrderId != null) {
      return _sendAccountConsumption(
        client,
        requestId: requestId,
        accountId: parentOrderId,
        lines: lines,
      );
    }
    return client.rpc(
      'crear_pedido_mesas_unidas',
      params: {
        'p_solicitud_id': requestId,
        'p_mesas_ids': tableIds,
        'p_comensales': diners,
        'p_items': _itemsToJson(lines),
      },
    );
  }

  Future<void> _createJoinedTableOrder({
    required RestaurantTable table,
    required List<RestaurantTable> joinedTables,
    required RestaurantOrder? existingGroup,
    required int? parentOrderId,
    required int diners,
    required List<OrderLine> lines,
  }) async {
    if (!supportsTableGroups) {
      throw StateError('La unión de mesas requiere actualizar Supabase.');
    }

    if (joinedTables.isEmpty) {
      if (existingGroup == null || existingGroup.id != parentOrderId) {
        throw StateError('Selecciona una cuenta abierta de las mesas unidas.');
      }
      await _addConsumptionToAccount(
        table: table,
        account: existingGroup,
        diners: diners,
        lines: lines,
      );
      return;
    }

    if (parentOrderId != null) {
      throw StateError('Inicia un pedido nuevo para unir las mesas.');
    }
    final selected = _availableJoinedTables(table, joinedTables);
    final capacity = selected.fold(0, (total, entry) => total + entry.capacity);
    if (diners < 1 || diners > capacity) {
      throw StateError(
        'Los comensales deben estar entre 1 y la capacidad de las mesas unidas.',
      );
    }
    final primary = selected.first;
    final tableIds = List<int>.unmodifiable(selected.map((entry) => entry.id));
    final tableNumbers = List<int>.unmodifiable(
      selected.map((entry) => entry.number),
    );
    if (lines.any((line) => line.quantity < 1)) {
      throw StateError('La cantidad de cada producto debe ser mayor que cero.');
    }

    final client = _client;
    final version = _sessionVersion;
    final int orderId;
    if (client != null) {
      final requestId = _newRequestId();
      dynamic result;
      try {
        result = await _sendJoinedTableOrder(
          client,
          requestId: requestId,
          tableIds: tableIds,
          diners: diners,
          parentOrderId: parentOrderId,
          lines: lines,
        );
      } catch (error) {
        if (error is PostgrestException && error.code == 'PT409') {
          await _refreshAfterWrite(version);
          if (version == _sessionVersion) _publish();
          rethrow;
        }
        if (!_connectionInterrupted(error)) rethrow;
        if (version != _sessionVersion) return;
        await _queueOfflineOrder(
          requestId: requestId,
          table: primary,
          diners: diners,
          lines: lines,
          parentOrderId: parentOrderId,
          fulfillmentType: FulfillmentType.dineIn,
          customerName: '',
          customerPhone: '',
          deliveryAddress: '',
          groupTableIds: tableIds,
          groupTableNumbers: tableNumbers,
        );
        _scheduleOrderRetry(version);
        return;
      }

      final confirmed = int.tryParse('$result');
      if (confirmed == null) {
        throw StateError('Supabase no confirmó el pedido de las mesas unidas.');
      }
      orderId = confirmed;
      final refreshed = await _refreshAfterWrite(version);
      if (version != _sessionVersion) return;
      if (refreshed) {
        _publish();
        return;
      }
    } else {
      orderId = _nextId++;
    }

    final order = RestaurantOrder(
      id: orderId,
      tableId: primary.id,
      tableNumber: primary.number,
      createdAt: _now(),
      diners: diners,
      lines: List.unmodifiable(_newGroupedLines(lines)),
      waiterId: userId,
      waiterName: displayName,
      groupTableIds: tableIds,
      groupTableNumbers: tableNumbers,
    );
    orders.insert(0, order);
    _setJoinedTableStatuses(order);
    if (isDemo) {
      await _persist();
    } else {
      await _saveRemoteCache();
    }
    _recordLocalAudit(
      'Crear pedido en mesas unidas',
      'pedidos',
      orderId.toString(),
    );
    _publish();
  }

  Future<void> _releaseJoinedTables(RestaurantOrder group) async {
    if (!_canManageJoinedOrder(group) ||
        group.pendingSync ||
        pendingOrders.any((order) => order.parentOrderId == group.id)) {
      throw StateError('Confirma el acceso y la sincronización del pedido.');
    }
    if (group.status != OrderStatus.cancelled &&
        (group.status != OrderStatus.paid ||
            kitchenStage(group) != OrderStatus.delivered)) {
      throw StateError(
        'Completa la entrega y el cobro antes de liberar las mesas unidas.',
      );
    }

    final client = _client;
    if (client != null) {
      final version = _sessionVersion;
      await client.rpc(
        'confirmar_retiro_mesas_unidas',
        params: {'p_pedido_id': group.id},
      );
      if (version != _sessionVersion) return;
      await _refreshAfterWrite(version);
      if (version != _sessionVersion) return;
    } else {
      final index = orders.indexWhere((order) => order.id == group.id);
      final released = group.copyWith(retirementConfirmed: true);
      orders[index] = released;
      _setJoinedTableStatuses(released);
      await _persist();
    }
    _recordLocalAudit(
      'Confirmar retiro de mesas unidas',
      'pedidos',
      group.id.toString(),
    );
    _publish();
  }

  List<OrderLine> _newGroupedLines(List<OrderLine> lines) => [
    for (final line in lines)
      line.copyWith(
        status: OrderStatus.pending,
        waiterService: isDemo ? isWaiterService(line) : line.waiterService,
      ),
  ];
}
