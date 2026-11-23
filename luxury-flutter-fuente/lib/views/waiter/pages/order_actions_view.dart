part of '../waiter_screen.dart';

String _joinedTablesLabel(List<RestaurantTable> tables) =>
    'Mesas ${tables.map((table) => table.number).join(' + ')}';

extension _WaiterOrderActionsView on _WaiterScreenState {
  RestaurantOrder? get _draftServiceOrder =>
      editingOrder ??
      store.orders.where((order) => order.id == additionalParentId).firstOrNull;

  bool get _usesJoinedTables =>
      joinedOrderTables.isNotEmpty ||
      (_draftServiceOrder?.hasJoinedTables ?? false);

  String _orderDestination(RestaurantTable? table) {
    if (joinedOrderTables.isNotEmpty) {
      return _joinedTablesLabel(joinedOrderTables);
    }
    if (table == null) return fulfillmentType.label;
    final order = _draftServiceOrder;
    if (order != null && order.hasJoinedTables) return order.locationLabel;
    return store.tableLocationLabel(table);
  }

  int _orderCapacity(RestaurantTable table) => joinedOrderTables.isEmpty
      ? store.tableServiceCapacity(table)
      : joinedOrderTables.fold(
          0,
          (capacity, table) => capacity + table.capacity,
        );

  void _openOrder(
    RestaurantTable table, {
    RestaurantOrder? editOrder,
    RestaurantOrder? parentOrder,
    List<RestaurantTable> joinedTables = const [],
  }) {
    final joining = joinedTables.isNotEmpty;
    final canOpen = joining
        ? joinedTables.length >= 2 && joinedTables.every(store.canJoinTable)
        : store.canOrderAtTable(table);
    if (!canOpen) {
      showResultDialog(
        context,
        success: false,
        message: joining
            ? 'Alguna mesa seleccionada ya está ocupada. Vuelve a elegir las mesas.'
            : 'Esta mesa ya no admite pedidos. Consulta su estado.',
      );
      return;
    }
    final serviceTable = store.serviceTableFor(table);
    final currentParent = editOrder == null
        ? parentOrder ?? store.additionalOrderParent(serviceTable)
        : null;
    _setState(() {
      selectedTableId = serviceTable.id;
      joinedOrderTables = List.unmodifiable(joinedTables);
      fulfillmentType = FulfillmentType.dineIn;
      customerName = editOrder?.customerName ?? '';
      customerPhone = editOrder?.customerPhone ?? '';
      deliveryAddress = editOrder?.deliveryAddress ?? '';
      editingOrder = editOrder;
      additionalParentId = currentParent?.id;
      diners =
          editOrder?.diners ??
          (currentParent != null
              ? currentParent.diners
              : math.min(2, _orderCapacity(serviceTable)));
      category = 'Todas';
      dishSearch.clear();
      cart.clear();
      _showCompactOrder = false;
      if (editOrder != null) {
        for (final line in editOrder.lines) {
          final item = store.menu
              .where((value) => value.id == line.menuItemId)
              .firstOrNull;
          if (item != null) {
            cart[item.id] = _CartLine(item)
              ..quantity = line.quantity
              ..note = line.note;
          }
        }
      }
      isCreatingOrder = true;
    });
  }

  void _openOffPremiseOrder(FulfillmentType type) {
    _setState(() {
      selectedTableId = null;
      joinedOrderTables = const [];
      fulfillmentType = type;
      customerName = '';
      customerPhone = '';
      deliveryAddress = '';
      editingOrder = null;
      additionalParentId = null;
      diners = 1;
      category = 'Todas';
      dishSearch.clear();
      cart.clear();
      _showCompactOrder = false;
      isCreatingOrder = true;
    });
  }

  Future<void> _submitOrder() async {
    if (operationPending) return;
    final table = selectedTable;
    if (fulfillmentType == FulfillmentType.dineIn && table == null) {
      await showResultDialog(
        context,
        success: false,
        message: 'Selecciona una mesa primero.',
      );
      return;
    }
    if (editingOrder == null &&
        fulfillmentType != FulfillmentType.dineIn &&
        (customerName.trim().isEmpty ||
            !RestaurantStore.isValidCustomerPhone(customerPhone))) {
      await showResultDialog(
        context,
        success: false,
        message: 'Indica el nombre del cliente y un teléfono de 9 dígitos.',
      );
      return;
    }
    if (fulfillmentType != FulfillmentType.dineIn &&
        !RestaurantStore.isValidDeliveryName(customerName)) {
      await showResultDialog(
        context,
        success: false,
        message: 'Usa solo letras y espacios en el nombre del cliente.',
      );
      return;
    }
    if (fulfillmentType == FulfillmentType.delivery &&
        deliveryAddress.trim().isEmpty) {
      await showResultDialog(
        context,
        success: false,
        message: 'Indica la dirección de entrega.',
      );
      return;
    }
    if (editingOrder == null) {
      final destination = _orderDestination(table);
      final joined = _usesJoinedTables;
      final adding = additionalParentId != null;
      final confirmed = await confirmAction(
        context,
        title: adding
            ? '¿Agregar el consumo?'
            : joined
            ? '¿Registrar el pedido?'
            : '¿Enviar pedido a cocina?',
        message: adding
            ? '$destination · ${money(cartTotal)}. Se sumará a la cuenta del pedido #$additionalParentId.'
            : joined
            ? '$destination · ${money(cartTotal)}. Los consumos se registrarán en una sola cuenta.'
            : '$destination · ${money(cartTotal)}. Cocina recibirá esta comanda.',
        actionLabel: adding
            ? 'Agregar consumo'
            : joined
            ? 'Registrar pedido'
            : 'Enviar pedido',
      );
      if (!confirmed || !mounted) return;
    }
    await _run(() async {
      final lines = cart.values
          .map(
            (line) => OrderLine(
              menuItemId: line.item.id,
              name: line.item.name,
              quantity: line.quantity,
              unitPrice: line.item.price,
              note: line.note,
            ),
          )
          .toList();
      if (editingOrder case final existing?) {
        await store.editOrder(order: existing, lines: lines, diners: diners);
      } else {
        await store.createOrder(
          table: table,
          diners: diners,
          lines: lines,
          joinedTables: joinedOrderTables,
          parentOrderId: additionalParentId,
          fulfillmentType: fulfillmentType,
          customerName: customerName.trim(),
          customerPhone: customerPhone.trim(),
          deliveryAddress: deliveryAddress.trim(),
        );
      }
      if (!mounted) return;
      final wasEditing = editingOrder != null;
      final wasJoined = _usesJoinedTables;
      final wasAdding = additionalParentId != null;
      _setState(() {
        category = 'Todas';
        dishSearch.clear();
        cart.clear();
        editingOrder = null;
        additionalParentId = null;
        joinedOrderTables = const [];
        isCreatingOrder = false;
        page = 1;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasEditing
                ? 'Cambios del pedido guardados.'
                : store.lastOrderQueued
                ? 'Pedido guardado. Se enviará al recuperar la conexión.'
                : wasAdding
                ? 'Consumo agregado a la cuenta existente.'
                : wasJoined
                ? 'Consumo registrado en la cuenta de las mesas unidas.'
                : 'Pedido enviado a cocina.',
          ),
        ),
      );
    }, label: editingOrder == null ? 'Enviando pedido…' : 'Guardando cambios…');
  }
}
