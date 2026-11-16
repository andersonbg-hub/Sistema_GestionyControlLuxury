import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' show ClientException;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

typedef CashierShift = ({
  int? id,
  DateTime? openedAt,
  bool open,
  double openingCash,
  double closingCash,
});

const CashierShift _noCashierShift = (
  id: null,
  openedAt: null,
  open: false,
  openingCash: 0,
  closingCash: 0,
);

class PaymentNotConfirmed implements Exception {
  const PaymentNotConfirmed();

  @override
  String toString() =>
      'Supabase no confirmó el cobro. Actualiza la información y revisa el saldo '
      'y los pagos registrados antes de volver a cobrar.';
}

class RestaurantStore extends ChangeNotifier {
  RestaurantStore({SupabaseClient? client, DateTime Function()? now})
    : _client = client,
      _now = now ?? DateTime.now {
    if (client == null) {
      _seed();
      _shift = _newDemoShift();
    } else {
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
        if (state.event == AuthChangeEvent.signedOut) {
          _clearConnectedState();
          notifyListeners();
        }
      });
    }
  }

  static const _storageKey = 'luxury.restaurant.demo.v1';
  static const _remoteCachePrefix = 'luxury.restaurant.offline.v1.';
  final SupabaseClient? _client;
  final DateTime Function() _now;
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
  CashierShift _shift = _noCashierShift;

  bool _shiftIsToday(CashierShift shift) {
    final openedAt = shift.openedAt;
    return openedAt != null && isSameLimaBusinessDay(openedAt, _now());
  }

  bool get shiftOpen => _shift.open && _shiftIsToday(_shift);
  double get openingCash => _shiftIsToday(_shift) ? _shift.openingCash : 0;
  double get closedCash => _shiftIsToday(_shift) ? _shift.closingCash : 0;

  CashierShift _newDemoShift([double amount = 0]) => (
    id: 0,
    openedAt: _now(),
    open: true,
    openingCash: amount,
    closingCash: 0,
  );
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
  Future<void>? _remoteLoad;
  Future<void>? _orderSync;
  final Set<int> _paymentsToVerify = {};
  Timer? _realtimeRefreshTimer;
  Timer? _orderRetryTimer;
  bool _realtimeRefreshRunning = false;
  bool _realtimeRefreshPending = false;
  int _sessionVersion = 0;
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
            if (!_connectionInterrupted(error) ||
                !await _restoreRemoteCache(user.id)) {
              if (_client.auth.currentUser?.id == user.id) await signOut();
              rethrow;
            }
            errorMessage =
                'Sin conexión con Supabase. Los datos guardados se muestran en modo local.';
            if (pendingOrders.isNotEmpty) {
              errorMessage =
                  '$errorMessage Hay pedidos pendientes de sincronización.';
            }
          }
        }
      }
    } catch (_) {
      errorMessage =
          'No se pudo restaurar la sesión. Intenta iniciar sesión de nuevo.';
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
    if (_signInInProgress) return;
    _signInInProgress = true;
    String? authenticatedId;
    try {
      final response = await client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      final user = response.user;
      if (user == null) {
        throw StateError('Supabase no devolvió un usuario autenticado.');
      }
      authenticatedId = user.id;
      await _loadProfile(user.id);
      errorMessage = null;
      notifyListeners();
    } catch (_) {
      if (authenticatedId != null &&
          client.auth.currentUser?.id == authenticatedId) {
        await signOut();
      }
      rethrow;
    } finally {
      _signInInProgress = false;
    }
  }

  Future<void> _loadProfile(String id) async {
    final client = _client!;
    final version = _sessionVersion;
    final profile = await client
        .from('usuarios')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (profile == null || profile['activo'] != true) {
      throw StateError(
        'No existe un perfil activo para esta cuenta. Solicita acceso al administrador.',
      );
    }
    final profileRole = StaffRole.fromDatabase(profile['rol'] as String);
    final queued = await _readPendingOrderQueue(id);
    if (!_sameSession(version, id)) return;
    await _loadRemoteData(profileId: id, profileRole: profileRole);
    if (!_sameSession(version, id)) return;
    userId = id;
    role = profileRole;
    displayName = profile['nombre_completo'] as String;
    mustChangePassword =
        _passwordRecoveryPending ||
        _client.auth.currentUser?.appMetadata['must_change_password'] == true;
    pendingOrders
      ..clear()
      ..addAll(queued);
    orders.addAll(queued);
    await _saveRemoteCache();
    if (_sameSession(version, id)) _subscribeRealtime();
  }

  Future<bool> _restoreRemoteCache(String id) async {
    final version = _sessionVersion;
    final prefs = await SharedPreferences.getInstance();
    if (!_sameSession(version, id)) return false;
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

  Future<List<RestaurantOrder>> _readPendingOrderQueue(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('$_remoteCachePrefix$id');
    if (saved == null) return [];
    final data = jsonDecode(saved) as Map<String, dynamic>;
    if (data['userId'] != id) return [];
    return [
      for (final row in data['pendingOrders'] as List<dynamic>? ?? [])
        RestaurantOrder.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }

  Future<void> signOut() async {
    _clearConnectedState();
    notifyListeners();
    final client = _client;
    if (client != null) {
      try {
        await client.auth.signOut();
      } on AuthException {
        // Supabase Auth clears the local session before revoking the token.
        if (client.auth.currentSession != null) rethrow;
      }
    }
  }

  bool _sameSession(int version, String? id) =>
      _sessionVersion == version &&
      (id == null || _client?.auth.currentUser?.id == id);

  bool _connectionInterrupted(Object error) =>
      error is TimeoutException ||
      error is ClientException ||
      error is AuthRetryableFetchException ||
      (error is PostgrestException &&
          const {'502', '503', '504', 'PGRST002'}.contains(error.code));

  void _clearConnectedState() {
    _sessionVersion++;
    _realtimeRefreshTimer?.cancel();
    _realtimeRefreshTimer = null;
    _orderRetryTimer?.cancel();
    _orderRetryTimer = null;
    _realtimeRefreshRunning = false;
    _realtimeRefreshPending = false;
    final channel = _realtime;
    _realtime = null;
    if (channel != null) unawaited(_client?.removeChannel(channel));
    _remoteLoad = null;
    _orderSync = null;
    _paymentsToVerify.clear();
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
      _shift = _noCashierShift;
      lastOnlineSyncAt = null;
    }
  }

  Future<void> _handleExternalSignIn(String id) async {
    _clearConnectedState();
    final version = _sessionVersion;
    notifyListeners();
    try {
      await _loadProfile(id);
      if (!_sameSession(version, id)) return;
      errorMessage = null;
      notifyListeners();
    } catch (_) {
      if (!_sameSession(version, id)) return;
      await signOut();
      errorMessage = 'No se pudo validar la sesión abierta en otra pestaña.';
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
        name: 'Administrador Luxury',
        email: 'administracion@example.invalid',
        role: StaffRole.administrator,
        department: 'Administración',
        employmentStatus: 'ACTIVO',
      ),
      StaffMember(
        id: 'local-manager',
        name: 'Gerente General',
        email: 'gerencia@example.invalid',
        role: StaffRole.manager,
        department: 'Gerencia',
        employmentStatus: 'ACTIVO',
      ),
      StaffMember(
        id: 'local-kitchen',
        name: 'Cocinero Principal',
        email: 'cocina@example.invalid',
        role: StaffRole.kitchen,
        department: 'Cocina',
        employmentStatus: 'ACTIVO',
      ),
      StaffMember(
        id: 'local-waiter',
        name: 'Mesero 1 - Salón',
        email: 'mesero1@example.invalid',
        role: StaffRole.waiter,
        department: 'Primer piso',
        employmentStatus: 'ACTIVO',
      ),
      StaffMember(
        id: 'local-waiter-2',
        name: 'Mesero 2 - Salón',
        email: 'mesero2@example.invalid',
        role: StaffRole.waiter,
        department: 'Segundo piso',
        employmentStatus: 'ACTIVO',
      ),
      StaffMember(
        id: 'local-cashier',
        name: 'Cajero Principal',
        email: 'caja@example.invalid',
        role: StaffRole.cashier,
        department: 'Caja y Facturación',
        employmentStatus: 'ACTIVO',
      ),
      StaffMember(
        id: 'local-head-chef',
        name: 'Jefatura de cocina',
        email: 'jefatura.cocina@example.invalid',
        role: StaffRole.headChef,
        department: 'Cocina',
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
      client
          .from('insumos')
          .select(
            'id,nombre,descripcion,unidad,stock_actual,stock_minimo,activo',
          ),
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
    orders.addAll(pendingOrders);
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
        notifyListeners();
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
    notifyListeners();
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
    _shift = _newDemoShift();
    _seed();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    notifyListeners();
  }

  static bool isValidCustomerPhone(String value) =>
      RegExp(r'^\d{9}$').hasMatch(value.trim());

  bool tableBillingStarted(RestaurantTable table) =>
      table.status == TableStatus.payment ||
      orders.any(
        (order) =>
            order.tableId == table.id &&
            !order.retirementConfirmed &&
            order.status != OrderStatus.cancelled &&
            (order.status == OrderStatus.forPayment ||
                order.status == OrderStatus.paid ||
                order.payments.isNotEmpty),
      );

  bool _canLinkAdditionalOrder(RestaurantOrder order, int tableId) =>
      order.tableId == tableId &&
      !order.retirementConfirmed &&
      !order.pendingSync &&
      order.status != OrderStatus.cancelled &&
      order.status != OrderStatus.forPayment &&
      order.status != OrderStatus.paid;

  RestaurantOrder? additionalOrderParent(RestaurantTable table) {
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
        (current.status == TableStatus.available &&
            !orders.any(
              (order) =>
                  order.tableId == current.id && !order.retirementConfirmed,
            ));
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
        (customerName.trim().isEmpty || !isValidCustomerPhone(customerPhone))) {
      throw StateError(
        'Indica el nombre del cliente y un teléfono de 9 dígitos.',
      );
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
          lines: List.unmodifiable(lines),
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
      waiterId: userId,
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
        if (requestId == null) {
          throw StateError(
            'Un pedido pendiente no tiene identificador de sincronización.',
          );
        }
        dynamic result;
        try {
          result = await client.rpc(
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
        pendingOrders.removeWhere(
          (pending) => pending.clientRequestId == requestId,
        );
        orders.removeWhere((pending) => pending.clientRequestId == requestId);
        if (!orders.any((item) => item.id == confirmedId)) {
          orders.insert(0, order.copyWith(id: confirmedId, pendingSync: false));
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
      notifyListeners();
    } catch (error) {
      if (_sessionVersion != version) return;
      errorMessage = 'Quedan pedidos por sincronizar. Revisa «Mis pedidos».';
      if (_connectionInterrupted(error)) _scheduleOrderRetry(version);
      await _saveRemoteCache();
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
    final index = orders.indexWhere((value) => value.id == order.id);
    if (index < 0) throw StateError('No se encontró el pedido.');
    final current = orders[index];
    if (current.pendingSync ||
        current.status != OrderStatus.pending ||
        current.payments.isNotEmpty ||
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
      orders[index] = current.copyWith(
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
    final linesToAdvance = order.lines.where(
      (line) => line.status == currentKitchenStage,
    );
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
      final index = orders.indexWhere((item) => item.id == order.id);
      final updatedLines = order.lines
          .map(
            (line) => line.status == currentKitchenStage
                ? line.copyWith(status: nextStatus)
                : line,
          )
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
    if (_paymentsToVerify.contains(order.id)) {
      throw const PaymentNotConfirmed();
    }
    if (!shiftOpen) {
      throw StateError(
        'La caja de hoy está cerrada. Administración debe abrir el turno para registrar cobros.',
      );
    }
    if (order.pendingSync) {
      throw StateError('Sincroniza el pedido antes de registrar pagos.');
    }
    final currentOrder = orders
        .where((item) => item.id == order.id)
        .firstOrNull;
    if (currentOrder == null || currentOrder.status == OrderStatus.cancelled) {
      throw StateError('El pedido ya no admite pagos.');
    }
    if (!amount.isFinite ||
        amount <= 0 ||
        amount > currentOrder.balance + 0.001) {
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
        (cashReceived == null ||
            !cashReceived.isFinite ||
            cashReceived < amount)) {
      throw StateError('El efectivo recibido debe cubrir el monto del abono.');
    }
    if ((kitchenStage(currentOrder) == OrderStatus.pending ||
            kitchenStage(currentOrder) == OrderStatus.preparing) &&
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
      final version = _sessionVersion;
      try {
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
        notifyListeners();
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
          createdAt: DateTime.now(),
          reference: reference.trim(),
          cashReceived: cashReceived,
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
    notifyListeners();
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
    notifyListeners();
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
    notifyListeners();
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
    notifyListeners();
  }

  Future<void> fulfillStockRequest(StockRequest request) async {
    if (request.status != 'EN_PROCESO') {
      throw StateError(
        'La solicitud debe estar en proceso para recibir stock.',
      );
    }
    if (_client != null) {
      await _client.rpc(
        'recibir_solicitud_reabastecimiento',
        params: {'p_solicitud_id': request.id},
      );
      await _loadRemoteData();
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
    notifyListeners();
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
    notifyListeners();
  }

  Future<bool> addStaffMember({
    required String name,
    required String email,
    required StaffRole role,
    String? password,
    String documentId = '',
    String personalEmail = '',
    String phone = '',
    String address = '',
    String department = '',
    String employmentStatus = 'ACTIVO',
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (staff.any((member) => member.email.toLowerCase() == normalizedEmail)) {
      throw StateError('Ya existe una cuenta con ese correo.');
    }
    final String id;
    var emailSent = false;
    if (_client != null) {
      final initialPassword = password?.trim() ?? '';
      if (initialPassword.length < 8) {
        throw StateError(
          'La contraseña temporal debe tener al menos 8 caracteres.',
        );
      }
      final FunctionResponse result;
      try {
        result = await _client.functions.invoke(
          'manage-staff',
          body: {
            'action': 'create',
            'name': name.trim(),
            'email': normalizedEmail,
            'role': role.databaseValue,
            'password': initialPassword,
            'documentId': documentId.trim(),
            'personalEmail': personalEmail.trim(),
            'phone': phone.trim(),
            'address': address.trim(),
            'department': department.trim(),
            'employmentStatus': employmentStatus,
          },
        );
      } on FunctionException catch (error) {
        final details = error.details;
        final message = details is Map ? details['error'] : null;
        throw StateError(
          message is String
              ? message
              : switch (error.status) {
                  401 => 'Vuelve a iniciar sesión para crear la cuenta.',
                  403 => 'Solo un administrador activo puede crear cuentas.',
                  404 => 'Falta publicar la función de cuentas en Supabase.',
                  409 => 'Ya existe una cuenta con ese correo.',
                  _ => 'No se pudo crear la cuenta. Inténtalo de nuevo.',
                },
        );
      } on Exception {
        throw StateError(
          'No se pudo confirmar el alta. Actualiza la lista antes de volver a intentarlo.',
        );
      }
      final response = result.data;
      if (response is! Map || response['id'] is! String) {
        throw StateError('Supabase no confirmó la creación de la cuenta.');
      }
      id = response['id'] as String;
      // Earlier versions of the function succeeded only when the mail was sent.
      emailSent = response['emailSent'] != false;
      try {
        await _loadRemoteData();
      } on Exception {
        // The function already confirmed the account. Keep it visible if refresh fails.
      }
    } else {
      id = 'local-${_nextId++}';
    }
    if (!staff.any((member) => member.id == id)) {
      staff.add(
        StaffMember(
          id: id,
          name: name.trim(),
          email: normalizedEmail,
          role: role,
          active: employmentStatus != 'INACTIVO',
          documentId: documentId.trim(),
          personalEmail: personalEmail.trim(),
          phone: phone.trim(),
          address: address.trim(),
          department: department.trim(),
          employmentStatus: employmentStatus,
        ),
      );
    }
    if (_client == null) await _persist();
    _recordLocalAudit('Crear usuario', 'usuarios', id);
    notifyListeners();
    return emailSent;
  }

  Future<void> updateStaffMember({
    required StaffMember member,
    required String name,
    required String email,
    required StaffRole role,
    String? documentId,
    String? personalEmail,
    String? phone,
    String? address,
    String? department,
    String? employmentStatus,
  }) async {
    final currentRole = this.role ?? StaffRole.waiter;
    if (staffRank(currentRole) < staffRank(member.role)) {
      throw StateError(
        'No tienes permisos para modificar a un usuario de mayor rango (${member.role.label}).',
      );
    }
    if (member.role == StaffRole.manager && currentRole != StaffRole.manager) {
      throw StateError(
        'Solo un Gerente puede gestionar la cuenta de otro Gerente.',
      );
    }
    final nextStatus = employmentStatus ?? member.employmentStatus;
    if (_client != null) {
      final result = await _client.functions.invoke(
        'manage-staff',
        body: {
          'action': 'update',
          'id': member.id,
          'name': name.trim(),
          'email': email.trim(),
          'role': role.databaseValue,
          'documentId': documentId?.trim() ?? member.documentId,
          'personalEmail': personalEmail?.trim() ?? member.personalEmail,
          'phone': phone?.trim() ?? member.phone,
          'address': address?.trim() ?? member.address,
          'department': department?.trim() ?? member.department,
          'employmentStatus': nextStatus,
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
        active: nextStatus != 'INACTIVO',
        employmentStatus: nextStatus,
        documentId: documentId?.trim() ?? member.documentId,
        personalEmail: personalEmail?.trim() ?? member.personalEmail,
        phone: phone?.trim() ?? member.phone,
        address: address?.trim() ?? member.address,
        department: department?.trim() ?? member.department,
      );
      await _persist();
    }
    notifyListeners();
  }

  StaffMember? get currentStaffMember =>
      staff.where((member) => member.id == userId).firstOrNull ??
      (isDemo
          ? staff.where((member) => member.role == role).firstOrNull
          : null);

  String get currentUserEmail =>
      _client?.auth.currentUser?.email ?? currentStaffMember?.email ?? '';

  String waiterDisplayLabel(RestaurantOrder? order) {
    if (order == null) return 'Mesero 1';
    final waiters = staff.where((s) => s.role == StaffRole.waiter).toList();
    if (order.waiterId != null) {
      final index = waiters.indexWhere((s) => s.id == order.waiterId);
      if (index >= 0) {
        final w = waiters[index];
        final num = index + 1;
        if (w.name.isEmpty ||
            w.name == 'Mesero' ||
            w.name.startsWith('Mesero $num')) {
          return 'Mesero $num';
        }
        return 'Mesero $num (${w.name})';
      }
    }
    final nameIndex = waiters.indexWhere((s) => s.name == order.waiterName);
    if (nameIndex >= 0) {
      final w = waiters[nameIndex];
      final num = nameIndex + 1;
      if (w.name.startsWith('Mesero $num')) return w.name;
      return 'Mesero $num (${w.name})';
    }
    if (order.waiterName.isNotEmpty && order.waiterName != 'Equipo Luxury') {
      return order.waiterName;
    }
    return 'Mesero 1';
  }

  String profilePhotoUrl(String path) {
    final client = _client;
    if (client == null || path.isEmpty) return '';
    return client.storage.from('employee-profiles').getPublicUrl(path);
  }

  Future<void> updateOwnStaffProfile({
    required String personalEmail,
    required String phone,
    required String address,
    required String department,
    String? photoPath,
  }) async {
    if (personalEmail.isNotEmpty &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(personalEmail.trim())) {
      throw StateError('Indica un correo personal válido.');
    }
    if (_client != null) {
      await _client.rpc(
        'actualizar_perfil_propio',
        params: {
          'p_correo_personal': personalEmail.trim(),
          'p_telefono': phone.trim(),
          'p_direccion': address.trim(),
          'p_departamento': department.trim(),
          'p_foto_path': photoPath,
        },
      );
      await _loadRemoteData();
    } else {
      final member = currentStaffMember;
      if (member == null) throw StateError('No se encontró el perfil propio.');
      final index = staff.indexWhere((item) => item.id == member.id);
      staff[index] = member.copyWith(
        personalEmail: personalEmail.trim(),
        phone: phone.trim(),
        address: address.trim(),
        department: department.trim(),
        photoPath: photoPath,
      );
      await _persist();
    }
    notifyListeners();
  }

  Future<void> uploadStaffPhoto({
    required StaffMember member,
    required Uint8List bytes,
    required String extension,
  }) async {
    final client = _client;
    if (client == null) {
      throw StateError('La carga de fotos requiere conexión con Supabase.');
    }
    if (bytes.isEmpty || bytes.length > 2 * 1024 * 1024) {
      throw StateError('La foto debe tener un tamaño máximo de 2 MB.');
    }
    final format = extension.toLowerCase();
    final contentType = switch (format) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => throw StateError('Usa una foto JPG, PNG o WebP.'),
    };
    final path = '${member.id}/perfil.$format';
    await client.storage
        .from('employee-profiles')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: contentType),
        );
    if (member.id == userId) {
      await updateOwnStaffProfile(
        personalEmail: member.personalEmail,
        phone: member.phone,
        address: member.address,
        department: member.department,
        photoPath: path,
      );
    } else {
      await client
          .from('usuarios')
          .update({'foto_path': path})
          .eq('id', member.id);
      await _loadRemoteData();
      notifyListeners();
    }
  }

  Future<void> resetStaffPassword({
    required StaffMember member,
    required String password,
  }) async {
    final currentRole = role ?? StaffRole.waiter;
    if (staffRank(currentRole) < staffRank(member.role)) {
      throw StateError(
        'No tienes permisos para restablecer la contraseña de un usuario de mayor rango (${member.role.label}).',
      );
    }
    if (member.role == StaffRole.manager && currentRole != StaffRole.manager) {
      throw StateError(
        'Solo un Gerente puede restablecer la cuenta de otro Gerente.',
      );
    }
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
    final currentRole = role ?? StaffRole.waiter;
    if (staffRank(currentRole) < staffRank(member.role)) {
      throw StateError(
        'No tienes permisos para cambiar el estado de un usuario de mayor rango (${member.role.label}).',
      );
    }
    if (member.role == StaffRole.manager && currentRole != StaffRole.manager) {
      throw StateError(
        'Solo un Gerente puede cambiar el estado de un Gerente.',
      );
    }
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
          .update({
            'activo': !member.active,
            'estado_laboral': member.active ? 'INACTIVO' : 'ACTIVO',
          })
          .eq('id', member.id);
      await _loadRemoteData();
    } else {
      final index = staff.indexWhere((item) => item.id == member.id);
      final active = !member.active;
      staff[index] = member.copyWith(
        active: active,
        employmentStatus: active ? 'ACTIVO' : 'INACTIVO',
      );
      await _persist();
    }
    _recordLocalAudit(
      member.active ? 'Desactivar usuario' : 'Activar usuario',
      'usuarios',
      member.id,
    );
    notifyListeners();
  }

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

  Future<void> setShiftOpen(
    bool open, {
    required String cashierId,
    required double countedCash,
    int? shiftId,
  }) async {
    _requireCashAdministration();
    if (!countedCash.isFinite || countedCash < 0) {
      throw StateError('Ingresa un importe válido.');
    }
    if (_client != null) {
      await _client.rpc(
        'administrar_turno_caja',
        params: {
          'p_cajero_id': cashierId,
          'p_abrir': open,
          'p_monto': countedCash,
          'p_turno_id': shiftId,
        },
      );
      return;
    }

    if (open && _shift.open && !_shiftIsToday(_shift)) {
      throw StateError('Cierra el turno anterior antes de abrir el de hoy.');
    }
    if (open == _shift.open) return;
    _shift = open
        ? _newDemoShift(countedCash)
        : (
            id: _shift.id,
            openedAt: _shift.openedAt,
            open: false,
            openingCash: _shift.openingCash,
            closingCash: countedCash,
          );
    await _persist();
    _recordLocalAudit(
      open ? 'Abrir turno de caja' : 'Cerrar turno de caja',
      'turnos_caja',
      cashierId,
    );
    notifyListeners();
  }

  Future<void> setOrderForPayment(RestaurantOrder order) async {
    final index = orders.indexWhere((item) => item.id == order.id);
    if (index < 0) throw StateError('No se encontró el pedido.');
    final current = orders[index];
    if (current.pendingSync) {
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
    notifyListeners();
  }

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
      'shiftOpenedAt': _shift.openedAt?.toIso8601String(),
      'openingCash': _shift.openingCash,
      'closedCash': _shift.closingCash,
      'nextId': _nextId,
    };
    final key = isDemo ? _storageKey : '$_remoteCachePrefix$id';
    if (!await prefs.setString(key, jsonEncode(saved))) {
      throw StateError('El navegador no pudo guardar los cambios locales.');
    }
  }

  void _restore(Map<String, dynamic> saved) {
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
      id: null,
      openedAt: DateTime.tryParse(saved['shiftOpenedAt'] as String? ?? ''),
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
    _sessionVersion++;
    _realtimeRefreshTimer?.cancel();
    _orderRetryTimer?.cancel();
    unawaited(_authSubscription?.cancel());
    unawaited(_realtime?.unsubscribe());
    super.dispose();
  }
}
