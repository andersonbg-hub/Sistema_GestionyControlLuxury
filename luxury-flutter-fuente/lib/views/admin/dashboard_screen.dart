import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/app_widgets.dart';
import '../../core/receipt_pdf.dart';
import '../../data/restaurant_store.dart';
import '../../models/models.dart';

part 'pages/dashboard_view.dart';
part 'pages/catalog_view.dart';
part 'pages/inventory_view.dart';
part 'pages/staff_view.dart';
part 'pages/tables_view.dart';
part 'pages/reports_view.dart';
part 'pages/incidents_view.dart';
part 'pages/audit_view.dart';
part 'pages/cash_management_view.dart';
part 'pages/manager_floor_view.dart';
part 'pages/manager_cash_view.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key, required this.store, this.managerOnly = false});
  final RestaurantStore store;
  final bool managerOnly;

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with OperationProgress<AdminScreen> {
  int page = 0;
  int inventoryTab = 0;
  String query = '';
  String auditQuery = '';
  String category = 'Todas';
  String reportRange = 'Hoy';
  String reportMethod = 'Todos';
  String reportWaiterId = '';
  int? _focusedRequestId;
  bool _attendingAlert = false;
  String? _cashierId;
  Future<CashierShift>? _cashierShift;
  bool _changingCashierShift = false;
  int _managerFloorTab = 0;
  int? _managerSelectedTable;
  String _managerTableQuery = '';

  RestaurantStore get store => widget.store;
  bool get managerOnly => widget.managerOnly;
  List<int> get _pages => widget.managerOnly
      ? const [0, 9, 10, 6, 5, 7]
      : const [0, 1, 2, 3, 4, 5, 6, 8];
  int get _activePage => _pages[page];
  void _setState(VoidCallback update) => setState(update);

  @override
  void initState() {
    super.initState();
    if (!widget.managerOnly) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cashier = store.staff
          .where((member) => member.active && member.role == StaffRole.cashier)
          .firstOrNull;
      if (cashier != null) _selectManagerCashier(cashier.id);
    });
  }

  Iterable<(InventoryItem?, List<StockAlert>)>
  get _pendingInventoryAlerts sync* {
    final byItem = <int, List<StockAlert>>{};
    for (final alert in store.alerts.where(
      (alert) => alert.status == 'NUEVA',
    )) {
      final item = store.inventory
          .where((item) => item.active && item.id == alert.inventoryId)
          .firstOrNull;
      if (item == null) {
        yield (null, [alert]);
      } else {
        byItem.putIfAbsent(item.id, () => []).add(alert);
      }
    }
    for (final item in store.inventory.where((item) => item.active)) {
      final notices = byItem[item.id] ?? const <StockAlert>[];
      if (item.lowStock || notices.isNotEmpty) yield (item, notices);
    }
  }

  Future<void> _attendInventoryAlert(
    InventoryItem? item,
    List<StockAlert> notices,
  ) async {
    if (managerOnly || _attendingAlert) return;
    setState(() => _attendingAlert = true);
    try {
      var request = item == null ? null : store.openStockRequestFor(item);
      final details = item != null && request == null
          ? await _restockDetails(item, notices)
          : null;
      if (!mounted || (item != null && request == null && details == null)) {
        return;
      }

      await _run(() async {
        if (item == null) {
          await store.reviewKitchenAlert(notices.single);
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Aviso revisado')));
          }
          return;
        }

        if (details != null) {
          // Check again after the dialog, since another user may have requested it.
          await store.refresh();
          final currentItem = store.inventory
              .where((entry) => entry.id == item.id && entry.active)
              .firstOrNull;
          if (currentItem == null) {
            throw StateError('El insumo ya no está activo.');
          }
          request = store.openStockRequestFor(currentItem);
          if (request == null) {
            await store.createStockRequest(currentItem, details.$1, details.$2);
            request = store.openStockRequestFor(currentItem);
            if (request == null) {
              throw StateError(
                'No se pudo confirmar el registro de la solicitud.',
              );
            }
          }
        }
        for (final notice in notices) {
          await store.reviewKitchenAlert(notice);
        }
        if (!mounted) return;
        setState(() {
          page = _pages.indexOf(2);
          inventoryTab = 1;
          _focusedRequestId = request!.id;
          query = '';
        });
      });
    } finally {
      if (mounted) setState(() => _attendingAlert = false);
    }
  }

  Future<(double, String)?> _restockDetails(
    InventoryItem item,
    List<StockAlert> notices,
  ) {
    final formKey = GlobalKey<FormState>();
    var quantity = math.max(1, item.minimum * 2 - item.quantity).toString();
    var note = notices.isEmpty
        ? 'Reposición por stock bajo'
        : notices.map((notice) => notice.message).toSet().join(' · ');
    double? parseQuantity() =>
        double.tryParse(quantity.trim().replaceAll(',', '.'));
    return showLuxuryDialog<(double, String)>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text('Atender reposición de ${item.name}'),
        content: SizedBox(
          width: 380,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Stock actual: ${item.quantity} ${item.unit} · mínimo ${item.minimum} ${item.unit}',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('stock-request-quantity'),
                  initialValue: quantity,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (value) => quantity = value,
                  validator: (_) {
                    final value = parseQuantity();
                    return value == null || !value.isFinite || value <= 0
                        ? 'Ingresa una cantidad mayor a cero.'
                        : null;
                  },
                  decoration: InputDecoration(
                    labelText: 'Cantidad (${item.unit})',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: note,
                  onChanged: (value) => note = value,
                  decoration: const InputDecoration(labelText: 'Observación'),
                ),
                const SizedBox(height: 12),
                const Text(
                  'El stock se actualizará al confirmar la recepción.',
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
                Navigator.pop(context, (parseQuantity()!, note));
              }
            },
            child: const Text('Registrar reposición'),
          ),
        ],
      ),
    );
  }

  Future<void> _run(
    Future<void> Function() action, {
    String label = 'Procesando…',
  }) => runOperation(action, label: label);

  Future<void> _cancelRestock(StockRequest request) async {
    final confirmed = await confirmAction(
      context,
      title: '¿Cancelar la solicitud?',
      message: 'Se cancelará la reposición de ${request.itemName}.',
      actionLabel: 'Cancelar solicitud',
    );
    if (!confirmed || !mounted) return;
    await _run(
      () => store.cancelRequest(request),
      label: 'Cancelando solicitud…',
    );
  }

  Future<void> _setInventoryActive(InventoryItem item, bool active) async {
    if (!active) {
      final confirmed = await confirmAction(
        context,
        title: '¿Archivar ${item.name}?',
        message: 'El insumo dejará de estar disponible en el catálogo.',
        actionLabel: 'Archivar insumo',
      );
      if (!confirmed || !mounted) return;
    }
    await _run(
      () => store.setInventoryActive(item, active),
      label: 'Actualizando catálogo…',
    );
  }

  Future<String?> _textDialog({
    required String title,
    required String label,
    String initial = '',
    TextInputType keyboardType = TextInputType.text,
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showLuxuryDialog<String>(
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
    final imageUrl = TextEditingController(text: item?.imageUrl ?? '');
    var selectedCategory =
        item?.category ??
        (store.categories.isEmpty ? 'Chifas' : store.categories.first);
    final result =
        await showLuxuryDialog<(String, String, String, String, String)>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: Text(
                  item == null ? 'Nuevo platillo' : 'Editar platillo',
                ),
                content: SizedBox(
                  width: 440,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: name,
                          decoration: const InputDecoration(
                            labelText: 'Nombre',
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue:
                              store.categories.contains(selectedCategory)
                              ? selectedCategory
                              : null,
                          decoration: const InputDecoration(
                            labelText: 'Categoría',
                          ),
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
                            helperText: 'Máximo S/ 999,999.99',
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
                        const SizedBox(height: 12),
                        TextField(
                          controller: imageUrl,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(
                            labelText: 'URL HTTPS de la imagen (opcional)',
                            prefixIcon: Icon(Icons.link),
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
                      imageUrl.text.trim(),
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
          imageUrl: result.$5,
        );
      });
    }
    name.dispose();
    price.dispose();
    description.dispose();
    imageUrl.dispose();
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
    final imageUrl = TextEditingController(text: item?.imageUrl ?? '');
    final quantity = TextEditingController(
      text: item?.quantity.toString() ?? '0',
    );
    final minimum = TextEditingController(
      text: item?.minimum.toString() ?? '0',
    );
    var unit = item?.unit ?? 'KG';
    final result =
        await showLuxuryDialog<
          (String, String, String, String, String, String)
        >(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              scrollable: true,
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
                      decoration: const InputDecoration(
                        labelText: 'Descripción',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: unit,
                      decoration: const InputDecoration(labelText: 'Unidad'),
                      items: const ['KG', 'G', 'LITRO', 'UNIDAD']
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ),
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
                      decoration: const InputDecoration(
                        labelText: 'Stock actual',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: minimum,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Mínimo'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: imageUrl,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'URL HTTPS de la imagen (opcional)',
                        prefixIcon: Icon(Icons.link),
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
                  onPressed: () => Navigator.pop(context, (
                    name.text.trim(),
                    description.text.trim(),
                    unit,
                    quantity.text.trim(),
                    minimum.text.trim(),
                    imageUrl.text.trim(),
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
          imageUrl: result.$6,
        );
      });
    }
    name.dispose();
    description.dispose();
    imageUrl.dispose();
    quantity.dispose();
    minimum.dispose();
  }

  Future<void> _editTable([RestaurantTable? table]) async {
    final number = TextEditingController(text: table?.number.toString() ?? '');
    final capacity = TextEditingController(
      text: table?.capacity.toString() ?? '4',
    );
    final result = await showLuxuryDialog<(String, String)>(
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
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Número de mesa'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: capacity,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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

  Future<void> _editStaff([StaffMember? member]) async {
    final form = GlobalKey<FormState>();
    final validEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    var name = member?.name ?? '';
    var email = member?.email ?? '';
    var documentId = member?.documentId ?? '';
    var phone = member?.phone ?? '';
    var personalEmail = member?.personalEmail ?? '';
    var address = member?.address ?? '';
    var department = member?.department ?? '';
    var password = '';
    const availableRoles = [
      StaffRole.cashier,
      StaffRole.waiter,
      StaffRole.kitchen,
    ];
    var role = member?.role ?? StaffRole.waiter;
    final canChangeRole = availableRoles.contains(role);
    final initialStatus = member?.active == false ? 'INACTIVO' : 'ACTIVO';
    var employmentStatus = initialStatus;
    var saving = false;
    String? failure;

    final saved = await showLuxuryDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> save() async {
            if (saving || !form.currentState!.validate()) return;
            FocusScope.of(dialogContext).unfocus();
            setDialogState(() {
              saving = true;
              failure = null;
            });

            try {
              await showBlockingProgress<void>(
                dialogContext,
                label: member == null
                    ? 'Creando cuenta…'
                    : 'Guardando usuario…',
                action: () async {
                  if (member == null) {
                    await store.addStaffMember(
                      name: name.trim(),
                      email: email.trim(),
                      role: role,
                      password: password,
                      documentId: documentId,
                      personalEmail: personalEmail,
                      phone: phone,
                      address: address,
                      department: department,
                      employmentStatus: employmentStatus,
                    );
                    return;
                  }
                  await store.updateStaffMember(
                    member: member,
                    name: name,
                    email: email,
                    role: role,
                    documentId: documentId,
                    personalEmail: personalEmail == member.personalEmail
                        ? null
                        : personalEmail,
                    phone: phone == member.phone ? null : phone,
                    address: address == member.address ? null : address,
                    department: department == member.department
                        ? null
                        : department,
                    employmentStatus: employmentStatus == initialStatus
                        ? null
                        : employmentStatus,
                  );
                },
              );
              if (mounted) setState(() {});
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext, true);
              }
            } catch (error) {
              if (dialogContext.mounted) {
                setDialogState(() {
                  saving = false;
                  failure = formatErrorMessage(error);
                });
              }
            }
          }

          return PopScope(
            canPop: !saving,
            child: AlertDialog(
              scrollable: true,
              title: Text(member == null ? 'Crear usuario' : 'Editar usuario'),
              content: SizedBox(
                width: 460,
                child: AbsorbPointer(
                  absorbing: saving,
                  child: Form(
                    key: form,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          initialValue: name,
                          onChanged: (value) => name = value,
                          validator: (value) => (value ?? '').trim().isEmpty
                              ? 'Ingresa el nombre completo.'
                              : null,
                          decoration: const InputDecoration(
                            labelText: 'Nombre completo',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          initialValue: email,
                          onChanged: (value) => email = value,
                          validator: (value) =>
                              validEmail.hasMatch((value ?? '').trim())
                              ? null
                              : 'Ingresa un correo de acceso válido.',
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Correo de acceso',
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (member == null && store.isConnected) ...[
                          TextFormField(
                            obscureText: true,
                            autocorrect: false,
                            enableSuggestions: false,
                            onChanged: (value) => password = value,
                            validator: (value) =>
                                (value ?? '').trim().length < 8
                                ? 'Usa al menos 8 caracteres.'
                                : null,
                            decoration: const InputDecoration(
                              labelText: 'Contraseña inicial',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            obscureText: true,
                            autocorrect: false,
                            enableSuggestions: false,
                            validator: (value) => value != password
                                ? 'Las contraseñas no coinciden.'
                                : null,
                            decoration: const InputDecoration(
                              labelText: 'Confirmar contraseña',
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (canChangeRole)
                          DropdownButtonFormField<StaffRole>(
                            initialValue: role,
                            decoration: const InputDecoration(
                              labelText: 'Puesto',
                            ),
                            items: [
                              for (final value in availableRoles)
                                DropdownMenuItem(
                                  value: value,
                                  child: Text(value.label),
                                ),
                            ],
                            onChanged: (value) => role = value ?? role,
                          )
                        else
                          InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Puesto actual',
                            ),
                            child: Text(role.label),
                          ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: employmentStatus,
                          decoration: const InputDecoration(
                            labelText: 'Estado laboral',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'ACTIVO',
                              child: Text('Activo'),
                            ),
                            DropdownMenuItem(
                              value: 'INACTIVO',
                              child: Text('Inactivo'),
                            ),
                          ],
                          onChanged: (value) =>
                              employmentStatus = value ?? employmentStatus,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          initialValue: documentId,
                          onChanged: (value) => documentId = value,
                          decoration: const InputDecoration(
                            labelText: 'Documento de identidad',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          initialValue: phone,
                          onChanged: (value) => phone = value,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(9),
                          ],
                          validator: (value) =>
                              value == null ||
                                  value.isEmpty ||
                                  value == member?.phone ||
                                  RestaurantStore.isValidCustomerPhone(value)
                              ? null
                              : 'Ingresa un teléfono de 9 dígitos.',
                          decoration: const InputDecoration(
                            labelText: 'Teléfono móvil',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          initialValue: personalEmail,
                          onChanged: (value) => personalEmail = value,
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) {
                            final current = value?.trim() ?? '';
                            return current.isEmpty ||
                                    current == member?.personalEmail ||
                                    validEmail.hasMatch(current)
                                ? null
                                : 'Ingresa un correo personal válido.';
                          },
                          decoration: const InputDecoration(
                            labelText: 'Correo personal',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          initialValue: address,
                          onChanged: (value) => address = value,
                          decoration: const InputDecoration(
                            labelText: 'Dirección',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          initialValue: department,
                          onChanged: (value) => department = value,
                          decoration: const InputDecoration(
                            labelText: 'Área de trabajo',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                if (failure != null)
                  SizedBox(
                    width: double.infinity,
                    child: ErrorBanner(message: failure!),
                  ),
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  onPressed: saving ? null : save,
                  icon: saving
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          member == null
                              ? Icons.person_add_alt
                              : Icons.save_outlined,
                        ),
                  label: Text(
                    saving
                        ? 'Guardando…'
                        : member == null
                        ? 'Crear cuenta'
                        : 'Guardar cambios',
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (saved != true || !mounted) return;
    await showResultDialog(
      context,
      success: true,
      title: member == null ? 'Cuenta creada' : 'Perfil guardado',
      message: member != null
          ? 'El perfil se actualizó.'
          : store.isDemo
          ? 'El usuario se agregó a la demostración.'
          : 'La cuenta se creó con la contraseña inicial que asignaste.',
    );
  }

  Future<void> _toggleStaff(StaffMember member) async {
    if (member.active) {
      final confirmed = await showLuxuryDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('¿Desactivar usuario?'),
          content: Text('${member.name} perderá el acceso a Luxury.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Desactivar'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    await _run(() => store.toggleStaff(member));
  }

  Future<void> _resetStaffPassword(StaffMember member) async {
    final form = GlobalKey<FormState>();
    var password = '';
    final newPassword = await showLuxuryDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Cambiar contraseña'),
        content: SizedBox(
          width: 400,
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(member.name),
                const SizedBox(height: 12),
                TextFormField(
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: (value) => password = value,
                  validator: (value) => (value ?? '').trim().length < 8
                      ? 'Usa al menos 8 caracteres.'
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Nueva contraseña',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  validator: (value) => value != password
                      ? 'Las contraseñas no coinciden.'
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Confirmar contraseña',
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
              if (form.currentState!.validate()) {
                Navigator.pop(context, password);
              }
            },
            child: const Text('Guardar contraseña'),
          ),
        ],
      ),
    );
    if (newPassword == null || !mounted) return;
    final changed = await runOperation(
      () => store.resetStaffPassword(member: member, password: newPassword),
      label: 'Guardando contraseña…',
    );
    if (changed && mounted) {
      await showResultDialog(
        context,
        success: true,
        message:
            'La contraseña se actualizó. El usuario deberá cambiarla en su próximo inicio de sesión.',
      );
    }
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
        issuedAt: DateTime.tryParse(receipt['createdAt'] as String? ?? ''),
      );
      if (receipt['id'] is int) {
        await store.recordReceiptPrint(receipt['id'] as int);
      }
    });
  }

  Future<void> _voidReceipt(Map<String, dynamic> receipt) async {
    final reason = TextEditingController();
    final result = await showLuxuryDialog<String>(
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

  Widget _pageContent() => switch (_activePage) {
    _ when _activePage == 0 => _dashboard(),
    _ when _activePage == 2 => _inventoryPage(),
    _ when _activePage == 3 => _staffPage(),
    _ when _activePage == 4 => _tablesPage(),
    _ when _activePage == 5 => _reportsPage(),
    _ when _activePage == 6 => _incidentsPage(),
    _ when _activePage == 8 => _cashAdministration(),
    _ when _activePage == 9 => _managerFloorPage(),
    _ when _activePage == 10 => _managerCashPage(),
    _ => _auditPage(),
  };

  Widget _content() {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return PinnedHeaderHost(
      section: (_activePage, inventoryTab),
      horizontalPadding: compact ? 16 : 24,
      maxWidth: 1320,
      child: _activePage == 1
          ? SectionTransition(section: _activePage, child: _menuPage())
          : SingleChildScrollView(
              key: ValueKey(_activePage == 2 ? (page, inventoryTab) : page),
              padding: EdgeInsets.fromLTRB(
                compact ? 16 : 24,
                22,
                compact ? 16 : 24,
                32,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1320),
                  child: SectionTransition(
                    section: (_activePage, inventoryTab),
                    child: _pageContent(),
                  ),
                ),
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final titles = managerOnly
          ? const [
              'Resumen',
              'Salón y pedidos',
              'Caja y cierres',
              'Incidencias',
              'Reportes',
              'Historial de movimientos',
            ]
          : const [
              'Resumen',
              'Menú y catálogo',
              'Inventario',
              'Usuarios y roles',
              'Mesas',
              'Reportes',
              'Incidencias',
              'Control de caja',
            ];
      final pageIcons = managerOnly
          ? const [
              Icons.space_dashboard_outlined,
              Icons.table_restaurant,
              Icons.point_of_sale,
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
              Icons.point_of_sale,
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
          navigation(),
          Expanded(child: _content()),
        ],
      );
    },
  );

  Widget navigation() {
    final entries = managerOnly
        ? const [
            LuxuryMenuEntry(
              label: 'Resumen',
              icon: Icons.space_dashboard_outlined,
            ),
            LuxuryMenuEntry(
              label: 'Salón y pedidos',
              icon: Icons.table_restaurant,
            ),
            LuxuryMenuEntry(label: 'Caja y cierres', icon: Icons.point_of_sale),
            LuxuryMenuEntry(
              label: 'Incidencias',
              icon: Icons.report_problem_outlined,
            ),
            LuxuryMenuEntry(label: 'Reportes', icon: Icons.bar_chart),
            LuxuryMenuEntry(label: 'Historial', icon: Icons.history),
          ]
        : const [
            LuxuryMenuEntry(
              label: 'Resumen',
              icon: Icons.space_dashboard_outlined,
            ),
            LuxuryMenuEntry(
              label: 'Menú y catálogo',
              icon: Icons.restaurant_menu,
            ),
            LuxuryMenuEntry(
              label: 'Inventario',
              icon: Icons.inventory_2_outlined,
            ),
            LuxuryMenuEntry(
              label: 'Usuarios y roles',
              icon: Icons.groups_outlined,
            ),
            LuxuryMenuEntry(label: 'Mesas', icon: Icons.table_restaurant),
            LuxuryMenuEntry(label: 'Reportes', icon: Icons.bar_chart),
            LuxuryMenuEntry(
              label: 'Incidencias',
              icon: Icons.report_problem_outlined,
            ),
            LuxuryMenuEntry(
              label: 'Control de caja',
              icon: Icons.point_of_sale,
            ),
          ];
    return LuxurySideMenu(
      entries: entries,
      selectedIndex: page,
      showBrand: true,
      onDestinationSelected: (value) => setState(() {
        page = value;
        query = '';
      }),
    );
  }
}
