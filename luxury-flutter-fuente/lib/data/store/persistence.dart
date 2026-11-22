part of '../restaurant_store.dart';

extension RestaurantStorePersistence on RestaurantStore {
  Future<void> _persist() async {
    final id = userId;
    final version = _sessionVersion;
    if (isConnected && id == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (isConnected && !_sameSession(version, id)) return;
    final saved = {
      'userId': userId,
      'role': role?.databaseValue,
      'displayName': displayName,
      'lastOnlineSyncAt': lastOnlineSyncAt?.toIso8601String(),
      if (isConnected) 'supportsTableGroups': _remoteSupportsTableGroups,
      'staff': staff.map((member) => member.toJson()).toList(),
      'tables': tables.map((item) => item.toJson()).toList(),
      'menu': menu.map((item) => item.toJson()).toList(),
      'orders': orders
          .where((item) => !item.pendingSync)
          .map((item) => item.toJson())
          .toList(),
      'pendingOrders': pendingOrders.map((item) => item.toJson()).toList(),
      'inventory': inventory.map((item) => item.toJson()).toList(),
      'requests': requests
          .map(
            (item) => {
              'id': item.id,
              'itemName': item.itemName,
              'quantity': item.quantity,
              'unit': item.unit,
              'note': item.note,
              'status': item.status,
              'priority': item.priority,
              'items': [
                for (final line in item.items)
                  {
                    'inventoryId': line.inventoryId,
                    'itemName': line.itemName,
                    'quantity': line.quantity,
                    'unit': line.unit,
                  },
              ],
            },
          )
          .toList(),
      'alerts': alerts.map((alert) => alert.toJson()).toList(),
      'categories': categories,
      'receipts': receipts,
      'auditEntries': auditEntries
          .map(
            (entry) => {
              'id': entry.id,
              'createdAt': entry.createdAt.toIso8601String(),
              'action': entry.action,
              'entity': entry.entity,
              'entityId': entry.entityId,
              'actorName': entry.actorName,
              'actorRole': entry.actorRole,
              'actorAccount': entry.actorAccount,
            },
          )
          .toList(),
      'shiftOpen': _shift.open,
      'shiftId': _shift.id,
      'shiftOpenedAt': _shift.openedAt?.toIso8601String(),
      'shiftClosedAt': _shift.closedAt?.toIso8601String(),
      'openingCash': _shift.openingCash,
      'closedCash': _shift.closingCash,
      'nextId': _nextId,
    };
    final key = isDemo
        ? RestaurantStore._storageKey
        : '${RestaurantStore._remoteCachePrefix}$id';
    if (!await prefs.setString(key, jsonEncode(saved))) {
      throw StateError('El navegador no pudo guardar los cambios locales.');
    }
  }

  void _restore(Map<String, dynamic> saved) {
    _remoteSupportsTableGroups = saved['supportsTableGroups'] == true;
    staff
      ..clear()
      ..addAll(
        (saved['staff'] as List<dynamic>? ?? []).map(
          (row) => StaffMember.fromJson(Map<String, dynamic>.from(row as Map)),
        ),
      );
    tables
      ..clear()
      ..addAll(
        (saved['tables'] as List<dynamic>).map(
          (row) =>
              RestaurantTable.fromJson(Map<String, dynamic>.from(row as Map)),
        ),
      );
    menu
      ..clear()
      ..addAll(
        (saved['menu'] as List<dynamic>).map(
          (row) => MenuItem.fromJson(Map<String, dynamic>.from(row as Map)),
        ),
      );
    orders
      ..clear()
      ..addAll(
        (saved['orders'] as List<dynamic>).map(
          (row) =>
              RestaurantOrder.fromJson(Map<String, dynamic>.from(row as Map)),
        ),
      );
    pendingOrders
      ..clear()
      ..addAll(
        (saved['pendingOrders'] as List<dynamic>? ?? []).map(
          (row) =>
              RestaurantOrder.fromJson(Map<String, dynamic>.from(row as Map)),
        ),
      );
    inventory
      ..clear()
      ..addAll(
        (saved['inventory'] as List<dynamic>).map(
          (row) =>
              InventoryItem.fromJson(Map<String, dynamic>.from(row as Map)),
        ),
      );
    requests
      ..clear()
      ..addAll(
        (saved['requests'] as List<dynamic>).map((row) {
          final json = Map<String, dynamic>.from(row as Map);
          return StockRequest(
            id: json['id'] as int,
            itemName: json['itemName'] as String,
            quantity: (json['quantity'] as num).toDouble(),
            unit: json['unit'] as String,
            note: json['note'] as String,
            status: json['status'] as String,
            priority: json['priority'] as String,
            items: [
              for (final line in json['items'] as List<dynamic>? ?? [])
                StockRequestLine(
                  inventoryId: line['inventoryId'] as int?,
                  itemName: line['itemName'] as String,
                  quantity: (line['quantity'] as num).toDouble(),
                  unit: line['unit'] as String,
                ),
            ],
          );
        }),
      );
    alerts
      ..clear()
      ..addAll(
        (saved['alerts'] as List<dynamic>? ?? []).map(
          (row) => StockAlert.fromJson(Map<String, dynamic>.from(row as Map)),
        ),
      );
    categories
      ..clear()
      ..addAll((saved['categories'] as List<dynamic>).cast<String>());
    receipts
      ..clear()
      ..addAll(
        (saved['receipts'] as List<dynamic>).map(
          (row) => Map<String, dynamic>.from(row as Map),
        ),
      );
    auditEntries
      ..clear()
      ..addAll(
        (saved['auditEntries'] as List<dynamic>? ?? []).map((row) {
          final value = Map<String, dynamic>.from(row as Map);
          return AuditEntry(
            id: value['id'] as int,
            createdAt: DateTime.parse(value['createdAt'] as String),
            action: value['action'] as String,
            entity: value['entity'] as String,
            entityId: value['entityId'] as String,
            actorName: value['actorName'] as String? ?? 'Usuario',
            actorRole: value['actorRole'] as String? ?? '',
            actorAccount: value['actorAccount'] as String? ?? '',
          );
        }),
      );
    _shift = (
      id: saved['shiftId'] as int?,
      openedAt: DateTime.tryParse(saved['shiftOpenedAt'] as String? ?? ''),
      closedAt: DateTime.tryParse(saved['shiftClosedAt'] as String? ?? ''),
      open: saved['shiftOpen'] as bool? ?? false,
      openingCash: (saved['openingCash'] as num?)?.toDouble() ?? 0,
      closingCash: (saved['closedCash'] as num?)?.toDouble() ?? 0,
    );
    _nextId = saved['nextId'] as int? ?? 500;
  }

  void _replaceMenu(MenuItem updated) {
    final index = menu.indexWhere((item) => item.id == updated.id);
    menu[index] = updated;
  }

  void _recalculateTable(int? tableId) {
    if (tableId == null) return;
    final table = _tableById(tableId);
    final group = table == null ? null : tableGroupFor(table);
    if (group != null) {
      _setJoinedTableStatuses(group);
      return;
    }
    final tableOrders = orders.where((order) => order.tableId == tableId);
    final status =
        tableOrders.any((order) => order.status == OrderStatus.forPayment)
        ? TableStatus.payment
        : tableOrders.any((order) => !order.retirementConfirmed)
        ? TableStatus.occupied
        : TableStatus.available;
    final index = tables.indexWhere((table) => table.id == tableId);
    if (index >= 0) tables[index] = tables[index].copyWith(status: status);
  }

  void _recordLocalAudit(String action, String entity, String entityId) {
    if (!isDemo || role == null) return;
    auditEntries.insert(
      0,
      AuditEntry(
        id: _nextId++,
        createdAt: DateTime.now(),
        action: action,
        entity: entity,
        entityId: entityId,
        actorName: currentStaffMember?.name ?? displayName,
        actorRole: role!.databaseValue,
        actorAccount: currentStaffMember?.email ?? '',
      ),
    );
    unawaited(_persist());
  }
}
