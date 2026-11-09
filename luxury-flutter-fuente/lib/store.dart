import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

class RestaurantStore extends ChangeNotifier {
  RestaurantStore({SupabaseClient? client}) : _client = client {
    if (client == null) {
      _seed();
    } else {
      shiftOpen = false;
      openingCash = 0;
      _authSubscription = client.auth.onAuthStateChange.listen((state) {
        final authUser = state.session?.user;
        if (state.event == AuthChangeEvent.passwordRecovery) {
          _passwordRecoveryPending = true;
          mustChangePassword = true;
          final user = state.session?.user;
          if (user != null && role == null) {
            unawaited(
              _loadProfile(user.id).catchError((Object error) {
                errorMessage = 'No se pudo validar la recuperación: $error';
                notifyListeners();
              }),
            );
          }
          notifyListeners();
        }
        if (state.event == AuthChangeEvent.signedIn &&
            authUser != null &&
            !_signInInProgress &&
            userId != authUser.id) {
          unawaited(_handleExternalSignIn(authUser.id));
        }
        if (state.event == AuthChangeEvent.signedOut && role != null) {
          _clearConnectedState();
          notifyListeners();
        }
      });
    }
  }

  static const _storageKey = 'luxury.restaurant.demo.v1';
  static const _remoteCachePrefix = 'luxury.restaurant.offline.v1.';
  final SupabaseClient? _client;
  final List<RestaurantTable> tables = [];
  final List<MenuItem> menu = [];
  final List<RestaurantOrder> orders = [];
  final List<RestaurantOrder> pendingOrders = [];
  final List<InventoryItem> inventory = [];
  final List<StaffMember> staff = [];
  final List<StockRequest> requests = [];
  final List<StockAlert> alerts = [];
  final List<String> categories = [];
  final List<Map<String, dynamic>> receipts = [];
  final List<AuditEntry> auditEntries = [];

  StaffRole? role;
  String? userId;
  String displayName = 'Equipo Luxury';
  String? errorMessage;
  bool loading = true;
  bool shiftOpen = true;
  double openingCash = 0;
  double closedCash = 0;
  bool mustChangePassword = false;
  bool _passwordRecoveryPending = false;
  bool _signInInProgress = false;
  bool lastOrderQueued = false;
  DateTime? lastOnlineSyncAt;
  int get pendingOrderCount => pendingOrders.length;
  bool get isConnected => _client != null;
  bool get isDemo => !isConnected;
  SupabaseClient? get client => _client;
  RealtimeChannel? _realtime;
  StreamSubscription<AuthState>? _authSubscription;
  int _nextId = 500;

  Future<void> initialize() async {
    try {
      if (_client == null) {
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getString(_storageKey);
        if (saved != null) _restore(jsonDecode(saved) as Map<String, dynamic>);
      } else {
        final user = _client.auth.currentUser;
        if (user != null) {
          try {
            await _loadProfile(user.id);
          } catch (error) {
            if (error is PostgrestException) rethrow;
            if (!await _restoreRemoteCache(user.id)) rethrow;
            errorMessage =
                'Sin conexión con Supabase. Los datos guardados se muestran en modo local.';
            if (pendingOrders.isNotEmpty) {
              errorMessage =
                  '$errorMessage Hay pedidos pendientes de sincronización.';
            }
          }
        }
      }
    } catch (error) {
      errorMessage = 'No se pudo iniciar la aplicación: $error';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> loginDemo(StaffRole selectedRole) async {
    if (!isDemo) {
      throw StateError(
        'El acceso por roles de demostración está desactivado al conectar Supabase.',
      );
    }
    role = selectedRole;
    displayName = switch (selectedRole) {
      StaffRole.administrator => 'Administración Luxury',
      StaffRole.manager => 'Gerencia Luxury',
      StaffRole.kitchen => 'Equipo de cocina',
      StaffRole.headChef => 'Jefatura de cocina',
      StaffRole.waiter => 'Mesero de turno',
      StaffRole.cashier => 'Caja Luxury',
    };
    userId = 'demo-${selectedRole.databaseValue.toLowerCase()}';
    errorMessage = null;
    notifyListeners();
  }

  Future<void> signIn(String email, String password) async {
    final client = _client;
    if (client == null) {
      throw StateError('No hay conexión de Supabase configurada.');
    }
    _signInInProgress = true;
    try {
      final response = await client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      final user = response.user;
      if (user == null) {
        throw StateError('Supabase no devolvió un usuario autenticado.');
      }
      await _loadProfile(user.id);
      errorMessage = null;
      notifyListeners();
    } finally {
      _signInInProgress = false;
    }
  }

  Future<void> _loadProfile(String id) async {
    final client = _client!;
    final profile = await client
        .from('usuarios')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (profile == null || profile['activo'] != true) {
      await client.auth.signOut();
      throw StateError(
        'No existe un perfil activo para esta cuenta. Solicita acceso al administrador.',
      );
    }
    userId = id;
    role = StaffRole.fromDatabase(profile['rol'] as String);
    displayName = profile['nombre_completo'] as String;
    mustChangePassword =
        _passwordRecoveryPending ||
        _client.auth.currentUser?.appMetadata['must_change_password'] == true;
    try {
      await _restorePendingOrderQueue(id);
      await _loadRemoteData();
      _subscribeRealtime();
    } catch (error) {
      if (error is PostgrestException) await signOut();
      rethrow;
    }
  }

  Future<bool> _restoreRemoteCache(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('$_remoteCachePrefix$id');
    if (saved == null) return false;
    final data = jsonDecode(saved) as Map<String, dynamic>;
    if (data['userId'] != id) return false;
    final savedRole = data['role'] as String?;
    final syncedAt = DateTime.tryParse(
      data['lastOnlineSyncAt'] as String? ?? '',
    );
    if (savedRole == null ||
        syncedAt == null ||
        DateTime.now().difference(syncedAt) > const Duration(hours: 12)) {
      return false;
    }
    _restore(data);
    userId = id;
    role = StaffRole.fromDatabase(savedRole);
    displayName = data['displayName'] as String? ?? 'Equipo Luxury';
    lastOnlineSyncAt = syncedAt;
    mustChangePassword =
        _passwordRecoveryPending ||
        _client?.auth.currentUser?.appMetadata['must_change_password'] == true;
    orders.addAll(pendingOrders);
    _subscribeRealtime();
    return true;
  }

  Future<void> _restorePendingOrderQueue(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('$_remoteCachePrefix$id');
    pendingOrders.clear();
    if (saved == null) return;
    final data = jsonDecode(saved) as Map<String, dynamic>;
    if (data['userId'] != id) return;
    pendingOrders.addAll(
      (data['pendingOrders'] as List<dynamic>? ?? []).map(
        (row) =>
            RestaurantOrder.fromJson(Map<String, dynamic>.from(row as Map)),
      ),
    );
  }

  Future<void> signOut() async {
    if (_client != null) await _client.auth.signOut();
    await _realtime?.unsubscribe();
    _realtime = null;
    _clearConnectedState();
    notifyListeners();
  }

  void _clearConnectedState() {
    role = null;
    userId = null;
    mustChangePassword = false;
    _passwordRecoveryPending = false;
    displayName = 'Equipo Luxury';
    errorMessage = null;
    if (isConnected) {
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
      pendingOrders.clear();
      shiftOpen = false;
      openingCash = 0;
      closedCash = 0;
    }
  }

  Future<void> _handleExternalSignIn(String id) async {
    await _realtime?.unsubscribe();
    _realtime = null;
    _clearConnectedState();
    notifyListeners();
    try {
      await _loadProfile(id);
      errorMessage = null;
      notifyListeners();
    } catch (error) {
      errorMessage =
          'No se pudo validar la sesión abierta en otra pestaña: $error';
      notifyListeners();
    }
  }

  void _seed() {
    categories.addAll([
      'Entradas',
      'Sopas',
      'Platos Especiales',
      'Chifas',
      'Bebidas',
      'Postres',
    ]);
    tables.addAll(
      List.generate(
        8,
        (index) => RestaurantTable(
          id: index + 1,
          number: index + 1,
          capacity: const [4, 4, 2, 4, 2, 6, 4, 4][index],
          status: switch (index) {
            1 || 4 || 6 => TableStatus.occupied,
            3 => TableStatus.payment,
            _ => TableStatus.available,
          },
        ),
      ),
    );
    final sampleMenu = <MenuItem>[
      const MenuItem(
        id: 1,
        name: 'Wantán frito',
        category: 'Entradas',
        price: 18,
        description: 'Masa de wantán, cerdo y salsa agridulce',
      ),
      const MenuItem(
        id: 2,
        name: 'Rollitos primavera',
        category: 'Entradas',
        price: 15,
        description: 'Verduras, pollo y salsa de ají',
      ),
      const MenuItem(
        id: 3,
        name: 'Sopa wantán',
        category: 'Sopas',
        price: 22,
        description: 'Caldo, wantán y cebolla china',
      ),
      const MenuItem(
        id: 4,
        name: 'Pollo tipakay',
        category: 'Platos Especiales',
        price: 30,
        description: 'Pollo frito, salsa agridulce y arroz',
      ),
      const MenuItem(
        id: 5,
        name: 'Arroz chaufa especial',
        category: 'Chifas',
        price: 28,
        description: 'Arroz, pollo, cerdo, huevo y cebolla china',
      ),
      const MenuItem(
        id: 6,
        name: 'Tallarín saltado',
        category: 'Chifas',
        price: 26,
        description: 'Tallarín, pollo, verduras y sillao',
      ),
      const MenuItem(
        id: 7,
        name: 'Aeropuerto',
        category: 'Chifas',
        price: 30,
        description: 'Arroz chaufa, tallarín saltado y pollo',
      ),
      const MenuItem(
        id: 8,
        name: 'Kam lu wantán',
        category: 'Chifas',
        price: 34,
        description: 'Wantán frito, pollo, piña y salsa agridulce',
      ),
      const MenuItem(
        id: 9,
        name: 'Chaufa de mariscos',
        category: 'Chifas',
        price: 32,
        description: 'Arroz, mariscos, huevo y cebolla china',
        available: false,
      ),
      const MenuItem(
        id: 10,
        name: 'Chicha morada jarra',
        category: 'Bebidas',
        price: 14,
        description: 'Maíz morado, piña, limón y canela',
      ),
      const MenuItem(
        id: 11,
        name: 'Té chifa',
        category: 'Bebidas',
        price: 6,
        description: 'Infusión de té caliente',
      ),
      const MenuItem(
        id: 12,
        name: 'Helado frito',
        category: 'Postres',
        price: 12,
        description: 'Helado, masa crocante y miel',
      ),
    ];
    menu.addAll(sampleMenu);
    inventory.addAll(const [
      InventoryItem(
        id: 1,
        name: 'Arroz',
        unit: 'KG',
        quantity: 18,
        minimum: 22,
        description: 'Arroz de grano largo para chaufa y guarniciones',
      ),
      InventoryItem(
        id: 2,
        name: 'Sillao',
        unit: 'LITRO',
        quantity: 3,
        minimum: 5,
        description: 'Salsa de soya para platos y marinados',
      ),
      InventoryItem(
        id: 3,
        name: 'Aceite',
        unit: 'LITRO',
        quantity: 42,
        minimum: 10,
        description: 'Aceite vegetal para cocina',
      ),
      InventoryItem(
        id: 4,
        name: 'Cebolla china',
        unit: 'KG',
        quantity: 1.2,
        minimum: 1.5,
        description: 'Para chaufa y sopas',
      ),
      InventoryItem(
        id: 5,
        name: 'Pollo',
        unit: 'KG',
        quantity: 15,
        minimum: 8,
        description: 'Pechuga y pierna',
      ),
    ]);
    staff.addAll(const [
      StaffMember(
        id: 'local-admin',
        name: 'Administración Luxury',
        email: 'admin@luxury.pe',
        role: StaffRole.administrator,
      ),
      StaffMember(
        id: 'local-manager',
        name: 'Gerencia Luxury',
        email: 'gerente@luxury.pe',
        role: StaffRole.manager,
      ),
      StaffMember(
        id: 'local-kitchen',
        name: 'Equipo de cocina',
        email: 'cocina@luxury.pe',
        role: StaffRole.kitchen,
      ),
      StaffMember(
        id: 'local-waiter',
        name: 'Mesero de turno',
        email: 'mesero@luxury.pe',
        role: StaffRole.waiter,
      ),
      StaffMember(
        id: 'local-cashier',
        name: 'Caja Luxury',
        email: 'caja@luxury.pe',
        role: StaffRole.cashier,
      ),
    ]);
    alerts.addAll([
      StockAlert(
        id: 4,
        inventoryId: 4,
        message: 'Bajo stock: cebolla china',
        createdAt: DateTime.now().subtract(const Duration(minutes: 8)),
        priority: 'ALTA',
      ),
      StockAlert(
        id: 3,
        inventoryId: 2,
        message: 'Bajo stock: sillao',
        createdAt: DateTime.now().subtract(const Duration(minutes: 20)),
      ),
    ]);
    requests.addAll(const [
      StockRequest(
        id: 1,
        itemName: 'Arroz',
        quantity: 25,
        unit: 'KG',
        note: 'Reposición para el turno de noche',
      ),
      StockRequest(
        id: 2,
        itemName: 'Sillao',
        quantity: 12,
        unit: 'LITRO',
        note: 'Compra semanal',
        status: 'EN_PROCESO',
      ),
    ]);
    orders.addAll([
      RestaurantOrder(
        id: 405,
        tableId: 4,
        tableNumber: 4,
        createdAt: DateTime.now().subtract(const Duration(minutes: 18)),
        status: OrderStatus.forPayment,
        lines: const [
          OrderLine(
            menuItemId: 4,
            name: 'Pollo tipakay',
            quantity: 1,
            unitPrice: 30,
            note: 'Sin cebolla',
            status: OrderStatus.ready,
          ),
          OrderLine(
            menuItemId: 6,
            name: 'Tallarín saltado',
            quantity: 1,
            unitPrice: 26,
            note: 'Sillao extra',
            status: OrderStatus.ready,
          ),
          OrderLine(
            menuItemId: 2,
            name: 'Rollitos primavera',
            quantity: 1,
            unitPrice: 15,
            status: OrderStatus.ready,
          ),
          OrderLine(
            menuItemId: 10,
            name: 'Chicha morada jarra',
            quantity: 1,
            unitPrice: 14,
            status: OrderStatus.ready,
          ),
        ],
      ),
      RestaurantOrder(
        id: 410,
        tableId: 2,
        tableNumber: 2,
        createdAt: DateTime.now().subtract(const Duration(minutes: 8)),
        status: OrderStatus.ready,
        lines: const [
          OrderLine(
            menuItemId: 4,
            name: 'Pollo tipakay',
            quantity: 1,
            unitPrice: 30,
            note: 'Sin cebolla',
            status: OrderStatus.ready,
          ),
          OrderLine(
            menuItemId: 1,
            name: 'Wantán frito',
            quantity: 2,
            unitPrice: 18,
            status: OrderStatus.ready,
          ),
        ],
      ),
      RestaurantOrder(
        id: 412,
        tableId: 7,
        tableNumber: 7,
        createdAt: DateTime.now().subtract(const Duration(minutes: 4)),
        status: OrderStatus.preparing,
        lines: const [
          OrderLine(
            menuItemId: 5,
            name: 'Arroz chaufa especial',
            quantity: 2,
            unitPrice: 28,
            note: 'Sin picante',
            status: OrderStatus.preparing,
          ),
          OrderLine(
            menuItemId: 6,
            name: 'Tallarín saltado',
            quantity: 1,
            unitPrice: 26,
            note: 'Sillao extra',
            status: OrderStatus.pending,
          ),
        ],
      ),
      RestaurantOrder(
        id: 413,
        tableId: 5,
        tableNumber: 5,
        createdAt: DateTime.now().subtract(const Duration(minutes: 1)),
        lines: const [
          OrderLine(
            menuItemId: 10,
            name: 'Chicha morada jarra',
            quantity: 1,
            unitPrice: 14,
          ),
          OrderLine(
            menuItemId: 2,
            name: 'Rollitos primavera',
            quantity: 2,
            unitPrice: 15,
          ),
        ],
      ),
    ]);
    _nextId = 500;
  }

  Future<void> _loadRemoteData() async {
    final client = _client!;
    final remoteTables = await client
        .from('mesas')
        .select()
        .eq('activa', true)
        .order('numero');
    final remoteCategories = await client
        .from('categorias')
        .select()
        .eq('activa', true)
        .order('orden');
    final remoteMenu = await client
        .from('platillos')
        .select()
        .eq('activo', true)
        .order('nombre');
    final remoteOrders = await client
        .from('pedidos')
        .select()
        .order('creado_en', ascending: false);
    final remoteLines = await client
        .from('detalle_pedido')
        .select()
        .order('creado_en');
    final remotePayments = await client
        .from('pagos')
        .select()
        .order('creado_en');
    final remoteInventory = await client
        .from('insumos')
        .select(
          'id,nombre,descripcion,unidad,stock_actual,stock_minimo,activo',
        );
    final remoteStaff = await client.from('usuarios').select();
    final canReadRequests =
        role == StaffRole.kitchen ||
        role == StaffRole.headChef ||
        role == StaffRole.manager ||
        role == StaffRole.administrator;
    final remoteRequests = canReadRequests
        ? await client
              .from('solicitudes_reabastecimiento')
              .select()
              .order('creado_en', ascending: false)
        : <dynamic>[];
    final remoteRequestItems = canReadRequests
        ? await client.from('solicitud_items').select()
        : <dynamic>[];
    final remoteAlerts = canReadRequests
        ? await client
              .from('alertas_cocina')
              .select()
              .order('creado_en', ascending: false)
        : <dynamic>[];
    final remoteReceipts =
        role == StaffRole.cashier ||
            role == StaffRole.manager ||
            role == StaffRole.administrator
        ? await client
              .from('notas_venta')
              .select()
              .order('emitida_en', ascending: false)
        : <dynamic>[];
    final remoteAudit =
        role == StaffRole.manager || role == StaffRole.administrator
        ? await client
              .from('auditoria_movimientos')
              .select(
                'id,actor_id,actor_rol,accion,entidad,entidad_id,creado_en',
              )
              .order('creado_en', ascending: false)
              .limit(200)
        : <dynamic>[];
    final remoteShifts =
        role == StaffRole.cashier || role == StaffRole.administrator
        ? await client
              .from('turnos_caja')
              .select()
              .eq('cajero_id', userId!)
              .order('abierto_en', ascending: false)
              .limit(1)
        : <dynamic>[];

    tables
      ..clear()
      ..addAll(
        remoteTables.map(
          (row) => RestaurantTable(
            id: row['id'] as int,
            number: row['numero'] as int,
            capacity: row['capacidad'] as int,
            status: TableStatus.fromDatabase(row['estado'] as String),
            active: row['activa'] as bool,
          ),
        ),
      );
    categories
      ..clear()
      ..addAll(remoteCategories.map((row) => row['nombre'] as String));
    menu
      ..clear()
      ..addAll(
        remoteMenu.map((row) {
          final categoryRow = remoteCategories.firstWhere(
            (category) => category['id'] == row['categoria_id'],
            orElse: () => {'nombre': 'Sin categoría'},
          );
          return MenuItem(
            id: row['id'] as int,
            name: row['nombre'] as String,
            category: categoryRow['nombre'] as String,
            price: (row['precio'] as num).toDouble(),
            description: row['descripcion'] as String? ?? '',
            available: row['agotado'] != true,
          );
        }),
      );

    final linesByOrder = <int, List<OrderLine>>{};
    for (final row in remoteLines) {
      final orderId = row['pedido_id'] as int;
      final dish = menu
          .where((item) => item.id == row['platillo_id'])
          .firstOrNull;
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
              method: _paymentLabel(row['metodo'] as String),
              amount: (row['monto'] as num).toDouble(),
              createdAt: DateTime.parse(row['creado_en'] as String),
              reference: row['referencia'] as String? ?? '',
              cashReceived: (row['efectivo_recibido'] as num?)?.toDouble(),
            ),
          );
    }
    final tableNumbers = {for (final table in tables) table.id: table.number};
    orders
      ..clear()
      ..addAll(
        remoteOrders.map((row) {
          final id = row['id'] as int;
          final tableId = row['mesa_id'] as int?;
          final lines = linesByOrder[id] ?? const <OrderLine>[];
          final databaseStatus = OrderStatus.fromDatabase(
            row['estado'] as String,
          );
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
            parentOrderId: row['pedido_padre_id'] as int?,
            retirementConfirmed: row['retirada_en'] != null,
            fulfillmentType: FulfillmentType.fromDatabase(
              row['tipo_pedido'] as String? ?? 'MESA',
            ),
            customerName: row['cliente_nombre'] as String? ?? '',
            customerPhone: row['cliente_telefono'] as String? ?? '',
            deliveryAddress: row['direccion_entrega'] as String? ?? '',
            waiterName:
                remoteStaff
                        .where(
                          (staffMember) =>
                              staffMember['id'] == row['mesero_id'],
                        )
                        .firstOrNull?['nombre_completo']
                    as String? ??
                'Mesero',
          );
        }),
      );
    inventory
      ..clear()
      ..addAll(
        remoteInventory.map(
          (row) => InventoryItem(
            id: row['id'] as int,
            name: row['nombre'] as String,
            unit: row['unidad'] as String,
            quantity: (row['stock_actual'] as num).toDouble(),
            minimum: (row['stock_minimo'] as num).toDouble(),
            description: row['descripcion'] as String? ?? '',
            active: row['activo'] as bool,
          ),
        ),
      );
    staff
      ..clear()
      ..addAll(
        remoteStaff.map(
          (row) => StaffMember(
            id: row['id'] as String,
            name: row['nombre_completo'] as String,
            email: row['correo'] as String? ?? '',
            role: StaffRole.fromDatabase(row['rol'] as String),
            active: row['activo'] as bool,
          ),
        ),
      );
    requests
      ..clear()
      ..addAll(
        remoteRequests.map((row) {
          final requestId = row['id'] as int;
          final rows = remoteRequestItems
              .where((entry) => entry['solicitud_id'] == requestId)
              .toList();
          final requestLines = rows
              .map((item) {
                final stock = inventory
                    .where((entry) => entry.id == item['insumo_id'])
                    .firstOrNull;
                return StockRequestLine(
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
        }),
      );
    alerts
      ..clear()
      ..addAll(
        remoteAlerts.map(
          (row) => StockAlert(
            id: row['id'] as int,
            inventoryId: row['insumo_id'] as int?,
            message: row['mensaje'] as String,
            createdAt: DateTime.parse(row['creado_en'] as String),
            status: row['estado'] as String,
            priority: row['prioridad'] as String? ?? 'MEDIA',
          ),
        ),
      );
    receipts
      ..clear()
      ..addAll(
        remoteReceipts.map(
          (row) => {
            'id': row['id'],
            'code': 'NV-${row['numero']}',
            'orderId': row['pedido_id'],
            'tableNumber': tableNumbersForReceipt(
              remoteOrders,
              row['pedido_id'] as int,
              tableNumbers,
            ),
            'locationLabel': orderLocationForReceipt(
              remoteOrders,
              row['pedido_id'] as int,
              tableNumbers,
            ),
            'total': row['total'],
            'createdAt': row['emitida_en'],
            'status': row['estado'],
            'voidReason': row['motivo_anulacion'],
            'payments': paymentsByOrder[row['pedido_id']] ?? const [],
          },
        ),
      );
    auditEntries
      ..clear()
      ..addAll(
        remoteAudit.map(
          (row) => AuditEntry(
            id: row['id'] as int,
            createdAt: DateTime.parse(row['creado_en'] as String),
            action: row['accion'] as String,
            entity: row['entidad'] as String,
            entityId: row['entidad_id'] as String? ?? '',
            actorRole: row['actor_rol'] as String? ?? '',
            actorName:
                remoteStaff
                        .where(
                          (staffMember) => staffMember['id'] == row['actor_id'],
                        )
                        .firstOrNull?['nombre_completo']
                    as String? ??
                'Usuario desactivado',
          ),
        ),
      );
    if (remoteShifts.isNotEmpty) {
      final openShift = remoteShifts.first;
      shiftOpen = openShift['cerrado_en'] == null;
      openingCash = (openShift['monto_apertura'] as num).toDouble();
      closedCash = (openShift['monto_cierre'] as num?)?.toDouble() ?? 0;
    } else if (role == StaffRole.cashier || role == StaffRole.administrator) {
      shiftOpen = false;
      openingCash = 0;
      closedCash = 0;
    }
    lastOnlineSyncAt = DateTime.now();
    orders.addAll(pendingOrders);
    await _persist();
  }

  void _subscribeRealtime() {
    if (_client == null) return;
    _realtime = _client
        .channel('luxury-restaurant-live')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pedidos',
          callback: (_) => unawaited(_refreshFromRealtime()),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'detalle_pedido',
          callback: (_) => unawaited(_refreshFromRealtime()),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'mesas',
          callback: (_) => unawaited(_refreshFromRealtime()),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'platillos',
          callback: (_) => unawaited(_refreshFromRealtime()),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'alertas_cocina',
          callback: (_) => unawaited(_refreshFromRealtime()),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'auditoria_movimientos',
          callback: (_) => unawaited(_refreshFromRealtime()),
        )
        .subscribe((status, _) {
          if (status == RealtimeSubscribeStatus.subscribed &&
              pendingOrders.isNotEmpty) {
            unawaited(_syncPendingOrdersSafely());
          }
        });
  }

  Future<void> _refreshFromRealtime() async {
    try {
      await _loadRemoteData();
      errorMessage = null;
      notifyListeners();
    } catch (error) {
      errorMessage =
          'No se pudo actualizar la información en tiempo real: $error';
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (_client != null) await _loadRemoteData();
    errorMessage = null;
    notifyListeners();
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
    shiftOpen = true;
    openingCash = 0;
    closedCash = 0;
    _seed();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    notifyListeners();
  }

  Future<void> createOrder({
    required RestaurantTable? table,
    required List<OrderLine> lines,
    required int diners,
    int? parentOrderId,
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
    if (fulfillmentType == FulfillmentType.dineIn &&
        (table == null || diners < 1 || diners > table.capacity)) {
      throw StateError(
        'Los comensales deben estar entre 1 y la capacidad de la mesa.',
      );
    }
    if (fulfillmentType != FulfillmentType.dineIn &&
        (customerName.trim().isEmpty || customerPhone.trim().isEmpty)) {
      throw StateError('Indica el nombre y teléfono del cliente.');
    }
    if (fulfillmentType != FulfillmentType.dineIn &&
        !RegExp(r'^\d{9}$').hasMatch(customerPhone.trim())) {
      throw StateError('El teléfono debe tener exactamente 9 dígitos.');
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
    final parent = parentOrderId == null
        ? null
        : orders.where((order) => order.id == parentOrderId).firstOrNull;
    if ((fulfillmentType == FulfillmentType.dineIn &&
            parentOrderId == null &&
            orders.any(
              (order) =>
                  order.tableId == table!.id &&
                  (order.status != OrderStatus.paid &&
                          order.status != OrderStatus.cancelled ||
                      !order.retirementConfirmed),
            )) ||
        (parentOrderId != null &&
            (parent == null ||
                parent.tableId != table!.id ||
                parent.status != OrderStatus.paid ||
                parent.retirementConfirmed))) {
      throw StateError(
        'Los consumos posteriores al pago deben vincularse al pedido principal vigente.',
      );
    }
    final client = _client;
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
        if (client.realtime.isConnected) rethrow;
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
        return;
      }
      if (result == null) {
        throw StateError('Supabase no confirmó la creación del pedido.');
      }
      await _loadRemoteData();
    } else {
      orders.insert(
        0,
        RestaurantOrder(
          id: _nextId++,
          tableId: table?.id,
          tableNumber: table?.number ?? 0,
          createdAt: DateTime.now(),
          diners: diners,
          lines: List.unmodifiable(lines),
          waiterName: displayName,
          parentOrderId: parentOrderId,
          fulfillmentType: fulfillmentType,
          customerName: customerName.trim(),
          customerPhone: customerPhone.trim(),
          deliveryAddress: deliveryAddress.trim(),
        ),
      );
      if (table != null) _recalculateTable(table.id);
      await _persist();
    }
    _recordLocalAudit('Crear pedido', 'pedidos', orders.first.id.toString());
    notifyListeners();
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
  }) async {
    final order = RestaurantOrder(
      id: -DateTime.now().microsecondsSinceEpoch,
      tableId: table?.id,
      tableNumber: table?.number ?? 0,
      createdAt: DateTime.now(),
      diners: diners,
      lines: List.unmodifiable(lines),
      waiterName: displayName,
      parentOrderId: parentOrderId,
      fulfillmentType: fulfillmentType,
      customerName: customerName.trim(),
      customerPhone: customerPhone.trim(),
      deliveryAddress: deliveryAddress.trim(),
      pendingSync: true,
      clientRequestId: requestId,
    );
    pendingOrders.add(order);
    orders.insert(0, order);
    if (table != null) _recalculateTable(table.id);
    lastOrderQueued = true;
    errorMessage =
        'Pedido guardado en este dispositivo y pendiente de sincronización.';
    await _persist();
    notifyListeners();
  }

  Future<void> syncPendingOrders() async {
    final client = _client;
    if (client == null || pendingOrders.isEmpty) return;
    try {
      for (final order in List<RestaurantOrder>.of(pendingOrders)) {
        final requestId = order.clientRequestId;
        if (requestId == null) {
          throw StateError(
            'Un pedido pendiente no tiene identificador de sincronización.',
          );
        }
        final result = await client.rpc(
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
        if (result == null) {
          throw StateError('Supabase no confirmó un pedido pendiente.');
        }
        pendingOrders.removeWhere(
          (pending) => pending.clientRequestId == requestId,
        );
        orders.removeWhere((pending) => pending.clientRequestId == requestId);
        await _persist();
      }
      await _loadRemoteData();
      errorMessage = null;
      notifyListeners();
    } catch (error) {
      errorMessage =
          'No se pudieron sincronizar los pedidos pendientes: $error';
      await _persist();
      notifyListeners();
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
    if (order.pendingSync ||
        order.status != OrderStatus.pending ||
        order.payments.isNotEmpty ||
        lines.isEmpty ||
        diners < 1) {
      throw StateError('Solo se edita un pedido pendiente y sin abonos.');
    }
    if (_client != null) {
      await _client.rpc(
        'editar_pedido',
        params: {
          'p_pedido_id': order.id,
          'p_comensales': diners,
          'p_items': _itemsToJson(lines),
        },
      );
      await _loadRemoteData();
    } else {
      final index = orders.indexWhere((value) => value.id == order.id);
      if (index < 0) throw StateError('No se encontró el pedido.');
      orders[index] = order.copyWith(
        diners: diners,
        lines: lines,
        status: OrderStatus.pending,
      );
      _recalculateTable(order.tableId);
      await _persist();
    }
    _recordLocalAudit('Editar pedido', 'pedidos', order.id.toString());
    notifyListeners();
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
    notifyListeners();
  }

  Future<void> confirmTableRelease(RestaurantTable table) async {
    final tableOrders = orders.where((order) => order.tableId == table.id);
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
    notifyListeners();
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

  Future<void> advanceOrder(RestaurantOrder order) async {
    if (order.pendingSync) {
      throw StateError('Sincroniza el pedido antes de actualizar su estado.');
    }
    final currentKitchenStage = kitchenStage(order);
    final nextStatus = switch (currentKitchenStage) {
      OrderStatus.pending => OrderStatus.preparing,
      OrderStatus.preparing => OrderStatus.ready,
      OrderStatus.ready => OrderStatus.delivered,
      _ => throw StateError(
        'Este pedido no puede avanzar desde el estado actual.',
      ),
    };
    if (_client != null) {
      for (final line in order.lines) {
        if (line.id == null) continue;
        await _client.rpc(
          'actualizar_estado_item',
          params: {
            'p_detalle_id': line.id,
            'p_estado': nextStatus.databaseValue,
          },
        );
      }
      await _loadRemoteData();
    } else {
      final index = orders.indexWhere((item) => item.id == order.id);
      final updatedLines = order.lines
          .map((line) => line.copyWith(status: nextStatus))
          .toList(growable: false);
      final preservedStatus =
          order.status == OrderStatus.paid ||
              order.status == OrderStatus.forPayment
          ? order.status
          : nextStatus;
      orders[index] = order.copyWith(
        lines: updatedLines,
        status: preservedStatus,
      );
      _recalculateTable(order.tableId);
      await _persist();
    }
    _recordLocalAudit(
      'Actualizar estado de comanda',
      'pedidos',
      order.id.toString(),
    );
    notifyListeners();
  }

  Future<void> recordPayment({
    required RestaurantOrder order,
    required String method,
    required double amount,
    String reference = '',
    double? cashReceived,
    bool earlyPaymentConfirmed = false,
  }) async {
    if (order.pendingSync) {
      throw StateError('Sincroniza el pedido antes de registrar pagos.');
    }
    if (amount <= 0 || amount > order.balance + 0.001) {
      throw StateError(
        'El monto debe ser mayor a cero y no superar el saldo pendiente.',
      );
    }
    if (method != 'Efectivo' && reference.trim().isEmpty) {
      throw StateError(
        'Registra el número de operación o referencia del pago.',
      );
    }
    if (method == 'Efectivo' &&
        (cashReceived == null || cashReceived < amount)) {
      throw StateError('El efectivo recibido debe cubrir el monto del abono.');
    }
    if ((kitchenStage(order) == OrderStatus.pending ||
            kitchenStage(order) == OrderStatus.preparing) &&
        !earlyPaymentConfirmed) {
      throw StateError(
        'Confirma el cobro anticipado antes de registrar el pago.',
      );
    }
    final databaseMethod = switch (method) {
      'Tarjeta' => 'TARJETA',
      'Yape' || 'Plin' || 'Yape / Plin' => 'YAPE_PLIN',
      _ => 'EFECTIVO',
    };
    if (_client != null) {
      await _client.rpc(
        'registrar_pago',
        params: {
          'p_pedido_id': order.id,
          'p_metodo': databaseMethod,
          'p_monto': amount,
          'p_referencia': reference.trim().isEmpty ? null : reference.trim(),
          'p_efectivo_recibido': cashReceived,
          'p_cobro_anticipado_confirmado': earlyPaymentConfirmed,
        },
      );
      await _loadRemoteData();
    } else {
      final index = orders.indexWhere((item) => item.id == order.id);
      final payments = [
        ...order.payments,
        PaymentEntry(
          method: method,
          amount: amount,
          createdAt: DateTime.now(),
          reference: reference.trim(),
          cashReceived: cashReceived,
        ),
      ];
      final complete =
          payments.fold<double>(0, (sum, payment) => sum + payment.amount) >=
          order.total - 0.001;
      orders[index] = order.copyWith(
        payments: payments,
        status: complete ? OrderStatus.paid : OrderStatus.forPayment,
      );
      if (complete) {
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
        _recalculateTable(order.tableId);
      }
      await _persist();
    }
    _recordLocalAudit('Registrar pago', 'pagos', order.id.toString());
    notifyListeners();
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
    notifyListeners();
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

  Future<void> setMenuAvailability(MenuItem item, bool available) async {
    if (_client != null) {
      await _client.rpc(
        'alternar_plato_agotado',
        params: {'p_platillo': item.id, 'p_agotado': !available},
      );
      await _loadRemoteData();
    } else {
      _replaceMenu(item.copyWith(available: available));
      await _persist();
    }
    _recordLocalAudit(
      available ? 'Habilitar platillo' : 'Marcar platillo agotado',
      'platillos',
      item.id.toString(),
    );
    notifyListeners();
  }

  Future<void> saveMenuItem({
    int? id,
    required String name,
    required String category,
    required double price,
    required String description,
  }) async {
    if (name.trim().isEmpty || price < 0) {
      throw StateError('Indica un nombre y un precio válido.');
    }
    if (_client != null) {
      final categoryRows = await _client
          .from('categorias')
          .select('id')
          .eq('nombre', category)
          .limit(1);
      if (categoryRows.isEmpty) {
        final inserted = await _client
            .from('categorias')
            .insert({'nombre': category})
            .select('id')
            .single();
        final categoryId = inserted['id'] as int;
        await _writeMenuItem(
          id: id,
          categoryId: categoryId,
          name: name,
          price: price,
          description: description,
        );
      } else {
        await _writeMenuItem(
          id: id,
          categoryId: categoryRows.first['id'] as int,
          name: name,
          price: price,
          description: description,
        );
      }
      await _loadRemoteData();
    } else {
      if (id == null) {
        final newId = _nextId++;
        menu.add(
          MenuItem(
            id: newId,
            name: name.trim(),
            category: category,
            price: price,
            description: description.trim(),
          ),
        );
      } else {
        final old = menu.firstWhere((item) => item.id == id);
        _replaceMenu(
          old.copyWith(
            name: name.trim(),
            category: category,
            price: price,
            description: description.trim(),
          ),
        );
      }
      if (!categories.contains(category)) categories.add(category);
      await _persist();
    }
    _recordLocalAudit(
      id == null ? 'Crear platillo' : 'Editar platillo',
      'platillos',
      id?.toString() ?? menu.last.id.toString(),
    );
    notifyListeners();
  }

  Future<void> saveCategory({
    String? previousName,
    required String name,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw StateError('El nombre de la categoría es obligatorio.');
    }
    if (_client != null) {
      final existing = await _client
          .from('categorias')
          .select('id')
          .eq('nombre', trimmed)
          .limit(1);
      if (existing.isNotEmpty &&
          (previousName == null ||
              existing.first['id'] !=
                  (await _client
                      .from('categorias')
                      .select('id')
                      .eq('nombre', previousName)
                      .single())['id'])) {
        throw StateError('Ya existe una categoría con ese nombre.');
      }
      if (previousName == null) {
        await _client.from('categorias').insert({'nombre': trimmed});
      } else {
        await _client
            .from('categorias')
            .update({'nombre': trimmed})
            .eq('nombre', previousName);
      }
      await _loadRemoteData();
    } else {
      if (categories.any(
        (value) =>
            value.toLowerCase() == trimmed.toLowerCase() &&
            value != previousName,
      )) {
        throw StateError('Ya existe una categoría con ese nombre.');
      }
      if (previousName == null) {
        categories.add(trimmed);
      } else {
        final index = categories.indexOf(previousName);
        categories[index] = trimmed;
        for (var i = 0; i < menu.length; i++) {
          if (menu[i].category == previousName) {
            menu[i] = menu[i].copyWith(category: trimmed);
          }
        }
      }
      await _persist();
    }
    _recordLocalAudit(
      previousName == null ? 'Crear categoría' : 'Editar categoría',
      'categorias',
      trimmed,
    );
    notifyListeners();
  }

  Future<void> removeCategory(String name) async {
    if (menu.any((item) => item.category == name)) {
      throw StateError(
        'No se puede eliminar la categoría porque todavía contiene platillos.',
      );
    }
    if (_client != null) {
      final category = await _client
          .from('categorias')
          .select('id')
          .eq('nombre', name)
          .single();
      await _client.from('categorias').delete().eq('id', category['id']);
      await _loadRemoteData();
    } else {
      categories.remove(name);
      await _persist();
    }
    _recordLocalAudit('Eliminar categoría', 'categorias', name);
    notifyListeners();
  }

  Future<void> _writeMenuItem({
    int? id,
    required int categoryId,
    required String name,
    required double price,
    required String description,
  }) async {
    final values = {
      'categoria_id': categoryId,
      'nombre': name.trim(),
      'precio': price,
      'descripcion': description.trim(),
    };
    if (id == null) {
      await _client!.from('platillos').insert(values);
    } else {
      await _client!.from('platillos').update(values).eq('id', id);
    }
  }

  Future<void> saveTable({
    int? id,
    required int number,
    required int capacity,
  }) async {
    if (number < 1 || capacity < 1) {
      throw StateError('El número y la capacidad deben ser mayores a cero.');
    }
    if (_client != null) {
      final values = {'numero': number, 'capacidad': capacity};
      if (id == null) {
        await _client.from('mesas').insert(values);
      } else {
        await _client.from('mesas').update(values).eq('id', id);
      }
      await _loadRemoteData();
    } else {
      if (id == null) {
        tables.add(
          RestaurantTable(id: _nextId++, number: number, capacity: capacity),
        );
      } else {
        final index = tables.indexWhere((table) => table.id == id);
        tables[index] = tables[index].copyWith(
          number: number,
          capacity: capacity,
        );
      }
      await _persist();
    }
    _recordLocalAudit(
      id == null ? 'Crear mesa' : 'Editar mesa',
      'mesas',
      number.toString(),
    );
    notifyListeners();
  }

  Future<void> removeTable(RestaurantTable table) async {
    final hasOpenOrder = orders.any(
      (order) =>
          order.tableId == table.id &&
          order.status != OrderStatus.paid &&
          order.status != OrderStatus.cancelled &&
          order.status != OrderStatus.delivered,
    );
    if (table.status != TableStatus.available || hasOpenOrder) {
      throw StateError(
        'La mesa ${table.number} tiene un pedido abierto y no se puede eliminar.',
      );
    }
    if (_client != null) {
      await _client.from('mesas').delete().eq('id', table.id);
      await _loadRemoteData();
    } else {
      tables.removeWhere((item) => item.id == table.id);
      await _persist();
    }
    _recordLocalAudit('Eliminar mesa', 'mesas', table.number.toString());
    notifyListeners();
  }

  Future<void> updateInventory({
    int? id,
    required String name,
    required String unit,
    required double quantity,
    required double minimum,
    String description = '',
  }) async {
    if (name.trim().isEmpty || quantity < 0 || minimum < 0) {
      throw StateError('Verifica el nombre, el stock y el mínimo del insumo.');
    }
    if (_client != null) {
      final values = {
        'nombre': name.trim(),
        'descripcion': description.trim(),
        'unidad': unit,
        'stock_actual': quantity,
        'stock_minimo': minimum,
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
      );
      await _persist();
    }
    _recordLocalAudit(
      id == null ? 'Crear insumo' : 'Actualizar insumo',
      'insumos',
      id?.toString() ?? inventory.last.id.toString(),
    );
    notifyListeners();
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
    notifyListeners();
  }

  Future<void> createStockRequest(
    InventoryItem item,
    double quantity,
    String note,
  ) async {
    if (quantity <= 0) {
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
    notifyListeners();
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
    notifyListeners();
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
    notifyListeners();
  }

  Future<void> reviewKitchenAlert(StockAlert alert) async {
    if (_client != null) {
      await _client.rpc(
        'revisar_alerta_cocina',
        params: {'p_alerta_id': alert.id, 'p_prioridad': alert.priority},
      );
      await _loadRemoteData();
    } else {
      final index = alerts.indexWhere((item) => item.id == alert.id);
      alerts[index] = alert.copyWith(status: 'REVISADA');
      await _persist();
    }
    _recordLocalAudit(
      'Revisar alerta de cocina',
      'alertas_cocina',
      alert.id.toString(),
    );
    notifyListeners();
  }

  Future<void> reportKitchenIncident(
    RestaurantOrder order,
    String reason,
  ) async {
    final trimmed = reason.trim();
    if (trimmed.length < 5) {
      throw StateError('Describe la incidencia con al menos cinco caracteres.');
    }
    if (_client != null) {
      await _client.rpc(
        'reportar_incidencia_cocina',
        params: {'p_pedido_id': order.id, 'p_motivo': trimmed},
      );
      await _loadRemoteData();
    } else {
      final index = orders.indexWhere((item) => item.id == order.id);
      orders[index] = order.copyWith(incident: trimmed);
      await _persist();
    }
    _recordLocalAudit(
      'Reportar incidencia de cocina',
      'pedidos',
      order.id.toString(),
    );
    notifyListeners();
  }

  Future<void> advanceRequest(StockRequest request) async {
    if (request.status != 'PENDIENTE' && request.status != 'EN_PROCESO') {
      throw StateError('Esta solicitud ya no puede avanzar de estado.');
    }
    final next = request.status == 'PENDIENTE' ? 'EN_PROCESO' : 'ATENDIDO';
    if (_client != null) {
      await _client
          .from('solicitudes_reabastecimiento')
          .update({
            'estado': next,
            if (next == 'ATENDIDO')
              'atendido_en': DateTime.now().toIso8601String(),
          })
          .eq('id', request.id);
      await _loadRemoteData();
    } else {
      final index = requests.indexWhere((item) => item.id == request.id);
      requests[index] = request.copyWith(status: next);
      await _persist();
    }
    _recordLocalAudit(
      'Actualizar solicitud de reabastecimiento',
      'solicitudes_reabastecimiento',
      request.id.toString(),
    );
    notifyListeners();
  }

  Future<void> cancelRequest(StockRequest request) async {
    if (request.status != 'PENDIENTE' && request.status != 'EN_PROCESO') {
      throw StateError('Solo se cancelan solicitudes pendientes o en proceso.');
    }
    if (_client != null) {
      await _client
          .from('solicitudes_reabastecimiento')
          .update({'estado': 'CANCELADA'})
          .eq('id', request.id);
      await _loadRemoteData();
    } else {
      final index = requests.indexWhere((item) => item.id == request.id);
      if (index < 0) throw StateError('No se encontró la solicitud.');
      requests[index] = request.copyWith(status: 'CANCELADA');
      await _persist();
    }
    _recordLocalAudit(
      'Cancelar solicitud de reabastecimiento',
      'solicitudes_reabastecimiento',
      request.id.toString(),
    );
    notifyListeners();
  }

  Future<void> addStaffMember({
    required String name,
    required String email,
    required StaffRole role,
    String? password,
  }) async {
    if (_client != null) {
      final initialPassword = password?.trim() ?? '';
      if (initialPassword.length < 8) {
        throw StateError(
          'La contraseña temporal debe tener al menos 8 caracteres.',
        );
      }
      final result = await _client.functions.invoke(
        'manage-staff',
        body: {
          'action': 'create',
          'name': name.trim(),
          'email': email.trim(),
          'role': role.databaseValue,
          'password': initialPassword,
        },
      );
      _throwFunctionError(result, 'No se pudo crear la cuenta.');
      await _loadRemoteData();
    } else {
      staff.add(
        StaffMember(
          id: 'local-${_nextId++}',
          name: name.trim(),
          email: email.trim(),
          role: role,
        ),
      );
      await _persist();
    }
    notifyListeners();
  }

  Future<void> updateStaffMember({
    required StaffMember member,
    required String name,
    required String email,
    required StaffRole role,
  }) async {
    if (_client != null) {
      final result = await _client.functions.invoke(
        'manage-staff',
        body: {
          'action': 'update',
          'id': member.id,
          'name': name.trim(),
          'email': email.trim(),
          'role': role.databaseValue,
        },
      );
      _throwFunctionError(result, 'No se pudo actualizar la cuenta.');
      await _loadRemoteData();
    } else {
      final index = staff.indexWhere((item) => item.id == member.id);
      if (index < 0) throw StateError('No se encontró el usuario.');
      staff[index] = member.copyWith(
        name: name.trim(),
        email: email.trim(),
        role: role,
      );
      await _persist();
    }
    notifyListeners();
  }

  Future<void> resetStaffPassword({
    required StaffMember member,
    required String password,
  }) async {
    if (_client == null) {
      throw StateError(
        'El restablecimiento de contraseña solo está disponible con Supabase.',
      );
    }
    if (password.trim().length < 8) {
      throw StateError(
        'La contraseña temporal debe tener al menos 8 caracteres.',
      );
    }
    final result = await _client.functions.invoke(
      'manage-staff',
      body: {
        'action': 'reset_password',
        'id': member.id,
        'password': password.trim(),
      },
    );
    _throwFunctionError(result, 'No se pudo restablecer la contraseña.');
  }

  Future<void> sendPasswordRecovery(String email) async {
    final client = _client;
    if (client == null) {
      throw StateError('La recuperación requiere conexión con Supabase.');
    }
    if (!email.trim().contains('@')) {
      throw StateError('Escribe el correo de la cuenta.');
    }
    await client.auth.resetPasswordForEmail(email.trim());
  }

  Future<void> changeOwnPassword(String password) async {
    final client = _client;
    if (client == null) {
      throw StateError('El cambio de contraseña requiere Supabase.');
    }
    if (password.trim().length < 8) {
      throw StateError('La contraseña debe tener al menos 8 caracteres.');
    }
    await client.auth.updateUser(
      UserAttributes(password: password, data: {'must_change_password': false}),
    );
    final result = await client.functions.invoke(
      'manage-staff',
      body: {'action': 'complete_password_change'},
    );
    _throwFunctionError(
      result,
      'No se pudo completar el cambio de contraseña.',
    );
    mustChangePassword = false;
    _passwordRecoveryPending = false;
    notifyListeners();
  }

  void _throwFunctionError(FunctionResponse result, String fallback) {
    if (result.status >= 400) {
      final body = result.data;
      final message = body is Map ? body['error'] : null;
      throw StateError(message is String ? message : fallback);
    }
  }

  Future<void> toggleStaff(StaffMember member) async {
    if (member.role == StaffRole.administrator &&
        member.active &&
        staff
                .where(
                  (item) => item.role == StaffRole.administrator && item.active,
                )
                .length <
            2) {
      throw StateError('Debe quedar al menos un administrador activo.');
    }
    if (member.role == StaffRole.manager &&
        member.active &&
        staff
                .where((item) => item.role == StaffRole.manager && item.active)
                .length <
            2) {
      throw StateError('Debe quedar al menos un gerente activo.');
    }
    if (_client != null) {
      await _client
          .from('usuarios')
          .update({'activo': !member.active})
          .eq('id', member.id);
      await _loadRemoteData();
    } else {
      final index = staff.indexWhere((item) => item.id == member.id);
      staff[index] = member.copyWith(active: !member.active);
      await _persist();
    }
    notifyListeners();
  }

  Future<void> setShiftOpen(bool open, {double? countedCash}) async {
    if (open == shiftOpen) return;
    if (_client != null) {
      if (open) {
        await _client.from('turnos_caja').insert({
          'cajero_id': userId,
          'monto_apertura': countedCash ?? 0,
        });
      } else {
        final shifts = await _client
            .from('turnos_caja')
            .select('id')
            .eq('cajero_id', userId!)
            .isFilter('cerrado_en', null)
            .order('abierto_en', ascending: false)
            .limit(1);
        if (shifts.isEmpty) {
          throw StateError('No hay un turno abierto que pueda cerrarse.');
        }
        await _client
            .from('turnos_caja')
            .update({
              'cerrado_en': DateTime.now().toIso8601String(),
              'monto_cierre': countedCash ?? 0,
            })
            .eq('id', shifts.first['id']);
      }
    }
    shiftOpen = open;
    if (open) {
      openingCash = countedCash ?? 0;
    } else {
      closedCash = countedCash ?? 0;
    }
    if (_client == null) await _persist();
    _recordLocalAudit(
      open ? 'Abrir turno de caja' : 'Cerrar turno de caja',
      'turnos_caja',
      userId ?? 'local',
    );
    notifyListeners();
  }

  Future<void> setOrderForPayment(RestaurantOrder order) async {
    if (order.pendingSync) {
      throw StateError('Sincroniza el pedido antes de solicitar la cuenta.');
    }
    if (_client != null) {
      await _client.rpc('solicitar_cuenta', params: {'p_pedido_id': order.id});
      await _loadRemoteData();
    } else {
      final index = orders.indexWhere((item) => item.id == order.id);
      orders[index] = order.copyWith(status: OrderStatus.forPayment);
      _recalculateTable(order.tableId);
      await _persist();
    }
    _recordLocalAudit('Solicitar cuenta', 'pedidos', order.id.toString());
    notifyListeners();
  }

  Future<void> _persist() async {
    if (_client != null && userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final saved = {
      'userId': userId,
      'role': role?.databaseValue,
      'displayName': displayName,
      'lastOnlineSyncAt': lastOnlineSyncAt?.toIso8601String(),
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
            },
          )
          .toList(),
      'shiftOpen': shiftOpen,
      'openingCash': openingCash,
      'closedCash': closedCash,
      'nextId': _nextId,
    };
    await prefs.setString(
      _client == null ? _storageKey : '$_remoteCachePrefix$userId',
      jsonEncode(saved),
    );
  }

  void _restore(Map<String, dynamic> saved) {
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
          );
        }),
      );
    shiftOpen = saved['shiftOpen'] as bool? ?? true;
    openingCash = (saved['openingCash'] as num?)?.toDouble() ?? 0;
    closedCash = (saved['closedCash'] as num?)?.toDouble() ?? 0;
    _nextId = saved['nextId'] as int? ?? 500;
  }

  void _replaceMenu(MenuItem updated) {
    final index = menu.indexWhere((item) => item.id == updated.id);
    menu[index] = updated;
  }

  void _recalculateTable(int? tableId) {
    if (tableId == null) return;
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
        actorName: displayName,
        actorRole: role!.databaseValue,
      ),
    );
    unawaited(_persist());
  }

  static String _paymentLabel(String value) => switch (value) {
    'YAPE_PLIN' => 'Yape / Plin',
    'TARJETA' => 'Tarjeta',
    _ => 'Efectivo',
  };

  static int tableNumbersForReceipt(
    List<dynamic> remoteOrders,
    int orderId,
    Map<int, int> tableNumbers,
  ) {
    final row = remoteOrders
        .where((entry) => entry['id'] == orderId)
        .firstOrNull;
    final tableId = row?['mesa_id'] as int?;
    return tableId == null ? 0 : tableNumbers[tableId] ?? 0;
  }

  static String orderLocationForReceipt(
    List<dynamic> remoteOrders,
    int orderId,
    Map<int, int> tableNumbers,
  ) {
    final row = remoteOrders
        .where((entry) => entry['id'] == orderId)
        .firstOrNull;
    if (row == null) return 'Pedido';
    final tableId = row['mesa_id'] as int?;
    return switch (FulfillmentType.fromDatabase(
      row['tipo_pedido'] as String? ?? 'MESA',
    )) {
      FulfillmentType.dineIn =>
        'Mesa ${tableId == null ? 0 : tableNumbers[tableId] ?? 0}',
      FulfillmentType.takeaway => 'Para llevar',
      FulfillmentType.delivery => 'Delivery',
    };
  }

  @override
  void dispose() {
    unawaited(_authSubscription?.cancel());
    unawaited(_realtime?.unsubscribe());
    super.dispose();
  }
}
