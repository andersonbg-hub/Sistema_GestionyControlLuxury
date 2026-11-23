part of '../kitchen_screen.dart';

// Solo permite escribir dígitos, punto y coma en los campos de cantidad.
final _supplyNumberFormatter = FilteringTextInputFormatter.allow(
  RegExp(r'[0-9.,]'),
);

// Devuelve el número validado o null si el texto no es válido.
// KG, LITRO y GRAMOS aceptan decimales; las demás unidades solo enteros.
double? _parseSupplyNumber(String text, String unit) {
  final t = text.trim().replaceAll(',', '.');
  if (t.isEmpty) return null;
  final allowsDecimal = unit == 'KG' || unit == 'LITRO' || unit == 'GRAMOS';
  final regex = allowsDecimal ? RegExp(r'^\d+(\.\d+)?$') : RegExp(r'^\d+$');
  if (!regex.hasMatch(t)) return null;
  return double.tryParse(t);
}

// Igual que el filtro anterior, pero avisa cuando se intenta escribir algo
// que no es número para poder mostrar un mensaje en el campo.
class _SupplyNumberFormatter extends TextInputFormatter {
  _SupplyNumberFormatter({required this.onRejected, required this.onAccepted});

  final VoidCallback onRejected;
  final VoidCallback onAccepted;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final filtered = newValue.text.replaceAll(RegExp(r'[^0-9.,]'), '');
    if (filtered.length != newValue.text.length) {
      onRejected();
      final removed = newValue.text.length - filtered.length;
      final offset = (newValue.selection.baseOffset - removed).clamp(
        0,
        filtered.length,
      );
      return TextEditingValue(
        text: filtered,
        selection: TextSelection.collapsed(offset: offset),
      );
    }
    onAccepted();
    return newValue;
  }
}

extension _KitchenInventoryView on _KitchenScreenState {
  Future<void> _addNewSupply() async {
    final name = TextEditingController();
    final quantity = TextEditingController();
    final minimum = TextEditingController();
    final description = TextEditingController();
    String unit = 'KG';
    bool submitted = false;
    bool minimumRejected = false;
    bool quantityRejected = false;

    final created = await showLuxuryDialog<bool>(
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
                    'Agrega un insumo que requiera la cocina. Se creará en el almacén para que luego puedas solicitarlo directamente.',
                    style: TextStyle(fontSize: 13, color: luxuryMuted),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: name,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Nuevo insumo a solicitar',
                      prefixIcon: const Icon(Icons.restaurant),
                      errorText: submitted && name.text.trim().isEmpty
                          ? 'Escribe el nombre del insumo'
                          : null,
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
                        child: Text('Kilogramos (KG)'),
                      ),
                      DropdownMenuItem(
                        value: 'UNIDAD',
                        child: Text('Unidades (UNIDAD)'),
                      ),
                      DropdownMenuItem(
                        value: 'LITRO',
                        child: Text('Litros (LITRO)'),
                      ),
                      DropdownMenuItem(
                        value: 'GRAMOS',
                        child: Text('Gramos (G)'),
                      ),
                      DropdownMenuItem(
                        value: 'PORCION',
                        child: Text('Porciones (PORCIÓN)'),
                      ),
                      DropdownMenuItem(
                        value: 'PAQUETE',
                        child: Text('Paquetes (PAQ)'),
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
                          inputFormatters: [
                            _SupplyNumberFormatter(
                              onRejected: () =>
                                  setDialogState(() => minimumRejected = true),
                              onAccepted: () {
                                if (minimumRejected) {
                                  setDialogState(() => minimumRejected = false);
                                }
                              },
                            ),
                          ],
                          decoration: InputDecoration(
                            labelText: 'Stock mínimo ($unit)',
                            hintText: '5',
                            errorText: minimumRejected
                                ? 'Solo se permiten números'
                                : (submitted &&
                                      _parseSupplyNumber(minimum.text, unit) ==
                                          null)
                                ? 'Ingresa un número válido'
                                : null,
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
                          inputFormatters: [
                            _SupplyNumberFormatter(
                              onRejected: () =>
                                  setDialogState(() => quantityRejected = true),
                              onAccepted: () {
                                if (quantityRejected) {
                                  setDialogState(
                                    () => quantityRejected = false,
                                  );
                                }
                              },
                            ),
                          ],
                          decoration: InputDecoration(
                            labelText: 'Stock actual ($unit)',
                            hintText: '0',
                            errorText: quantityRejected
                                ? 'Solo se permiten números'
                                : (submitted &&
                                      _parseSupplyNumber(quantity.text, unit) ==
                                          null)
                                ? 'Ingresa un número válido'
                                : null,
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
                final valid =
                    name.text.trim().isNotEmpty &&
                    _parseSupplyNumber(minimum.text, unit) != null &&
                    _parseSupplyNumber(quantity.text, unit) != null;
                if (!valid) {
                  setDialogState(() => submitted = true);
                  return;
                }
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
      final minVal = _parseSupplyNumber(minimum.text, unit) ?? 1.0;
      final qtyVal = _parseSupplyNumber(quantity.text, unit) ?? 0.0;
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
    final result = await showLuxuryDialog<(String, String)>(
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
                'Indica la cantidad requerida en ${item.unit}.',
                style: const TextStyle(fontSize: 13, color: luxuryMuted),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: quantity,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [_supplyNumberFormatter],
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
        final amount = double.tryParse(result.$1.trim().replaceAll(',', '.'));
        if (amount == null) {
          throw StateError('Escribe una cantidad válida.');
        }
        await store.createStockRequest(item, amount, result.$2);
      });
    }
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
        ),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _addNewSupply,
            icon: const Icon(Icons.add),
            label: const Text('Nuevo insumo a solicitar'),
          ),
        ),
        const SizedBox(height: 8),
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
}
