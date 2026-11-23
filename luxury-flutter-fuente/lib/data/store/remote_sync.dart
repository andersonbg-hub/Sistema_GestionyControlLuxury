part of '../restaurant_store.dart';

extension RestaurantStoreRemotesync on RestaurantStore {
  Future<void> _loadRemoteData({String? profileId, StaffRole? profileRole}) {
    final version = _sessionVersion;
    final id = profileId ?? userId;
    final signedInRole = profileRole ?? role;
    final previous = _remoteLoad;

    final load = (() async {
      // A refresh requested after a write must start after any older snapshot.
      if (previous != null) {
        try {
          await previous;
        } catch (_) {
          // The new request gets its own opportunity to read the data.
        }
      }
      if (_sameSession(version, id)) {
        await _fetchRemoteData(version, id, signedInRole);
      }
    })();
    _remoteLoad = load;
    return load.whenComplete(() {
      if (identical(_remoteLoad, load)) _remoteLoad = null;
    });
  }

  Future<PostgrestList> _fetchPages(
    PostgrestTransformBuilder<PostgrestList> query,
  ) async {
    const pageSize = 500;
    final rows = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += pageSize) {
      final page = await query.range(offset, offset + pageSize - 1);
      rows.addAll(page);
      if (page.length < pageSize) return rows;
    }
  }

  Future<PostgrestList> _fetchInventory(SupabaseClient client) async {
    const columns =
        'id,nombre,descripcion,unidad,stock_actual,stock_minimo,activo';
    try {
      return await client.from('insumos').select('$columns,imagen_url');
    } on PostgrestException catch (error) {
      if (error.code != '42703' && error.code != 'PGRST204') rethrow;
      if (!error.message.contains('imagen_url')) rethrow;
      return client.from('insumos').select(columns);
    }
  }

  Future<void> _fetchRemoteData(
    int version,
    String? id,
    StaffRole? signedInRole,
  ) async {
    final client = _client!;
    final isOffice =
        signedInRole == StaffRole.manager ||
        signedInRole == StaffRole.administrator;
    final canReadRequests =
        isOffice ||
        signedInRole == StaffRole.kitchen ||
        signedInRole == StaffRole.headChef;
    final canReadCash = isOffice || signedInRole == StaffRole.cashier;
    final empty = Future<PostgrestList>.value(const []);
    final [
      remoteTables,
      remoteCategories,
      remoteMenu,
      remoteOrders,
      remoteLines,
      remotePayments,
      remoteInventory,
      remoteStaff,
      remoteRequests,
      remoteRequestItems,
      remoteAlerts,
      remoteReceipts,
      remoteAudit,
      remoteShifts,
    ] = await Future.wait<PostgrestList>([
      client.from('mesas').select().eq('activa', true).order('numero'),
      client.from('categorias').select().eq('activa', true).order('orden'),
      client.from('platillos').select().eq('activo', true).order('nombre'),
      _fetchPages(
        client
            .from('pedidos')
            .select()
            .order('creado_en', ascending: false)
            .order('id', ascending: false),
      ),
      _fetchPages(
        client
            .from('detalle_pedido')
            .select()
            .order('creado_en', ascending: true)
            .order('id', ascending: true),
      ),
      _fetchPages(
        client
            .from('pagos')
            .select()
            .order('creado_en', ascending: true)
            .order('id', ascending: true),
      ),
      _fetchInventory(client),
      if (isOffice)
        _fetchPages(client.from('usuarios').select().order('id'))
      else if (id != null)
        client.from('usuarios').select().eq('id', id)
      else
        empty,
      if (canReadRequests)
        _fetchPages(
          client
              .from('solicitudes_reabastecimiento')
              .select()
              .order('creado_en', ascending: false)
              .order('id', ascending: false),
        )
      else
        empty,
      if (canReadRequests)
        _fetchPages(
          client
              .from('solicitud_items')
              .select()
              .order('solicitud_id')
              .order('insumo_id'),
        )
      else
        empty,
      if (canReadRequests)
        _fetchPages(
          client
              .from('alertas_cocina')
              .select()
              .order('creado_en', ascending: false)
              .order('id', ascending: false),
        )
      else
        empty,
      if (canReadCash)
        _fetchPages(
          client
              .from('notas_venta')
              .select()
              .order('emitida_en', ascending: false)
              .order('id', ascending: false),
        )
      else
        empty,
      if (signedInRole == StaffRole.manager)
        _loadManagementAudit(client)
      else
        empty,
      if (signedInRole == StaffRole.cashier && id != null)
        _cashierShiftRows(client, id)
      else
        empty,
    ], eagerError: true);
    if (!_sameSession(version, id)) return;

    final nextTables = remoteTables
        .map(
          (row) => RestaurantTable(
            id: row['id'] as int,
            number: row['numero'] as int,
            capacity: row['capacidad'] as int,
            status: TableStatus.fromDatabase(row['estado'] as String),
            active: row['activa'] as bool,
            groupOrderId: row['pedido_grupo_id'] as int?,
          ),
        )
        .toList();
    final nextCategories = remoteCategories
        .map((row) => row['nombre'] as String)
        .toList();
    final categoryNames = {
      for (final row in remoteCategories) row['id']: row['nombre'] as String,
    };
    final nextMenu = remoteMenu
        .map(
          (row) => MenuItem(
            id: row['id'] as int,
            name: row['nombre'] as String,
            category: categoryNames[row['categoria_id']] ?? 'Sin categoría',
            price: (row['precio'] as num).toDouble(),
            description: row['descripcion'] as String? ?? '',
            imageUrl: (row['foto_url'] as String?)?.trim() ?? '',
            available: row['agotado'] != true,
          ),
        )
        .toList();

    final menuById = {for (final dish in nextMenu) dish.id: dish};
    final linesByOrder = <int, List<OrderLine>>{};
    for (final row in remoteLines) {
      final orderId = row['pedido_id'] as int;
      final dish = menuById[row['platillo_id']];
      linesByOrder
          .putIfAbsent(orderId, () => [])
          .add(
            OrderLine(
              id: row['id'] as int,
              menuItemId: row['platillo_id'] as int,
              name: dish?.name ?? 'Platillo',
              quantity: row['cantidad'] as int,
              unitPrice: (row['precio_unitario'] as num).toDouble(),
              note: row['observaciones'] as String? ?? '',
              status: OrderStatus.fromDatabase(row['estado'] as String),
              waiterService: row['atiende_mesero'] as bool?,
              createdAt: DateTime.tryParse(row['creado_en'] as String? ?? ''),
            ),
          );
    }
    final paymentsByOrder = <int, List<PaymentEntry>>{};
    for (final row in remotePayments) {
      final orderId = row['pedido_id'] as int;
      paymentsByOrder
          .putIfAbsent(orderId, () => [])
          .add(
            PaymentEntry(
              method: RestaurantStore._paymentLabel(row['metodo'] as String),
              amount: (row['monto'] as num).toDouble(),
              createdAt: DateTime.parse(row['creado_en'] as String),
              reference: row['referencia'] as String? ?? '',
              cashReceived: (row['efectivo_recibido'] as num?)?.toDouble(),
              cashierId: row['cajero_id'] as String?,
              shiftId: row['turno_id'] as int?,
            ),
          );
    }
    final tableNumbers = {
      for (final table in nextTables) table.id: table.number,
    };
    final staffNames = {
      for (final row in remoteStaff)
        row['id']: row['nombre_completo'] as String,
    };
    final nextOrders = remoteOrders.map((row) {
      final id = row['id'] as int;
      final tableId = row['mesa_id'] as int?;
      final lines = linesByOrder[id] ?? const <OrderLine>[];
      final databaseStatus = OrderStatus.fromDatabase(row['estado'] as String);
      return RestaurantOrder(
        id: id,
        tableId: tableId,
        tableNumber: tableId == null ? 0 : tableNumbers[tableId] ?? 0,
        createdAt: DateTime.parse(row['creado_en'] as String),
        diners: row['comensales'] as int? ?? 1,
        status:
            databaseStatus == OrderStatus.ready &&
                lines.isNotEmpty &&
                lines.every((line) => line.status == OrderStatus.delivered)
            ? OrderStatus.delivered
            : databaseStatus,
        lines: lines,
        payments: paymentsByOrder[id] ?? const [],
        incident: row['incidencia_cocina'] as String? ?? '',
        incidentSolution: row['solucion_incidencia_cocina'] as String? ?? '',
        parentOrderId: row['pedido_padre_id'] as int?,
        retirementConfirmed: row['retirada_en'] != null,
        fulfillmentType: FulfillmentType.fromDatabase(
          row['tipo_pedido'] as String? ?? 'MESA',
        ),
        customerName: row['cliente_nombre'] as String? ?? '',
        customerPhone: row['cliente_telefono'] as String? ?? '',
        deliveryAddress: row['direccion_entrega'] as String? ?? '',
        waiterId: row['mesero_id'] as String?,
        waiterName: staffNames[row['mesero_id']] ?? 'Mesero',
        groupTableIds: (row['mesas_unidas_ids'] as List<dynamic>? ?? [])
            .cast<int>(),
        groupTableNumbers: (row['mesas_unidas_numeros'] as List<dynamic>? ?? [])
            .cast<int>(),
      );
    }).toList();
    final nextInventory = remoteInventory
        .map(
          (row) => InventoryItem(
            id: row['id'] as int,
            name: row['nombre'] as String,
            unit: row['unidad'] as String,
            quantity: (row['stock_actual'] as num).toDouble(),
            minimum: (row['stock_minimo'] as num).toDouble(),
            description: row['descripcion'] as String? ?? '',
            imageUrl: row['imagen_url'] as String? ?? '',
            active: row['activo'] as bool,
          ),
        )
        .toList();
    final nextStaff = remoteStaff
        .map(
          (row) => StaffMember(
            id: row['id'] as String,
            name: row['nombre_completo'] as String,
            email: row['correo'] as String? ?? '',
            role: StaffRole.fromDatabase(row['rol'] as String),
            active: row['activo'] as bool,
            employmentStatus:
                row['estado_laboral'] as String? ??
                ((row['activo'] as bool) ? 'ACTIVO' : 'INACTIVO'),
            department: row['departamento'] as String? ?? '',
            documentId: row['documento_identidad'] as String? ?? '',
            personalEmail: row['correo_personal'] as String? ?? '',
            phone: row['telefono'] as String? ?? '',
            address: row['direccion'] as String? ?? '',
            photoPath: row['foto_path'] as String? ?? '',
          ),
        )
        .toList();
    final inventoryById = {for (final item in nextInventory) item.id: item};
    final linesByRequest = <int, List<Map<String, dynamic>>>{};
    for (final row in remoteRequestItems) {
      linesByRequest.putIfAbsent(row['solicitud_id'] as int, () => []).add(row);
    }
    final nextRequests = remoteRequests.map((row) {
      final requestId = row['id'] as int;
      final rows = linesByRequest[requestId] ?? const [];
      final requestLines = rows
          .map((item) {
            final stock = inventoryById[item['insumo_id']];
            return StockRequestLine(
              inventoryId: item['insumo_id'] as int?,
              itemName: stock?.name ?? 'Insumo',
              quantity: (item['cantidad'] as num).toDouble(),
              unit: stock?.unit ?? 'UNIDAD',
            );
          })
          .toList(growable: false);
      final firstLine = requestLines.firstOrNull;
      return StockRequest(
        id: requestId,
        itemName: firstLine?.itemName ?? 'Insumo',
        quantity: firstLine?.quantity ?? 0,
        unit: firstLine?.unit ?? 'UNIDAD',
        note: row['observaciones'] as String? ?? '',
        status: row['estado'] as String,
        priority: row['prioridad'] as String,
        items: requestLines,
      );
    }).toList();
    final nextAlerts = remoteAlerts
        .map(
          (row) => StockAlert(
            id: row['id'] as int,
            inventoryId: row['insumo_id'] as int?,
            message: row['mensaje'] as String,
            createdAt: DateTime.parse(row['creado_en'] as String),
            status: row['estado'] as String,
            priority: row['prioridad'] as String? ?? 'MEDIA',
          ),
        )
        .toList();
    final ordersById = {for (final order in nextOrders) order.id: order};
    final nextReceipts = remoteReceipts
        .map(
          (row) => {
            'id': row['id'],
            'code': 'NV-${row['numero']}',
            'orderId': row['pedido_id'],
            'tableNumber': ordersById[row['pedido_id']]?.tableNumber ?? 0,
            'locationLabel':
                ordersById[row['pedido_id']]?.locationLabel ??
                'Pedido #${row['pedido_id']}',
            'total': row['total'],
            'createdAt': row['emitida_en'],
            'status': row['estado'],
            'voidReason': row['motivo_anulacion'],
            'payments': paymentsByOrder[row['pedido_id']] ?? const [],
          },
        )
        .toList();
    final staffById = {for (final member in nextStaff) member.id: member};
    final nextAuditEntries = remoteAudit.map((row) {
      final member = staffById[row['actor_id']];
      final savedName = row['actor_nombre'] as String? ?? '';
      return AuditEntry(
        id: row['id'] as int,
        createdAt: DateTime.parse(row['creado_en'] as String),
        action: row['accion'] as String,
        entity: row['entidad'] as String,
        entityId: row['entidad_id']?.toString() ?? '',
        actorRole: row['actor_rol'] as String? ?? '',
        actorName: AuditEntry.isGenericName(savedName)
            ? member?.name ?? savedName
            : savedName,
        actorAccount: (row['actor_cuenta'] as String?) ?? member?.email ?? '',
      );
    }).toList();
    final remoteShift = _shiftFromRow(remoteShifts.firstOrNull);

    _remoteSupportsTableGroups = remoteTables.any(
      (row) => row.containsKey('pedido_grupo_id'),
    );
    tables
      ..clear()
      ..addAll(nextTables);
    categories
      ..clear()
      ..addAll(nextCategories);
    menu
      ..clear()
      ..addAll(nextMenu);
    orders
      ..clear()
      ..addAll(nextOrders);
    inventory
      ..clear()
      ..addAll(nextInventory);
    staff
      ..clear()
      ..addAll(nextStaff);
    requests
      ..clear()
      ..addAll(nextRequests);
    alerts
      ..clear()
      ..addAll(nextAlerts);
    receipts
      ..clear()
      ..addAll(nextReceipts);
    auditEntries
      ..clear()
      ..addAll(nextAuditEntries);
    _shift = remoteShift;
    lastOnlineSyncAt = _now();
    _showPendingOrderQueue(pendingOrders);
    if (userId != null) await _saveRemoteCache();
  }

  Future<void> _saveRemoteCache() async {
    try {
      await _persist();
    } catch (_) {
      // A full local cache must not turn a successful cloud operation into an error.
    }
  }

  Future<List<Map<String, dynamic>>> _loadManagementAudit(
    SupabaseClient client,
  ) async {
    const columns = 'id,actor_id,actor_rol,accion,entidad,entidad_id,creado_en';
    final actions = AuditEntry.movements.keys
        .map((action) => '"$action"')
        .join(',');
    Future<List<Map<String, dynamic>>> load(String projection) => client
        .from('auditoria_movimientos')
        .select(projection)
        .or('accion.in.($actions),and(accion.eq.INSERT,entidad.eq.pagos)')
        .order('creado_en', ascending: false)
        .order('id', ascending: false)
        .limit(200);

    try {
      return await load('$columns,actor_nombre,actor_cuenta');
    } on PostgrestException catch (error) {
      if (error.code != '42703' && error.code != 'PGRST204') rethrow;
      return load(columns);
    }
  }

  void _subscribeRealtime() {
    if (_client == null || _realtime != null) return;
    final version = _sessionVersion;
    _realtime = _client
        .channel('luxury-restaurant-live-$version')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pedidos',
          callback: (_) => _scheduleRealtimeRefresh(version),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'detalle_pedido',
          callback: (_) => _scheduleRealtimeRefresh(version),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'mesas',
          callback: (_) => _scheduleRealtimeRefresh(version),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'platillos',
          callback: (_) => _scheduleRealtimeRefresh(version),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'alertas_cocina',
          callback: (_) => _scheduleRealtimeRefresh(version),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'auditoria_movimientos',
          callback: (_) => _scheduleRealtimeRefresh(version),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'turnos_caja',
          callback: (_) => _scheduleRealtimeRefresh(version),
        )
        .subscribe((status, _) {
          if (_sessionVersion == version &&
              status == RealtimeSubscribeStatus.subscribed &&
              pendingOrders.isNotEmpty) {
            unawaited(_syncPendingOrdersSafely());
          }
        });
  }

  void _scheduleRealtimeRefresh(int version) {
    if (_sessionVersion != version) return;
    if (_realtimeRefreshRunning) {
      _realtimeRefreshPending = true;
      return;
    }
    _realtimeRefreshTimer ??= Timer(const Duration(milliseconds: 320), () {
      _realtimeRefreshTimer = null;
      unawaited(_refreshFromRealtime(version));
    });
  }

  Future<void> _refreshFromRealtime(int version) async {
    _realtimeRefreshRunning = true;
    try {
      await refresh(reconcilePayments: false);
    } catch (_) {
      if (_sessionVersion == version) {
        errorMessage =
            'No se pudo actualizar en vivo. Puedes recargar desde el menú de usuario.';
        _publish();
      }
    } finally {
      if (_sessionVersion == version) {
        _realtimeRefreshRunning = false;
        if (_realtimeRefreshPending) {
          _realtimeRefreshPending = false;
          _scheduleRealtimeRefresh(version);
        }
      }
    }
  }

  Future<void> refresh({bool reconcilePayments = true}) async {
    final version = _sessionVersion;
    if (_client != null) await _loadRemoteData();
    if (_sessionVersion != version) return;
    if (reconcilePayments) _paymentsToVerify.clear();
    errorMessage = null;
    _publish();
  }

  Future<bool> _refreshAfterWrite(int version) async {
    try {
      await _loadRemoteData();
      if (_sessionVersion == version) errorMessage = null;
      return true;
    } catch (_) {
      if (_sessionVersion == version) {
        errorMessage =
            'El cambio se guardó. Usa «Actualizar información» para ver los datos actuales.';
      }
      return false;
    }
  }

  Future<void> resetDemo() async {
    if (!isDemo) {
      throw StateError(
        'El reinicio de demostración solo está disponible en modo local.',
      );
    }
    tables.clear();
    menu.clear();
    orders.clear();
    inventory.clear();
    staff.clear();
    requests.clear();
    alerts.clear();
    categories.clear();
    receipts.clear();
    auditEntries.clear();
    _shift = _noCashierShift;
    _seed();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(RestaurantStore._storageKey);
    _publish();
  }
}
