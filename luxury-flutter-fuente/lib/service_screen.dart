import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_widgets.dart';
import 'models.dart';
import 'receipt_pdf.dart';
import 'staff_profile_dialog.dart';
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

  Future<void> _run(
    Future<void> Function() action, {
    String label = 'Procesando…',
  }) => runOperation(action, label: label);

  void _openOrder(
    RestaurantTable table, {
    RestaurantOrder? editOrder,
    RestaurantOrder? parentOrder,
  }) {
    if (!store.canOrderAtTable(table)) {
      showResultDialog(
        context,
        success: false,
        message: 'Esta mesa ya no admite pedidos. Consulta su estado.',
      );
      return;
    }
    final currentParent = editOrder == null
        ? parentOrder ?? store.additionalOrderParent(table)
        : null;
    setState(() {
      selectedTableId = table.id;
      fulfillmentType = FulfillmentType.dineIn;
      customerName = editOrder?.customerName ?? '';
      customerPhone = editOrder?.customerPhone ?? '';
      deliveryAddress = editOrder?.deliveryAddress ?? '';
      editingOrder = editOrder;
      additionalParentId = currentParent?.id;
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
      isCreatingOrder = true;
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
      isCreatingOrder = true;
    });
  }

  Future<void> _submitOrder() async {
    if (operationPending) return;
    final table = selectedTable;
    if (fulfillmentType == FulfillmentType.dineIn && table == null) {
      await showResultDialog(
        context,
        success: false,
        message: 'Selecciona una mesa primero.',
      );
      return;
    }
    if (editingOrder == null &&
        fulfillmentType != FulfillmentType.dineIn &&
        (customerName.trim().isEmpty ||
            !RestaurantStore.isValidCustomerPhone(customerPhone))) {
      await showResultDialog(
        context,
        success: false,
        message: 'Indica el nombre del cliente y un teléfono de 9 dígitos.',
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
    if (editingOrder == null) {
      final destination = table == null
          ? fulfillmentType.label
          : 'Mesa ${table.number}';
      final confirmed = await confirmAction(
        context,
        title: '¿Enviar pedido a cocina?',
        message:
            '$destination · ${money(cartTotal)}. Cocina recibirá esta comanda.',
        actionLabel: 'Enviar pedido',
      );
      if (!confirmed || !mounted) return;
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
        isCreatingOrder = false;
        page = 1;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasEditing
                ? 'Cambios del pedido guardados.'
                : store.lastOrderQueued
                ? 'Pedido guardado. Se enviará al recuperar la conexión.'
                : 'Pedido enviado a cocina.',
          ),
        ),
      );
    }, label: editingOrder == null ? 'Enviando pedido…' : 'Guardando cambios…');
  }

  Future<void> _tableActions(RestaurantTable table) async {
    final activeOrders = store.orders.where(
      (order) =>
          order.tableId == table.id &&
          !order.retirementConfirmed &&
          order.status != OrderStatus.paid &&
          order.status != OrderStatus.cancelled,
    );
    final canOrder = store.canOrderAtTable(table);
    final parent = store.additionalOrderParent(table);
    final settledOrders = store.orders
        .where(
          (order) =>
              order.tableId == table.id &&
              (order.status == OrderStatus.paid ||
                  order.status == OrderStatus.cancelled) &&
              !order.retirementConfirmed,
        )
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
              if (canOrder)
                ResponsiveListTile(
                  leading: const Icon(Icons.add_shopping_cart),
                  title: Text(
                    parent == null ? 'Nuevo pedido' : 'Agregar pedido',
                  ),
                  subtitle: parent == null
                      ? null
                      : Text('Vinculado al pedido #${parent.id}'),
                  onTap: () {
                    Navigator.pop(context);
                    _openOrder(table, parentOrder: parent);
                  },
                )
              else if (store.tableBillingStarted(table))
                const ResponsiveListTile(
                  leading: Icon(Icons.lock_outline),
                  title: Text('La mesa ya está en cobro'),
                  subtitle: Text(
                    'Los pedidos se habilitan al liberar la mesa.',
                  ),
                ),
              if (activeOrders.isNotEmpty)
                ResponsiveListTile(
                  leading: const Icon(Icons.receipt_long),
                  title: Text('Ver pedidos abiertos (${activeOrders.length})'),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() => page = 1);
                  },
                ),
              if (canRelease)
                ResponsiveListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: const Text('Confirmar retiro y liberar mesa'),
                  onTap: () {
                    Navigator.pop(context);
                    _confirmTableRelease(table);
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
    final firstAvailable = tables
        .where(
          (table) =>
              store.canOrderAtTable(table) &&
              store.additionalOrderParent(table) == null,
        )
        .firstOrNull;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SectionTitle(
          title: 'Mesas',
          subtitle: 'Toca una mesa para abrir el servicio',
          trailing: FilledButton.icon(
            onPressed: firstAvailable == null
                ? null
                : () => _openOrder(firstAvailable),
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
                            !order.retirementConfirmed &&
                            order.status != OrderStatus.paid &&
                            order.status != OrderStatus.cancelled,
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
                            _RectangularTableGraphic(table: table),
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
              onPressed: () => setState(() {
                isCreatingOrder = false;
                page = 0;
              }),
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
                  key: const ValueKey('customer-phone'),
                  initialValue: customerPhone,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(9),
                  ],
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
    onPressed: cart.isEmpty || operationPending ? null : _submitOrder,
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

  Future<void> _requestBill(RestaurantOrder order) async {
    final confirmed = await confirmAction(
      context,
      title: '¿Solicitar la cuenta?',
      message: order.fulfillmentType == FulfillmentType.dineIn
          ? '${order.locationLabel} pasará a Por cobrar y se cerrará el ingreso de pedidos para esta mesa.'
          : 'La cuenta del pedido #${order.id} se enviará a Caja.',
      actionLabel: 'Solicitar cuenta',
    );
    if (!confirmed || !mounted) return;
    await _run(
      () => store.setOrderForPayment(order),
      label: 'Solicitando cuenta…',
    );
  }

  Future<void> _confirmTableRelease(RestaurantTable table) async {
    final confirmed = await confirmAction(
      context,
      title: '¿Liberar la mesa ${table.number}?',
      message:
          'Confirma que los clientes se retiraron. La mesa volverá a estar disponible.',
      actionLabel: 'Liberar mesa',
    );
    if (!confirmed || !mounted) return;
    await _run(
      () => store.confirmTableRelease(table),
      label: 'Liberando mesa…',
    );
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
    final today = limaBusinessDay(DateTime.now());
    final orders = store.orders.where((order) {
      final isToday = limaBusinessDay(order.createdAt) == today;
      final finished =
          order.status == OrderStatus.cancelled ||
          (order.balance <= .001 &&
              kitchenStage(order) == OrderStatus.delivered) ||
          (order.status == OrderStatus.delivered && order.balance <= .001);
      if (history) return finished || !isToday;
      return isToday && order.status != OrderStatus.cancelled && !finished;
    }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SectionTitle(
          title: history ? 'Historial' : 'Mis pedidos',
          subtitle: history
              ? 'Pedidos de días anteriores y pedidos finalizados'
              : 'Seguimiento de pedidos abiertos de hoy',
        ),
        if (orders.isEmpty)
          EmptyState(
            message: history
                ? 'Aún no hay pedidos en el historial.'
                : 'No hay pedidos abiertos para hoy.',
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
                          if (store.tables.any(
                            (table) =>
                                table.id == order.tableId &&
                                store.canOrderAtTable(table),
                          ))
                            OutlinedButton.icon(
                              onPressed: () {
                                final table = store.tables.firstWhere(
                                  (value) => value.id == order.tableId,
                                );
                                _openOrder(table, editOrder: order);
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
                            onPressed: () => _requestBill(order),
                            icon: const Icon(Icons.point_of_sale),
                            label: const Text('Solicitar cuenta'),
                          ),
                        if (order.balance > 0)
                          Text(
                            'Saldo ${money(order.balance)}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        if (order.fulfillmentType == FulfillmentType.dineIn &&
                            order.tableId != null &&
                            order.status == OrderStatus.paid &&
                            kitchenStage(order) == OrderStatus.delivered &&
                            !order.retirementConfirmed) ...[
                          OutlinedButton.icon(
                            onPressed: () {
                              final table = store.tables
                                  .where((value) => value.id == order.tableId)
                                  .firstOrNull;
                              if (table != null) {
                                _confirmTableRelease(table);
                              }
                            },
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('Confirmar retiro de mesa'),
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
    entries: const [
      LuxuryMenuEntry(label: 'Mesas', icon: Icons.table_restaurant),
      LuxuryMenuEntry(label: 'Nuevo pedido', icon: Icons.add_shopping_cart),
      LuxuryMenuEntry(label: 'Mis pedidos', icon: Icons.receipt_long),
      LuxuryMenuEntry(label: 'Historial', icon: Icons.history),
      LuxuryMenuEntry(label: 'Perfil', icon: Icons.person_outline),
      LuxuryMenuEntry(
        label: 'Para llevar y delivery',
        icon: Icons.delivery_dining,
      ),
    ],
    sectionBreakIndices: const {5},
    selectedIndex: isCreatingOrder
        ? (fulfillmentType == FulfillmentType.dineIn ? 1 : 5)
        : page == 0
        ? 0
        : page + 1,
    userName: store.displayName,
    userRole: store.role?.label ?? 'Mesero',
    onProfileTap: () => showOwnStaffProfile(context, store),
    onDestinationSelected: (value) {
      switch (value) {
        case 0:
          setState(() {
            page = 0;
            isCreatingOrder = false;
          });
        case 1:
          final table = store.tables
              .where(
                (table) =>
                    store.canOrderAtTable(table) &&
                    store.additionalOrderParent(table) == null,
              )
              .firstOrNull;
          if (table == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No hay mesas disponibles.')),
            );
          } else {
            _openOrder(table);
          }
        case 2:
          setState(() {
            page = 1;
            isCreatingOrder = false;
          });
        case 3:
          setState(() {
            page = 2;
            isCreatingOrder = false;
          });
        case 4:
          showOwnStaffProfile(context, store);
        case 5:
          _chooseOffPremiseOrder();
      }
    },
  );

  void _chooseOffPremiseOrder() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.shopping_bag_outlined),
              title: const Text('Para llevar'),
              onTap: () {
                Navigator.pop(context);
                _openOffPremiseOrder(FulfillmentType.takeaway);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delivery_dining),
              title: const Text('Delivery'),
              onTap: () {
                Navigator.pop(context);
                _openOffPremiseOrder(FulfillmentType.delivery);
              },
            ),
          ],
        ),
      ),
    );
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
              child: SectionTransition(
                section: (page, isCreatingOrder),
                child: _body(),
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

class KitchenScreen extends StatefulWidget {
  const KitchenScreen({super.key, required this.store});
  final RestaurantStore store;

  @override
  State<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends State<KitchenScreen>
    with OperationProgress<KitchenScreen> {
  static const stages = [
    (
      status: OrderStatus.pending,
      title: 'Nuevas comandas',
      filter: 'Nuevas',
      icon: Icons.receipt_long_outlined,
    ),
    (
      status: OrderStatus.preparing,
      title: 'En preparación',
      filter: 'En preparación',
      icon: Icons.soup_kitchen_outlined,
    ),
    (
      status: OrderStatus.ready,
      title: 'Listas para servir',
      filter: 'Listas',
      icon: Icons.room_service_outlined,
    ),
  ];

  int page = 0;
  final _search = TextEditingController();
  String query = '';
  bool notesOnly = false;
  OrderStatus? stageFilter;
  RestaurantStore get store => widget.store;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<bool> _run(
    Future<void> Function() action, {
    String label = 'Procesando…',
  }) => runOperation(action, label: label);

  Future<void> _advanceKitchenOrder(RestaurantOrder order) async {
    final stage = kitchenStage(order);
    if (stage == OrderStatus.ready) {
      final confirmed = await confirmAction(
        context,
        title: '¿Entregar el pedido #${order.id}?',
        message: 'La comanda saldrá de la lista de pedidos listos.',
        actionLabel: 'Entregar pedido',
      );
      if (!confirmed || !mounted) return;
    }
    await _run(
      () => store.advanceOrder(order),
      label: switch (stage) {
        OrderStatus.pending => 'Iniciando preparación…',
        OrderStatus.preparing => 'Marcando pedido listo…',
        _ => 'Registrando entrega…',
      },
    );
  }

  Future<void> _reportIncident(RestaurantOrder order) async {
    final (reportedDish, originalReason) = order.kitchenIncident;
    final formKey = GlobalKey<FormState>();
    var reason = originalReason;
    var dish = order.lines
        .where((line) => line.name == reportedDish)
        .firstOrNull;
    if (dish == null && order.lines.length == 1) dish = order.lines.single;

    final report = await showDialog<(OrderLine?, String)>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text('Incidencia · Pedido #${order.id}'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (order.lines.isNotEmpty) ...[
                  DropdownButtonFormField<OrderLine>(
                    key: const ValueKey('incident-dish'),
                    initialValue: dish,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Platillo afectado',
                    ),
                    items: [
                      for (final line in order.lines)
                        DropdownMenuItem(
                          value: line,
                          child: Text(
                            '${line.quantity} × ${line.name}${line.note.isEmpty ? '' : ' · ${line.note}'}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) => dish = value,
                    validator: (value) => value == null
                        ? 'Selecciona el platillo afectado.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  key: const ValueKey('incident-reason'),
                  initialValue: reason,
                  onChanged: (value) => reason = value,
                  validator: (value) => (value?.trim().length ?? 0) < 5
                      ? 'Describe la incidencia con al menos cinco caracteres.'
                      : null,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 240,
                  decoration: const InputDecoration(
                    labelText: 'Motivo',
                    hintText: 'Describe el problema para administración y caja',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, (dish, reason.trim()));
              }
            },
            child: const Text('Registrar incidencia'),
          ),
        ],
      ),
    );
    if (report != null && mounted) {
      await _run(
        () => store.reportKitchenIncident(order, report.$2, dish: report.$1),
      );
    }
  }

  Future<void> _addNewSupply() async {
    final name = TextEditingController();
    final quantity = TextEditingController(text: '0');
    final minimum = TextEditingController(text: '5');
    final description = TextEditingController();
    String unit = 'KG';

    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.inventory_2_outlined, color: luxuryGold),
              SizedBox(width: 10),
              Text('Nuevo insumo a solicitar'),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Agrega un insumo que requiera la cocina (ej. pollo, arroz, gaseosas). Se creará en el almacén para que luego puedas solicitarlo directamente.',
                    style: TextStyle(fontSize: 13, color: luxuryMuted),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: name,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Nuevo insumo a solicitar',
                      hintText: 'Ej. Pollo, Gaseosa Inka Cola, Arroz',
                      prefixIcon: Icon(Icons.restaurant),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: unit,
                    decoration: const InputDecoration(
                      labelText: 'Unidad de medida',
                      prefixIcon: Icon(Icons.scale_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'KG',
                        child: Text(
                          'Kilogramos (KG) - ej. pollo, arroz, carne',
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'UNIDAD',
                        child: Text(
                          'Unidades (UNIDAD) - ej. bebidas, gaseosas, huevos',
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'LITRO',
                        child: Text(
                          'Litros (LITRO) - ej. aceite, sillao, vinagre',
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'GRAMOS',
                        child: Text('Gramos (G) - ej. especias, condimentos'),
                      ),
                      DropdownMenuItem(
                        value: 'PORCION',
                        child: Text('Porciones (PORCIÓN) - ej. wantán, masas'),
                      ),
                      DropdownMenuItem(
                        value: 'PAQUETE',
                        child: Text('Paquetes (PAQ) - ej. fideos, servilletas'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setDialogState(() => unit = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: minimum,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Stock mínimo ($unit)',
                            hintText: '5',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: quantity,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Stock actual ($unit)',
                            hintText: '0',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: description,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Detalle o descripción (opcional)',
                      hintText: 'Ej. Pechuga de pollo, gaseosa 500ml',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () {
                if (name.text.trim().isEmpty) return;
                Navigator.pop(context, true);
              },
              icon: const Icon(Icons.check),
              label: const Text('Guardar insumo'),
            ),
          ],
        ),
      ),
    );

    if (created == true) {
      final itemName = name.text.trim();
      final minVal = double.tryParse(minimum.text.replaceAll(',', '.')) ?? 1.0;
      final qtyVal = double.tryParse(quantity.text.replaceAll(',', '.')) ?? 0.0;
      final descVal = description.text.trim();
      name.dispose();
      minimum.dispose();
      quantity.dispose();
      description.dispose();
      final saved = await _run(() async {
        await store.saveInventoryItem(
          name: itemName,
          unit: unit,
          quantity: qtyVal,
          minimum: minVal,
          description: descVal,
        );
        await store.createKitchenAlert(
          message: 'Nuevo insumo registrado desde cocina: $itemName ($unit)',
        );
      }, label: 'Registrando insumo…');
      if (saved && mounted) {
        await showResultDialog(
          context,
          success: true,
          message:
              'Insumo "$itemName" agregado correctamente. Ya puedes solicitarlo desde la lista.',
        );
      }
    } else {
      name.dispose();
      minimum.dispose();
      quantity.dispose();
      description.dispose();
    }
  }

  Future<void> _requestStock(InventoryItem item) async {
    final defaultQty = item.unit == 'UNIDAD'
        ? (item.minimum * 2).toInt().toString()
        : '';
    final quantity = TextEditingController(text: defaultQty);
    final note = TextEditingController();
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.add_shopping_cart, color: luxuryGold),
            const SizedBox(width: 10),
            Expanded(child: Text('Solicitar ${item.name}')),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Indica la cantidad requerida en ${item.unit} (ej. para bebidas en unidades, pollo/arroz en kg).',
                style: const TextStyle(fontSize: 13, color: luxuryMuted),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: quantity,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Cantidad a solicitar en ${item.unit}',
                  suffixText: item.unit,
                  helperText:
                      'Stock actual: ${item.quantity} ${item.unit} · Mínimo: ${item.minimum} ${item.unit}',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Observación o urgencia (opcional)',
                  hintText: 'Ej. Se requiere para el turno de la noche',
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
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, (quantity.text, note.text)),
            icon: const Icon(Icons.send_outlined),
            label: const Text('Enviar solicitud'),
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
    final today = limaBusinessDay(DateTime.now());
    final byStage = {
      for (final stage in stages) stage.status: <RestaurantOrder>[],
    };
    var activeCount = 0;
    var matchingCount = 0;
    for (final order in store.orders) {
      if (order.status == OrderStatus.cancelled ||
          limaBusinessDay(order.createdAt) != today) {
        continue;
      }
      final lane = byStage[kitchenStage(order)];
      if (lane == null) continue;
      activeCount++;
      if (notesOnly &&
          order.incident.trim().isEmpty &&
          !order.lines.any((line) => line.note.trim().isNotEmpty)) {
        continue;
      }
      if (query.isNotEmpty) {
        final text = [
          order.locationLabel,
          order.customerName,
          order.customerPhone,
          order.deliveryAddress,
          order.id,
          order.incident,
          ...order.lines.expand((line) => [line.name, line.note]),
        ].join(' ').toLowerCase();
        if (!text.contains(query)) continue;
      }
      lane.add(order);
      matchingCount++;
    }
    for (final lane in byStage.values) {
      lane.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
    final shownStages = stages
        .where((stage) => stageFilter == null || stage.status == stageFilter)
        .toList();
    final shownCount = stageFilter == null
        ? matchingCount
        : byStage[stageFilter]!.length;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SectionTitle(
          title: 'Comandas de cocina',
          subtitle: 'Comandas de hoy · Actualización en vivo',
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
        TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Buscar mesa, pedido o plato',
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpiar búsqueda',
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _search.clear();
                      setState(() => query = '');
                    },
                  ),
          ),
          onChanged: (value) =>
              setState(() => query = value.toLowerCase().trim()),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: Text('Todas ($matchingCount)'),
              selected: stageFilter == null,
              onSelected: (_) => setState(() => stageFilter = null),
            ),
            for (final stage in stages)
              ChoiceChip(
                label: Text(
                  '${stage.filter} (${byStage[stage.status]!.length})',
                ),
                selected: stageFilter == stage.status,
                onSelected: (value) =>
                    setState(() => stageFilter = value ? stage.status : null),
              ),
            FilterChip(
              label: const Text('Con observaciones'),
              selected: notesOnly,
              onSelected: (value) => setState(() => notesOnly = value),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (activeCount == 0)
          const EmptyState(
            message: 'No hay comandas pendientes.',
            icon: Icons.check_circle_outline,
          )
        else if (shownCount == 0)
          EmptyState(
            message: notesOnly
                ? 'No hay comandas con observaciones o incidencias para este filtro.'
                : query.isNotEmpty
                ? 'No hay comandas que coincidan con la búsqueda.'
                : 'No hay comandas en esta etapa.',
            icon: Icons.search_off,
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = [
                for (final stage in shownStages)
                  _lane(
                    stage.status,
                    stage.title,
                    stage.icon,
                    byStage[stage.status]!,
                  ),
              ];
              if (columns.length > 1 && constraints.maxWidth >= 980) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final column in columns)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: column,
                        ),
                      ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: columns,
              );
            },
          ),
      ],
    );
  }

  Widget _lane(
    OrderStatus status,
    String title,
    IconData icon,
    List<RestaurantOrder> orders,
  ) => Card(
    key: ValueKey(status),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: orderColor(status), size: 20),
              const SizedBox(width: 8),
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
            for (final order in orders) _ticket(order, status),
        ],
      ),
    ),
  );

  Widget _ticket(RestaurantOrder order, OrderStatus stage) {
    final (incidentDish, incidentReason) = order.kitchenIncident;
    final elapsed = DateTime.now().difference(order.createdAt).inMinutes;
    final units = order.lines.fold(0, (total, line) => total + line.quantity);
    final nextAction = switch (stage) {
      OrderStatus.pending => 'Iniciar preparación',
      OrderStatus.preparing => 'Marcar listo',
      OrderStatus.ready => 'Entregar al mesero',
      _ => '',
    };
    return Card(
      key: ValueKey(order.id),
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
                const SizedBox(width: 8),
                StatusBadge(
                  label: '${elapsed < 0 ? 0 : elapsed} min',
                  color: elapsed >= 20 ? luxuryRed : luxuryBrown,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${order.createdAt.toLocal().toString().substring(11, 16)} · '
              '$units ${units == 1 ? 'porción' : 'porciones'}',
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
            if (incidentReason.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ErrorBanner(
                  message:
                      'Incidencia: $incidentReason\n'
                      'Platillo: ${incidentDish ?? 'Sin identificar'}',
                ),
              ),
            const Divider(),
            ...order.lines.map(
              (line) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StatusBadge(label: '${line.quantity}×', color: luxuryBrown),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            line.name,
                            style: TextStyle(
                              color: line.name == incidentDish
                                  ? luxuryRed
                                  : null,
                              fontWeight: FontWeight.w600,
                            ),
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
                          if (line.status != stage)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: StatusBadge.order(line.status),
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
                    : () => _advanceKitchenOrder(order),
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

  Widget _kitchenInventory() {
    final lowStockItems = store.inventory
        .where((item) => item.active && item.lowStock)
        .toList();
    final normalItems = store.inventory
        .where((item) => item.active && !item.lowStock)
        .toList();
    final activeAlerts = store.alerts
        .where((alert) => alert.status == 'NUEVA')
        .toList();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SectionTitle(
          title: 'Insumos y disponibilidad de cocina',
          subtitle:
              'Comunica faltantes, solicita reposición y bloquea platos agotados',
          trailing: FilledButton.icon(
            onPressed: _addNewSupply,
            icon: const Icon(Icons.add),
            label: const Text('Nuevo insumo a solicitar'),
          ),
        ),
        if (store.inventory.where((item) => item.active).isEmpty)
          const EmptyState(
            message: 'No hay insumos registrados en cocina.',
            icon: Icons.inventory_2_outlined,
          )
        else ...[
          // Grid or list of supplies
          ...[...lowStockItems, ...normalItems].map(
            (item) => Card(
              margin: const EdgeInsets.symmetric(vertical: 5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: item.lowStock
                      ? luxuryRed.withValues(alpha: .35)
                      : luxuryBorder,
                  width: item.lowStock ? 1.5 : 1,
                ),
              ),
              child: ResponsiveListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: item.lowStock
                        ? luxuryRed.withValues(alpha: .12)
                        : luxuryGold.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    item.lowStock
                        ? Icons.warning_amber_rounded
                        : Icons.inventory_2_outlined,
                    color: item.lowStock ? luxuryRed : luxuryBrown,
                    size: 22,
                  ),
                ),
                title: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: luxuryInk,
                      ),
                    ),
                    StatusBadge(
                      label: item.lowStock
                          ? 'Bajo stock · ${item.quantity} ${item.unit}'
                          : '${item.quantity} ${item.unit}',
                      color: item.lowStock ? luxuryRed : luxuryGreen,
                    ),
                  ],
                ),
                subtitle: Text(
                  'Mínimo: ${item.minimum} ${item.unit}${item.description.isNotEmpty ? ' · ${item.description}' : ''}',
                  style: const TextStyle(fontSize: 13, color: luxuryMuted),
                ),
                trailing: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Avisar a administración',
                      onPressed: () => _run(
                        () => store.createKitchenAlert(
                          item: item,
                          message:
                              'Bajo stock: ${item.name} (${item.quantity} ${item.unit})',
                        ),
                      ),
                      icon: const Icon(
                        Icons.notification_add_outlined,
                        color: luxuryBrown,
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _requestStock(item),
                      icon: const Icon(Icons.add_shopping_cart, size: 16),
                      label: const Text('Solicitar'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: luxuryBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.notifications_active_outlined,
                      color: luxuryRed,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Alertas recientes',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20),
                if (activeAlerts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No hay alertas activas enviadas a administración.',
                      style: TextStyle(color: luxuryMuted),
                    ),
                  )
                else
                  ...activeAlerts.map(
                    (alert) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: luxuryRed,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              alert.message,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Chip(
                            label: Text(
                              alert.priority,
                              style: const TextStyle(fontSize: 11),
                            ),
                            visualDensity: VisualDensity.compact,
                            backgroundColor: luxuryRed.withValues(alpha: .1),
                            side: BorderSide.none,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: luxuryBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.restaurant_menu,
                      color: luxuryGold,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Disponibilidad en carta',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20),
                ...store.menu.map(
                  (item) => SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: item.available,
                    title: Text(
                      item.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      item.available
                          ? 'Disponible para comandas'
                          : 'Agotado (bloqueado para meseros)',
                      style: TextStyle(
                        color: item.available ? luxuryGreen : luxuryRed,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onChanged: (value) =>
                        _run(() => store.setMenuAvailability(item, value)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _kitchenHistory() {
    final today = limaBusinessDay(DateTime.now());
    final history = store.orders
        .where(
          (order) =>
              limaBusinessDay(order.createdAt) != today ||
              order.status == OrderStatus.cancelled ||
              kitchenStage(order) == OrderStatus.delivered,
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SectionTitle(
          title: 'Historial de cocina',
          subtitle: 'Comandas de días anteriores y comandas finalizadas',
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
              LuxurySideMenu(
                entries: const [
                  LuxuryMenuEntry(
                    label: 'Comandas',
                    icon: Icons.soup_kitchen_outlined,
                  ),
                  LuxuryMenuEntry(
                    label: 'Insumos y carta',
                    icon: Icons.inventory_2_outlined,
                  ),
                  LuxuryMenuEntry(label: 'Historial', icon: Icons.history),
                ],
                selectedIndex: page,
                userName: store.displayName,
                userRole: store.role?.label ?? 'Cocina',
                onProfileTap: () => showOwnStaffProfile(context, store),
                onDestinationSelected: (value) => setState(() => page = value),
              ),
            ],
            Expanded(
              child: SectionTransition(section: page, child: body),
            ),
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

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.order, required this.store});
  final RestaurantOrder order;
  final RestaurantStore store;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late RestaurantOrder order;
  late final TextEditingController amount;
  late final TextEditingController received;
  final reference = TextEditingController();
  String selectedMethod = 'Efectivo';
  bool earlyPaymentConfirmed = false;
  bool saving = false;
  bool paymentNotConfirmed = false;
  String? paymentError;

  bool get isCash => selectedMethod == 'Efectivo';
  bool get requiresEarlyConfirmation =>
      kitchenStage(order) == OrderStatus.pending ||
      kitchenStage(order) == OrderStatus.preparing;

  int get balanceCents => (order.balance * 100).round();

  int? get receivedCents {
    final input = received.text.trim();
    if (!RegExp(r'^\d+(?:[.,]\d{1,2})?$').hasMatch(input)) return null;
    final value = double.tryParse(input.replaceAll(',', '.'));
    return value == null || !value.isFinite || value > 9999999999
        ? null
        : (value * 100).round();
  }

  @override
  void initState() {
    super.initState();
    order = widget.order;
    amount = TextEditingController(text: order.balance.toStringAsFixed(2));
    received = TextEditingController(text: amount.text);
  }

  @override
  void dispose() {
    amount.dispose();
    received.dispose();
    reference.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final tendered = receivedCents;
    if (saving ||
        paymentNotConfirmed ||
        tendered == null ||
        tendered <= 0 ||
        balanceCents <= 0) {
      return;
    }
    if (!isCash && tendered > balanceCents) {
      setState(
        () => paymentError = 'El importe recibido supera el saldo pendiente.',
      );
      return;
    }
    final applied = tendered < balanceCents ? tendered : balanceCents;
    setState(() {
      saving = true;
      paymentError = null;
    });
    try {
      await showBlockingProgress(
        context,
        label: 'Registrando pago…',
        action: () => widget.store.recordPayment(
          order: order,
          method: selectedMethod,
          amount: applied / 100,
          cashReceived: isCash ? tendered / 100 : null,
          reference: reference.text,
          earlyPaymentConfirmed: earlyPaymentConfirmed,
        ),
      );
      if (!mounted) return;
      final updated = widget.store.orders
          .where((item) => item.id == order.id)
          .firstOrNull;
      if (updated == null) {
        Navigator.pop(context);
        return;
      }
      if (updated.balance <= .001) {
        Navigator.pop(context, isCash ? (tendered - applied) / 100 : 0.0);
        return;
      }
      setState(() {
        order = updated;
        amount.text = order.balance.toStringAsFixed(2);
        received.clear();
        reference.clear();
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          paymentNotConfirmed = error is PaymentNotConfirmed;
          paymentError = formatErrorMessage(error);
        });
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tendered = receivedCents ?? 0;
    final outstanding = tendered < balanceCents ? balanceCents - tendered : 0;
    final change = isCash && tendered > balanceCents
        ? tendered - balanceCents
        : 0;
    return PopScope(
      canPop: !saving,
      child: AlertDialog(
        scrollable: true,
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
                  onChanged: saving
                      ? null
                      : (value) => setState(
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
                decoration: const InputDecoration(labelText: 'Método de pago'),
                items: const ['Efectivo', 'Yape', 'Plin', 'Tarjeta']
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: saving
                    ? null
                    : (value) => setState(() {
                        selectedMethod = value ?? selectedMethod;
                        received.text = amount.text;
                        reference.clear();
                        paymentError = null;
                      }),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('payment-amount-field'),
                controller: amount,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Monto pendiente',
                  prefixText: 'S/ ',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('payment-received-field'),
                controller: received,
                enabled: !saving,
                autofocus: true,
                onChanged: (_) => setState(() => paymentError = null),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: isCash ? 'Efectivo recibido' : 'Importe recibido',
                  prefixText: 'S/ ',
                ),
              ),
              if (!isCash) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: reference,
                  enabled: !saving,
                  decoration: const InputDecoration(
                    labelText: 'N.º de operación / referencia',
                  ),
                ),
              ],
              const SizedBox(height: 8),
              if (isCash) Text('Vuelto: ${money(change / 100)}'),
              Text('Saldo después del pago: ${money(outstanding / 100)}'),
              if (paymentError != null)
                Text(paymentError!, style: const TextStyle(color: luxuryRed)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context),
            child: Text(
              order.paid > 0 || paymentNotConfirmed
                  ? 'Cerrar ventana'
                  : 'Cancelar',
            ),
          ),
          FilledButton(
            onPressed:
                !saving &&
                    !paymentNotConfirmed &&
                    tendered > 0 &&
                    (!requiresEarlyConfirmation || earlyPaymentConfirmed)
                ? _submit
                : null,
            child: OperationLabel(
              loading: saving,
              label: saving
                  ? 'Registrando…'
                  : outstanding > 0
                  ? 'Registrar abono'
                  : 'Confirmar pago',
            ),
          ),
        ],
      ),
    );
  }
}

class _CashierScreenState extends State<CashierScreen>
    with OperationProgress<CashierScreen> {
  int page = 0;
  DateTime? _previousAccountsDay;
  String method = 'Efectivo';
  RestaurantStore get store => widget.store;

  Future<void> _run(
    Future<void> Function() action, {
    String label = 'Procesando…',
  }) => runOperation(action, label: label);

  Future<void> _collect(RestaurantOrder order) async {
    if (!store.shiftOpen) {
      setState(() => page = 2);
      await showResultDialog(
        context,
        success: false,
        message:
            'Solicita a Administración que abra tu turno antes de registrar pagos.',
      );
      return;
    }
    final change = await showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _PaymentDialog(order: order, store: store),
    );
    if (change != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            change > 0
                ? 'Cuenta pagada · Vuelto: ${money(change)}'
                : 'Cuenta pagada',
          ),
        ),
      );
      setState(() {});
    } else if (mounted) {
      setState(() {});
    }
  }

  Widget _accounts(DateTime businessDay) {
    final showPrevious = _previousAccountsDay == businessDay;
    final active = store.orders.where((order) {
      if (order.balance <= .001 || order.status == OrderStatus.cancelled) {
        return false;
      }
      final orderDay = limaBusinessDay(order.createdAt);
      return showPrevious
          ? orderDay.isBefore(businessDay)
          : orderDay == businessDay;
    }).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SectionTitle(
          title: 'Cuentas y cobros',
          subtitle: 'Cuentas pendientes por fecha de Lima',
        ),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Hoy'),
              selected: !showPrevious,
              onSelected: (_) => setState(() => _previousAccountsDay = null),
            ),
            ChoiceChip(
              label: const Text('Pendientes anteriores'),
              selected: showPrevious,
              onSelected: (_) =>
                  setState(() => _previousAccountsDay = businessDay),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (active.isEmpty)
          EmptyState(
            message: showPrevious
                ? 'No hay cuentas pendientes de días anteriores.'
                : 'No hay cuentas pendientes de hoy.',
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

  Widget _shift(DateTime businessDay) {
    var collected = 0.0;
    var cash = 0.0;
    for (final payment in store.orders.expand((order) => order.payments)) {
      if (limaBusinessDay(payment.createdAt) != businessDay) continue;
      collected += payment.amount;
      if (payment.method == 'Efectivo') cash += payment.amount;
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SectionTitle(
          title: 'Arqueo de caja',
          subtitle: 'Turno y pagos de hoy, según la fecha de Lima',
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
                const SizedBox(height: 8),
                const Text(
                  'Administración gestiona la apertura y el cierre de los turnos.',
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
      final businessDay = limaBusinessDay(DateTime.now());
      final body = switch (page) {
        0 => _accounts(businessDay),
        1 => _receipts(),
        2 => _shift(businessDay),
        _ => _activity(),
      };
      return Scaffold(
        body: Row(
          children: [
            if (!narrow) ...[
              LuxurySideMenu(
                entries: const [
                  LuxuryMenuEntry(
                    label: 'Cuentas y cobros',
                    icon: Icons.payments_outlined,
                  ),
                  LuxuryMenuEntry(
                    label: 'Notas de venta',
                    icon: Icons.receipt_long,
                  ),
                  LuxuryMenuEntry(
                    label: 'Arqueo de caja',
                    icon: Icons.point_of_sale,
                  ),
                  LuxuryMenuEntry(label: 'Actividad', icon: Icons.history),
                ],
                selectedIndex: page,
                userName: store.displayName,
                userRole: store.role?.label ?? 'Caja',
                onProfileTap: () => showOwnStaffProfile(context, store),
                onDestinationSelected: (value) => setState(() => page = value),
              ),
            ],
            Expanded(
              child: SectionTransition(section: page, child: body),
            ),
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
