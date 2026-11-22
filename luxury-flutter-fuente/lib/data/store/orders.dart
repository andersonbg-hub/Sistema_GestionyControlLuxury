part of '../restaurant_store.dart';

extension RestaurantStoreOrders on RestaurantStore {
  bool isWaiterService(OrderLine line) =>
      line.waiterService ??
      (isDemo &&
          menu.any(
            (dish) => dish.id == line.menuItemId && dish.servedByWaiter,
          ));

  List<OrderLine> kitchenLines(RestaurantOrder order) => order.lines
      .where((line) => !isWaiterService(line))
      .toList(growable: false);

  bool _awaitsWaiterService(OrderLine line) =>
      isWaiterService(line) &&
      (line.status == OrderStatus.pending ||
          line.status == OrderStatus.preparing ||
          line.status == OrderStatus.ready);

  bool canConfirmWaiterService(RestaurantOrder order) =>
      !order.pendingSync &&
      !order.retirementConfirmed &&
      order.status != OrderStatus.cancelled &&
      order.lines.any(_awaitsWaiterService);

  bool tableBillingStarted(RestaurantTable table) {
    final current = _tableById(table.id) ?? table;
    final group = tableGroupFor(current);
    if (group != null) {
      return current.status == TableStatus.payment ||
          _groupBillingStarted(group);
    }
    return current.status == TableStatus.payment ||
        orders.any(
          (order) =>
              order.tableId == table.id &&
              !order.retirementConfirmed &&
              order.status != OrderStatus.cancelled &&
              (order.status == OrderStatus.forPayment ||
                  order.status == OrderStatus.paid ||
                  order.payments.isNotEmpty),
        );
  }

  bool _canLinkAdditionalOrder(RestaurantOrder order, int tableId) =>
      order.tableId == tableId &&
      order.fulfillmentType == FulfillmentType.dineIn &&
      _canManageJoinedOrder(order) &&
      !order.retirementConfirmed &&
      !order.pendingSync &&
      !_hasPendingConsumption(order) &&
      order.payments.isEmpty &&
      order.status != OrderStatus.cancelled &&
      order.status != OrderStatus.forPayment &&
      order.status != OrderStatus.paid;

  bool _hasPendingConsumption(RestaurantOrder order) => pendingOrders.any(
    (pending) =>
        pending.parentOrderId == order.id ||
        (pending.appendsToAccount &&
            order.tableId != null &&
            pending.tableId == order.tableId),
  );

  RestaurantOrder? additionalOrderParent(RestaurantTable table) {
    final group = tableGroupFor(table);
    if (group != null) {
      return _canLinkAdditionalOrder(group, group.tableId!) ? group : null;
    }
    final openOrders = orders.where(
      (order) => _canLinkAdditionalOrder(order, table.id),
    );
    return openOrders
            .where((order) => order.parentOrderId == null)
            .firstOrNull ??
        openOrders.firstOrNull;
  }

  bool canOrderAtTable(RestaurantTable table) {
    final current = tables.where((entry) => entry.id == table.id).firstOrNull;
    if (current == null || !current.active || tableBillingStarted(current)) {
      return false;
    }
    return additionalOrderParent(current) != null ||
        (current.groupOrderId == null &&
            current.status == TableStatus.available &&
            !_hasOpenOrderAtTable(current.id));
  }

  Future<void> createOrder({
    required RestaurantTable? table,
    required List<OrderLine> lines,
    required int diners,
    int? parentOrderId,
    List<RestaurantTable> joinedTables = const [],
    FulfillmentType fulfillmentType = FulfillmentType.dineIn,
    String customerName = '',
    String customerPhone = '',
    String deliveryAddress = '',
  }) async {
    lastOrderQueued = false;
    if (lines.isEmpty) {
      throw StateError(
        'Agrega al menos un platillo antes de enviar la comanda.',
      );
    }
    final group = table == null ? null : tableGroupFor(table);
    if (joinedTables.isNotEmpty || group != null) {
      if (fulfillmentType != FulfillmentType.dineIn || table == null) {
        throw StateError('La unión de mesas se usa para pedidos en el salón.');
      }
      await _createJoinedTableOrder(
        table: table,
        joinedTables: joinedTables,
        existingGroup: group,
        parentOrderId: parentOrderId,
        diners: diners,
        lines: lines,
      );
      return;
    }
    if (fulfillmentType == FulfillmentType.dineIn &&
        (table == null || diners < 1 || diners > table.capacity)) {
      throw StateError(
        'Los comensales deben estar entre 1 y la capacidad de la mesa.',
      );
    }
    if (fulfillmentType != FulfillmentType.dineIn &&
        (customerName.trim().isEmpty ||
            !RestaurantStore.isValidCustomerPhone(customerPhone))) {
      throw StateError(
        'Indica el nombre del cliente y un teléfono de 9 dígitos.',
      );
    }
    if (fulfillmentType != FulfillmentType.dineIn &&
        !RestaurantStore.isValidDeliveryName(customerName)) {
      throw StateError('Usa solo letras y espacios en el nombre del cliente.');
    }
    if (fulfillmentType == FulfillmentType.delivery &&
        deliveryAddress.trim().isEmpty) {
      throw StateError('Indica la dirección de entrega.');
    }
    if (fulfillmentType != FulfillmentType.dineIn && parentOrderId != null) {
      throw StateError(
        'Los consumos adicionales solo se pueden vincular a un pedido en mesa.',
      );
    }
    if (fulfillmentType == FulfillmentType.dineIn) {
      final current = tables
          .where((entry) => entry.id == table!.id)
          .firstOrNull;
      if (current == null || !current.active) {
        throw StateError('La mesa ya no está disponible.');
      }
      if (diners > current.capacity) {
        throw StateError('El número de comensales supera la capacidad actual.');
      }
      if (tableBillingStarted(current)) {
        throw StateError('La mesa ya está en cobro y no admite más pedidos.');
      }
      final parent = orders
          .where((order) => order.id == parentOrderId)
          .firstOrNull;
      if (!canOrderAtTable(current) ||
          (parentOrderId == null && additionalOrderParent(current) != null) ||
          (parentOrderId != null &&
              (parent == null ||
                  !_canLinkAdditionalOrder(parent, current.id)))) {
        throw StateError(
          'Selecciona un pedido abierto y sincronizado de esta mesa.',
        );
      }
      if (parent != null) {
        await _addConsumptionToAccount(
          table: current,
          account: parent,
          diners: diners,
          lines: lines,
        );
        return;
      }
    }
    final client = _client;
    final version = _sessionVersion;
    final int orderId;
    if (client != null) {
      final requestId = _newRequestId();
      dynamic result;
      try {
        result = await client.rpc(
          'crear_pedido_sincronizado',
          params: {
            'p_solicitud_id': requestId,
            'p_mesa_id': fulfillmentType == FulfillmentType.dineIn
                ? table!.id
                : null,
            'p_comensales': diners,
            'p_pedido_padre_id': parentOrderId,
            'p_tipo_pedido': fulfillmentType.databaseValue,
            'p_cliente_nombre': customerName.trim(),
            'p_cliente_telefono': customerPhone.trim(),
            'p_direccion_entrega': fulfillmentType == FulfillmentType.delivery
                ? deliveryAddress.trim()
                : null,
            'p_items': _itemsToJson(lines),
          },
        );
      } catch (error) {
        if (parentOrderId != null &&
            error is PostgrestException &&
            (error.code == 'PT409' ||
                error.message.contains(
                  'pedido principal no está disponible',
                ))) {
          try {
            await refresh(reconcilePayments: false);
          } catch (_) {
            // Keep the cart and report that the order was rejected.
          }
          throw StateError(
            'La comanda adicional no se guardó. Revisa el estado actual de la mesa antes de volver a enviarla.',
          );
        }
        if (!_connectionInterrupted(error)) rethrow;
        if (_sessionVersion != version) return;
        await _queueOfflineOrder(
          requestId: requestId,
          table: table,
          diners: diners,
          lines: lines,
          parentOrderId: parentOrderId,
          fulfillmentType: fulfillmentType,
          customerName: customerName,
          customerPhone: customerPhone,
          deliveryAddress: deliveryAddress,
        );
        _scheduleOrderRetry(version);
        return;
      }
      final confirmedId = int.tryParse('$result');
      if (confirmedId == null) {
        throw StateError('Supabase no confirmó la creación del pedido.');
      }
      orderId = confirmedId;
      await _refreshAfterWrite(version);
      if (_sessionVersion != version) return;
    } else {
      orderId = _nextId++;
    }
    if (!orders.any((order) => order.id == orderId)) {
      orders.insert(
        0,
        RestaurantOrder(
          id: orderId,
          tableId: table?.id,
          tableNumber: table?.number ?? 0,
          createdAt: _now(),
          diners: diners,
          lines: List.unmodifiable(
            isDemo
                ? [
                    for (final line in lines)
                      line.copyWith(waiterService: isWaiterService(line)),
                  ]
                : lines,
          ),
          waiterName: displayName,
          waiterId: userId,
          parentOrderId: parentOrderId,
          fulfillmentType: fulfillmentType,
          customerName: customerName.trim(),
          customerPhone: customerPhone.trim(),
          deliveryAddress: deliveryAddress.trim(),
        ),
      );
      if (table != null) _recalculateTable(table.id);
      if (isDemo) {
        await _persist();
      } else {
        await _saveRemoteCache();
      }
    }
    _recordLocalAudit('Crear pedido', 'pedidos', orderId.toString());
    _publish();
  }

  String _newRequestId() {
    final random = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0'));
    final value = hex.join();
    return '${value.substring(0, 8)}-${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-${value.substring(16, 20)}-'
        '${value.substring(20)}';
  }

  Future<void> _addConsumptionToAccount({
    required RestaurantTable table,
    required RestaurantOrder account,
    required int diners,
    required List<OrderLine> lines,
  }) async {
    if (additionalOrderParent(table)?.id != account.id ||
        tableBillingStarted(table) ||
        diners != account.diners) {
      throw StateError('Selecciona una cuenta abierta de esta mesa.');
    }
    if (lines.any((line) => line.quantity < 1)) {
      throw StateError('La cantidad de cada producto debe ser mayor que cero.');
    }

    final client = _client;
    final version = _sessionVersion;
    if (client != null) {
      final requestId = _newRequestId();
      try {
        final result = await _sendAccountConsumption(
          client,
          requestId: requestId,
          accountId: account.id,
          lines: lines,
        );
        if (int.tryParse('$result') != account.id) {
          throw StateError('Supabase no confirmó el consumo en esta cuenta.');
        }
        final refreshed = await _refreshAfterWrite(version);
        if (version != _sessionVersion) return;
        if (refreshed) {
          _publish();
          return;
        }
      } catch (error) {
        if (error is PostgrestException && error.code == 'PT409') {
          await _refreshAfterWrite(version);
          if (version == _sessionVersion) _publish();
          rethrow;
        }
        if (!_connectionInterrupted(error)) rethrow;
        if (version != _sessionVersion) return;
      }
      // Keep the original token until a fresh snapshot confirms the account.
      // Retrying the acknowledged write is safe through the request ledger.
      await _queueOfflineOrder(
        requestId: requestId,
        table: serviceTableFor(table),
        diners: account.diners,
        lines: lines,
        parentOrderId: account.id,
        fulfillmentType: FulfillmentType.dineIn,
        customerName: '',
        customerPhone: '',
        deliveryAddress: '',
        groupTableIds: account.groupTableIds,
        groupTableNumbers: account.groupTableNumbers,
        appendsToAccount: true,
      );
      _scheduleOrderRetry(version);
      return;
    }

    final index = orders.indexWhere((order) => order.id == account.id);
    final current = orders[index];
    orders[index] = current.copyWith(
      lines: List.unmodifiable([
        ...current.lines,
        ..._newGroupedLines(
          lines,
        ).map((line) => line.copyWith(createdAt: _now())),
      ]),
      status: OrderStatus.pending,
    );
    _recalculateTable(current.tableId);
    await _persist();
    _recordLocalAudit(
      'Agregar consumo a la cuenta',
      'pedidos',
      account.id.toString(),
    );
    _publish();
  }

  Future<dynamic> _sendAccountConsumption(
    SupabaseClient client, {
    required String requestId,
    required int accountId,
    required List<OrderLine> lines,
  }) => client.rpc(
    'agregar_consumo_cuenta_mesa',
    params: {
      'p_solicitud_id': requestId,
      'p_pedido_id': accountId,
      'p_items': _itemsToJson(lines),
    },
  );

  Future<void> _queueOfflineOrder({
    required String requestId,
    required RestaurantTable? table,
    required int diners,
    required List<OrderLine> lines,
    required int? parentOrderId,
    required FulfillmentType fulfillmentType,
    required String customerName,
    required String customerPhone,
    required String deliveryAddress,
    List<int> groupTableIds = const [],
    List<int> groupTableNumbers = const [],
    bool appendsToAccount = false,
  }) async {
    final order = RestaurantOrder(
      id: -DateTime.now().microsecondsSinceEpoch,
      tableId: table?.id,
      tableNumber: table?.number ?? 0,
      createdAt: DateTime.now(),
      diners: diners,
      lines: List.unmodifiable(lines),
      waiterName: displayName,
      waiterId: userId,
      parentOrderId: parentOrderId,
      fulfillmentType: fulfillmentType,
      customerName: customerName.trim(),
      customerPhone: customerPhone.trim(),
      deliveryAddress: deliveryAddress.trim(),
      pendingSync: true,
      clientRequestId: requestId,
      appendsToAccount: appendsToAccount,
      groupTableIds: groupTableIds,
      groupTableNumbers: groupTableNumbers,
    );
    pendingOrders.add(order);
    orders.insert(0, order);
    if (order.hasJoinedTables && parentOrderId == null) {
      _showPendingJoinedTableMembership(order);
    } else if (table != null) {
      _recalculateTable(table.id);
    }
    lastOrderQueued = true;
    errorMessage =
        'Pedido guardado en este dispositivo y pendiente de sincronización.';
    await _persist();
    _publish();
  }

  void _scheduleOrderRetry(int version) {
    if (version != _sessionVersion || pendingOrders.isEmpty) return;
    _orderRetryTimer ??= Timer(const Duration(seconds: 25), () {
      _orderRetryTimer = null;
      unawaited(_syncPendingOrdersSafely());
    });
  }

  Future<void> syncPendingOrders() {
    final client = _client;
    if (client == null || pendingOrders.isEmpty) return Future.value();
    final currentSync = _orderSync;
    if (currentSync != null) return currentSync;
    final sync = _syncPendingOrders(client, _sessionVersion);
    _orderSync = sync;
    return sync.whenComplete(() {
      if (identical(_orderSync, sync)) _orderSync = null;
    });
  }

  Future<void> _syncPendingOrders(SupabaseClient client, int version) async {
    try {
      final blockedTables = <int>{};
      for (final order in List<RestaurantOrder>.of(pendingOrders)) {
        final requestId = order.clientRequestId;
        final accountAddition =
            order.appendsToAccount ||
            (order.hasJoinedTables && order.parentOrderId != null);
        if (requestId == null) {
          throw StateError(
            'Un pedido pendiente no tiene identificador de sincronización.',
          );
        }
        dynamic result;
        try {
          result = accountAddition
              ? await _sendAccountConsumption(
                  client,
                  requestId: requestId,
                  accountId: order.parentOrderId!,
                  lines: order.lines,
                )
              : order.hasJoinedTables
              ? await _sendJoinedTableOrder(
                  client,
                  requestId: requestId,
                  tableIds: order.groupTableIds,
                  diners: order.diners,
                  parentOrderId: order.parentOrderId,
                  lines: order.lines,
                )
              : await client.rpc(
                  'crear_pedido_sincronizado',
                  params: {
                    'p_solicitud_id': requestId,
                    'p_mesa_id': order.tableId,
                    'p_comensales': order.diners,
                    'p_pedido_padre_id': order.parentOrderId,
                    'p_tipo_pedido': order.fulfillmentType.databaseValue,
                    'p_cliente_nombre': order.customerName,
                    'p_cliente_telefono': order.customerPhone,
                    'p_direccion_entrega':
                        order.fulfillmentType == FulfillmentType.delivery
                        ? order.deliveryAddress
                        : null,
                    'p_items': _itemsToJson(order.lines),
                  },
                );
        } on PostgrestException catch (error) {
          if (error.code != 'PT409' || order.tableId == null) rethrow;
          blockedTables.add(order.tableNumber);
          continue;
        }
        if (_sessionVersion != version) return;
        final confirmedId = int.tryParse('$result');
        if (confirmedId == null) {
          throw StateError('Supabase no confirmó un pedido pendiente.');
        }
        if (accountAddition && confirmedId != order.parentOrderId) {
          throw StateError('Supabase no confirmó el consumo en su cuenta.');
        }
        pendingOrders.removeWhere(
          (pending) => pending.clientRequestId == requestId,
        );
        orders.removeWhere((pending) => pending.clientRequestId == requestId);
        if (accountAddition) {
          final refreshed = await _refreshAfterWrite(version);
          if (_sessionVersion != version) return;
          if (!refreshed) {
            pendingOrders.add(order);
            orders.insert(0, order);
            await _saveRemoteCache();
            _scheduleOrderRetry(version);
            throw StateError(
              'Actualiza la cuenta para confirmar el consumo adicional.',
            );
          }
        } else if (!orders.any((item) => item.id == confirmedId)) {
          final confirmed = order.copyWith(id: confirmedId, pendingSync: false);
          orders.insert(0, confirmed);
          if (confirmed.hasJoinedTables) {
            for (var i = 0; i < tables.length; i++) {
              final table = tables[i];
              if (table.groupOrderId == order.id) {
                tables[i] = table.copyWith(groupOrderId: confirmedId);
              }
            }
            _setJoinedTableStatuses(confirmed);
          }
        }
        await _saveRemoteCache();
        if (_sessionVersion != version) return;
      }
      await _refreshAfterWrite(version);
      if (_sessionVersion != version) return;
      if (blockedTables.isNotEmpty) {
        throw StateError(
          'Revisa los pedidos sin sincronizar de las mesas ${blockedTables.join(', ')}. '
          'Se conservaron en este dispositivo porque la mesa cambió de estado.',
        );
      }
      _publish();
    } catch (error) {
      if (_sessionVersion != version) return;
      errorMessage = 'Quedan pedidos por sincronizar. Revisa «Mis pedidos».';
      if (_connectionInterrupted(error)) _scheduleOrderRetry(version);
      await _saveRemoteCache();
      _publish();
      rethrow;
    }
  }

  Future<void> _syncPendingOrdersSafely() async {
    try {
      await syncPendingOrders();
    } catch (_) {
      // syncPendingOrders exposes the failure through errorMessage.
    }
  }

  Future<void> editOrder({
    required RestaurantOrder order,
    required List<OrderLine> lines,
    required int diners,
  }) async {
    final index = orders.indexWhere((value) => value.id == order.id);
    if (index < 0) throw StateError('No se encontró el pedido.');
    final current = orders[index];
    if (current.pendingSync ||
        pendingOrders.any((order) => order.parentOrderId == current.id) ||
        current.status != OrderStatus.pending ||
        current.payments.isNotEmpty ||
        current.lines.any((line) => line.status != OrderStatus.pending) ||
        lines.isEmpty ||
        diners < 1) {
      throw StateError('Solo se edita un pedido pendiente y sin abonos.');
    }
    final table = tables
        .where((entry) => entry.id == current.tableId)
        .firstOrNull;
    if (table != null && tableBillingStarted(table)) {
      throw StateError(
        'La mesa ya está en cobro y no admite cambios en los pedidos.',
      );
    }
    if (current.hasJoinedTables &&
        (table == null ||
            !_canManageJoinedOrder(current) ||
            diners > tableServiceCapacity(table))) {
      throw StateError('Verifica la capacidad y el acceso a las mesas unidas.');
    }
    if (_client != null) {
      await _client.rpc(
        current.hasJoinedTables
            ? 'editar_pedido_mesas_unidas'
            : 'editar_pedido',
        params: {
          'p_pedido_id': order.id,
          'p_comensales': diners,
          'p_items': _itemsToJson(lines),
        },
      );
      await _loadRemoteData();
    } else {
      orders[index] = current.copyWith(
        diners: diners,
        lines: [
          for (final line in lines)
            line.copyWith(waiterService: isWaiterService(line)),
        ],
        status: OrderStatus.pending,
      );
      _recalculateTable(order.tableId);
      await _persist();
    }
    _recordLocalAudit('Editar pedido', 'pedidos', order.id.toString());
    _publish();
  }

  Future<void> cancelOrder(RestaurantOrder order) async {
    if (order.pendingSync ||
        order.status != OrderStatus.pending ||
        order.payments.isNotEmpty) {
      throw StateError(
        'Solo puedes cancelar un pedido pendiente y sin abonos.',
      );
    }
    if (order.lines.any((line) => line.status != OrderStatus.pending)) {
      throw StateError('Cocina ya inició la preparación de este pedido.');
    }
    if (pendingOrders.any((item) => item.parentOrderId == order.id)) {
      throw StateError('Sincroniza el consumo adicional antes de cancelar.');
    }
    if (_client != null) {
      await _client.rpc('cancelar_pedido', params: {'p_pedido_id': order.id});
      await _loadRemoteData();
    } else {
      final index = orders.indexWhere((value) => value.id == order.id);
      if (index < 0) throw StateError('No se encontró el pedido.');
      orders[index] = order.copyWith(status: OrderStatus.cancelled);
      _recalculateTable(order.tableId);
      await _persist();
    }
    _recordLocalAudit('Cancelar pedido', 'pedidos', order.id.toString());
    _publish();
  }

  Future<void> confirmTableRelease(RestaurantTable table) async {
    final currentGroupId = _tableById(table.id)?.groupOrderId;
    if (table.groupOrderId != currentGroupId) {
      throw StateError('Las mesas cambiaron de servicio. Revisa su estado.');
    }
    final group = tableGroupFor(table);
    if (group != null) {
      await _releaseJoinedTables(group);
      return;
    }
    if (currentGroupId != null) {
      throw StateError('Actualiza la información de las mesas unidas.');
    }
    final tableOrders = orders.where((order) => order.tableId == table.id);
    if (pendingOrders.any((order) => order.tableId == table.id)) {
      throw StateError('Sincroniza los consumos antes de liberar la mesa.');
    }
    if (tableOrders.any(
      (order) =>
          (order.status != OrderStatus.paid &&
              order.status != OrderStatus.cancelled) ||
          (order.status == OrderStatus.paid &&
              kitchenStage(order) != OrderStatus.delivered),
    )) {
      throw StateError(
        'Completa la entrega y el cobro de todos los pedidos antes de liberar la mesa.',
      );
    }
    if (_client != null) {
      await _client.rpc(
        'confirmar_retiro_mesa',
        params: {'p_mesa_id': table.id},
      );
      await _loadRemoteData();
    } else {
      for (var i = 0; i < orders.length; i++) {
        if (orders[i].tableId == table.id) {
          orders[i] = orders[i].copyWith(retirementConfirmed: true);
        }
      }
      _recalculateTable(table.id);
      await _persist();
    }
    _recordLocalAudit(
      'Confirmar retiro de mesa',
      'mesas',
      table.number.toString(),
    );
    _publish();
  }

  List<Map<String, dynamic>> _itemsToJson(List<OrderLine> lines) => lines
      .map(
        (line) => {
          'platillo_id': line.menuItemId,
          'cantidad': line.quantity,
          'observaciones': line.note,
        },
      )
      .toList(growable: false);

  Future<void> confirmWaiterService(RestaurantOrder order) async {
    final index = orders.indexWhere((item) => item.id == order.id);
    if (index < 0) throw StateError('No se encontró el pedido.');
    final current = orders[index];
    if (!canConfirmWaiterService(current)) return;

    if (_client != null) {
      final version = _sessionVersion;
      try {
        await _client.rpc(
          'entregar_productos_de_mesero',
          params: {'p_pedido_id': current.id},
        );
      } catch (_) {
        if (version == _sessionVersion) _scheduleRealtimeRefresh(version);
        rethrow;
      }
      if (version != _sessionVersion) return;
      await _refreshAfterWrite(version);
    } else {
      final lines = [
        for (final line in current.lines)
          _awaitsWaiterService(line)
              ? line.copyWith(status: OrderStatus.delivered)
              : line,
      ];
      final status =
          current.status == OrderStatus.paid ||
              current.status == OrderStatus.forPayment
          ? current.status
          : orderLineStage(lines);
      orders[index] = current.copyWith(lines: lines, status: status);
      _recalculateTable(current.tableId);
      await _persist();
    }
    _recordLocalAudit(
      'Entregar bebidas y postres',
      'pedidos',
      current.id.toString(),
    );
    _publish();
  }

  Future<void> advanceOrder(
    RestaurantOrder order, {
    OrderStatus? forStage,
  }) async {
    final index = orders.indexWhere((item) => item.id == order.id);
    if (index < 0) throw StateError('No se encontró el pedido.');
    final current = orders[index];
    if (current.pendingSync) {
      throw StateError('Sincroniza el pedido antes de actualizar su estado.');
    }
    if (current.status == OrderStatus.cancelled) {
      throw StateError('El pedido está cancelado.');
    }
    final food = kitchenLines(current);
    final currentKitchenStage = forStage ?? orderLineStage(food);
    final shownLineIds = order.lines
        .where((line) => line.status == currentKitchenStage)
        .map((line) => line.id)
        .whereType<int>()
        .toSet();
    bool shouldAdvance(OrderLine line) =>
        line.status == currentKitchenStage &&
        (forStage == null || line.id == null || shownLineIds.contains(line.id));
    final linesToAdvance = food.where(shouldAdvance);
    if (forStage != null && linesToAdvance.isEmpty) return;
    if ((role == StaffRole.kitchen || role == StaffRole.headChef) &&
        currentKitchenStage == OrderStatus.ready) {
      throw StateError('La entrega la confirma el mesero.');
    }
    final nextStatus = switch (currentKitchenStage) {
      OrderStatus.pending => OrderStatus.preparing,
      OrderStatus.preparing => OrderStatus.ready,
      OrderStatus.ready => OrderStatus.delivered,
      _ => throw StateError(
        'Este pedido no puede avanzar desde el estado actual.',
      ),
    };
    if (_client != null) {
      final version = _sessionVersion;
      try {
        for (final line in linesToAdvance) {
          if (line.id == null || version != _sessionVersion) continue;
          await _client.rpc(
            'actualizar_estado_item',
            params: {
              'p_detalle_id': line.id,
              'p_estado': nextStatus.databaseValue,
            },
          );
        }
      } catch (_) {
        if (version == _sessionVersion) {
          _scheduleRealtimeRefresh(version);
        }
        rethrow;
      }
      if (version != _sessionVersion) return;
      await _refreshAfterWrite(version);
    } else {
      final updatedLines = [
        for (final line in current.lines)
          !isWaiterService(line) && shouldAdvance(line)
              ? line.copyWith(status: nextStatus)
              : line,
      ];
      final kitchenStatus = orderLineStage(
        updatedLines.where((line) => !isWaiterService(line)),
      );
      final status =
          current.status == OrderStatus.paid ||
              current.status == OrderStatus.forPayment
          ? current.status
          : kitchenStatus == OrderStatus.delivered &&
                updatedLines.any(_awaitsWaiterService)
          ? OrderStatus.ready
          : kitchenStatus;
      orders[index] = current.copyWith(lines: updatedLines, status: status);
      _recalculateTable(current.tableId);
      await _persist();
    }
    _recordLocalAudit(
      'Actualizar estado de comanda',
      'pedidos',
      order.id.toString(),
    );
    _publish();
  }

  Future<void> recordPayment({
    required RestaurantOrder order,
    required String method,
    required double amount,
    String reference = '',
    double? cashReceived,
    bool earlyPaymentConfirmed = false,
  }) async {
    if (!_paymentsInProgress.add(order.id)) {
      throw StateError('Ya se está registrando un pago para esta cuenta.');
    }
    try {
      if (_paymentsToVerify.contains(order.id)) {
        throw const PaymentNotConfirmed();
      }
      if (!shiftOpen) {
        throw StateError(
          'La caja de hoy está cerrada. Administración debe abrir el turno para registrar cobros.',
        );
      }
      if (order.pendingSync || _hasPendingConsumption(order)) {
        throw StateError('Sincroniza el pedido antes de registrar pagos.');
      }
      final currentOrder = orders
          .where((item) => item.id == order.id)
          .firstOrNull;
      if (currentOrder == null ||
          currentOrder.status == OrderStatus.cancelled) {
        throw StateError('El pedido ya no admite pagos.');
      }
      if ((currentOrder.balance * 100).round() !=
          (order.balance * 100).round()) {
        throw StateError(
          'El saldo de la cuenta cambió. Revisa los pagos antes de continuar.',
        );
      }
      if (!amount.isFinite ||
          (amount * 100 - (amount * 100).roundToDouble()).abs() > .000001 ||
          amount <= 0 ||
          amount > currentOrder.balance + 0.001) {
        throw StateError(
          'El monto debe ser mayor a cero y no superar el saldo pendiente.',
        );
      }
      if (method != 'Efectivo' &&
          !RegExp(
            r'^[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*$',
          ).hasMatch(reference.trim())) {
        throw StateError(
          'Escribe un código de operación con letras, números o guiones.',
        );
      }
      if (method == 'Efectivo' &&
          (cashReceived == null ||
              !cashReceived.isFinite ||
              cashReceived < amount)) {
        throw StateError(
          'El efectivo recibido debe cubrir el monto del abono.',
        );
      }
      if ((kitchenStage(currentOrder) == OrderStatus.pending ||
              kitchenStage(currentOrder) == OrderStatus.preparing) &&
          !earlyPaymentConfirmed) {
        throw StateError(
          'Confirma el cobro anticipado antes de registrar el pago.',
        );
      }
      final databaseMethod = switch (method) {
        'Efectivo' => 'EFECTIVO',
        'Tarjeta' => 'TARJETA',
        'Yape' || 'Plin' || 'Yape / Plin' => 'YAPE_PLIN',
        _ => throw StateError('Selecciona un método de pago disponible.'),
      };
      if (_client != null) {
        final version = _sessionVersion;
        try {
          await _client.rpc(
            'registrar_pago',
            params: {
              'p_pedido_id': order.id,
              'p_metodo': databaseMethod,
              'p_monto': amount,
              'p_referencia': reference.trim().isEmpty
                  ? null
                  : reference.trim(),
              'p_efectivo_recibido': cashReceived,
              'p_cobro_anticipado_confirmado': earlyPaymentConfirmed,
            },
          );
        } catch (error) {
          if (version == _sessionVersion && _connectionInterrupted(error)) {
            _paymentsToVerify.add(order.id);
            throw const PaymentNotConfirmed();
          }
          rethrow;
        }
        if (version != _sessionVersion) return;
        final refreshed = await _refreshAfterWrite(version);
        if (version != _sessionVersion) return;
        if (refreshed) {
          _publish();
          return;
        }
      }
      {
        final index = orders.indexWhere((item) => item.id == order.id);
        if (index < 0) return;
        final payments = [
          ...currentOrder.payments,
          PaymentEntry(
            method: method,
            amount: amount,
            createdAt: _now(),
            reference: reference.trim(),
            cashReceived: cashReceived,
            cashierId: userId,
            shiftId: _client == null ? null : _shift.id,
          ),
        ];
        final complete =
            payments.fold<double>(0, (sum, payment) => sum + payment.amount) >=
            order.total - 0.001;
        orders[index] = currentOrder.copyWith(
          payments: payments,
          status: complete ? OrderStatus.paid : OrderStatus.forPayment,
        );
        if (complete && isDemo) {
          receipts.insert(0, {
            'id': _nextId++,
            'code':
                'NV-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
            'orderId': order.id,
            'tableNumber': order.tableNumber,
            'locationLabel': order.locationLabel,
            'total': order.total,
            'createdAt': DateTime.now().toIso8601String(),
            'status': 'VIGENTE',
            'payments': payments.map((payment) => payment.toJson()).toList(),
          });
        }
        _recalculateTable(order.tableId);
        if (isDemo) {
          await _persist();
        } else {
          await _saveRemoteCache();
        }
      }
      _recordLocalAudit('Registrar pago', 'pedidos', order.id.toString());
      _publish();
    } finally {
      _paymentsInProgress.remove(order.id);
    }
  }

  Future<void> voidReceipt({
    required Map<String, dynamic> receipt,
    required String reason,
  }) async {
    if (role != StaffRole.administrator) {
      throw StateError('Solo administración puede anular una nota de venta.');
    }
    final trimmed = reason.trim();
    if (trimmed.length < 5) throw StateError('Indica un motivo de anulación.');
    if (receipt['status'] == 'ANULADO') {
      throw StateError('Esta nota ya fue anulada.');
    }
    if (_client != null) {
      await _client.rpc(
        'anular_nota_venta',
        params: {'p_nota_id': receipt['id'], 'p_motivo': trimmed},
      );
      await _loadRemoteData();
    } else {
      final index = receipts.indexWhere((item) => item['id'] == receipt['id']);
      if (index < 0) throw StateError('No se encontró la nota de venta.');
      final orderId = receipt['orderId'];
      final orderIndex = orders.indexWhere((order) => order.id == orderId);
      if (orderIndex < 0) {
        throw StateError('No se encontró el pedido relacionado.');
      }
      receipts[index] = {
        ...receipts[index],
        'status': 'ANULADO',
        'voidReason': trimmed,
        'refunds': orders[orderIndex].payments
            .map((payment) => payment.toJson())
            .toList(),
      };
      final order = orders[orderIndex];
      orders[orderIndex] = order.copyWith(status: OrderStatus.cancelled);
      _recalculateTable(order.tableId);
      await _persist();
    }
    _recordLocalAudit(
      'Anular nota de venta',
      'notas_venta',
      receipt['id'].toString(),
    );
    _publish();
  }

  Future<void> recordReceiptPrint(int receiptId) async {
    if (_client != null) {
      await _client.rpc(
        'registrar_reimpresion_nota',
        params: {'p_nota_id': receiptId},
      );
    } else {
      final index = receipts.indexWhere((item) => item['id'] == receiptId);
      if (index >= 0) {
        receipts[index] = {
          ...receipts[index],
          'reprints': ((receipts[index]['reprints'] as int?) ?? 0) + 1,
        };
        await _persist();
      }
    }
  }
}
