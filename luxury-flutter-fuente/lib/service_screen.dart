import 'package:flutter/material.dart';

import 'app_widgets.dart';
import 'models.dart';
import 'receipt_pdf.dart';
import 'store.dart';

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

class _WaiterScreenState extends State<WaiterScreen> {
  int page = 0;
  int? selectedTableId;
  int diners = 2;
  String category = 'Todas';
  FulfillmentType fulfillmentType = FulfillmentType.dineIn;
  String customerName = '';
  String customerPhone = '';
  String deliveryAddress = '';
  final Map<int, _CartLine> cart = {};
  RestaurantOrder? editingOrder;
  int? additionalParentId;

  RestaurantStore get store => widget.store;
  RestaurantTable? get selectedTable =>
      store.tables.where((table) => table.id == selectedTableId).firstOrNull;
  double get cartTotal =>
      cart.values.fold(0, (sum, line) => sum + line.item.price * line.quantity);

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) {
        await showResultDialog(context, success: false, message: '$error');
      }
    }
  }

  void _openOrder(
    RestaurantTable table, {
    RestaurantOrder? editOrder,
    RestaurantOrder? parentOrder,
  }) {
    setState(() {
      selectedTableId = table.id;
      fulfillmentType = FulfillmentType.dineIn;
      customerName = editOrder?.customerName ?? '';
      customerPhone = editOrder?.customerPhone ?? '';
      deliveryAddress = editOrder?.deliveryAddress ?? '';
      editingOrder = editOrder;
      additionalParentId = parentOrder?.id;
      diners = editOrder?.diners ?? (table.capacity < 2 ? table.capacity : 2);
      cart.clear();
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
      page = 1;
    });
  }

  void _openOffPremiseOrder(FulfillmentType type) {
    setState(() {
      selectedTableId = null;
      fulfillmentType = type;
      customerName = '';
      customerPhone = '';
      deliveryAddress = '';
      editingOrder = null;
      additionalParentId = null;
      diners = 1;
      cart.clear();
      page = 1;
    });
  }

  Future<void> _submitOrder() async {
    final table = selectedTable;
    if (fulfillmentType == FulfillmentType.dineIn && table == null) {
      await showResultDialog(
        context,
        success: false,
        message: 'Selecciona una mesa primero.',
      );
      return;
    }
    if (fulfillmentType != FulfillmentType.dineIn &&
        (customerName.trim().isEmpty || customerPhone.trim().isEmpty)) {
      await showResultDialog(
        context,
        success: false,
        message: 'Indica el nombre y teléfono del cliente.',
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
          parentOrderId: additionalParentId,
          fulfillmentType: fulfillmentType,
          customerName: customerName.trim(),
          customerPhone: customerPhone.trim(),
          deliveryAddress: deliveryAddress.trim(),
        );
      }
      if (!mounted) return;
      final wasEditing = editingOrder != null;
      setState(() {
        cart.clear();
        editingOrder = null;
        additionalParentId = null;
        page = 2;
      });
      await showResultDialog(
        context,
        success: true,
        message: wasEditing
            ? 'Cambios del pedido guardados.'
            : store.lastOrderQueued
            ? 'Pedido guardado sin conexión. Se sincronizará al recuperar la red.'
            : 'Comanda enviada a cocina.',
      );
    });
  }

  Future<void> _tableActions(RestaurantTable table) async {
    final activeOrders = store.orders.where(
      (order) =>
          order.tableId == table.id &&
          order.status != OrderStatus.paid &&
          order.status != OrderStatus.cancelled &&
          order.status != OrderStatus.delivered,
    );
    final settledOrders = store.orders
        .where(
          (order) =>
              order.tableId == table.id &&
              (order.status == OrderStatus.paid ||
                  order.status == OrderStatus.cancelled) &&
              !order.retirementConfirmed,
        )
        .toList();
    final paidOrders = settledOrders
        .where((order) => order.status == OrderStatus.paid)
        .toList();
    final canRelease =
        settledOrders.isNotEmpty &&
        store.orders
            .where((order) => order.tableId == table.id)
            .every(
              (order) =>
                  order.status == OrderStatus.paid ||
                  order.status == OrderStatus.cancelled,
            ) &&
        settledOrders.every(
          (order) =>
              order.status != OrderStatus.paid ||
              kitchenStage(order) == OrderStatus.delivered,
        );
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ResponsiveListTile(
                leading: const Icon(Icons.table_restaurant, color: luxuryGold),
                title: Text('Mesa ${table.number}'),
                subtitle: Text(
                  '${table.capacity} personas · ${table.status.label}',
                ),
              ),
              ResponsiveListTile(
                leading: const Icon(Icons.add_shopping_cart),
                title: const Text('Nuevo pedido'),
                onTap: () {
                  Navigator.pop(context);
                  _openOrder(table);
                },
              ),
              if (activeOrders.isNotEmpty)
                ResponsiveListTile(
                  leading: const Icon(Icons.receipt_long),
                  title: Text('Ver pedidos abiertos (${activeOrders.length})'),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() => page = 2);
                  },
                ),
              if (paidOrders.isNotEmpty)
                ResponsiveListTile(
                  leading: const Icon(Icons.add_shopping_cart),
                  title: const Text('Agregar consumo adicional'),
                  subtitle: Text('Vinculado al pedido #${paidOrders.last.id}'),
                  onTap: () {
                    Navigator.pop(context);
                    _openOrder(table, parentOrder: paidOrders.last);
                  },
                ),
              if (canRelease)
                ResponsiveListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: const Text('Confirmar retiro y liberar mesa'),
                  onTap: () {
                    Navigator.pop(context);
                    _run(() => store.confirmTableRelease(table));
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _floor() {
    final tables = store.tables.where((table) => table.active).toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SectionTitle(
          title: 'Mesas',
          subtitle: 'Toca una mesa para abrir el servicio',
          trailing: FilledButton.icon(
            onPressed: tables.isEmpty ? null : () => _openOrder(tables.first),
            icon: const Icon(Icons.add),
            label: const Text('Nuevo pedido'),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => _openOffPremiseOrder(FulfillmentType.takeaway),
              icon: const Icon(Icons.shopping_bag_outlined),
              label: const Text('Para llevar'),
            ),
            OutlinedButton.icon(
              onPressed: () => _openOffPremiseOrder(FulfillmentType.delivery),
              icon: const Icon(Icons.delivery_dining),
              label: const Text('Delivery'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 9,
          runSpacing: 9,
          children: [
            _legend('Disponible', luxuryGreen),
            _legend('Ocupada', luxuryGold),
            _legend('Por cobrar', luxuryRed),
          ],
        ),
        const SizedBox(height: 14),
        if (tables.isEmpty)
          const EmptyState(
            message: 'No hay mesas activas en el salón.',
            icon: Icons.table_restaurant,
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 850
                  ? 4
                  : constraints.maxWidth > 650
                  ? 3
                  : constraints.maxWidth > 360
                  ? 2
                  : 1;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: tables.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  mainAxisExtent:
                      205 * MediaQuery.textScalerOf(context).scale(1),
                ),
                itemBuilder: (context, index) {
                  final table = tables[index];
                  final orderCount = store.orders
                      .where(
                        (order) =>
                            order.tableId == table.id &&
                            order.status != OrderStatus.paid &&
                            order.status != OrderStatus.cancelled &&
                            order.status != OrderStatus.delivered,
                      )
                      .length;
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _tableActions(table),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(
                              color: statusColor(table.status.databaseValue),
                              width: 5,
                            ),
                          ),
                        ),
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.table_restaurant,
                              color: luxuryBrown,
                            ),
                            const Spacer(),
                            Text(
                              'Mesa ${table.number}',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${table.capacity} asientos · $orderCount ${orderCount == 1 ? 'pedido' : 'pedidos'}',
                            ),
                            const SizedBox(height: 8),
                            StatusBadge.table(table.status),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
      ],
    );
  }

  Widget _legend(String label, Color color) => Chip(
    avatar: CircleAvatar(radius: 6, backgroundColor: color),
    label: Text(label),
  );

  Widget _newOrder() {
    final table = selectedTable;
    if (table == null && fulfillmentType == FulfillmentType.dineIn) {
      return Center(
        child: FilledButton.icon(
          onPressed: () => setState(() => page = 0),
          icon: const Icon(Icons.table_restaurant),
          label: const Text('Elegir mesa'),
        ),
      );
    }
    final categories = ['Todas', ...store.categories];
    final items = store.menu
        .where(
          (item) =>
              item.available &&
              (category == 'Todas' || item.category == category),
        )
        .toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 1000;
        if (desktop) {
          return Column(
            children: [
              _orderHeader(table),
              _orderPanelHeadings(table),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 8, 16),
                        child: _menuPanel(
                          items,
                          categories: categories,
                          table: table,
                          showHeading: false,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 350,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 16, 16),
                        child: _orderCartPanel(
                          key: const ValueKey('order-cart-panel'),
                          table: table,
                          showHeading: false,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        return Column(
          children: [
            Expanded(
              child: ListView(
                key: const ValueKey('order-form-scroll'),
                padding: EdgeInsets.zero,
                children: [
                  _orderHeader(table),
                  _menuPanel(
                    items,
                    categories: categories,
                    table: table,
                    compact: true,
                  ),
                  if (cart.isNotEmpty)
                    _orderCartPanel(
                      key: const ValueKey('order-cart-panel'),
                      table: table,
                      compact: true,
                    ),
                ],
              ),
            ),
            _orderSubmitBar(),
          ],
        );
      },
    );
  }

  Widget _orderHeader(RestaurantTable? table) {
    final title = editingOrder != null
        ? 'Editar pedido'
        : additionalParentId != null
        ? 'Consumo adicional'
        : 'Nueva comanda';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
          child: SectionTitle(
            title:
                '$title · ${table == null ? fulfillmentType.label : 'Mesa ${table.number}'}',
            subtitle: editingOrder != null
                ? 'Solo se puede editar antes de que cocina inicie la preparación'
                : 'Elige los platos y agrega observaciones especiales',
            trailing: IconButton(
              tooltip: 'Volver',
              onPressed: () => setState(() => page = 0),
              icon: const Icon(Icons.arrow_back),
            ),
          ),
        ),
        if (fulfillmentType != FulfillmentType.dineIn)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
            child: Column(
              children: [
                TextFormField(
                  initialValue: customerName,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del cliente',
                  ),
                  onChanged: (value) => customerName = value,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  initialValue: customerPhone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Teléfono'),
                  onChanged: (value) => customerPhone = value,
                ),
                if (fulfillmentType == FulfillmentType.delivery) ...[
                  const SizedBox(height: 10),
                  TextFormField(
                    initialValue: deliveryAddress,
                    decoration: const InputDecoration(
                      labelText: 'Dirección de entrega',
                    ),
                    onChanged: (value) => deliveryAddress = value,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _orderPanelHeadings(RestaurantTable? table) => SizedBox(
    height: 48,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'Carta',
                    key: const ValueKey('menu-panel-title'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (table != null) ...[
                  const Icon(
                    Icons.people_outline,
                    size: 18,
                    color: luxuryMuted,
                  ),
                  const SizedBox(width: 6),
                  const Text('Comensales'),
                  const SizedBox(width: 4),
                  DropdownButton<int>(
                    value: diners,
                    underline: const SizedBox.shrink(),
                    items: List.generate(
                      table.capacity,
                      (index) => DropdownMenuItem(
                        value: index + 1,
                        child: Text('${index + 1}'),
                      ),
                    ),
                    onChanged: (value) =>
                        setState(() => diners = value ?? diners),
                  ),
                  Text('/ ${table.capacity}'),
                ],
              ],
            ),
          ),
        ),
        SizedBox(
          width: 350,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _orderLabel(table),
                    key: const ValueKey('cart-panel-title'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Text(
                  '${cart.values.fold<int>(0, (sum, line) => sum + line.quantity)} productos',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _menuPanel(
    List<MenuItem> items, {
    required List<String> categories,
    required RestaurantTable? table,
    bool compact = false,
    bool showHeading = true,
  }) => Container(
    key: const ValueKey('order-menu-panel'),
    margin: compact
        ? EdgeInsets.zero
        : const EdgeInsets.fromLTRB(16, 0, 10, 16),
    decoration: BoxDecoration(
      color: const Color(0xFFFFFDFC),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: luxuryBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeading)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Carta',
                    key: const ValueKey('menu-panel-title'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (table != null) ...[
                  const Icon(
                    Icons.people_outline,
                    size: 18,
                    color: luxuryMuted,
                  ),
                  const SizedBox(width: 6),
                  const Text('Comensales'),
                  const SizedBox(width: 4),
                  DropdownButton<int>(
                    value: diners,
                    underline: const SizedBox.shrink(),
                    items: List.generate(
                      table.capacity,
                      (index) => DropdownMenuItem(
                        value: index + 1,
                        child: Text('${index + 1}'),
                      ),
                    ),
                    onChanged: (value) =>
                        setState(() => diners = value ?? diners),
                  ),
                  Text('/ ${table.capacity}'),
                ],
              ],
            ),
          ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(14, 3, 14, 4),
            children: categories
                .map(
                  (value) => Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: ChoiceChip(
                      label: Text(value),
                      selected: category == value,
                      onSelected: (_) => setState(() => category = value),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        if (showHeading) const Divider(height: 1),
        if (compact)
          _menuGrid(items, desktop: false)
        else
          Expanded(child: _menuGrid(items, desktop: true)),
      ],
    ),
  );

  Widget _menuGrid(List<MenuItem> items, {required bool desktop}) =>
      LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth > 880
              ? 3
              : constraints.maxWidth > 580
              ? 2
              : 1;
          return GridView.builder(
            key: desktop ? const ValueKey('order-form-scroll') : null,
            shrinkWrap: !desktop,
            physics: desktop
                ? const ClampingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            itemCount: items.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              mainAxisExtent: 224 * MediaQuery.textScalerOf(context).scale(1),
            ),
            itemBuilder: (context, index) {
              final item = items[index];
              final line = cart[item.id];
              return Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _DishArtwork(item: item),
                          Positioned(
                            top: 10,
                            right: 10,
                            child: Material(
                              color: Colors.white.withValues(alpha: .94),
                              shape: const CircleBorder(),
                              child: IconButton(
                                key: ValueKey('add-menu-item-${item.id}'),
                                tooltip: line == null
                                    ? 'Agregar ${item.name}'
                                    : 'Agregar otro ${item.name}',
                                onPressed: () => setState(() {
                                  if (line == null) {
                                    cart[item.id] = _CartLine(item);
                                  } else {
                                    line.quantity++;
                                  }
                                }),
                                icon: Icon(
                                  line == null
                                      ? Icons.add_rounded
                                      : Icons.add_shopping_cart,
                                  color: luxuryBrown,
                                ),
                              ),
                            ),
                          ),
                          if (line != null)
                            Positioned(
                              left: 10,
                              top: 10,
                              child: StatusBadge(
                                label: '${line.quantity} en la orden',
                                color: luxuryBrown,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(13, 10, 13, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  money(item.price),
                                  style: const TextStyle(
                                    color: luxuryBrown,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (line != null)
                            Icon(
                              Icons.check_circle,
                              color: luxuryGold,
                              size: 21,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );

  Widget _orderCartPanel({
    Key? key,
    required RestaurantTable? table,
    bool compact = false,
    bool showHeading = true,
  }) => Container(
    key: key,
    margin: compact
        ? const EdgeInsets.fromLTRB(16, 0, 16, 18)
        : EdgeInsets.zero,
    decoration: BoxDecoration(
      color: const Color(0xFFFFFDFC),
      border: Border.all(color: luxuryBorder),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Padding(
      padding: EdgeInsets.fromLTRB(16, showHeading ? 8 : 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        children: [
          if (showHeading) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    _orderLabel(table),
                    key: const ValueKey('cart-panel-title'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Text(
                  '${cart.values.fold<int>(0, (sum, line) => sum + line.quantity)} productos',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const Divider(height: 22),
          ],
          if (compact)
            ...cart.values.map(_orderLineTile)
          else if (cart.isEmpty)
            Expanded(
              child: EmptyState(
                message: 'Agrega platos para comenzar la comanda.',
                icon: Icons.restaurant_menu,
              ),
            )
          else
            Expanded(
              child: ListView(
                children: cart.values
                    .map((line) => _orderLineTile(line))
                    .toList(),
              ),
            ),
          const Divider(height: 22),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'TOTAL',
                  style: TextStyle(
                    color: luxuryMuted,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
              Text(
                money(cartTotal),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: luxuryBrown,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!compact) _orderSubmitButton(),
        ],
      ),
    ),
  );

  String _orderLabel(RestaurantTable? table) {
    final relatedOrders = store.orders.where((order) {
      if (fulfillmentType == FulfillmentType.dineIn) {
        return order.tableId == table?.id;
      }
      return order.fulfillmentType == fulfillmentType;
    }).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final existingIndex = editingOrder == null
        ? -1
        : relatedOrders.indexWhere((order) => order.id == editingOrder!.id);
    final number = existingIndex >= 0
        ? existingIndex + 1
        : relatedOrders.length + 1;
    final location = table == null
        ? fulfillmentType.label
        : 'Mesa ${table.number}';
    return 'Orden #$number · $location';
  }

  Widget _orderLineTile(_CartLine line) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _DishArtwork(item: line.item, compact: true),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    money(line.item.price * line.quantity),
                    style: const TextStyle(
                      color: luxuryRed,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            _quantityControl(line),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.only(left: 2),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () async {
              final note = await _noteDialog(line.note);
              if (note != null) setState(() => line.note = note);
            },
            icon: const Icon(Icons.edit_note, size: 18),
            label: Text(
              line.note.isEmpty ? 'Agregar observación' : line.note,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const Divider(height: 12),
      ],
    ),
  );

  Widget _quantityControl(_CartLine line) => DecoratedBox(
    decoration: BoxDecoration(
      color: luxuryBone,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          onPressed: () => setState(() {
            line.quantity--;
            if (line.quantity <= 0) cart.remove(line.item.id);
          }),
          icon: const Icon(Icons.remove, size: 16),
        ),
        Text(
          '${line.quantity}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          onPressed: () => setState(() => line.quantity++),
          icon: const Icon(Icons.add, size: 16),
        ),
      ],
    ),
  );

  Widget _orderSubmitBar() => Material(
    elevation: 7,
    color: const Color(0xFFFFFDFC),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${cart.values.fold<int>(0, (sum, line) => sum + line.quantity)} productos  ·  ${money(cartTotal)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          _orderSubmitButton(),
        ],
      ),
    ),
  );

  Widget _orderSubmitButton() => FilledButton.icon(
    onPressed: cart.isEmpty ? null : _submitOrder,
    icon: const Icon(Icons.send_rounded),
    label: Text(editingOrder != null ? 'Guardar cambios' : 'Enviar a cocina'),
  );

  Future<String?> _noteDialog(String initial) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Observaciones del plato'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 2,
          decoration: const InputDecoration(
            hintText: 'Ej. Sin picante, sillao extra',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _cancelOrder(RestaurantOrder order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar pedido'),
        content: Text(
          '¿Cancelar el pedido #${order.id}? Solo se puede hacer antes de que cocina inicie y sin abonos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancelar pedido'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _run(() => store.cancelOrder(order));
  }

  Widget _orders({bool history = false}) {
    final orders = store.orders.where((order) {
      final finished =
          order.status == OrderStatus.cancelled ||
          (order.balance <= .001 &&
              kitchenStage(order) == OrderStatus.delivered) ||
          (order.status == OrderStatus.delivered && order.balance <= .001);
      if (history) return finished;
      return order.status != OrderStatus.cancelled && !finished;
    }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SectionTitle(
          title: history ? 'Historial' : 'Mis pedidos',
          subtitle: history
              ? 'Pedidos cerrados y entregados'
              : 'Seguimiento de cocina y cuentas pendientes',
        ),
        if (orders.isEmpty)
          EmptyState(
            message: history
                ? 'Aún no hay pedidos en el historial.'
                : 'No hay pedidos abiertos.',
            icon: Icons.receipt_long,
          )
        else
          ...orders.map(
            (order) => Card(
              child: ExpansionTile(
                leading: CircleAvatar(
                  backgroundColor: luxuryGold.withValues(alpha: .14),
                  child: Text(
                    order.fulfillmentType == FulfillmentType.dineIn
                        ? '${order.tableNumber}'
                        : order.fulfillmentType == FulfillmentType.delivery
                        ? 'D'
                        : 'L',
                  ),
                ),
                title: Text('Pedido #${order.id} · ${order.locationLabel}'),
                subtitle: Text(
                  '${order.lines.fold<int>(0, (sum, line) => sum + line.quantity)} productos · ${money(order.total)}',
                ),
                trailing: order.pendingSync
                    ? const StatusBadge(
                        label: 'Sin sincronizar',
                        color: luxuryGold,
                      )
                    : StatusBadge.order(order.status),
                children: [
                  if (order.fulfillmentType != FulfillmentType.dineIn)
                    ResponsiveListTile(
                      dense: true,
                      leading: const Icon(Icons.person_outline),
                      title: Text(order.customerName),
                      subtitle: Text(
                        order.fulfillmentType == FulfillmentType.delivery
                            ? '${order.customerPhone} · ${order.deliveryAddress}'
                            : order.customerPhone,
                      ),
                    ),
                  ...order.lines.map(
                    (line) => ResponsiveListTile(
                      dense: true,
                      title: Text('${line.quantity} × ${line.name}'),
                      subtitle: line.note.isEmpty ? null : Text(line.note),
                      trailing: Text(money(line.subtotal)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (!order.pendingSync &&
                            order.status == OrderStatus.pending &&
                            order.payments.isEmpty) ...[
                          OutlinedButton.icon(
                            onPressed: () {
                              final table = store.tables
                                  .where((value) => value.id == order.tableId)
                                  .firstOrNull;
                              if (table != null) {
                                _openOrder(table, editOrder: order);
                              }
                            },
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Editar pedido'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _cancelOrder(order),
                            icon: const Icon(Icons.cancel_outlined),
                            label: const Text('Cancelar pedido'),
                          ),
                        ],
                        if (order.status == OrderStatus.ready)
                          FilledButton.tonalIcon(
                            onPressed: () =>
                                _run(() => store.advanceOrder(order)),
                            icon: const Icon(Icons.done_all),
                            label: const Text('Confirmar entrega'),
                          ),
                        if (order.status == OrderStatus.ready ||
                            order.status == OrderStatus.delivered)
                          OutlinedButton.icon(
                            onPressed: () =>
                                _run(() => store.setOrderForPayment(order)),
                            icon: const Icon(Icons.point_of_sale),
                            label: const Text('Solicitar cuenta'),
                          ),
                        if (order.balance > 0)
                          Text(
                            'Saldo ${money(order.balance)}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        if (order.status == OrderStatus.paid &&
                            kitchenStage(order) == OrderStatus.delivered &&
                            !order.retirementConfirmed) ...[
                          OutlinedButton.icon(
                            onPressed: () {
                              final table = store.tables
                                  .where((value) => value.id == order.tableId)
                                  .firstOrNull;
                              if (table != null) {
                                _run(() => store.confirmTableRelease(table));
                              }
                            },
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('Confirmar retiro de mesa'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              final table = store.tables
                                  .where((value) => value.id == order.tableId)
                                  .firstOrNull;
                              if (table != null) {
                                _openOrder(table, parentOrder: order);
                              }
                            },
                            icon: const Icon(Icons.add_shopping_cart),
                            label: const Text('Consumo adicional'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _profile() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const SectionTitle(title: 'Perfil', subtitle: 'Sesión de trabajo'),
      Card(
        child: ResponsiveListTile(
          leading: const CircleAvatar(child: Icon(Icons.person_outline)),
          title: Text(store.displayName),
          subtitle: Text(
            '${store.role?.label ?? 'Equipo'} · ${store.isConnected ? 'Supabase' : 'Demostración local'}',
          ),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: ResponsiveListTile(
          leading: const Icon(Icons.sync),
          title: const Text('Sincronizar información'),
          subtitle: const Text(
            'Actualizar mesas, menú y pedidos desde el servicio',
          ),
          onTap: () => _run(store.refresh),
        ),
      ),
    ],
  );

  Widget _body() => switch (page) {
    0 => _floor(),
    1 => _newOrder(),
    2 => _orders(),
    3 => _orders(history: true),
    _ => _profile(),
  };

  static const _labels = [
    'Mesas',
    'Nuevo pedido',
    'Mis pedidos',
    'Historial',
    'Perfil',
  ];
  static const _icons = [
    Icons.table_restaurant,
    Icons.add_shopping_cart,
    Icons.receipt_long,
    Icons.history,
    Icons.person_outline,
  ];

  Widget _nav(bool compact) => NavigationRail(
    scrollable: true,
    selectedIndex: page,
    onDestinationSelected: (value) => setState(() => page = value),
    extended: !compact,
    labelType: compact ? NavigationRailLabelType.all : null,
    destinations: List.generate(
      _labels.length,
      (index) => NavigationRailDestination(
        icon: Icon(_icons[index]),
        selectedIcon: Icon(_icons[index], color: luxuryGold),
        label: Text(_labels[index]),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final narrow = constraints.maxWidth < 760;
      return Scaffold(
        body: Row(
          children: [
            if (!narrow) ...[
              _nav(constraints.maxWidth < 1050),
              const VerticalDivider(width: 1),
            ],
            Expanded(child: _body()),
          ],
        ),
        bottomNavigationBar: narrow
            ? NavigationBar(
                selectedIndex: page,
                onDestinationSelected: (value) => setState(() => page = value),
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

class KitchenScreen extends StatefulWidget {
  const KitchenScreen({super.key, required this.store});
  final RestaurantStore store;

  @override
  State<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends State<KitchenScreen> {
  int page = 0;
  String query = '';
  bool notesOnly = false;
  RestaurantStore get store => widget.store;

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) {
        await showResultDialog(context, success: false, message: '$error');
      }
    }
  }

  Future<void> _reportIncident(RestaurantOrder order) async {
    final controller = TextEditingController(text: order.incident);
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Incidencia · Pedido #${order.id}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          maxLength: 240,
          decoration: const InputDecoration(
            labelText: 'Motivo',
            hintText: 'Describe el problema para administración y caja',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Registrar incidencia'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason != null) {
      await _run(() => store.reportKitchenIncident(order, reason));
    }
  }

  Future<void> _createAlert() async {
    final message = TextEditingController();
    InventoryItem? selectedItem = store.inventory
        .where((item) => item.active && item.lowStock)
        .firstOrNull;
    final result = await showDialog<(InventoryItem?, String)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Aviso de cocina'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<InventoryItem?>(
                  initialValue: selectedItem,
                  decoration: const InputDecoration(
                    labelText: 'Insumo relacionado (opcional)',
                  ),
                  items: [
                    const DropdownMenuItem<InventoryItem?>(
                      value: null,
                      child: Text('Aviso general'),
                    ),
                    ...store.inventory
                        .where((item) => item.active)
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(item.name),
                          ),
                        ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => selectedItem = value),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: message,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 240,
                  decoration: const InputDecoration(
                    labelText: 'Detalle del aviso',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, (selectedItem, message.text.trim())),
              child: const Text('Enviar a administración'),
            ),
          ],
        ),
      ),
    );
    message.dispose();
    if (result != null) {
      await _run(
        () => store.createKitchenAlert(item: result.$1, message: result.$2),
      );
    }
  }

  Future<void> _requestStock(InventoryItem item) async {
    final quantity = TextEditingController(
      text: (item.minimum * 2).toStringAsFixed(1),
    );
    final note = TextEditingController();
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Solicitar ${item.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: quantity,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(labelText: 'Cantidad (${item.unit})'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Observación'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, (quantity.text, note.text)),
            child: const Text('Enviar solicitud'),
          ),
        ],
      ),
    );
    quantity.dispose();
    note.dispose();
    if (result != null) {
      await _run(() async {
        final amount = double.tryParse(result.$1);
        if (amount == null) {
          throw StateError('Escribe una cantidad válida.');
        }
        await store.createStockRequest(item, amount, result.$2);
      });
    }
  }

  Widget _board() {
    final active =
        store.orders
            .where(
              (order) =>
                  order.status != OrderStatus.cancelled &&
                  kitchenStage(order) != OrderStatus.delivered,
            )
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final visible = active.where((order) {
      final hasNotes =
          !notesOnly || order.lines.any((line) => line.note.isNotEmpty);
      final text =
          '${order.locationLabel} ${order.customerName} ${order.customerPhone} ${order.deliveryAddress} ${order.id} ${order.lines.map((line) => line.name).join(' ')}'
              .toLowerCase();
      return hasNotes && text.contains(query);
    }).toList();
    final lanes = [
      (OrderStatus.pending, 'Nuevas comandas'),
      (OrderStatus.preparing, 'En preparación'),
      (OrderStatus.ready, 'Listas para servir'),
    ];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SectionTitle(
          title: 'Comandas de cocina',
          subtitle:
              'Actualización en vivo · Respeta las observaciones del mesero',
          trailing: Wrap(
            children: [
              if (store.isDemo)
                IconButton(
                  tooltip: 'Pedido de prueba',
                  onPressed: () async {
                    final table = store.tables
                        .where((value) => value.status == TableStatus.available)
                        .firstOrNull;
                    final item = store.menu
                        .where((value) => value.available)
                        .firstOrNull;
                    if (table == null || item == null) {
                      await showResultDialog(
                        context,
                        success: false,
                        message:
                            'No hay una mesa disponible o un plato habilitado.',
                      );
                      return;
                    }
                    _run(
                      () => store.createOrder(
                        table: table,
                        diners: 1,
                        lines: [
                          OrderLine(
                            menuItemId: item.id,
                            name: item.name,
                            quantity: 1,
                            unitPrice: item.price,
                          ),
                        ],
                      ),
                    );
                  },
                  icon: const Icon(Icons.add_box_outlined),
                ),
              IconButton(
                tooltip: 'Actualizar',
                onPressed: () => _run(store.refresh),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar mesa, pedido o plato',
              ),
              onChanged: (value) =>
                  setState(() => query = value.toLowerCase().trim()),
            ),
            const SizedBox(height: 8),
            FilterChip(
              label: const Text('Con observaciones'),
              selected: notesOnly,
              onSelected: (value) => setState(() => notesOnly = value),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (active.isEmpty)
          const EmptyState(
            message: 'No hay comandas pendientes.',
            icon: Icons.check_circle_outline,
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final horizontal = constraints.maxWidth >= 980;
              if (horizontal) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: lanes
                      .map(
                        (lane) => Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            child: _lane(
                              lane.$1,
                              lane.$2,
                              visible
                                  .where(
                                    (order) => kitchenStage(order) == lane.$1,
                                  )
                                  .toList(),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                );
              }
              return Column(
                children: lanes
                    .map(
                      (lane) => _lane(
                        lane.$1,
                        lane.$2,
                        visible
                            .where((order) => kitchenStage(order) == lane.$1)
                            .toList(),
                      ),
                    )
                    .toList(),
              );
            },
          ),
      ],
    );
  }

  Widget _lane(
    OrderStatus status,
    String title,
    List<RestaurantOrder> orders,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              CircleAvatar(
                radius: 13,
                backgroundColor: orderColor(status).withValues(alpha: .16),
                child: Text(
                  '${orders.length}',
                  style: TextStyle(color: orderColor(status), fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (orders.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Sin pedidos',
                style: TextStyle(color: Colors.black45),
              ),
            )
          else
            ...orders.map((order) => _ticket(order)),
        ],
      ),
    ),
  );

  Widget _ticket(RestaurantOrder order) {
    final elapsed = DateTime.now().difference(order.createdAt).inMinutes;
    final nextAction = switch (kitchenStage(order)) {
      OrderStatus.pending => 'Iniciar preparación',
      OrderStatus.preparing => 'Marcar listo',
      OrderStatus.ready => 'Entregar al mesero',
      _ => '',
    };
    return Card(
      color: luxuryBone,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${order.locationLabel} · #${order.id}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                Text(
                  '${elapsed}m',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: elapsed >= 20 ? luxuryRed : luxuryBrown,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              order.createdAt.toLocal().toString().substring(11, 16),
              style: const TextStyle(color: Colors.black54),
            ),
            if (order.pendingSync) ...[
              const SizedBox(height: 6),
              const StatusBadge(
                label: 'PENDIENTE DE SINCRONIZACIÓN',
                color: luxuryGold,
              ),
            ],
            if (order.fulfillmentType != FulfillmentType.dineIn)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${order.customerName} · ${order.customerPhone}'
                  '${order.deliveryAddress.isEmpty ? '' : ' · ${order.deliveryAddress}'}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            if (order.status == OrderStatus.paid)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: StatusBadge(
                  label: 'PAGADO · CONTINÚA EN COCINA',
                  color: luxuryGreen,
                ),
              ),
            if (order.status == OrderStatus.forPayment)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: StatusBadge(
                  label: 'CUENTA SOLICITADA',
                  color: luxuryRed,
                ),
              ),
            if (order.incident.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ErrorBanner(message: 'Incidencia: ${order.incident}'),
              ),
            const Divider(),
            ...order.lines.map(
              (line) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 34,
                      child: Text(
                        '${line.quantity}×',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            line.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (line.note.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                line.note,
                                style: const TextStyle(
                                  color: luxuryRed,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: order.pendingSync
                    ? null
                    : () => _run(() => store.advanceOrder(order)),
                child: Text(
                  order.pendingSync ? 'Esperando conexión' : nextAction,
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: order.pendingSync
                    ? null
                    : () => _reportIncident(order),
                icon: const Icon(Icons.report_problem_outlined, size: 18),
                label: const Text('Reportar incidencia'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kitchenInventory() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      SectionTitle(
        title: 'Insumos y disponibilidad',
        subtitle: 'Comunica faltantes y bloquea platos agotados',
        trailing: FilledButton.tonalIcon(
          onPressed: _createAlert,
          icon: const Icon(Icons.notification_add_outlined),
          label: const Text('Aviso de bajo stock'),
        ),
      ),
      ...store.inventory
          .where((item) => item.active)
          .map(
            (item) => Card(
              child: ResponsiveListTile(
                leading: Icon(
                  item.lowStock
                      ? Icons.warning_amber
                      : Icons.inventory_2_outlined,
                  color: item.lowStock ? luxuryRed : luxuryBrown,
                ),
                title: Text(item.name),
                subtitle: Text(
                  '${item.quantity} ${item.unit} · mínimo ${item.minimum}',
                ),
                trailing: Wrap(
                  children: [
                    IconButton(
                      tooltip: 'Avisar a administración',
                      onPressed: () => _run(
                        () => store.createKitchenAlert(
                          item: item,
                          message: 'Bajo stock: ${item.name}',
                        ),
                      ),
                      icon: const Icon(Icons.notification_add_outlined),
                    ),
                    FilledButton.tonal(
                      onPressed: () => _requestStock(item),
                      child: const Text('Solicitar'),
                    ),
                  ],
                ),
              ),
            ),
          ),
      const SizedBox(height: 14),
      Text('Alertas recientes', style: Theme.of(context).textTheme.titleMedium),
      ...store.alerts
          .where((alert) => alert.status == 'NUEVA')
          .map(
            (alert) => ResponsiveListTile(
              leading: const Icon(
                Icons.notifications_active_outlined,
                color: luxuryRed,
              ),
              title: Text(alert.message),
              subtitle: Text('${alert.priority} · enviada a administración'),
            ),
          ),
      const SizedBox(height: 14),
      Text(
        'Disponibilidad en carta',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      ...store.menu.map(
        (item) => SwitchListTile(
          value: item.available,
          title: Text(item.name),
          subtitle: Text(
            item.available ? 'Disponible para comandas' : 'Agotado',
          ),
          onChanged: (value) =>
              _run(() => store.setMenuAvailability(item, value)),
        ),
      ),
    ],
  );

  Widget _kitchenHistory() {
    final history = store.orders
        .where(
          (order) =>
              order.status == OrderStatus.cancelled ||
              kitchenStage(order) == OrderStatus.delivered,
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SectionTitle(
          title: 'Historial de cocina',
          subtitle: 'Comandas entregadas o cerradas',
        ),
        if (history.isEmpty)
          const EmptyState(message: 'Todavía no hay comandas cerradas.')
        else
          ...history.map(
            (order) => Card(
              child: ResponsiveListTile(
                leading: const Icon(Icons.done_all),
                title: Text('${order.locationLabel} · #${order.id}'),
                subtitle: Text(
                  order.lines
                      .map((line) => '${line.quantity}× ${line.name}')
                      .join(', '),
                ),
                trailing: order.pendingSync
                    ? const StatusBadge(
                        label: 'Sin sincronizar',
                        color: luxuryGold,
                      )
                    : StatusBadge.order(order.status),
              ),
            ),
          ),
      ],
    );
  }

  static const _labels = ['Comandas', 'Insumos y carta', 'Historial'];
  static const _icons = [
    Icons.soup_kitchen_outlined,
    Icons.inventory_2_outlined,
    Icons.history,
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final narrow = constraints.maxWidth < 760;
      final body = switch (page) {
        0 => _board(),
        1 => _kitchenInventory(),
        _ => _kitchenHistory(),
      };
      return Scaffold(
        body: Row(
          children: [
            if (!narrow) ...[
              NavigationRail(
                scrollable: true,
                selectedIndex: page,
                onDestinationSelected: (value) => setState(() => page = value),
                extended: constraints.maxWidth > 1040,
                labelType: constraints.maxWidth > 1040
                    ? null
                    : NavigationRailLabelType.all,
                destinations: List.generate(
                  _labels.length,
                  (index) => NavigationRailDestination(
                    icon: Icon(_icons[index]),
                    label: Text(_labels[index]),
                  ),
                ),
              ),
              const VerticalDivider(width: 1),
            ],
            Expanded(child: body),
          ],
        ),
        bottomNavigationBar: narrow
            ? NavigationBar(
                selectedIndex: page,
                onDestinationSelected: (value) => setState(() => page = value),
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

class CashierScreen extends StatefulWidget {
  const CashierScreen({super.key, required this.store});
  final RestaurantStore store;

  @override
  State<CashierScreen> createState() => _CashierScreenState();
}

class _CashierScreenState extends State<CashierScreen> {
  int page = 0;
  String method = 'Efectivo';
  RestaurantStore get store => widget.store;

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) {
        await showResultDialog(context, success: false, message: '$error');
      }
    }
  }

  Future<void> _collect(RestaurantOrder order) async {
    if (!store.shiftOpen) {
      setState(() => page = 2);
      await showResultDialog(
        context,
        success: false,
        message: 'Abre el turno de caja antes de registrar pagos.',
      );
      return;
    }
    final amount = TextEditingController(
      text: order.balance.toStringAsFixed(2),
    );
    final reference = TextEditingController();
    final received = TextEditingController(
      text: order.balance.toStringAsFixed(2),
    );
    var selectedMethod = 'Efectivo';
    final requiresEarlyConfirmation =
        kitchenStage(order) == OrderStatus.pending ||
        kitchenStage(order) == OrderStatus.preparing;
    var earlyPaymentConfirmed = !requiresEarlyConfirmation;
    final result = await showDialog<(String, String, String, String, bool)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Cobrar · Pedido #${order.id}'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total ${money(order.total)} · Pagado ${money(order.paid)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (requiresEarlyConfirmation) ...[
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: earlyPaymentConfirmed,
                    onChanged: (value) => setDialogState(
                      () => earlyPaymentConfirmed = value ?? false,
                    ),
                    title: const Text(
                      'El cliente solicita pagar antes de terminar la preparación',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedMethod,
                  decoration: const InputDecoration(
                    labelText: 'Método de pago',
                  ),
                  items:
                      const [
                            'Efectivo',
                            'Yape',
                            'Plin',
                            'Yape / Plin',
                            'Tarjeta',
                          ]
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                  onChanged: (value) => setDialogState(
                    () => selectedMethod = value ?? selectedMethod,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amount,
                  autofocus: true,
                  onChanged: (_) => setDialogState(() {}),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Monto',
                    prefixText: 'S/ ',
                    helperText: 'Saldo pendiente ${money(order.balance)}',
                  ),
                ),
                const SizedBox(height: 12),
                if (selectedMethod == 'Efectivo')
                  TextField(
                    controller: received,
                    onChanged: (_) => setDialogState(() {}),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Efectivo recibido',
                      prefixText: 'S/ ',
                    ),
                  )
                else
                  TextField(
                    controller: reference,
                    decoration: const InputDecoration(
                      labelText: 'N.º de operación / referencia',
                    ),
                  ),
                if (selectedMethod == 'Efectivo') ...[
                  const SizedBox(height: 8),
                  Builder(
                    builder: (context) {
                      final paidAmount = double.tryParse(amount.text) ?? 0;
                      final cashAmount = double.tryParse(received.text) ?? 0;
                      final change = (cashAmount - paidAmount)
                          .clamp(0, double.infinity)
                          .toDouble();
                      return Text('Vuelto: ${money(change)}');
                    },
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: earlyPaymentConfirmed
                  ? () => Navigator.pop(context, (
                      selectedMethod,
                      amount.text,
                      reference.text,
                      received.text,
                      earlyPaymentConfirmed,
                    ))
                  : null,
              child: const Text('Registrar abono'),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      await _run(() async {
        final value = double.tryParse(result.$2);
        if (value == null) throw StateError('Escribe un monto válido.');
        final receivedAmount = result.$1 == 'Efectivo'
            ? double.tryParse(result.$4)
            : null;
        await store.recordPayment(
          order: order,
          method: result.$1,
          amount: value,
          reference: result.$3,
          cashReceived: receivedAmount,
          earlyPaymentConfirmed: result.$5,
        );
      });
    }
    amount.dispose();
    reference.dispose();
    received.dispose();
  }

  Widget _accounts() {
    final active =
        store.orders
            .where(
              (order) =>
                  order.balance > .001 && order.status != OrderStatus.cancelled,
            )
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SectionTitle(
          title: 'Cuentas y cobros',
          subtitle: 'Admite abonos y pagos mixtos por pedido',
        ),
        if (active.isEmpty)
          const EmptyState(
            message: 'No hay cuentas pendientes de pago.',
            icon: Icons.task_alt,
          )
        else
          ...active.map(
            (order) => Card(
              child: ExpansionTile(
                leading: CircleAvatar(
                  backgroundColor: luxuryGold.withValues(alpha: .14),
                  child: Text(
                    order.fulfillmentType == FulfillmentType.dineIn
                        ? '${order.tableNumber}'
                        : order.fulfillmentType == FulfillmentType.delivery
                        ? 'D'
                        : 'L',
                  ),
                ),
                title: Text('Pedido #${order.id} · ${order.locationLabel}'),
                subtitle: Text(
                  '${order.lines.length} productos · Total ${money(order.total)}',
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Saldo', style: TextStyle(fontSize: 11)),
                    Text(
                      money(order.balance),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: luxuryRed,
                      ),
                    ),
                  ],
                ),
                children: [
                  if (order.fulfillmentType != FulfillmentType.dineIn)
                    ResponsiveListTile(
                      dense: true,
                      leading: const Icon(Icons.person_outline),
                      title: Text(order.customerName),
                      subtitle: Text(
                        order.fulfillmentType == FulfillmentType.delivery
                            ? '${order.customerPhone} · ${order.deliveryAddress}'
                            : order.customerPhone,
                      ),
                    ),
                  ...order.lines.map(
                    (line) => ResponsiveListTile(
                      dense: true,
                      title: Text('${line.quantity} × ${line.name}'),
                      subtitle: line.note.isEmpty ? null : Text(line.note),
                      trailing: Text(money(line.subtotal)),
                    ),
                  ),
                  if (order.payments.isNotEmpty)
                    ...order.payments.map(
                      (payment) => ResponsiveListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.check_circle_outline,
                          color: luxuryGreen,
                        ),
                        title: Text(payment.method),
                        trailing: Text(money(payment.amount)),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: () => _printPreAccount(order),
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: const Text('Imprimir precuenta'),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: SizedBox(
                      width: double.infinity,
                      child: order.pendingSync
                          ? const Text(
                              'El cobro estará disponible al sincronizar el pedido.',
                            )
                          : FilledButton.icon(
                              onPressed: () => _collect(order),
                              icon: const Icon(Icons.point_of_sale),
                              label: Text(
                                order.paid > 0
                                    ? 'Registrar siguiente abono · ${money(order.balance)}'
                                    : 'Cobrar cuenta · ${money(order.balance)}',
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _printPreAccount(RestaurantOrder order) async {
    await _run(() => printPreAccountPdf(order: order));
  }

  Widget _receipts() {
    final receipts = [...store.receipts];
    final paidOrders = store.orders
        .where((order) => order.status == OrderStatus.paid)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SectionTitle(
          title: 'Notas de venta',
          subtitle: 'Comprobantes registrados en el turno',
        ),
        if (receipts.isEmpty && paidOrders.isEmpty)
          const EmptyState(
            message: 'Todavía no hay notas de venta emitidas.',
            icon: Icons.receipt_long,
          )
        else ...[
          ...receipts.map(
            (receipt) => Card(
              child: ResponsiveListTile(
                leading: const Icon(Icons.receipt_long),
                title: Text(
                  '${receipt['code']} · ${receipt['locationLabel'] ?? 'Mesa ${receipt['tableNumber']}'}',
                ),
                subtitle: Text(
                  'Pedido #${receipt['orderId']} · ${receipt['createdAt']}',
                ),
                trailing: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      money((receipt['total'] as num).toDouble()),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    IconButton(
                      tooltip: 'Imprimir nota',
                      onPressed: () => _printReceipt(receipt),
                      icon: const Icon(Icons.print_outlined),
                    ),
                    if (receipt['status'] == 'ANULADO')
                      const StatusBadge(label: 'Anulada', color: luxuryRed),
                  ],
                ),
              ),
            ),
          ),
          ...paidOrders
              .where(
                (order) =>
                    !receipts.any((receipt) => receipt['orderId'] == order.id),
              )
              .map(
                (order) => Card(
                  child: ResponsiveListTile(
                    leading: const Icon(Icons.receipt_long),
                    title: Text('Nota de venta · Pedido #${order.id}'),
                    subtitle: Text(
                      '${order.locationLabel} · ${order.payments.map((payment) => payment.method).toSet().join(', ')}',
                    ),
                    trailing: Text(
                      money(order.total),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
        ],
      ],
    );
  }

  Future<void> _printReceipt(Map<String, dynamic> receipt) async {
    await _run(() async {
      final order = store.orders
          .where((value) => value.id == receipt['orderId'])
          .firstOrNull;
      if (order == null) {
        throw StateError('No se encontró el pedido de esta nota.');
      }
      await printReceiptPdf(
        order: order,
        code: receipt['code'] as String,
        status: receipt['status'] as String? ?? 'VIGENTE',
      );
      if (receipt['id'] is int) {
        await store.recordReceiptPrint(receipt['id'] as int);
      }
    });
  }

  Widget _shift() {
    final collected = store.orders.fold<double>(
      0,
      (sum, order) => sum + order.paid,
    );
    final cash = store.orders.fold<double>(
      0,
      (sum, order) =>
          sum +
          order.payments
              .where((payment) => payment.method == 'Efectivo')
              .fold<double>(0, (sub, payment) => sub + payment.amount),
    );
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SectionTitle(
          title: 'Arqueo de caja',
          subtitle: 'Control de apertura, medios de pago y cierre',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.point_of_sale,
                      size: 30,
                      color: luxuryGold,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        store.shiftOpen ? 'Turno abierto' : 'Turno cerrado',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    StatusBadge(
                      label: store.shiftOpen ? 'Abierto' : 'Cerrado',
                      color: store.shiftOpen ? luxuryGreen : luxuryRed,
                    ),
                  ],
                ),
                const Divider(height: 28),
                ResponsiveListTile(
                  title: const Text('Monto de apertura'),
                  trailing: Text(money(store.openingCash)),
                ),
                ResponsiveListTile(
                  title: const Text('Efectivo recaudado'),
                  trailing: Text(money(cash)),
                ),
                ResponsiveListTile(
                  title: const Text('Total recaudado'),
                  trailing: Text(
                    money(collected),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (!store.shiftOpen)
                  ResponsiveListTile(
                    title: const Text('Monto de cierre registrado'),
                    trailing: Text(money(store.closedCash)),
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: () async {
                      final controller = TextEditingController(
                        text: store.shiftOpen
                            ? (store.openingCash + cash).toStringAsFixed(2)
                            : '0',
                      );
                      final counted = await showDialog<double>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(
                            store.shiftOpen ? 'Cerrar turno' : 'Abrir turno',
                          ),
                          content: TextField(
                            controller: controller,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Efectivo contado',
                              prefixText: 'S/ ',
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancelar'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(
                                context,
                                double.tryParse(controller.text),
                              ),
                              child: const Text('Confirmar'),
                            ),
                          ],
                        ),
                      );
                      controller.dispose();
                      if (counted != null) {
                        await _run(
                          () => store.setShiftOpen(
                            !store.shiftOpen,
                            countedCash: counted,
                          ),
                        );
                      }
                    },
                    icon: Icon(
                      store.shiftOpen ? Icons.lock_outline : Icons.lock_open,
                    ),
                    label: Text(
                      store.shiftOpen ? 'Cerrar caja' : 'Abrir nuevo turno',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _activity() {
    final recent = store.orders.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SectionTitle(
          title: 'Actividad de caja',
          subtitle: 'Pedidos y pagos recientes',
        ),
        if (recent.isEmpty)
          const EmptyState(message: 'No hay actividad registrada.')
        else
          ...recent.map(
            (order) => Card(
              child: ResponsiveListTile(
                leading: Icon(
                  order.status == OrderStatus.paid
                      ? Icons.check_circle_outline
                      : Icons.receipt_long,
                  color: order.status == OrderStatus.paid
                      ? luxuryGreen
                      : luxuryBrown,
                ),
                title: Text('Pedido #${order.id} · ${order.locationLabel}'),
                subtitle: Text(
                  order.payments.isEmpty
                      ? 'Sin pagos registrados'
                      : order.payments
                            .map(
                              (payment) =>
                                  '${payment.method} ${money(payment.amount)}',
                            )
                            .join(' + '),
                ),
                trailing: Text(
                  money(order.paid),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
      ],
    );
  }

  static const _labels = [
    'Cuentas y cobros',
    'Notas de venta',
    'Arqueo de caja',
    'Actividad',
  ];
  static const _icons = [
    Icons.payments_outlined,
    Icons.receipt_long,
    Icons.point_of_sale,
    Icons.history,
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final narrow = constraints.maxWidth < 760;
      final body = switch (page) {
        0 => _accounts(),
        1 => _receipts(),
        2 => _shift(),
        _ => _activity(),
      };
      return Scaffold(
        body: Row(
          children: [
            if (!narrow) ...[
              NavigationRail(
                scrollable: true,
                selectedIndex: page,
                onDestinationSelected: (value) => setState(() => page = value),
                extended: constraints.maxWidth > 1050,
                labelType: constraints.maxWidth > 1050
                    ? null
                    : NavigationRailLabelType.all,
                destinations: List.generate(
                  _labels.length,
                  (index) => NavigationRailDestination(
                    icon: Icon(_icons[index]),
                    label: Text(_labels[index]),
                  ),
                ),
              ),
              const VerticalDivider(width: 1),
            ],
            Expanded(child: body),
          ],
        ),
        bottomNavigationBar: narrow
            ? NavigationBar(
                selectedIndex: page,
                onDestinationSelected: (value) => setState(() => page = value),
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
