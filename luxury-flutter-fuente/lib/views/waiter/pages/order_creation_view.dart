part of '../waiter_screen.dart';

extension _WaiterOrderCreationView on _WaiterScreenState {
  Widget _newOrder() {
    final table = selectedTable;
    if (table == null && fulfillmentType == FulfillmentType.dineIn) {
      return Center(
        child: FilledButton.icon(
          onPressed: () => _setState(() {
            page = 0;
            isCreatingOrder = false;
          }),
          icon: const Icon(Icons.table_restaurant),
          label: const Text('Elegir mesa'),
        ),
      );
    }
    final categories = ['Todas', ...store.categories];
    final query = searchText(dishSearch.text);
    final items = store.menu
        .where(
          (item) =>
              item.available &&
              (category == 'Todas' || item.category == category) &&
              (query.isEmpty ||
                  searchText('${item.name} ${item.category}').contains(query)),
        )
        .toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBySide =
            constraints.maxWidth >= 900 && constraints.maxHeight >= 460;
        if (sideBySide) {
          final cartWidth = (constraints.maxWidth * .25).clamp(296.0, 400.0);
          return Column(
            children: [
              _orderHeader(table, horizontalFields: true),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _menuHeading()),
                    const SizedBox(width: 16),
                    SizedBox(width: cartWidth, child: _cartHeading(table)),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _menuPanel(items, categories: categories),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: cartWidth,
                        child: _orderCartPanel(table: table),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }

        return Column(
          children: [
            Expanded(
              child: CustomScrollView(
                key: const ValueKey('order-form-scroll'),
                slivers: [
                  SliverToBoxAdapter(
                    child: _orderHeader(table, showDetails: !_showCompactOrder),
                  ),
                  if (_showCompactOrder)
                    SliverToBoxAdapter(
                      child: _orderCartPanel(table: table, compact: true),
                    )
                  else ...[
                    SliverToBoxAdapter(
                      child: _menuFilters(categories, compact: true),
                    ),
                    _menuGrid(items),
                  ],
                ],
              ),
            ),
            _orderSubmitBar(),
          ],
        );
      },
    );
  }

  Widget _orderHeader(
    RestaurantTable? table, {
    bool horizontalFields = false,
    bool showDetails = true,
  }) {
    final title = editingOrder != null
        ? 'Editar pedido'
        : additionalParentId != null
        ? 'Consumo adicional'
        : 'Nueva comanda';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
          child: SectionTitle(
            title: '$title · ${_orderDestination(table)}',
            subtitle: editingOrder != null
                ? 'Solo se puede editar antes de que cocina inicie la preparación'
                : additionalParentId != null
                ? 'Los productos nuevos se sumarán a la cuenta del pedido #$additionalParentId'
                : 'Elige los platos y agrega observaciones especiales',
            trailing: IconButton(
              tooltip: 'Volver',
              onPressed: () => _setState(() {
                isCreatingOrder = false;
                page = 0;
              }),
              icon: const Icon(Icons.arrow_back),
            ),
          ),
        ),
        if (showDetails && table != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 16, 8),
            child: _dinersSummary(table),
          ),
        if (showDetails && fulfillmentType != FulfillmentType.dineIn)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: _customerFields(horizontal: horizontalFields),
          ),
      ],
    );
  }

  Widget _customerFields({required bool horizontal}) {
    final fields = [
      TextFormField(
        initialValue: customerName,
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            RestaurantStore.customerNameCharacters,
          ),
        ],
        decoration: const InputDecoration(labelText: 'Nombre del cliente'),
        onChanged: (value) => customerName = value,
      ),
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
      if (fulfillmentType == FulfillmentType.delivery)
        TextFormField(
          initialValue: deliveryAddress,
          decoration: const InputDecoration(labelText: 'Dirección de entrega'),
          onChanged: (value) => deliveryAddress = value,
        ),
    ];
    return Flex(
      direction: horizontal ? Axis.horizontal : Axis.vertical,
      spacing: 10,
      children: [
        for (final (index, field) in fields.indexed)
          if (horizontal)
            Expanded(flex: index == 1 ? 2 : 3, child: field)
          else
            field,
      ],
    );
  }

  Widget _dinersSummary(RestaurantTable table) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    children: additionalParentId == null
        ? _dinerControls(table)
        : [
            const Icon(Icons.people_outline, size: 18, color: luxuryMuted),
            const SizedBox(width: 7),
            Text('$diners / ${_orderCapacity(table)}'),
          ],
  );

  List<Widget> _dinerControls(RestaurantTable table) {
    final capacity = _orderCapacity(table);
    return [
      const Icon(Icons.people_outline, size: 18, color: luxuryMuted),
      const SizedBox(width: 6),
      const Text('Comensales'),
      const SizedBox(width: 4),
      DropdownButton<int>(
        value: diners >= 1 && diners <= capacity ? diners : null,
        underline: const SizedBox.shrink(),
        items: List.generate(
          capacity,
          (index) =>
              DropdownMenuItem(value: index + 1, child: Text('${index + 1}')),
        ),
        onChanged: (value) => _setState(() => diners = value ?? diners),
      ),
      Text('/ $capacity'),
    ];
  }

  Widget _menuHeading() => Text(
    'Carta',
    key: const ValueKey('menu-panel-title'),
    style: Theme.of(context).textTheme.titleLarge,
  );

  Widget _cartHeading(RestaurantTable? table) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Text(
          _orderLabel(table),
          key: const ValueKey('cart-panel-title'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
      const SizedBox(width: 8),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          _cartQuantity == 1 ? '1 producto' : '$_cartQuantity productos',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ],
  );

  Widget _menuPanel(List<MenuItem> items, {required List<String> categories}) =>
      Container(
        key: const ValueKey('order-menu-panel'),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFFFFFDFC),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: luxuryBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _menuFilters(categories),
            Expanded(
              child: CustomScrollView(
                key: const ValueKey('order-form-scroll'),
                slivers: [_menuGrid(items)],
              ),
            ),
          ],
        ),
      );

  Widget _menuFilters(List<String> categories, {bool compact = false}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (compact)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: _menuHeading(),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 5),
            child: _dishSearchField(dense: true),
          ),
          SizedBox(height: 44, child: _categoryChips(categories)),
        ],
      );

  Widget _dishSearchField({bool dense = false}) => TextField(
    controller: dishSearch,
    textInputAction: TextInputAction.search,
    onChanged: (_) => _setState(() {}),
    decoration: InputDecoration(
      labelText: 'Buscar platos o categorías',
      isDense: dense,
      prefixIcon: const Icon(Icons.search),
      suffixIcon: dishSearch.text.isEmpty
          ? null
          : IconButton(
              tooltip: 'Limpiar búsqueda de platos',
              icon: const Icon(Icons.close),
              onPressed: () => _setState(dishSearch.clear),
            ),
    ),
  );

  Widget _categoryChips(List<String> categories) => ListView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(16, 3, 16, 4),
    children: categories
        .map(
          (value) => Padding(
            padding: const EdgeInsets.only(right: 7),
            child: ChoiceChip(
              label: Text(value),
              selected: category == value,
              onSelected: (_) => _setState(() => category = value),
            ),
          ),
        )
        .toList(),
  );

  Widget _menuGrid(List<MenuItem> items) {
    if (items.isEmpty) {
      return const SliverToBoxAdapter(
        child: EmptyState(
          message: 'No se encontraron platos.',
          icon: Icons.search_off,
        ),
      );
    }
    final indexes = {for (final (index, item) in items.indexed) item.id: index};
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final columns = width >= 740
            ? 3
            : width >= 348
            ? 2
            : 1;
        const gap = 14.0;
        final cardWidth = (width - 32 - (columns - 1) * gap) / columns;
        final photoSize = (cardWidth * .42).clamp(65.0, 112.0);
        final scale = MediaQuery.textScalerOf(context).scale(1);
        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
          sliver: SliverGrid.builder(
            itemCount: items.length,
            findChildIndexCallback: (key) =>
                key is ValueKey<int> ? indexes[key.value] : null,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: gap,
              mainAxisSpacing: gap,
              mainAxisExtent: photoSize + 32 + 104 * scale,
            ),
            itemBuilder: (context, index) =>
                _dishCard(items[index], index, photoSize),
          ),
        );
      },
    );
  }

  Widget _dishCard(MenuItem item, int index, double photoSize) {
    final quantity = cart[item.id]?.quantity ?? 0;
    final theme = Theme.of(context);

    void addItem() => _setState(() {
      final current = cart[item.id];
      if (current == null) {
        cart[item.id] = _CartLine(item);
      } else {
        current.quantity++;
      }
    });

    Widget fallback() => ColoredBox(
      color: luxuryBone,
      child: Center(
        child: Icon(
          Icons.restaurant_menu,
          color: luxuryBrown,
          size: photoSize * .38,
        ),
      ),
    );

    return LuxuryReveal(
      key: ValueKey(item.id),
      index: index,
      hover: true,
      child: Stack(
        children: [
          Positioned.fill(
            top: 16,
            child: Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: addItem,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(10, photoSize - 5, 10, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: luxuryBrown,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (item.description.trim().isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          item.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: luxuryMuted,
                          ),
                        ),
                      ],
                      const Spacer(),
                      Text(
                        money(item.price),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: luxuryBrown,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: IgnorePointer(
              child: Container(
                width: photoSize,
                height: photoSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: luxuryBrown.withValues(alpha: .15),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: item.imageUrl.isEmpty
                      ? fallback()
                      : Image.network(
                          item.imageUrl,
                          key: ValueKey(item.imageUrl),
                          fit: BoxFit.cover,
                          webHtmlElementStrategy:
                              WebHtmlElementStrategy.fallback,
                          errorBuilder: (_, _, _) => fallback(),
                        ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 25,
            right: 7,
            child: Material(
              color: luxuryBone,
              shape: const CircleBorder(),
              child: Badge(
                isLabelVisible: quantity > 0,
                label: Text('$quantity'),
                backgroundColor: luxuryBrown,
                child: IconButton(
                  key: ValueKey('add-menu-item-${item.id}'),
                  style: IconButton.styleFrom(
                    minimumSize: const Size.square(36),
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  tooltip: quantity == 0
                      ? 'Agregar ${item.name}'
                      : 'Agregar otro ${item.name}',
                  onPressed: addItem,
                  icon: const Icon(
                    Icons.add_rounded,
                    color: luxuryBrown,
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _orderCartPanel({
    required RestaurantTable? table,
    bool compact = false,
  }) => Container(
    key: const ValueKey('order-cart-panel'),
    margin: compact
        ? const EdgeInsets.fromLTRB(16, 0, 16, 18)
        : EdgeInsets.zero,
    decoration: BoxDecoration(
      color: const Color(0xFFFFFDFC),
      border: Border.all(color: luxuryBorder),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        children: [
          if (compact) ...[_cartHeading(table), const Divider(height: 22)],
          if (compact && cart.isEmpty)
            _emptyCart()
          else if (compact)
            ...cart.values.map(_orderLineTile)
          else
            Expanded(
              child: cart.isEmpty
                  ? _emptyCart()
                  : ListView(
                      children: cart.values.map(_orderLineTile).toList(),
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

  Widget _emptyCart() => const EmptyState(
    message: 'Agrega platos para comenzar la comanda.',
    icon: Icons.restaurant_menu,
  );

  String _orderLabel(RestaurantTable? table) {
    final location = _orderDestination(table);
    if (_usesJoinedTables || additionalParentId != null) {
      final order = _draftServiceOrder;
      return order == null
          ? 'Orden · $location'
          : 'Pedido #${order.id} · $location';
    }
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
                    maxLines: 2,
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
              if (note != null) _setState(() => line.note = note);
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
          onPressed: () => _setState(() {
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
          onPressed: () => _setState(() => line.quantity++),
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
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () =>
                    _setState(() => _showCompactOrder = !_showCompactOrder),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _showCompactOrder
                          ? 'Ver carta'
                          : 'Ver orden ($_cartQuantity)',
                    ),
                    Text(
                      money(cartTotal),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
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
    label: Text(
      editingOrder != null
          ? 'Guardar cambios'
          : additionalParentId != null
          ? 'Agregar consumo'
          : _usesJoinedTables
          ? 'Registrar pedido'
          : 'Enviar a cocina',
    ),
  );

  Future<String?> _noteDialog(String initial) async {
    final controller = TextEditingController(text: initial);
    final result = await showLuxuryDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Observaciones del plato'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 3,
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
}
