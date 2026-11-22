// Lima uses UTC−05:00 for the restaurant's current operating dates.
const _limaOffset = Duration(hours: 5);

DateTime limaWallTime(DateTime time) => time.toUtc().subtract(_limaOffset);

DateTime limaBusinessDay(DateTime time) {
  final lima = limaWallTime(time);
  return DateTime.utc(lima.year, lima.month, lima.day);
}

bool isSameLimaBusinessDay(DateTime first, DateTime second) =>
    limaBusinessDay(first) == limaBusinessDay(second);

DateTime nextLimaMidnight(DateTime time) =>
    limaBusinessDay(time).add(const Duration(days: 1)).add(_limaOffset);

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

int staffRank(StaffRole role) => switch (role) {
  StaffRole.manager => 100,
  StaffRole.administrator => 80,
  StaffRole.headChef => 60,
  StaffRole.kitchen => 40,
  StaffRole.cashier => 40,
  StaffRole.waiter => 20,
};

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
    this.groupOrderId,
  });

  final int id;
  final int number;
  final int capacity;
  final TableStatus status;
  final bool active;
  final int? groupOrderId;

  RestaurantTable copyWith({
    int? number,
    int? capacity,
    TableStatus? status,
    bool? active,
    int? groupOrderId,
    bool clearGroup = false,
  }) => RestaurantTable(
    id: id,
    number: number ?? this.number,
    capacity: capacity ?? this.capacity,
    status: status ?? this.status,
    active: active ?? this.active,
    groupOrderId: clearGroup ? null : groupOrderId ?? this.groupOrderId,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'number': number,
    'capacity': capacity,
    'status': status.databaseValue,
    'active': active,
    if (groupOrderId != null) 'groupOrderId': groupOrderId,
  };

  factory RestaurantTable.fromJson(Map<String, dynamic> json) =>
      RestaurantTable(
        id: json['id'] as int,
        number: json['number'] as int,
        capacity: json['capacity'] as int,
        status: TableStatus.fromDatabase(json['status'] as String),
        active: json['active'] as bool? ?? true,
        groupOrderId: json['groupOrderId'] as int?,
      );
}

class MenuItem {
  const MenuItem({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    this.description = '',
    this.imageUrl = '',
    this.available = true,
  });

  final int id;
  final String name;
  final String category;
  final double price;
  final String description;
  final String imageUrl;
  final bool available;

  bool get servedByWaiter => switch (category.trim().toLowerCase()) {
    'bebida' || 'bebidas' || 'postre' || 'postres' => true,
    _ => false,
  };

  MenuItem copyWith({
    String? name,
    String? category,
    double? price,
    String? description,
    String? imageUrl,
    bool? available,
  }) => MenuItem(
    id: id,
    name: name ?? this.name,
    category: category ?? this.category,
    price: price ?? this.price,
    description: description ?? this.description,
    imageUrl: imageUrl ?? this.imageUrl,
    available: available ?? this.available,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'price': price,
    'description': description,
    'imageUrl': imageUrl,
    'available': available,
  };

  factory MenuItem.fromJson(Map<String, dynamic> json) => MenuItem(
    id: json['id'] as int,
    name: json['name'] as String,
    category: json['category'] as String,
    price: (json['price'] as num).toDouble(),
    description: json['description'] as String? ?? '',
    imageUrl: json['imageUrl'] as String? ?? '',
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
    this.waiterService,
    this.createdAt,
  });

  final int? id;
  final int menuItemId;
  final String name;
  final int quantity;
  final double unitPrice;
  final String note;
  final OrderStatus status;
  final bool? waiterService;
  final DateTime? createdAt;
  double get subtotal => quantity * unitPrice;

  OrderLine copyWith({
    int? id,
    int? quantity,
    String? note,
    OrderStatus? status,
    bool? waiterService,
    DateTime? createdAt,
  }) => OrderLine(
    id: id ?? this.id,
    menuItemId: menuItemId,
    name: name,
    quantity: quantity ?? this.quantity,
    unitPrice: unitPrice,
    note: note ?? this.note,
    status: status ?? this.status,
    waiterService: waiterService ?? this.waiterService,
    createdAt: createdAt ?? this.createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'menuItemId': menuItemId,
    'name': name,
    'quantity': quantity,
    'unitPrice': unitPrice,
    'note': note,
    'status': status.databaseValue,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (waiterService != null) 'waiterService': waiterService,
  };

  factory OrderLine.fromJson(Map<String, dynamic> json) => OrderLine(
    id: json['id'] as int?,
    menuItemId: json['menuItemId'] as int,
    name: json['name'] as String,
    quantity: json['quantity'] as int,
    unitPrice: (json['unitPrice'] as num).toDouble(),
    note: json['note'] as String? ?? '',
    status: OrderStatus.fromDatabase(json['status'] as String? ?? 'PENDIENTE'),
    waiterService: json['waiterService'] as bool?,
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
  );
}

class PaymentEntry {
  const PaymentEntry({
    required this.method,
    required this.amount,
    required this.createdAt,
    this.reference = '',
    this.cashReceived,
    this.cashierId,
    this.shiftId,
  });

  final String method;
  final double amount;
  final DateTime createdAt;
  final String reference;
  final double? cashReceived;
  final String? cashierId;
  final int? shiftId;

  double get change => cashReceived == null
      ? 0
      : (cashReceived! - amount).clamp(0, double.infinity).toDouble();

  Map<String, dynamic> toJson() => {
    'method': method,
    'amount': amount,
    'createdAt': createdAt.toIso8601String(),
    'reference': reference,
    'cashReceived': cashReceived,
    'cashierId': cashierId,
    'shiftId': shiftId,
  };

  factory PaymentEntry.fromJson(Map<String, dynamic> json) => PaymentEntry(
    method: json['method'] as String,
    amount: (json['amount'] as num).toDouble(),
    createdAt: DateTime.parse(json['createdAt'] as String),
    reference: json['reference'] as String? ?? '',
    cashReceived: (json['cashReceived'] as num?)?.toDouble(),
    cashierId: json['cashierId'] as String?,
    shiftId: json['shiftId'] as int?,
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
    this.incidentSolution = '',
    this.parentOrderId,
    this.retirementConfirmed = false,
    this.fulfillmentType = FulfillmentType.dineIn,
    this.customerName = '',
    this.customerPhone = '',
    this.deliveryAddress = '',
    this.pendingSync = false,
    this.clientRequestId,
    this.appendsToAccount = false,
    this.waiterId,
    this.groupTableIds = const [],
    this.groupTableNumbers = const [],
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
  final String? waiterId;
  final String incident;
  final String incidentSolution;

  static const incidentDishPrefix = 'Platillo: ';

  (String?, String) get kitchenIncident {
    final separator = incident.indexOf('\n');
    if (incident.startsWith(incidentDishPrefix) &&
        separator > incidentDishPrefix.length) {
      return (
        incident.substring(incidentDishPrefix.length, separator),
        incident.substring(separator + 1),
      );
    }
    return (null, incident);
  }

  final int? parentOrderId;
  final bool retirementConfirmed;
  final FulfillmentType fulfillmentType;
  final String customerName;
  final String customerPhone;
  final String deliveryAddress;
  final bool pendingSync;
  final String? clientRequestId;
  final bool appendsToAccount;
  final List<int> groupTableIds;
  final List<int> groupTableNumbers;

  bool get hasJoinedTables => groupTableIds.length > 1;
  String get locationLabel => switch (fulfillmentType) {
    FulfillmentType.dineIn when groupTableNumbers.length > 1 =>
      joinedTablesLabel(groupTableNumbers),
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
    String? waiterId,
    String? incident,
    String? incidentSolution,
    int? diners,
    int? parentOrderId,
    bool? retirementConfirmed,
    bool? pendingSync,
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
    waiterId: waiterId ?? this.waiterId,
    incident: incident ?? this.incident,
    incidentSolution: incidentSolution ?? this.incidentSolution,
    parentOrderId: parentOrderId ?? this.parentOrderId,
    retirementConfirmed: retirementConfirmed ?? this.retirementConfirmed,
    fulfillmentType: fulfillmentType,
    customerName: customerName,
    customerPhone: customerPhone,
    deliveryAddress: deliveryAddress,
    pendingSync: pendingSync ?? this.pendingSync,
    clientRequestId: clientRequestId,
    appendsToAccount: appendsToAccount,
    groupTableIds: groupTableIds,
    groupTableNumbers: groupTableNumbers,
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
    'waiterId': waiterId,
    'incident': incident,
    'incidentSolution': incidentSolution,
    'parentOrderId': parentOrderId,
    'retirementConfirmed': retirementConfirmed,
    'fulfillmentType': fulfillmentType.databaseValue,
    'customerName': customerName,
    'customerPhone': customerPhone,
    'deliveryAddress': deliveryAddress,
    'pendingSync': pendingSync,
    'clientRequestId': clientRequestId,
    if (appendsToAccount) 'appendsToAccount': true,
    if (hasJoinedTables) 'groupTableIds': groupTableIds,
    if (hasJoinedTables) 'groupTableNumbers': groupTableNumbers,
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
    waiterId: json['waiterId'] as String? ?? json['mesero_id'] as String?,
    incident: json['incident'] as String? ?? '',
    incidentSolution: json['incidentSolution'] as String? ?? '',
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
    appendsToAccount: json['appendsToAccount'] as bool? ?? false,
    groupTableIds: (json['groupTableIds'] as List<dynamic>? ?? []).cast<int>(),
    groupTableNumbers: (json['groupTableNumbers'] as List<dynamic>? ?? [])
        .cast<int>(),
  );
}

String joinedTablesLabel(Iterable<int> tableNumbers) =>
    'Mesas ${(tableNumbers.toList()..sort()).join(' + ')}';

OrderStatus kitchenStage(RestaurantOrder order) => orderLineStage(order.lines);

OrderStatus orderLineStage(Iterable<OrderLine> lines) {
  if (lines.any((line) => line.status == OrderStatus.pending)) {
    return OrderStatus.pending;
  }
  if (lines.any((line) => line.status == OrderStatus.preparing)) {
    return OrderStatus.preparing;
  }
  if (lines.any((line) => line.status == OrderStatus.ready)) {
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
    this.imageUrl = '',
    this.active = true,
  });

  final int id;
  final String name;
  final String unit;
  final double quantity;
  final double minimum;
  final String description;
  final String imageUrl;
  final bool active;
  bool get lowStock => quantity <= minimum;

  InventoryItem copyWith({
    String? name,
    String? unit,
    double? quantity,
    double? minimum,
    String? description,
    String? imageUrl,
    bool? active,
  }) => InventoryItem(
    id: id,
    name: name ?? this.name,
    unit: unit ?? this.unit,
    quantity: quantity ?? this.quantity,
    minimum: minimum ?? this.minimum,
    description: description ?? this.description,
    imageUrl: imageUrl ?? this.imageUrl,
    active: active ?? this.active,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'unit': unit,
    'quantity': quantity,
    'minimum': minimum,
    'description': description,
    'imageUrl': imageUrl,
    'active': active,
  };

  factory InventoryItem.fromJson(Map<String, dynamic> json) => InventoryItem(
    id: json['id'] as int,
    name: json['name'] as String,
    unit: json['unit'] as String,
    quantity: (json['quantity'] as num).toDouble(),
    minimum: (json['minimum'] as num).toDouble(),
    description: json['description'] as String? ?? '',
    imageUrl: json['imageUrl'] as String? ?? '',
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
    this.employmentStatus = 'ACTIVO',
    this.department = '',
    this.documentId = '',
    this.personalEmail = '',
    this.phone = '',
    this.address = '',
    this.photoPath = '',
  });

  final String id;
  final String name;
  final String email;
  final StaffRole role;
  final bool active;
  final String employmentStatus;
  final String department;
  final String documentId;
  final String personalEmail;
  final String phone;
  final String address;
  final String photoPath;
  String get employeeCode {
    final normalizedId = id.replaceAll('-', '').toUpperCase();
    return 'EMP-${normalizedId.length > 8 ? normalizedId.substring(0, 8) : normalizedId}';
  }

  StaffMember copyWith({
    String? name,
    String? email,
    StaffRole? role,
    bool? active,
    String? employmentStatus,
    String? department,
    String? documentId,
    String? personalEmail,
    String? phone,
    String? address,
    String? photoPath,
  }) => StaffMember(
    id: id,
    name: name ?? this.name,
    email: email ?? this.email,
    role: role ?? this.role,
    active: active ?? this.active,
    employmentStatus: employmentStatus ?? this.employmentStatus,
    department: department ?? this.department,
    documentId: documentId ?? this.documentId,
    personalEmail: personalEmail ?? this.personalEmail,
    phone: phone ?? this.phone,
    address: address ?? this.address,
    photoPath: photoPath ?? this.photoPath,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'role': role.databaseValue,
    'active': active,
    'employmentStatus': employmentStatus,
    'department': department,
    'documentId': documentId,
    'personalEmail': personalEmail,
    'phone': phone,
    'address': address,
    'photoPath': photoPath,
  };

  factory StaffMember.fromJson(Map<String, dynamic> json) => StaffMember(
    id: json['id'] as String,
    name: json['name'] as String,
    email: json['email'] as String,
    role: StaffRole.fromDatabase(json['role'] as String),
    active: json['active'] as bool? ?? true,
    employmentStatus:
        json['employmentStatus'] as String? ??
        ((json['active'] as bool? ?? true) ? 'ACTIVO' : 'INACTIVO'),
    department: json['department'] as String? ?? '',
    documentId: json['documentId'] as String? ?? '',
    personalEmail: json['personalEmail'] as String? ?? '',
    phone: json['phone'] as String? ?? '',
    address: json['address'] as String? ?? '',
    photoPath: json['photoPath'] as String? ?? '',
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

  bool get isOpen => status == 'PENDIENTE' || status == 'EN_PROCESO';

  Iterable<StockRequestLine> get lines => items.isEmpty
      ? [StockRequestLine(itemName: itemName, quantity: quantity, unit: unit)]
      : items;

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
    this.inventoryId,
  });

  final String itemName;
  final double quantity;
  final String unit;
  final int? inventoryId;

  bool matches(InventoryItem item) => inventoryId == null
      ? itemName.trim().toLowerCase() == item.name.trim().toLowerCase()
      : inventoryId == item.id;
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
    this.actorName = '',
    this.actorRole = '',
    this.actorAccount = '',
  });

  final int id;
  final DateTime createdAt;
  final String action;
  final String entity;
  final String entityId;
  final String actorName;
  final String actorRole;
  final String actorAccount;

  static const movements = {
    'Registrar pago': ('Pago registrado', 'Caja'),
    'Anular nota de venta': ('Nota de venta anulada', 'Caja'),
    'Abrir turno de caja': ('Turno de caja abierto', 'Caja'),
    'Cerrar turno de caja': ('Turno de caja cerrado', 'Caja'),
    'Abrir caja': ('Turno de caja abierto', 'Caja'),
    'Cerrar caja': ('Turno de caja cerrado', 'Caja'),
    'Cancelar pedido': ('Pedido cancelado', 'Pedidos'),
    'Solicitar cuenta': ('Cuenta solicitada', 'Pedidos'),
    'Reportar incidencia de cocina': (
      'Incidencia de cocina reportada',
      'Cocina',
    ),
    'Resolver incidencia de cocina': (
      'Incidencia de cocina solucionada',
      'Cocina',
    ),
    'Crear alerta de cocina': ('Alerta de cocina registrada', 'Cocina'),
    'Procesar solicitud de reabastecimiento': (
      'Reposición puesta en proceso',
      'Inventario',
    ),
    'Recibir reabastecimiento': ('Reposición recibida', 'Inventario'),
    'Cancelar solicitud de reabastecimiento': (
      'Reposición cancelada',
      'Inventario',
    ),
    'Archivar insumo': ('Insumo archivado', 'Inventario'),
    'Crear usuario': ('Cuenta de usuario creada', 'Usuarios'),
    'Cambiar rol de usuario': ('Rol de usuario cambiado', 'Usuarios'),
    'Activar usuario': ('Cuenta de usuario activada', 'Usuarios'),
    'Desactivar usuario': ('Cuenta de usuario desactivada', 'Usuarios'),
    'Restablecer contraseña de usuario': (
      'Contraseña restablecida por Administración',
      'Usuarios',
    ),
  };

  (String, String)? get movement => action == 'INSERT' && entity == 'pagos'
      ? movements['Registrar pago']
      : movements[action];

  String get actorRoleLabel => switch (actorRole.trim().toUpperCase()) {
    'COCINERO' || 'COCINA' => 'Cocinero',
    'CAJERO' || 'CAJA' => 'Cajero',
    'JEFE_COCINA' || 'JEFE DE COCINA' => 'Jefe de cocina',
    'MESERO' => 'Mesero',
    'ADMINISTRADOR' => 'Administrador',
    'GERENTE' => 'Gerente',
    'SISTEMA' => 'Sistema',
    _ => '',
  };

  static bool isGenericName(String name) => const {
    '',
    'usuario',
    'usuario desactivado',
    'mesero',
    'cocinero',
    'cocina',
    'cajero',
    'caja',
    'jefe de cocina',
    'administrador',
    'gerente',
    'sistema',
  }.contains(name.trim().toLowerCase().replaceAll('_', ' '));

  String get actorLabel => !isGenericName(actorName)
      ? actorName.trim()
      : actorAccount.trim().isNotEmpty
      ? actorAccount.trim()
      : actorRoleLabel == 'Sistema'
      ? 'Sistema'
      : 'Autor sin identificar';
}
