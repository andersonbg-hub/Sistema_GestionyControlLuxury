import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_widgets.dart';
import 'models.dart';
import 'receipt_pdf.dart';
import 'store.dart';

class _StockRequestDraft {
  _StockRequestDraft(this.inventoryId);

  int inventoryId;
  final TextEditingController quantity = TextEditingController(text: '10');

  void dispose() => quantity.dispose();
}

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key, required this.store, this.managerOnly = false});
  final RestaurantStore store;
  final bool managerOnly;

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  int page = 0;
  int inventoryTab = 0;
  String query = '';
  String category = 'Todas';
  String reportRange = 'Hoy';
  String reportMethod = 'Todos';
  String reportWaiter = 'Todos';

  RestaurantStore get store => widget.store;
  bool get managerOnly => widget.managerOnly;
  List<int> get _pages => widget.managerOnly
      ? const [0, 3, 4, 6, 5, 7]
      : const [0, 1, 2, 3, 4, 5, 6, 7];
  int get _activePage => _pages[page];

  Future<void> _newStockRequest() async {
    final available = store.inventory.where((item) => item.active).toList();
    if (available.isEmpty) {
      await showResultDialog(
        context,
        success: false,
        message: 'No hay insumos activos para solicitar.',
      );
      return;
    }
    final note = TextEditingController();
    var validationError = '';
    final rows = <_StockRequestDraft>[_StockRequestDraft(available.first.id)];
    final result = await showDialog<List<(int, double)>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nueva solicitud de reabastecimiento'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...rows.map((row) {
                    final used = rows
                        .where((other) => !identical(other, row))
                        .map((other) => other.inventoryId)
                        .toSet();
                    final choices = available
                        .where(
                          (item) =>
                              item.id == row.inventoryId ||
                              !used.contains(item.id),
                        )
                        .toList();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<int>(
                              isExpanded: true,
                              initialValue: row.inventoryId,
                              decoration: const InputDecoration(
                                labelText: 'Insumo',
                              ),
                              items: choices
                                  .map(
                                    (item) => DropdownMenuItem(
                                      value: item.id,
                                      child: Text(item.name),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) => setDialogState(
                                () =>
                                    row.inventoryId = value ?? row.inventoryId,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: row.quantity,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText:
                                    'Cantidad (${store.inventory.firstWhere((item) => item.id == row.inventoryId).unit})',
                              ),
                            ),
                          ),
                          if (rows.length > 1)
                            IconButton(
                              tooltip: 'Quitar insumo',
                              onPressed: () => setDialogState(() {
                                rows.remove(row);
                                row.dispose();
                              }),
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                color: luxuryRed,
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: rows.length >= available.length
                          ? null
                          : () => setDialogState(() {
                              final used = rows
                                  .map((row) => row.inventoryId)
                                  .toSet();
                              final next = available.firstWhere(
                                (item) => !used.contains(item.id),
                              );
                              rows.add(_StockRequestDraft(next.id));
                            }),
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar otro insumo'),
                    ),
                  ),
                  TextField(
                    controller: note,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Observación'),
                  ),
                  if (validationError.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          validationError,
                          style: const TextStyle(color: luxuryRed),
                        ),
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
                final values = <(int, double)>[];
                for (final row in rows) {
                  final quantity = double.tryParse(row.quantity.text.trim());
                  if (quantity == null || quantity <= 0) {
                    setDialogState(
                      () => validationError =
                          'Ingresa una cantidad válida mayor que cero.',
                    );
                    return;
                  }
                  values.add((row.inventoryId, quantity));
                }
                validationError = '';
                Navigator.pop(context, values);
              },
              child: const Text('Enviar solicitud'),
            ),
          ],
        ),
      ),
    );
    final observation = note.text.trim();
    note.dispose();
    for (final row in rows) {
      row.dispose();
    }
    if (result == null) return;
    await _run(
      () => store.createStockRequestBatch(
        items: result
            .map(
              (entry) => (
                store.inventory.firstWhere((item) => item.id == entry.$1),
                entry.$2,
              ),
            )
            .toList(),
        note: observation,
      ),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) {
        await showResultDialog(context, success: false, message: '$error');
      }
    }
  }

  Future<String?> _textDialog({
    required String title,
    required String label,
    String initial = '',
    TextInputType keyboardType = TextInputType.text,
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: keyboardType,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (_) => Navigator.pop(context, controller.text.trim()),
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

  Future<void> _editMenuItem([MenuItem? item]) async {
    final name = TextEditingController(text: item?.name ?? '');
    final price = TextEditingController(
      text: item?.price.toStringAsFixed(2) ?? '',
    );
    final description = TextEditingController(text: item?.description ?? '');
    var selectedCategory =
        item?.category ??
        (store.categories.isEmpty ? 'Chifas' : store.categories.first);
    final result = await showDialog<(String, String, String, String)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(item == null ? 'Nuevo platillo' : 'Editar platillo'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(labelText: 'Nombre'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: store.categories.contains(selectedCategory)
                          ? selectedCategory
                          : null,
                      decoration: const InputDecoration(labelText: 'Categoría'),
                      items: store.categories
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setDialogState(
                        () => selectedCategory = value ?? selectedCategory,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: price,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Precio (S/)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: description,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Descripción',
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
                onPressed: () => Navigator.pop(context, (
                  name.text.trim(),
                  selectedCategory,
                  price.text.trim(),
                  description.text.trim(),
                )),
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );
    if (result != null) {
      await _run(() async {
        final value = double.tryParse(result.$3);
        if (value == null || value < 0) {
          throw StateError('Escribe un precio válido.');
        }
        await store.saveMenuItem(
          id: item?.id,
          name: result.$1,
          category: result.$2,
          price: value,
          description: result.$4,
        );
      });
    }
    name.dispose();
    price.dispose();
    description.dispose();
  }

  Future<void> _editCategory([String? oldName]) async {
    final name = await _textDialog(
      title: oldName == null ? 'Nueva categoría' : 'Renombrar categoría',
      label: 'Nombre de categoría',
      initial: oldName ?? '',
    );
    if (name == null) return;
    await _run(() async {
      await store.saveCategory(previousName: oldName, name: name);
      if (oldName != null && category == oldName) {
        setState(() => category = name);
      }
    });
  }

  Future<void> _editInventory([InventoryItem? item]) async {
    final name = TextEditingController(text: item?.name ?? '');
    final description = TextEditingController(text: item?.description ?? '');
    final quantity = TextEditingController(
      text: item?.quantity.toString() ?? '0',
    );
    final minimum = TextEditingController(
      text: item?.minimum.toString() ?? '0',
    );
    var unit = item?.unit ?? 'KG';
    final result = await showDialog<(String, String, String, String, String)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(item == null ? 'Nuevo insumo' : 'Editar insumo'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: description,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Descripción'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: unit,
                  decoration: const InputDecoration(labelText: 'Unidad'),
                  items: const ['KG', 'G', 'LITRO', 'UNIDAD']
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => unit = value ?? unit),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: quantity,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Stock actual'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: minimum,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Mínimo'),
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
              onPressed: () => Navigator.pop(context, (
                name.text.trim(),
                description.text.trim(),
                unit,
                quantity.text.trim(),
                minimum.text.trim(),
              )),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      await _run(() async {
        final count = double.tryParse(result.$4);
        final threshold = double.tryParse(result.$5);
        if (count == null || threshold == null) {
          throw StateError('Escribe valores de stock válidos.');
        }
        await store.updateInventory(
          id: item?.id,
          name: result.$1,
          description: result.$2,
          unit: result.$3,
          quantity: count,
          minimum: threshold,
        );
      });
    }
    name.dispose();
    description.dispose();
    quantity.dispose();
    minimum.dispose();
  }

  Future<void> _editTable([RestaurantTable? table]) async {
    final number = TextEditingController(text: table?.number.toString() ?? '');
    final capacity = TextEditingController(
      text: table?.capacity.toString() ?? '4',
    );
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(table == null ? 'Nueva mesa' : 'Editar mesa'),
        content: SizedBox(
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: number,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Número de mesa'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: capacity,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Capacidad'),
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
                Navigator.pop(context, (number.text, capacity.text)),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (result != null) {
      await _run(() async {
        final n = int.tryParse(result.$1);
        final c = int.tryParse(result.$2);
        if (n == null || c == null) {
          throw StateError('Escribe números de mesa y capacidad válidos.');
        }
        await store.saveTable(id: table?.id, number: n, capacity: c);
      });
    }
    number.dispose();
    capacity.dispose();
  }

  String _temporaryPassword() {
    const characters =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#%';
    final random = math.Random.secure();
    return List.generate(
      14,
      (_) => characters[random.nextInt(characters.length)],
    ).join();
  }

  Future<void> _editStaff([StaffMember? member]) async {
    final name = TextEditingController(text: member?.name ?? '');
    final email = TextEditingController(text: member?.email ?? '');
    final password = TextEditingController(text: _temporaryPassword());
    var role = member?.role ?? StaffRole.waiter;
    final result = await showDialog<(String, String, StaffRole, String)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(member == null ? 'Crear usuario' : 'Editar usuario'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'Nombre completo',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Correo'),
                ),
                const SizedBox(height: 12),
                if (member == null) ...[
                  TextField(
                    controller: password,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Contraseña temporal',
                      helperText:
                          'Se enviará al correo y deberá cambiarse al ingresar.',
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                DropdownButtonFormField<StaffRole>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Rol'),
                  items: StaffRole.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => role = value ?? role),
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
              onPressed: () => Navigator.pop(context, (
                name.text.trim(),
                email.text.trim(),
                role,
                password.text,
              )),
              child: Text(member == null ? 'Crear cuenta' : 'Guardar cambios'),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      await _run(() async {
        if (result.$1.isEmpty || !result.$2.contains('@')) {
          throw StateError('Indica un nombre y un correo válidos.');
        }
        if (member == null) {
          if (result.$4.length < 8) {
            throw StateError(
              'La contraseña temporal debe tener al menos 8 caracteres.',
            );
          }
          await store.addStaffMember(
            name: result.$1,
            email: result.$2,
            role: result.$3,
            password: result.$4,
          );
        } else {
          await store.updateStaffMember(
            member: member,
            name: result.$1,
            email: result.$2,
            role: result.$3,
          );
        }
      });
    }
    name.dispose();
    email.dispose();
    password.dispose();
  }

  Future<void> _resetStaffPassword(StaffMember member) async {
    final password = TextEditingController(text: _temporaryPassword());
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restablecer contraseña'),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: password,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Contraseña temporal para ${member.name}',
              helperText: 'Se enviará al correo registrado.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, password.text.trim()),
            child: const Text('Restablecer y enviar'),
          ),
        ],
      ),
    );
    if (result != null) {
      await _run(
        () => store.resetStaffPassword(member: member, password: result),
      );
    }
    password.dispose();
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

  Future<void> _voidReceipt(Map<String, dynamic> receipt) async {
    final reason = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Anulación y devolución'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${receipt['code']} · ${money((receipt['total'] as num).toDouble())}',
            ),
            const SizedBox(height: 12),
            const Text(
              'Se registrará el extorno interno de cada método de pago. El reembolso externo debe ejecutarse por separado.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              minLines: 2,
              maxLines: 4,
              maxLength: 240,
              decoration: const InputDecoration(
                labelText: 'Motivo de anulación',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: luxuryRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, reason.text.trim()),
            child: const Text('Anular nota'),
          ),
        ],
      ),
    );
    reason.dispose();
    if (result != null) {
      await _run(() => store.voidReceipt(receipt: receipt, reason: result));
    }
  }

  Widget _searchField() => TextField(
    decoration: const InputDecoration(
      prefixIcon: Icon(Icons.search),
      hintText: 'Buscar en esta vista',
    ),
    onChanged: (value) => setState(() => query = value.toLowerCase().trim()),
  );

  Widget _dashboard() {
    final today = DateTime.now();
    final startToday = DateTime(today.year, today.month, today.day);
    final startYesterday = startToday.subtract(const Duration(days: 1));
    final validReceipts = store.receipts.where(
      (receipt) => receipt['status'] == 'VIGENTE',
    );
    final todayReceipts = validReceipts.where((receipt) {
      final issued = DateTime.tryParse(receipt['createdAt'] as String? ?? '');
      return issued != null && !issued.isBefore(startToday);
    }).toList();
    final yesterdayReceipts = validReceipts.where((receipt) {
      final issued = DateTime.tryParse(receipt['createdAt'] as String? ?? '');
      return issued != null &&
          !issued.isBefore(startYesterday) &&
          issued.isBefore(startToday);
    }).toList();
    final revenue = todayReceipts.fold<double>(
      0,
      (sum, receipt) => sum + (receipt['total'] as num).toDouble(),
    );
    final yesterdayRevenue = yesterdayReceipts.fold<double>(
      0,
      (sum, receipt) => sum + (receipt['total'] as num).toDouble(),
    );
    final activeOrders = store.orders.where(
      (order) =>
          order.status != OrderStatus.paid &&
          order.status != OrderStatus.cancelled &&
          order.status != OrderStatus.delivered,
    );
    final lowStock = store.inventory
        .where((item) => item.active && item.lowStock)
        .toList();
    final weekStart = startToday.subtract(const Duration(days: 6));
    final bestSellers = <String, int>{};
    for (final order in store.orders.where(
      (order) =>
          order.status == OrderStatus.paid &&
          !order.createdAt.isBefore(weekStart),
    )) {
      for (final line in order.lines) {
        bestSellers.update(
          line.name,
          (count) => count + line.quantity,
          ifAbsent: () => line.quantity,
        );
      }
    }
    final topItems = bestSellers.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(
          title: 'Dashboard general',
          subtitle: 'Resumen del servicio y la operación',
        ),
        StatGrid(
          children: [
            StatCard(
              label: 'Ventas del día',
              value: money(revenue),
              icon: Icons.payments,
              color: luxuryGold,
            ),
            StatCard(
              label: 'Pedidos atendidos',
              value: '${todayReceipts.length}',
              icon: Icons.receipt_long,
            ),
            StatCard(
              label: 'Ticket promedio',
              value: money(
                todayReceipts.isEmpty ? 0 : revenue / todayReceipts.length,
              ),
              icon: Icons.show_chart,
            ),
            StatCard(
              label: 'Alertas pendientes',
              value:
                  '${store.alerts.where((alert) => alert.status == 'NUEVA').length + lowStock.length}',
              icon: Icons.warning_amber,
              color: luxuryRed,
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'Ayer se registraron ${money(yesterdayRevenue)} · ${activeOrders.length} pedidos actualmente abiertos',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final vertical = constraints.maxWidth < 800;
            final left = _dashboardTables();
            final right = _dashboardAlerts(lowStock);
            return vertical
                ? Column(children: [left, const SizedBox(height: 16), right])
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: left),
                      const SizedBox(width: 16),
                      Expanded(flex: 2, child: right),
                    ],
                  );
          },
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Platillos más solicitados',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                if (topItems.isEmpty)
                  const Text('Aún no hay ventas para mostrar.')
                else
                  ...topItems
                      .take(5)
                      .map(
                        (entry) => ResponsiveListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.restaurant_menu,
                            color: luxuryGold,
                          ),
                          title: Text(entry.key),
                          trailing: Text('${entry.value} vendidos'),
                        ),
                      ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _dashboardTables() {
    final available = store.tables
        .where((table) => table.status == TableStatus.available)
        .length;
    final occupied = store.tables
        .where((table) => table.status == TableStatus.occupied)
        .length;
    final payment = store.tables
        .where((table) => table.status == TableStatus.payment)
        .length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Estado del salón',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _countChip('Disponibles', available, luxuryGreen),
                _countChip('Ocupadas', occupied, luxuryGold),
                _countChip('Por cobrar', payment, luxuryRed),
              ],
            ),
            const SizedBox(height: 10),
            ...store.tables
                .take(8)
                .map(
                  (table) => ResponsiveListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.table_restaurant,
                      color: statusColor(table.status.databaseValue),
                    ),
                    title: Text('Mesa ${table.number}'),
                    subtitle: Text('${table.capacity} personas'),
                    trailing: StatusBadge.table(table.status),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _dashboardAlerts(List<InventoryItem> lowStock) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Alertas de inventario',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          ...store.alerts
              .where((alert) => alert.status == 'NUEVA')
              .take(3)
              .map(
                (alert) => ResponsiveListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.notifications_active_outlined,
                    color: luxuryRed,
                  ),
                  title: Text(alert.message),
                  subtitle: Text('Aviso de cocina · ${alert.priority}'),
                  trailing: TextButton(
                    onPressed: managerOnly
                        ? null
                        : () => _run(() => store.reviewKitchenAlert(alert)),
                    child: Text(managerOnly ? 'Pendiente' : 'Atender'),
                  ),
                ),
              ),
          if (lowStock.isEmpty &&
              store.alerts.every((alert) => alert.status != 'NUEVA'))
            const EmptyState(
              message: 'No hay alertas pendientes.',
              icon: Icons.check_circle_outline,
            )
          else
            ...lowStock.map(
              (item) => ResponsiveListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.warning_amber, color: luxuryRed),
                title: Text(item.name),
                subtitle: Text(
                  '${item.quantity} ${item.unit} · mínimo ${item.minimum}',
                ),
                trailing: TextButton(
                  onPressed: () => _run(
                    () => store.createStockRequest(
                      item,
                      item.minimum * 2,
                      'Reposición por stock bajo',
                    ),
                  ),
                  child: const Text('Solicitar'),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _countChip(String label, int count, Color color) => Chip(
    avatar: CircleAvatar(radius: 7, backgroundColor: color),
    label: Text('$label · $count'),
  );

  Widget _menuPage() {
    final categories = ['Todas', ...store.categories];
    final items = store.menu.where((item) {
      final matchesText = '${item.name} ${item.description}'
          .toLowerCase()
          .contains(query);
      return matchesText && (category == 'Todas' || item.category == category);
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          title: 'Menú y catálogo',
          subtitle: 'Categorías, disponibilidad y precios',
          trailing: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _editCategory(),
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('Categoría'),
              ),
              if (category != 'Todas')
                IconButton(
                  tooltip: 'Renombrar categoría',
                  onPressed: () => _editCategory(category),
                  icon: const Icon(Icons.edit_outlined),
                ),
              if (category != 'Todas')
                IconButton(
                  tooltip: 'Eliminar categoría',
                  onPressed: () => _run(() async {
                    await store.removeCategory(category);
                    setState(() => category = 'Todas');
                  }),
                  icon: const Icon(Icons.delete_outline, color: luxuryRed),
                ),
              FilledButton.icon(
                onPressed: () => _editMenuItem(),
                icon: const Icon(Icons.add),
                label: const Text('Nuevo plato'),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: categories
              .map(
                (value) => ChoiceChip(
                  label: Text(value),
                  selected: category == value,
                  onSelected: (_) => setState(() => category = value),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 12),
        _searchField(),
        const SizedBox(height: 10),
        if (items.isEmpty)
          const EmptyState(
            message: 'No hay platillos que coincidan con la búsqueda.',
          )
        else
          ...items.map(
            (item) => Card(
              child: ResponsiveListTile(
                leading: CircleAvatar(
                  backgroundColor: luxuryGold.withValues(alpha: .18),
                  child: const Icon(Icons.restaurant, color: luxuryBrown),
                ),
                title: Text(
                  item.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${item.category}${item.description.isEmpty ? '' : ' · ${item.description}'}',
                ),
                trailing: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    Text(
                      money(item.price),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Switch(
                      value: item.available,
                      onChanged: (value) =>
                          _run(() => store.setMenuAvailability(item, value)),
                    ),
                    IconButton(
                      tooltip: 'Editar',
                      onPressed: () => _editMenuItem(item),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _inventoryPage() {
    final items = store.inventory
        .where(
          (item) => '${item.name} ${item.description} ${item.unit}'
              .toLowerCase()
              .contains(query),
        )
        .toList();
    final requests = store.requests
        .where(
          (request) => '${request.itemName} ${request.status} ${request.note}'
              .toLowerCase()
              .contains(query),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          title: 'Inventario',
          subtitle: 'Existencias, mínimos y reabastecimiento',
          trailing: inventoryTab == 0
              ? FilledButton.icon(
                  onPressed: () => _editInventory(),
                  icon: const Icon(Icons.add),
                  label: const Text('Nuevo insumo'),
                )
              : inventoryTab == 1
              ? FilledButton.icon(
                  onPressed: _newStockRequest,
                  icon: const Icon(Icons.add),
                  label: const Text('Nueva solicitud'),
                )
              : null,
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Insumos')),
              ButtonSegment(value: 1, label: Text('Solicitudes')),
              ButtonSegment(value: 2, label: Text('Alertas')),
            ],
            selected: {inventoryTab},
            onSelectionChanged: (selection) =>
                setState(() => inventoryTab = selection.first),
          ),
        ),
        const SizedBox(height: 12),
        _searchField(),
        const SizedBox(height: 12),
        if (inventoryTab == 2) ...[
          ...store.alerts
              .where(
                (alert) => '${alert.message} ${alert.priority}'
                    .toLowerCase()
                    .contains(query),
              )
              .map((alert) {
                final item = store.inventory
                    .where((value) => value.id == alert.inventoryId)
                    .firstOrNull;
                return Card(
                  child: ResponsiveListTile(
                    leading: Icon(
                      alert.status == 'NUEVA'
                          ? Icons.notifications_active_outlined
                          : Icons.check_circle_outline,
                      color: alert.status == 'NUEVA' ? luxuryRed : luxuryGreen,
                    ),
                    title: Text(alert.message),
                    subtitle: Text(
                      '${alert.priority} · ${alert.createdAt.toLocal()}',
                    ),
                    trailing: Wrap(
                      children: [
                        if (item != null)
                          IconButton(
                            tooltip: 'Crear solicitud de reabastecimiento',
                            onPressed: () => _run(
                              () => store.createStockRequest(
                                item,
                                item.minimum * 2,
                                'Por alerta: ${alert.message}',
                              ),
                            ),
                            icon: const Icon(Icons.add_shopping_cart),
                          ),
                        if (alert.status == 'NUEVA')
                          FilledButton.tonal(
                            onPressed: () =>
                                _run(() => store.reviewKitchenAlert(alert)),
                            child: const Text('Atender'),
                          )
                        else
                          const StatusBadge(
                            label: 'Revisada',
                            color: luxuryGreen,
                          ),
                      ],
                    ),
                  ),
                );
              }),
          ...store.inventory
              .where(
                (item) =>
                    item.active &&
                    item.lowStock &&
                    '${item.name} ${item.unit}'.toLowerCase().contains(query),
              )
              .map(
                (item) => Card(
                  child: ResponsiveListTile(
                    leading: const Icon(Icons.warning_amber, color: luxuryRed),
                    title: Text('Stock bajo: ${item.name}'),
                    subtitle: Text(
                      'Actual ${item.quantity} ${item.unit} · mínimo ${item.minimum} ${item.unit}',
                    ),
                    trailing: FilledButton.tonal(
                      onPressed: managerOnly
                          ? null
                          : () => _run(
                              () => store.createStockRequest(
                                item,
                                item.minimum * 2,
                                'Alerta de stock bajo',
                              ),
                            ),
                      child: const Text('Reabastecer'),
                    ),
                  ),
                ),
              ),
        ] else if (inventoryTab == 1)
          ...requests.map(
            (request) => Card(
              child: ResponsiveListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text(
                  request.items.isEmpty
                      ? '${request.itemName} · ${request.quantity} ${request.unit}'
                      : request.items
                            .map(
                              (item) =>
                                  '${item.itemName} · ${item.quantity} ${item.unit}',
                            )
                            .join(' · '),
                ),
                subtitle: Text('${request.note} · ${request.priority}'),
                trailing: Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusBadge(
                      label: switch (request.status) {
                        'ATENDIDO' => 'Atendido',
                        'CANCELADA' => 'Cancelada',
                        'EN_PROCESO' => 'En proceso',
                        _ => 'Pendiente',
                      },
                      color: request.status == 'ATENDIDO'
                          ? luxuryGreen
                          : request.status == 'CANCELADA'
                          ? luxuryRed
                          : luxuryGold,
                    ),
                    if (request.status == 'PENDIENTE' ||
                        request.status == 'EN_PROCESO') ...[
                      OutlinedButton(
                        onPressed: () =>
                            _run(() => store.advanceRequest(request)),
                        child: Text(
                          request.status == 'PENDIENTE'
                              ? 'Procesar'
                              : 'Atender',
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cancelar solicitud',
                        onPressed: () =>
                            _run(() => store.cancelRequest(request)),
                        icon: const Icon(
                          Icons.cancel_outlined,
                          color: luxuryRed,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          )
        else
          ...items.map(
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
                  [
                    if (item.description.isNotEmpty) item.description,
                    'Mínimo ${item.minimum} ${item.unit}',
                    if (!item.active) 'Archivado',
                  ].join(' · '),
                ),
                trailing: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    Text(
                      '${item.quantity} ${item.unit}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: item.lowStock ? luxuryRed : null,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Editar insumo',
                      onPressed: () => _editInventory(item),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    Text(item.active ? 'En catálogo' : 'Archivado'),
                    Switch(
                      value: item.active,
                      onChanged: (value) =>
                          _run(() => store.setInventoryActive(item, value)),
                    ),
                    IconButton(
                      tooltip: 'Solicitar insumo',
                      onPressed: !item.active
                          ? null
                          : () => _run(
                              () => store.createStockRequest(
                                item,
                                item.minimum * 2,
                                'Reposición solicitada por administración',
                              ),
                            ),
                      icon: const Icon(Icons.add_shopping_cart),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _staffPage() {
    final members = store.staff
        .where(
          (member) => '${member.name} ${member.email} ${member.role.label}'
              .toLowerCase()
              .contains(query),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          title: 'Usuarios y roles',
          subtitle: store.isDemo
              ? 'Personal de la demostración'
              : 'Perfiles activos de Supabase Auth',
          trailing: managerOnly
              ? null
              : FilledButton.icon(
                  onPressed: _editStaff,
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Nuevo usuario'),
                ),
        ),
        _searchField(),
        const SizedBox(height: 12),
        if (members.isEmpty)
          const EmptyState(message: 'No se encontraron usuarios.')
        else
          ...members.map(
            (member) => Card(
              child: ResponsiveListTile(
                leading: CircleAvatar(
                  child: Text(
                    member.name.isEmpty ? '?' : member.name[0].toUpperCase(),
                  ),
                ),
                title: Text(member.name),
                subtitle: Text(member.email),
                trailing: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Chip(label: Text(member.role.label)),
                    if (!managerOnly)
                      IconButton(
                        tooltip: 'Editar usuario',
                        onPressed: () => _editStaff(member),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    if (!managerOnly && store.isConnected)
                      IconButton(
                        tooltip: 'Restablecer contraseña',
                        onPressed: () => _resetStaffPassword(member),
                        icon: const Icon(Icons.lock_reset),
                      ),
                    Switch(
                      value: member.active,
                      onChanged: managerOnly
                          ? null
                          : (value) => _run(() => store.toggleStaff(member)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (!store.isDemo)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'La creación, edición y el restablecimiento requieren desplegar la función manage-staff y configurar el correo saliente en Supabase.',
              style: TextStyle(color: Colors.black54),
            ),
          ),
      ],
    );
  }

  Widget _tablesPage() {
    final tables = store.tables
        .where((table) => 'mesa ${table.number}'.contains(query))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          title: 'Mesas',
          subtitle:
              '${store.tables.fold<int>(0, (sum, table) => sum + table.capacity)} asientos disponibles en el salón',
          trailing: managerOnly
              ? null
              : FilledButton.icon(
                  onPressed: () => _editTable(),
                  icon: const Icon(Icons.add),
                  label: const Text('Nueva mesa'),
                ),
        ),
        _searchField(),
        const SizedBox(height: 12),
        if (tables.isEmpty)
          const EmptyState(message: 'No hay mesas registradas.')
        else
          ...tables.map(
            (table) => Card(
              child: ResponsiveListTile(
                leading: const Icon(Icons.table_restaurant),
                title: Text('Mesa ${table.number}'),
                subtitle: Text('${table.capacity} personas'),
                trailing: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusBadge.table(table.status),
                    if (!managerOnly) ...[
                      IconButton(
                        tooltip: 'Editar mesa',
                        onPressed: () => _editTable(table),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Eliminar mesa',
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Eliminar mesa'),
                              content: Text(
                                '¿Eliminar la mesa ${table.number}?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancelar'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Eliminar'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await _run(() => store.removeTable(table));
                          }
                        },
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  List<PaymentEntry> _receiptPayments(Map<String, dynamic> receipt) =>
      (receipt['payments'] as List<dynamic>? ?? const [])
          .map(
            (payment) => payment is PaymentEntry
                ? payment
                : PaymentEntry.fromJson(
                    Map<String, dynamic>.from(payment as Map),
                  ),
          )
          .toList(growable: false);

  Widget _reportsPage() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final cutoff = switch (reportRange) {
      'Hoy' => today,
      '7 días' => today.subtract(const Duration(days: 6)),
      _ => DateTime.fromMillisecondsSinceEpoch(0),
    };
    final allValidReceipts = store.receipts.where(
      (receipt) => receipt['status'] == 'VIGENTE',
    );
    final receipts =
        allValidReceipts.where((receipt) {
          final issued = DateTime.tryParse(
            receipt['createdAt'] as String? ?? '',
          );
          if (issued == null || issued.isBefore(cutoff)) return false;
          if (reportMethod != 'Todos' &&
              !_receiptPayments(
                receipt,
              ).any((payment) => payment.method == reportMethod)) {
            return false;
          }
          if (reportWaiter != 'Todos') {
            final order = store.orders
                .where((order) => order.id == receipt['orderId'])
                .firstOrNull;
            if (order?.waiterName != reportWaiter) return false;
          }
          return true;
        }).toList()..sort(
          (a, b) => DateTime.parse(
            b['createdAt'] as String,
          ).compareTo(DateTime.parse(a['createdAt'] as String)),
        );
    final total = receipts.fold<double>(
      0,
      (sum, receipt) => sum + (receipt['total'] as num).toDouble(),
    );
    final methods = <String, double>{};
    for (final receipt in receipts) {
      for (final payment in _receiptPayments(receipt)) {
        methods.update(
          payment.method,
          (value) => value + payment.amount,
          ifAbsent: () => payment.amount,
        );
      }
    }
    final waiters =
        store.orders
            .map((order) => order.waiterName)
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    String csvCell(Object? value) =>
        '"${(value ?? '').toString().replaceAll('"', '""')}"';
    final csvRows = [
      ['Nota', 'Fecha', 'Mesa', 'Mesero', 'Métodos de pago', 'Total'],
      ...receipts.map((receipt) {
        final order = store.orders
            .where((value) => value.id == receipt['orderId'])
            .firstOrNull;
        final payments = _receiptPayments(receipt)
            .map(
              (payment) =>
                  '${payment.method} ${payment.amount.toStringAsFixed(2)}',
            )
            .join(' + ');
        return [
          receipt['code'],
          receipt['createdAt'],
          receipt['tableNumber'],
          order?.waiterName ?? 'Mesero',
          payments,
          (receipt['total'] as num).toStringAsFixed(2),
        ];
      }),
    ].map((row) => row.map(csvCell).join(';')).join('\r\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          title: 'Reportes',
          subtitle: 'Ventas, cobros y actividad',
          trailing: OutlinedButton.icon(
            onPressed: receipts.isEmpty
                ? null
                : () async {
                    Clipboard.setData(ClipboardData(text: csvRows));
                    await showResultDialog(
                      context,
                      success: true,
                      message: 'CSV copiado · ${receipts.length} comprobantes',
                    );
                  },
            icon: const Icon(Icons.content_copy),
            label: const Text('Copiar CSV'),
          ),
        ),
        Wrap(
          spacing: 8,
          children: ['Hoy', '7 días', 'Todo']
              .map(
                (range) => ChoiceChip(
                  label: Text(range),
                  selected: reportRange == range,
                  onSelected: (_) => setState(() => reportRange = range),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Método'),
            DropdownButton<String>(
              value: reportMethod,
              items: const ['Todos', 'Efectivo', 'Yape / Plin', 'Tarjeta']
                  .map(
                    (method) =>
                        DropdownMenuItem(value: method, child: Text(method)),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => reportMethod = value ?? 'Todos'),
            ),
            const Text('Mesero'),
            DropdownButton<String>(
              value: reportWaiter,
              items: [
                const DropdownMenuItem(value: 'Todos', child: Text('Todos')),
                ...waiters.map(
                  (name) => DropdownMenuItem(value: name, child: Text(name)),
                ),
              ],
              onChanged: (value) =>
                  setState(() => reportWaiter = value ?? 'Todos'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        StatGrid(
          maxColumns: 3,
          children: [
            StatCard(
              label: 'Total cobrado',
              value: money(total),
              icon: Icons.payments,
              color: luxuryGold,
            ),
            StatCard(
              label: 'Notas de venta',
              value: '${receipts.length}',
              icon: Icons.receipt_long,
            ),
            StatCard(
              label: 'Ticket promedio',
              value: money(receipts.isEmpty ? 0 : total / receipts.length),
              icon: Icons.show_chart,
            ),
          ],
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cobros por método',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                if (methods.isEmpty)
                  const Text('No hay pagos en el periodo seleccionado.')
                else
                  ...methods.entries.map(
                    (entry) => ResponsiveListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.account_balance_wallet_outlined,
                      ),
                      title: Text(entry.key),
                      trailing: Text(
                        money(entry.value),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (receipts.isEmpty)
          const EmptyState(
            message: 'No hay notas vigentes con estos filtros.',
            icon: Icons.receipt_long,
          )
        else
          ...receipts.map((receipt) {
            final order = store.orders
                .where((value) => value.id == receipt['orderId'])
                .firstOrNull;
            return Card(
              child: ResponsiveListTile(
                title: Text(
                  '${receipt['code']} · ${receipt['locationLabel'] ?? 'Mesa ${receipt['tableNumber']}'}',
                ),
                subtitle: Text(
                  '${order?.waiterName ?? 'Mesero'} · ${receipt['createdAt']}',
                ),
                trailing: Text(money((receipt['total'] as num).toDouble())),
              ),
            );
          }),
        const SizedBox(height: 18),
        Text('Notas de venta', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (store.receipts.isEmpty)
          const Text('No se han emitido notas de venta en este entorno.')
        else
          ...store.receipts.map(
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
                    Text(money((receipt['total'] as num).toDouble())),
                    IconButton(
                      tooltip: 'Imprimir nota',
                      onPressed: () => _printReceipt(receipt),
                      icon: const Icon(Icons.print_outlined),
                    ),
                    if (receipt['status'] == 'ANULADO')
                      const StatusBadge(label: 'Anulada', color: luxuryRed)
                    else
                      IconButton(
                        tooltip: 'Anular nota',
                        onPressed: () => _voidReceipt(receipt),
                        icon: const Icon(Icons.undo, color: luxuryRed),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _incidentsPage() {
    final incidents =
        store.orders.where((order) => order.incident.trim().isNotEmpty).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(
          title: 'Incidencias',
          subtitle: 'Reportes de cocina para seguimiento de caja y gerencia',
        ),
        if (incidents.isEmpty)
          const EmptyState(
            message: 'No hay incidencias de cocina registradas.',
            icon: Icons.task_alt,
          )
        else
          ...incidents.map(
            (order) => Card(
              child: ResponsiveListTile(
                leading: const Icon(
                  Icons.report_problem_outlined,
                  color: luxuryRed,
                ),
                title: Text('Pedido #${order.id} · ${order.locationLabel}'),
                subtitle: Text(
                  '${order.incident}\n${order.createdAt.toLocal()} · ${order.status.label}',
                ),
                isThreeLine: true,
              ),
            ),
          ),
      ],
    );
  }

  Widget _auditPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SectionTitle(
        title: 'Auditoría de movimientos',
        subtitle: 'Trazabilidad de operaciones registradas en PostgreSQL',
      ),
      if (store.auditEntries.isEmpty)
        const EmptyState(
          message: 'No hay movimientos registrados todavía.',
          icon: Icons.history,
        )
      else
        ...store.auditEntries.map(
          (entry) => Card(
            child: ResponsiveListTile(
              leading: const Icon(Icons.history),
              title: Text(
                '${entry.action} · ${entry.entity} #${entry.entityId}',
              ),
              subtitle: Text(
                '${entry.actorName} · ${entry.actorRole} · ${entry.createdAt.toLocal()}',
              ),
            ),
          ),
        ),
    ],
  );

  Widget _pageContent() => switch (_activePage) {
    _ when _activePage == 0 => _dashboard(),
    _ when _activePage == 1 => _menuPage(),
    _ when _activePage == 2 => _inventoryPage(),
    _ when _activePage == 3 => _staffPage(),
    _ when _activePage == 4 => _tablesPage(),
    _ when _activePage == 5 => _reportsPage(),
    _ when _activePage == 6 => _incidentsPage(),
    _ => _auditPage(),
  };

  Widget _content() => Column(
    children: [
      if (store.errorMessage != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: ErrorBanner(message: store.errorMessage!),
        ),
      Expanded(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
            22,
            MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
            32,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1320),
              child: _pageContent(),
            ),
          ),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final titles = managerOnly
          ? const [
              'Resumen',
              'Usuarios',
              'Mesas',
              'Incidencias',
              'Reportes',
              'Auditoría',
            ]
          : const [
              'Resumen',
              'Menú y catálogo',
              'Inventario',
              'Usuarios y roles',
              'Mesas',
              'Reportes',
              'Incidencias',
              'Auditoría',
            ];
      final pageIcons = managerOnly
          ? const [
              Icons.space_dashboard_outlined,
              Icons.groups_outlined,
              Icons.table_restaurant,
              Icons.report_problem_outlined,
              Icons.bar_chart,
              Icons.history,
            ]
          : const [
              Icons.space_dashboard_outlined,
              Icons.restaurant_menu,
              Icons.inventory_2_outlined,
              Icons.groups_outlined,
              Icons.table_restaurant,
              Icons.bar_chart,
              Icons.report_problem_outlined,
              Icons.history,
            ];
      if (constraints.maxWidth < 760) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: DropdownButtonFormField<int>(
                key: ValueKey('admin-navigation-$page'),
                initialValue: page,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Sección'),
                items: List.generate(
                  _pages.length,
                  (index) => DropdownMenuItem(
                    value: index,
                    child: Row(
                      children: [
                        Icon(pageIcons[index], size: 20),
                        const SizedBox(width: 12),
                        Expanded(child: Text(titles[index])),
                      ],
                    ),
                  ),
                ),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    page = value;
                    query = '';
                  });
                },
              ),
            ),
            Expanded(child: _content()),
          ],
        );
      }
      return Row(
        children: [
          navigation(constraints.maxWidth < 1050),
          const VerticalDivider(width: 1),
          Expanded(child: _content()),
        ],
      );
    },
  );

  Widget navigation(bool compact) => NavigationRail(
    scrollable: true,
    selectedIndex: page,
    onDestinationSelected: (value) => setState(() {
      page = value;
      query = '';
    }),
    extended: !compact,
    labelType: compact ? NavigationRailLabelType.all : null,
    destinations: List.generate(
      _pages.length,
      (index) => NavigationRailDestination(
        icon: Icon(
          managerOnly
              ? const [
                  Icons.space_dashboard_outlined,
                  Icons.groups_outlined,
                  Icons.table_restaurant,
                  Icons.report_problem_outlined,
                  Icons.bar_chart,
                  Icons.history,
                ][index]
              : const [
                  Icons.space_dashboard_outlined,
                  Icons.restaurant_menu,
                  Icons.inventory_2_outlined,
                  Icons.groups_outlined,
                  Icons.table_restaurant,
                  Icons.bar_chart,
                  Icons.report_problem_outlined,
                  Icons.history,
                ][index],
        ),
        selectedIcon: Icon(
          managerOnly
              ? const [
                  Icons.space_dashboard_outlined,
                  Icons.groups_outlined,
                  Icons.table_restaurant,
                  Icons.report_problem_outlined,
                  Icons.bar_chart,
                  Icons.history,
                ][index]
              : const [
                  Icons.space_dashboard_outlined,
                  Icons.restaurant_menu,
                  Icons.inventory_2_outlined,
                  Icons.groups_outlined,
                  Icons.table_restaurant,
                  Icons.bar_chart,
                  Icons.report_problem_outlined,
                  Icons.history,
                ][index],
          color: luxuryGold,
        ),
        label: Text(
          (managerOnly
              ? const [
                  'Resumen',
                  'Usuarios',
                  'Mesas',
                  'Incidencias',
                  'Reportes',
                  'Auditoría',
                ]
              : const [
                  'Resumen',
                  'Menú y catálogo',
                  'Inventario',
                  'Usuarios y roles',
                  'Mesas',
                  'Reportes',
                  'Incidencias',
                  'Auditoría',
                ])[index],
        ),
      ),
    ),
  );
}
