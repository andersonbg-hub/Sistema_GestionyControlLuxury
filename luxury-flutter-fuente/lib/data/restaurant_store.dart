import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' show ClientException;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';

part 'store/authentication.dart';
part 'store/remote_sync.dart';
part 'store/orders.dart';
part 'store/table_groups.dart';
part 'store/catalog.dart';
part 'store/inventory.dart';
part 'store/staff.dart';
part 'store/cashier.dart';
part 'store/persistence.dart';

typedef CashierShift = ({
  int? id,
  DateTime? openedAt,
  DateTime? closedAt,
  bool open,
  double openingCash,
  double closingCash,
});

const CashierShift _noCashierShift = (
  id: null,
  openedAt: null,
  closedAt: null,
  open: false,
  openingCash: 0,
  closingCash: 0,
);

String? _catalogImageUrl(String? value) {
  final url = value?.trim();
  if (url == null || url.isEmpty) return url;
  final parsed = Uri.tryParse(url);
  if (parsed == null ||
      parsed.scheme != 'https' ||
      parsed.host.isEmpty ||
      parsed.userInfo.isNotEmpty ||
      url.length > 2048 ||
      RegExp(r'\s').hasMatch(url)) {
    throw StateError('Ingresa una URL HTTPS válida para la imagen.');
  }
  return url;
}

class PaymentNotConfirmed implements Exception {
  const PaymentNotConfirmed({this.saved = false});

  final bool saved;

  @override
  String toString() => saved
      ? 'El cobro se registró. Actualiza la información para ver el recibo '
            'y el saldo antes de volver a cobrar.'
      : 'Supabase no confirmó el cobro. Actualiza la información y revisa el saldo '
            'y los pagos registrados antes de volver a cobrar.';
}

class LoginAttemptException implements Exception {
  const LoginAttemptException({this.isLastAttempt = false})
    : lockedUntil = null,
      message = 'El correo o la contraseña son incorrectos.';

  LoginAttemptException._locked(DateTime until, DateTime now)
    : isLastAttempt = false,
      lockedUntil = until,
      message = _lockMessage(until.difference(now));

  final bool isLastAttempt;
  final DateTime? lockedUntil;
  final String message;

  @override
  String toString() => message;

  static String _lockMessage(Duration remaining) {
    final minutes = math.max(
      1,
      (remaining.inMilliseconds / Duration.millisecondsPerMinute).ceil(),
    );
    final unit = minutes == 1 ? 'minuto' : 'minutos';
    return 'El acceso está bloqueado temporalmente. '
        'Vuelve a intentarlo en $minutes $unit.';
  }
}

class RestaurantStore extends ChangeNotifier {
  RestaurantStore({SupabaseClient? client, DateTime Function()? now})
    : _client = client,
      _now = now ?? DateTime.now {
    if (client == null) {
      _seed();
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

  CashierShift _newDemoShift() => (
    id: 0,
    openedAt: _now(),
    closedAt: null,
    open: true,
    openingCash: 0,
    closingCash: 0,
  );
  bool mustChangePassword = false;
  bool _passwordRecoveryPending = false;
  bool _signInInProgress = false;
  final Map<String, int> _volatileLoginAttempts = {};
  bool lastOrderQueued = false;
  bool _remoteSupportsTableGroups = false;
  DateTime? lastOnlineSyncAt;
  int get pendingOrderCount => pendingOrders.length;
  bool get isConnected => _client != null;
  bool get isDemo => !isConnected;
  SupabaseClient? get client => _client;
  RealtimeChannel? _realtime;
  StreamSubscription<AuthState>? _authSubscription;
  Future<void>? _remoteLoad;
  Future<void>? _orderSync;
  final Set<int> _paymentsInProgress = {};
  final Set<int> _paymentsToVerify = {};
  Timer? _realtimeRefreshTimer;
  Timer? _orderRetryTimer;
  bool _realtimeRefreshRunning = false;
  bool _realtimeRefreshPending = false;
  int _sessionVersion = 0;
  int _nextId = 500;

  void _publish() => notifyListeners();

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

  static final customerNameCharacters = RegExp(r'[\p{L}\p{M} ]', unicode: true);

  static bool isValidDeliveryName(String value) {
    final name = value.trim();
    return RegExp(r'\p{L}', unicode: true).hasMatch(name) &&
        name.replaceAll(customerNameCharacters, '').isEmpty;
  }

  static bool isValidCustomerPhone(String value) =>
      RegExp(r'^\d{9}$').hasMatch(value.trim());

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
