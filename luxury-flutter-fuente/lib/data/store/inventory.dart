part of '../restaurant_store.dart';

extension RestaurantStoreInventory on RestaurantStore {
  Future<void> updateInventory({
    int? id,
    required String name,
    required String unit,
    required double quantity,
    required double minimum,
    String description = '',
    String? imageUrl,
  }) async {
    if (name.trim().isEmpty || quantity < 0 || minimum < 0) {
      throw StateError('Verifica el nombre, el stock y el mínimo del insumo.');
    }
    final image = _catalogImageUrl(imageUrl);
    final previous = inventory.where((item) => item.id == id).firstOrNull;
    final changedImage = image != null && image != (previous?.imageUrl ?? '');
    if (_client != null) {
      final values = {
        'nombre': name.trim(),
        'descripcion': description.trim(),
        'unidad': unit,
        'stock_actual': quantity,
        'stock_minimo': minimum,
        if (changedImage) 'imagen_url': image.isEmpty ? null : image,
      };
      if (id == null) {
        await _client.from('insumos').insert(values);
      } else {
        await _client.from('insumos').update(values).eq('id', id);
      }
      await _loadRemoteData();
    } else if (id == null) {
      inventory.add(
        InventoryItem(
          id: _nextId++,
          name: name.trim(),
          unit: unit,
          quantity: quantity,
          minimum: minimum,
          description: description.trim(),
          imageUrl: image ?? '',
        ),
      );
      await _persist();
    } else {
      final index = inventory.indexWhere((item) => item.id == id);
      inventory[index] = inventory[index].copyWith(
        name: name.trim(),
        unit: unit,
        quantity: quantity,
        minimum: minimum,
        description: description.trim(),
        imageUrl: image,
      );
      await _persist();
    }
    _recordLocalAudit(
      id == null ? 'Crear insumo' : 'Actualizar insumo',
      'insumos',
      id?.toString() ?? inventory.last.id.toString(),
    );
    _publish();
  }

  Future<void> saveInventoryItem({
    required String name,
    required String unit,
    required double quantity,
    required double minimum,
    String description = '',
  }) async {
    if (name.trim().isEmpty) {
      throw StateError('El nombre del insumo no puede estar vacío.');
    }
    if (minimum < 0) throw StateError('El stock mínimo no puede ser negativo.');
    if (quantity < 0) {
      throw StateError('El stock actual no puede ser negativo.');
    }
    if (_client != null) {
      await _client.from('insumos').insert({
        'nombre': name.trim(),
        'unidad': unit,
        'stock_actual': quantity,
        'stock_minimo': minimum,
        'descripcion': description,
        'activo': true,
      });
      await _loadRemoteData();
    } else {
      final newId = inventory.isEmpty
          ? 1
          : inventory.map((i) => i.id).reduce((a, b) => a > b ? a : b) + 1;
      inventory.add(
        InventoryItem(
          id: newId,
          name: name.trim(),
          unit: unit,
          quantity: quantity,
          minimum: minimum,
          description: description,
          active: true,
        ),
      );
      await _persist();
    }
    _recordLocalAudit('Crear insumo', 'insumos', name.trim());
    _publish();
  }

  Future<void> setInventoryActive(InventoryItem item, bool active) async {
    if (_client != null) {
      await _client
          .from('insumos')
          .update({'activo': active})
          .eq('id', item.id);
      await _loadRemoteData();
    } else {
      final index = inventory.indexWhere((value) => value.id == item.id);
      if (index < 0) throw StateError('No se encontró el insumo.');
      inventory[index] = item.copyWith(active: active);
      await _persist();
    }
    _recordLocalAudit(
      active ? 'Habilitar insumo' : 'Archivar insumo',
      'insumos',
      item.id.toString(),
    );
    _publish();
  }

  StockRequest? openStockRequestFor(InventoryItem item) => requests
      .where(
        (request) =>
            request.isOpen && request.lines.any((line) => line.matches(item)),
      )
      .firstOrNull;

  Future<void> createStockRequest(
    InventoryItem item,
    double quantity,
    String note,
  ) async {
    if (!quantity.isFinite || quantity <= 0) {
      throw StateError('La cantidad solicitada debe ser mayor a cero.');
    }
    if (!item.active) {
      throw StateError('El insumo está archivado y no admite solicitudes.');
    }
    if (_client != null) {
      await _client.rpc(
        'solicitar_reabastecimiento',
        params: {
          'p_insumo_id': item.id,
          'p_cantidad': quantity,
          'p_observaciones': note.trim(),
        },
      );
      await _loadRemoteData();
    } else {
      requests.insert(
        0,
        StockRequest(
          id: _nextId++,
          itemName: item.name,
          quantity: quantity,
          unit: item.unit,
          note: note.trim(),
          priority: item.lowStock ? 'ALTA' : 'MEDIA',
          items: [
            StockRequestLine(
              inventoryId: item.id,
              itemName: item.name,
              quantity: quantity,
              unit: item.unit,
            ),
          ],
        ),
      );
      await _persist();
    }
    _recordLocalAudit(
      'Crear solicitud de reabastecimiento',
      'solicitudes_reabastecimiento',
      requests.first.id.toString(),
    );
    _publish();
  }

  Future<void> createStockRequestBatch({
    required List<(InventoryItem, double)> items,
    required String note,
  }) async {
    if (items.isEmpty ||
        items.any((entry) => !entry.$1.active || entry.$2 <= 0) ||
        items.map((entry) => entry.$1.id).toSet().length != items.length) {
      throw StateError(
        'Selecciona insumos activos, cantidades válidas y sin duplicados.',
      );
    }
    final priority = items.any((entry) => entry.$1.lowStock) ? 'ALTA' : 'MEDIA';
    if (_client != null) {
      await _client.rpc(
        'crear_solicitud_reabastecimiento',
        params: {
          'p_items': items
              .map((entry) => {'insumo_id': entry.$1.id, 'cantidad': entry.$2})
              .toList(),
          'p_observaciones': note.trim(),
        },
      );
      await _loadRemoteData();
    } else {
      final id = _nextId++;
      final lines = items
          .map(
            (entry) => StockRequestLine(
              inventoryId: entry.$1.id,
              itemName: entry.$1.name,
              quantity: entry.$2,
              unit: entry.$1.unit,
            ),
          )
          .toList(growable: false);
      requests.insert(
        0,
        StockRequest(
          id: id,
          itemName: lines.first.itemName,
          quantity: lines.first.quantity,
          unit: lines.first.unit,
          note: note.trim(),
          priority: priority,
          items: lines,
        ),
      );
      await _persist();
    }
    _recordLocalAudit(
      'Crear solicitud de reabastecimiento',
      'solicitudes_reabastecimiento',
      requests.first.id.toString(),
    );
    _publish();
  }

  Future<void> createKitchenAlert({
    InventoryItem? item,
    required String message,
  }) async {
    final trimmed = message.trim();
    if (trimmed.length < 5) {
      throw StateError('Describe el aviso con al menos cinco caracteres.');
    }
    if (item != null && !item.active) {
      throw StateError('El insumo está archivado.');
    }
    if (_client != null) {
      await _client.rpc(
        'crear_alerta_cocina',
        params: {'p_mensaje': trimmed, 'p_insumo_id': item?.id},
      );
      await _loadRemoteData();
    } else {
      alerts.insert(
        0,
        StockAlert(
          id: _nextId++,
          inventoryId: item?.id,
          message: trimmed,
          createdAt: DateTime.now(),
          priority: item?.lowStock == true ? 'ALTA' : 'MEDIA',
        ),
      );
      await _persist();
    }
    _recordLocalAudit(
      'Crear alerta de cocina',
      'alertas_cocina',
      alerts.first.id.toString(),
    );
    _publish();
  }

  Future<void> reviewKitchenAlert(StockAlert alert) async {
    final index = alerts.indexWhere((item) => item.id == alert.id);
    if (index < 0 || alerts[index].status != 'NUEVA') return;
    if (_client != null) {
      await _client.rpc(
        'revisar_alerta_cocina',
        params: {'p_alerta_id': alert.id, 'p_prioridad': alert.priority},
      );
      await _loadRemoteData();
    } else {
      alerts[index] = alerts[index].copyWith(status: 'REVISADA');
      await _persist();
    }
    _recordLocalAudit(
      'Revisar alerta de cocina',
      'alertas_cocina',
      alert.id.toString(),
    );
    _publish();
  }

  Future<void> reportKitchenIncident(
    RestaurantOrder order,
    String reason, {
    OrderLine? dish,
  }) async {
    final trimmed = reason.trim();
    if (trimmed.length < 5) {
      throw StateError('Describe la incidencia con al menos cinco caracteres.');
    }
    final index = orders.indexWhere((item) => item.id == order.id);
    if (index < 0) throw StateError('El pedido ya no está disponible.');
    final current = orders[index];
    if (dish != null &&
        !current.lines.any(
          (line) => dish.id == null
              ? line.menuItemId == dish.menuItemId
              : line.id == dish.id,
        )) {
      throw StateError('El platillo ya no forma parte del pedido.');
    }
    final incident = dish == null
        ? trimmed
        : '${RestaurantOrder.incidentDishPrefix}${dish.name.replaceAll(RegExp(r"[\r\n]+"), " ")}\n$trimmed';
    if (_client != null) {
      await _client.rpc(
        'reportar_incidencia_cocina',
        params: {'p_pedido_id': order.id, 'p_motivo': incident},
      );
      await _loadRemoteData();
    } else {
      orders[index] = current.copyWith(
        incident: incident,
        incidentSolution: '',
      );
      await _persist();
    }
    _recordLocalAudit(
      'Reportar incidencia de cocina',
      'pedidos',
      order.id.toString(),
    );
    _publish();
  }

  Future<void> resolveKitchenIncident(
    RestaurantOrder order,
    String solution,
  ) async {
    final trimmed = solution.trim();
    if (trimmed.length < 5) {
      throw StateError('Describe la solución con al menos cinco caracteres.');
    }
    if (order.incident.trim().isEmpty) {
      throw StateError('Este pedido no tiene una incidencia registrada.');
    }
    if (_client != null) {
      await _client.rpc(
        'resolver_incidencia_cocina',
        params: {'p_pedido_id': order.id, 'p_solucion': trimmed},
      );
      await _loadRemoteData();
    } else {
      final index = orders.indexWhere((item) => item.id == order.id);
      if (index < 0) throw StateError('No se encontró el pedido.');
      orders[index] = orders[index].copyWith(incidentSolution: trimmed);
      await _persist();
    }
    _recordLocalAudit(
      'Resolver incidencia de cocina',
      'pedidos',
      order.id.toString(),
    );
    _publish();
  }

  Future<void> advanceRequest(StockRequest request) async {
    if (request.status != 'PENDIENTE') {
      throw StateError('Solo se pueden procesar solicitudes pendientes.');
    }
    if (_client != null) {
      await _client.rpc(
        'procesar_solicitud_reabastecimiento',
        params: {'p_solicitud_id': request.id},
      );
      await _loadRemoteData();
    } else {
      final index = requests.indexWhere((item) => item.id == request.id);
      if (index < 0) throw StateError('No se encontró la solicitud.');
      final current = requests[index];
      if (current.status != 'PENDIENTE') {
        throw StateError('Solo se pueden procesar solicitudes pendientes.');
      }
      requests[index] = current.copyWith(status: 'EN_PROCESO');
      await _persist();
    }
    _recordLocalAudit(
      'Procesar solicitud de reabastecimiento',
      'solicitudes_reabastecimiento',
      request.id.toString(),
    );
    _publish();
  }

  Future<void> fulfillStockRequest(StockRequest request) async {
    if (request.status != 'EN_PROCESO') {
      throw StateError(
        'La solicitud debe estar en proceso para recibir stock.',
      );
    }
    if (_client != null) {
      final version = _sessionVersion;
      await _client.rpc(
        'recibir_solicitud_reabastecimiento',
        params: {'p_solicitud_id': request.id},
      );
      if (version != _sessionVersion) return;
      if (!await _refreshAfterWrite(version) && version == _sessionVersion) {
        final index = requests.indexWhere(
          (current) => current.id == request.id,
        );
        if (index >= 0) {
          requests[index] = requests[index].copyWith(status: 'ATENDIDO');
        }
      }
      if (version != _sessionVersion) return;
    } else {
      final requestIndex = requests.indexWhere((item) => item.id == request.id);
      if (requestIndex < 0) throw StateError('No se encontró la solicitud.');
      final current = requests[requestIndex];
      if (current.status != 'EN_PROCESO') {
        throw StateError(
          'La solicitud debe estar en proceso para recibir stock.',
        );
      }
      final receivedItems = <(int, double)>[];
      for (final line in current.lines) {
        if (!line.quantity.isFinite || line.quantity <= 0) {
          throw StateError('La cantidad recibida debe ser mayor a cero.');
        }
        final index = inventory.indexWhere(
          (item) => item.active && line.matches(item),
        );
        if (index < 0) {
          throw StateError('No se encontró el insumo "${line.itemName}".');
        }
        receivedItems.add((index, line.quantity));
      }
      for (final (index, quantity) in receivedItems) {
        final item = inventory[index];
        inventory[index] = item.copyWith(quantity: item.quantity + quantity);
      }
      requests[requestIndex] = current.copyWith(status: 'ATENDIDO');
      await _persist();
    }
    _recordLocalAudit(
      'Recibir reabastecimiento',
      'solicitudes_reabastecimiento',
      request.id.toString(),
    );
    _publish();
  }

  Future<void> cancelRequest(StockRequest request) async {
    if (request.status != 'PENDIENTE' && request.status != 'EN_PROCESO') {
      throw StateError('Solo se cancelan solicitudes pendientes o en proceso.');
    }
    if (_client != null) {
      await _client.rpc(
        'cancelar_solicitud_reabastecimiento',
        params: {'p_solicitud_id': request.id},
      );
      await _loadRemoteData();
    } else {
      final index = requests.indexWhere((item) => item.id == request.id);
      if (index < 0) throw StateError('No se encontró la solicitud.');
      final current = requests[index];
      if (!current.isOpen) {
        throw StateError(
          'Solo se cancelan solicitudes pendientes o en proceso.',
        );
      }
      requests[index] = current.copyWith(status: 'CANCELADA');
      await _persist();
    }
    _recordLocalAudit(
      'Cancelar solicitud de reabastecimiento',
      'solicitudes_reabastecimiento',
      request.id.toString(),
    );
    _publish();
  }
}
