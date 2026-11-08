enum StaffRole {
  administrator('Administrador', 'ADMINISTRADOR'),
  manager('Gerente', 'GERENTE'),
  kitchen('Cocina', 'COCINERO'),
  headChef('Jefe de cocina', 'JEFE_COCINA'),
  waiter('Mesero', 'MESERO'),
  cashier('Caja', 'CAJERO');

  const StaffRole(this.label, this.databaseValue);
  final String label;
  final String databaseValue;

  static StaffRole fromDatabase(String value) => switch (value) {
    'ADMINISTRADOR' => StaffRole.administrator,
    'GERENTE' => StaffRole.manager,
    'COCINERO' => StaffRole.kitchen,
    'JEFE_COCINA' => StaffRole.headChef,
    'CAJERO' => StaffRole.cashier,
    _ => StaffRole.waiter,
  };
}

enum TableStatus {
  available('Disponible', 'DISPONIBLE'),
  occupied('Ocupada', 'OCUPADA'),
  payment('Por cobrar', 'POR_COBRAR');

  const TableStatus(this.label, this.databaseValue);
  final String label;
  final String databaseValue;

  static TableStatus fromDatabase(String value) => switch (value) {
    'OCUPADA' => TableStatus.occupied,
    'POR_COBRAR' => TableStatus.payment,
    _ => TableStatus.available,
  };
}

enum OrderStatus {
  pending('Pendiente', 'PENDIENTE'),
  preparing('En preparación', 'EN_PREPARACION'),
  ready('Listo', 'LISTO'),
  forPayment('Por cobrar', 'POR_COBRAR'),
  paid('Pagado', 'PAGADO'),
  delivered('Entregado', 'ENTREGADO'),
  cancelled('Cancelado', 'CANCELADO');

  const OrderStatus(this.label, this.databaseValue);
  final String label;
  final String databaseValue;

  static OrderStatus fromDatabase(String value) => switch (value) {
    'EN_PREPARACION' => OrderStatus.preparing,
    'LISTO' => OrderStatus.ready,
    'POR_COBRAR' => OrderStatus.forPayment,
    'PAGADO' => OrderStatus.paid,
    'ENTREGADO' => OrderStatus.delivered,
    'CANCELADO' => OrderStatus.cancelled,
    _ => OrderStatus.pending,
  };
}

enum FulfillmentType {
  dineIn('En mesa', 'MESA'),
  takeaway('Para llevar', 'PARA_LLEVAR'),
  delivery('Delivery', 'DELIVERY');

  const FulfillmentType(this.label, this.databaseValue);
  final String label;
  final String databaseValue;

  static FulfillmentType fromDatabase(String value) => switch (value) {
    'PARA_LLEVAR' => FulfillmentType.takeaway,
    'DELIVERY' => FulfillmentType.delivery,
    _ => FulfillmentType.dineIn,
  };
}

class RestaurantTable {
  const RestaurantTable({
    required this.id,
    required this.number,
    required this.capacity,
    this.status = TableStatus.available,
    this.active = true,
  });

  final int id;
  final int number;
  final int capacity;
  final TableStatus status;
  final bool active;

  RestaurantTable copyWith({
    int? number,
    int? capacity,
    TableStatus? status,
    bool? active,
  }) => RestaurantTable(
    id: id,
    number: number ?? this.number,
    capacity: capacity ?? this.capacity,
    status: status ?? this.status,
    active: active ?? this.active,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'number': number,
    'capacity': capacity,
    'status': status.databaseValue,
    'active': active,
  };

  factory RestaurantTable.fromJson(Map<String, dynamic> json) =>
      RestaurantTable(
        id: json['id'] as int,
        number: json['number'] as int,
        capacity: json['capacity'] as int,
        status: TableStatus.fromDatabase(json['status'] as String),
        active: json['active'] as bool? ?? true,
      );
}

class MenuItem {
  const MenuItem({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    this.description = '',
    this.available = true,
  });

  final int id;
  final String name;
  final String category;
  final double price;
  final String description;
  final bool available;

  MenuItem copyWith({
    String? name,
    String? category,
    double? price,
    String? description,
    bool? available,
  }) => MenuItem(
    id: id,
    name: name ?? this.name,
    category: category ?? this.category,
    price: price ?? this.price,
    description: description ?? this.description,
    available: available ?? this.available,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'price': price,
    'description': description,
    'available': available,
  };

  factory MenuItem.fromJson(Map<String, dynamic> json) => MenuItem(
    id: json['id'] as int,
    name: json['name'] as String,
    category: json['category'] as String,
    price: (json['price'] as num).toDouble(),
    description: json['description'] as String? ?? '',
    available: json['available'] as bool? ?? true,
  );
}

class OrderLine {
  const OrderLine({
    required this.menuItemId,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    this.note = '',
    this.status = OrderStatus.pending,
    this.id,
  });

  final int? id;
  final int menuItemId;
  final String name;
  final int quantity;
  final double unitPrice;
  final String note;
  final OrderStatus status;
  double get subtotal => quantity * unitPrice;

  OrderLine copyWith({
    int? id,
    int? quantity,
    String? note,
    OrderStatus? status,
  }) => OrderLine(
    id: id ?? this.id,
    menuItemId: menuItemId,
    name: name,
    quantity: quantity ?? this.quantity,
    unitPrice: unitPrice,
    note: note ?? this.note,
    status: status ?? this.status,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'menuItemId': menuItemId,
    'name': name,
    'quantity': quantity,
    'unitPrice': unitPrice,
    'note': note,
    'status': status.databaseValue,
  };

  factory OrderLine.fromJson(Map<String, dynamic> json) => OrderLine(
    id: json['id'] as int?,
    menuItemId: json['menuItemId'] as int,
    name: json['name'] as String,
    quantity: json['quantity'] as int,
    unitPrice: (json['unitPrice'] as num).toDouble(),
    note: json['note'] as String? ?? '',
    status: OrderStatus.fromDatabase(json['status'] as String? ?? 'PENDIENTE'),
  );
}

class PaymentEntry {
  const PaymentEntry({
    required this.method,
    required this.amount,
    required this.createdAt,
    this.reference = '',
    this.cashReceived,
  });

  final String method;
  final double amount;
  final DateTime createdAt;
  final String reference;
  final double? cashReceived;

  double get change => cashReceived == null
      ? 0
      : (cashReceived! - amount).clamp(0, double.infinity).toDouble();

  Map<String, dynamic> toJson() => {
    'method': method,
    'amount': amount,
    'createdAt': createdAt.toIso8601String(),
    'reference': reference,
    'cashReceived': cashReceived,
  };

  factory PaymentEntry.fromJson(Map<String, dynamic> json) => PaymentEntry(
    method: json['method'] as String,
    amount: (json['amount'] as num).toDouble(),
    createdAt: DateTime.parse(json['createdAt'] as String),
    reference: json['reference'] as String? ?? '',
    cashReceived: (json['cashReceived'] as num?)?.toDouble(),
  );
}

class RestaurantOrder {
  const RestaurantOrder({
    required this.id,
    required this.tableId,
    required this.tableNumber,
    required this.createdAt,
    required this.lines,
    this.diners = 1,
    this.status = OrderStatus.pending,
    this.payments = const [],
    this.waiterName = 'Equipo Luxury',
    this.incident = '',
    this.parentOrderId,
    this.retirementConfirmed = false,
    this.fulfillmentType = FulfillmentType.dineIn,
    this.customerName = '',
    this.customerPhone = '',
    this.deliveryAddress = '',
    this.pendingSync = false,
    this.clientRequestId,
  });

  final int id;
  final int? tableId;
  final int tableNumber;
  final DateTime createdAt;
  final int diners;
  final List<OrderLine> lines;
  final OrderStatus status;
  final List<PaymentEntry> payments;
  final String waiterName;
  final String incident;
  final int? parentOrderId;
  final bool retirementConfirmed;
  final FulfillmentType fulfillmentType;
  final String customerName;
  final String customerPhone;
  final String deliveryAddress;
  final bool pendingSync;
  final String? clientRequestId;
  String get locationLabel => switch (fulfillmentType) {
    FulfillmentType.dineIn => 'Mesa $tableNumber',
    FulfillmentType.takeaway => 'Para llevar',
    FulfillmentType.delivery => 'Delivery',
  };

  double get total => lines.fold(0, (sum, line) => sum + line.subtotal);
  double get paid => payments.fold(0, (sum, payment) => sum + payment.amount);
  double get balance => (total - paid).clamp(0, total).toDouble();

  RestaurantOrder copyWith({
    int? id,
    List<OrderLine>? lines,
    OrderStatus? status,
    List<PaymentEntry>? payments,
    String? waiterName,
    String? incident,
    int? diners,
    int? parentOrderId,
    bool? retirementConfirmed,
  }) => RestaurantOrder(
    id: id ?? this.id,
    tableId: tableId,
    tableNumber: tableNumber,
    createdAt: createdAt,
    diners: diners ?? this.diners,
    lines: lines ?? this.lines,
    status: status ?? this.status,
    payments: payments ?? this.payments,
    waiterName: waiterName ?? this.waiterName,
    incident: incident ?? this.incident,
    parentOrderId: parentOrderId ?? this.parentOrderId,
    retirementConfirmed: retirementConfirmed ?? this.retirementConfirmed,
    fulfillmentType: fulfillmentType,
    customerName: customerName,
    customerPhone: customerPhone,
    deliveryAddress: deliveryAddress,
    pendingSync: pendingSync,
    clientRequestId: clientRequestId,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'tableId': tableId,
    'tableNumber': tableNumber,
    'createdAt': createdAt.toIso8601String(),
    'diners': diners,
    'lines': lines.map((line) => line.toJson()).toList(),
    'status': status.databaseValue,
    'payments': payments.map((payment) => payment.toJson()).toList(),
    'waiterName': waiterName,
    'incident': incident,
    'parentOrderId': parentOrderId,
    'retirementConfirmed': retirementConfirmed,
    'fulfillmentType': fulfillmentType.databaseValue,
    'customerName': customerName,
    'customerPhone': customerPhone,
    'deliveryAddress': deliveryAddress,
    'pendingSync': pendingSync,
    'clientRequestId': clientRequestId,
  };

  factory RestaurantOrder.fromJson(
    Map<String, dynamic> json,
  ) => RestaurantOrder(
    id: json['id'] as int,
    tableId: json['tableId'] as int?,
    tableNumber: json['tableNumber'] as int,
    createdAt: DateTime.parse(json['createdAt'] as String),
    diners: json['diners'] as int? ?? 1,
    lines: (json['lines'] as List<dynamic>)
        .map(
          (line) => OrderLine.fromJson(Map<String, dynamic>.from(line as Map)),
        )
        .toList(),
    status: OrderStatus.fromDatabase(json['status'] as String),
    payments: (json['payments'] as List<dynamic>? ?? [])
        .map(
          (payment) =>
              PaymentEntry.fromJson(Map<String, dynamic>.from(payment as Map)),
        )
        .toList(),
    waiterName: json['waiterName'] as String? ?? 'Equipo Luxury',
    incident: json['incident'] as String? ?? '',
    parentOrderId: json['parentOrderId'] as int?,
    retirementConfirmed: json['retirementConfirmed'] as bool? ?? false,
    fulfillmentType: FulfillmentType.fromDatabase(
      json['fulfillmentType'] as String? ?? 'MESA',
    ),
    customerName: json['customerName'] as String? ?? '',
    customerPhone: json['customerPhone'] as String? ?? '',
    deliveryAddress: json['deliveryAddress'] as String? ?? '',
    pendingSync: json['pendingSync'] as bool? ?? false,
    clientRequestId: json['clientRequestId'] as String?,
  );
}

OrderStatus kitchenStage(RestaurantOrder order) {
  if (order.lines.any((line) => line.status == OrderStatus.pending)) {
    return OrderStatus.pending;
  }
  if (order.lines.any((line) => line.status == OrderStatus.preparing)) {
    return OrderStatus.preparing;
  }
  if (order.lines.any((line) => line.status == OrderStatus.ready)) {
    return OrderStatus.ready;
  }
  return OrderStatus.delivered;
}

class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.name,
    required this.unit,
    required this.quantity,
    required this.minimum,
    this.description = '',
    this.active = true,
  });

  final int id;
  final String name;
  final String unit;
  final double quantity;
  final double minimum;
  final String description;
  final bool active;
  bool get lowStock => quantity <= minimum;

  InventoryItem copyWith({
    String? name,
    String? unit,
    double? quantity,
    double? minimum,
    String? description,
    bool? active,
  }) => InventoryItem(
    id: id,
    name: name ?? this.name,
    unit: unit ?? this.unit,
    quantity: quantity ?? this.quantity,
    minimum: minimum ?? this.minimum,
    description: description ?? this.description,
    active: active ?? this.active,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'unit': unit,
    'quantity': quantity,
    'minimum': minimum,
    'description': description,
    'active': active,
  };

  factory InventoryItem.fromJson(Map<String, dynamic> json) => InventoryItem(
    id: json['id'] as int,
    name: json['name'] as String,
    unit: json['unit'] as String,
    quantity: (json['quantity'] as num).toDouble(),
    minimum: (json['minimum'] as num).toDouble(),
    description: json['description'] as String? ?? '',
    active: json['active'] as bool? ?? true,
  );
}

class StaffMember {
  const StaffMember({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.active = true,
  });

  final String id;
  final String name;
  final String email;
  final StaffRole role;
  final bool active;

  StaffMember copyWith({
    String? name,
    String? email,
    StaffRole? role,
    bool? active,
  }) => StaffMember(
    id: id,
    name: name ?? this.name,
    email: email ?? this.email,
    role: role ?? this.role,
    active: active ?? this.active,
  );
}

class StockRequest {
  const StockRequest({
    required this.id,
    required this.itemName,
    required this.quantity,
    required this.unit,
    required this.note,
    this.status = 'PENDIENTE',
    this.priority = 'MEDIA',
    this.items = const [],
  });

  final int id;
  final String itemName;
  final double quantity;
  final String unit;
  final String note;
  final String status;
  final String priority;
  final List<StockRequestLine> items;

  StockRequest copyWith({String? status, List<StockRequestLine>? items}) =>
      StockRequest(
        id: id,
        itemName: itemName,
        quantity: quantity,
        unit: unit,
        note: note,
        status: status ?? this.status,
        priority: priority,
        items: items ?? this.items,
      );
}

class StockRequestLine {
  const StockRequestLine({
    required this.itemName,
    required this.quantity,
    required this.unit,
  });

  final String itemName;
  final double quantity;
  final String unit;
}

class StockAlert {
  const StockAlert({
    required this.id,
    required this.message,
    required this.createdAt,
    this.inventoryId,
    this.status = 'NUEVA',
    this.priority = 'MEDIA',
  });

  final int id;
  final String message;
  final DateTime createdAt;
  final int? inventoryId;
  final String status;
  final String priority;

  StockAlert copyWith({String? status, String? priority}) => StockAlert(
    id: id,
    message: message,
    createdAt: createdAt,
    inventoryId: inventoryId,
    status: status ?? this.status,
    priority: priority ?? this.priority,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'message': message,
    'createdAt': createdAt.toIso8601String(),
    'inventoryId': inventoryId,
    'status': status,
    'priority': priority,
  };

  factory StockAlert.fromJson(Map<String, dynamic> json) => StockAlert(
    id: json['id'] as int,
    message: json['message'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    inventoryId: json['inventoryId'] as int?,
    status: json['status'] as String,
    priority: json['priority'] as String,
  );
}

class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.createdAt,
    required this.action,
    required this.entity,
    required this.entityId,
    this.actorName = 'Usuario',
    this.actorRole = '',
  });

  final int id;
  final DateTime createdAt;
  final String action;
  final String entity;
  final String entityId;
  final String actorName;
  final String actorRole;
}
