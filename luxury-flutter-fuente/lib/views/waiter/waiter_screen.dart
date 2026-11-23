import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_widgets.dart';
import '../../data/restaurant_store.dart';
import '../../models/models.dart';

part 'pages/order_actions_view.dart';
part 'pages/floor_view.dart';
part 'pages/order_creation_view.dart';
part 'pages/orders_view.dart';

class WaiterScreen extends StatefulWidget {
  const WaiterScreen({super.key, required this.store});
  final RestaurantStore store;

  @override
  State<WaiterScreen> createState() => _WaiterScreenState();
}

class _CartLine {
  _CartLine(this.item);
  final MenuItem item;
  int quantity = 1;
  String note = '';
}

class _DishArtwork extends StatelessWidget {
  const _DishArtwork({required this.item, this.compact = false});

  final MenuItem item;
  final bool compact;

  static const _backgrounds = [
    Color(0xFFF0D7BD),
    Color(0xFFE7D8B7),
    Color(0xFFE9C7B5),
    Color(0xFFD8E1C5),
    Color(0xFFE7D1D8),
  ];
  static const _accents = [
    Color(0xFFC65C36),
    Color(0xFF77914B),
    Color(0xFFE6A13A),
    Color(0xFF87443A),
    Color(0xFFD87C57),
  ];

  @override
  Widget build(BuildContext context) {
    final seed = item.id.abs();
    final background = _backgrounds[seed % _backgrounds.length];
    final accent = _accents[seed % _accents.length];
    final category = item.category.toLowerCase();
    final name = item.name.toLowerCase();
    final icon = category.contains('bebida') || name.contains('jugo')
        ? Icons.local_drink_outlined
        : category.contains('postre') || name.contains('helado')
        ? Icons.cake_outlined
        : category.contains('sopa') || name.contains('caldo')
        ? Icons.ramen_dining
        : name.contains('pollo') || name.contains('carne')
        ? Icons.kebab_dining
        : name.contains('arroz') || name.contains('chaufa')
        ? Icons.rice_bowl
        : name.contains('wontan') ||
              name.contains('wantan') ||
              name.contains('roll')
        ? Icons.lunch_dining
        : Icons.restaurant_menu;

    return Container(
      width: compact ? 48 : null,
      height: compact ? 48 : null,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [background.withValues(alpha: .6), luxuryBone],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            right: compact ? -10 : -20,
            top: compact ? -12 : -25,
            child: Container(
              width: compact ? 35 : 100,
              height: compact ? 35 : 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: .32),
              ),
            ),
          ),
          Container(
            width: compact ? 36 : 94,
            height: compact ? 36 : 94,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFFFDFC),
              border: Border.all(color: const Color(0xFFE8DED6), width: 2),
              boxShadow: [
                BoxShadow(
                  color: luxuryBrown.withValues(alpha: .12),
                  blurRadius: compact ? 4 : 12,
                  offset: Offset(0, compact ? 2 : 5),
                ),
              ],
            ),
            child: Center(
              child: Container(
                width: compact ? 27 : 74,
                height: compact ? 27 : 74,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: background.withValues(alpha: .72),
                ),
                child: Icon(icon, size: compact ? 18 : 46, color: luxuryBrown),
              ),
            ),
          ),
          if (!compact) ...[
            Positioned(
              left: 18,
              bottom: 20,
              child: _GarnishDot(color: accent, size: 12),
            ),
            Positioned(
              right: 24,
              top: 18,
              child: _GarnishDot(color: luxuryGreen, size: 9),
            ),
            Positioned(
              right: 34,
              bottom: 24,
              child: _GarnishDot(color: luxuryGold, size: 7),
            ),
          ],
        ],
      ),
    );
  }
}

class _GarnishDot extends StatelessWidget {
  const _GarnishDot({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}

class _RectangularTableGraphic extends StatelessWidget {
  const _RectangularTableGraphic({required this.table});

  final RestaurantTable table;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(table.status.databaseValue);
    final visibleSeats = table.capacity.clamp(1, 16).toInt();
    final topSeats = (visibleSeats + 1) ~/ 2;

    Widget seatRow(int count) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          Container(
            width: 12,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .24),
              border: Border.all(color: color.withValues(alpha: .65)),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );

    return ExcludeSemantics(
      child: SizedBox(
        height: 50,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              seatRow(topSeats),
              const SizedBox(height: 3),
              Container(
                width: math.max(64, topSeats * 16 + 8).toDouble(),
                height: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  border: Border.all(color: color),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.table_restaurant, size: 17),
              ),
              const SizedBox(height: 3),
              seatRow(visibleSeats - topSeats),
            ],
          ),
        ),
      ),
    );
  }
}

class _WaiterScreenState extends State<WaiterScreen>
    with OperationProgress<WaiterScreen> {
  int page = 0;
  bool isCreatingOrder = false;
  bool _showCompactOrder = false;
  int? selectedTableId;
  List<RestaurantTable> joinedOrderTables = const [];
  int diners = 2;
  String category = 'Todas';
  final dishSearch = TextEditingController();
  DateTimeRange? historyRange;
  String historyQuery = '';
  FulfillmentType fulfillmentType = FulfillmentType.dineIn;
  String customerName = '';
  String customerPhone = '';
  String deliveryAddress = '';
  final Map<int, _CartLine> cart = {};
  RestaurantOrder? editingOrder;
  int? additionalParentId;

  RestaurantStore get store => widget.store;
  void _setState(VoidCallback update) => setState(update);
  RestaurantTable? get selectedTable =>
      store.tables.where((table) => table.id == selectedTableId).firstOrNull;
  int get _cartQuantity =>
      cart.values.fold(0, (sum, line) => sum + line.quantity);
  double get cartTotal =>
      cart.values.fold(0, (sum, line) => sum + line.item.price * line.quantity);

  Future<void> _run(
    Future<void> Function() action, {
    String label = 'Procesando…',
  }) => runOperation(action, label: label);

  @override
  void dispose() {
    dishSearch.dispose();
    super.dispose();
  }

  Widget _body() {
    if (isCreatingOrder) {
      return _newOrder();
    }
    return switch (page) {
      0 => _floor(),
      1 => _orders(),
      2 => _orders(history: true),
      _ => _floor(),
    };
  }

  static const _labels = ['Mesas', 'Mis pedidos', 'Historial'];
  static const _icons = [
    Icons.table_restaurant,
    Icons.receipt_long,
    Icons.history,
  ];

  Widget _nav() => LuxurySideMenu(
    entries: [
      for (final (index, label) in _labels.indexed)
        LuxuryMenuEntry(label: label, icon: _icons[index]),
    ],
    selectedIndex: isCreatingOrder ? 0 : page,
    onDestinationSelected: (value) => setState(() {
      page = value;
      isCreatingOrder = false;
    }),
  );

  Future<void> _chooseNewOrderTable() async {
    final table = await showLuxuryDialog<RestaurantTable>(
      context: context,
      builder: (context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final available = store.tables.where(
            (table) =>
                store.canOrderAtTable(table) &&
                store.additionalOrderParent(table) == null,
          );
          return AlertDialog(
            scrollable: true,
            title: const Text('Elegir mesa'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (available.isEmpty)
                    const Text('No hay mesas disponibles.'),
                  for (final table in available)
                    ListTile(
                      leading: const Icon(Icons.table_restaurant),
                      title: Text('Mesa ${table.number}'),
                      subtitle: Text('${table.capacity} asientos'),
                      onTap: () => Navigator.pop(context, table),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
            ],
          );
        },
      ),
    );
    if (table != null && mounted) _openOrder(table);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final narrow = constraints.maxWidth < 760;
      return Scaffold(
        body: Row(
          children: [
            if (!narrow) ...[_nav()],
            Expanded(
              child: PinnedHeaderHost(
                section: (page, isCreatingOrder),
                child: SectionTransition(
                  section: (page, isCreatingOrder),
                  child: _body(),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: narrow
            ? NavigationBar(
                selectedIndex: isCreatingOrder ? 0 : page,
                onDestinationSelected: (value) => setState(() {
                  page = value;
                  isCreatingOrder = false;
                }),
                destinations: List.generate(
                  _labels.length,
                  (index) => NavigationDestination(
                    icon: Icon(_icons[index]),
                    label: _labels[index],
                  ),
                ),
              )
            : null,
      );
    },
  );
}
