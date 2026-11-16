import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_widgets.dart';
import 'models.dart';
import 'receipt_pdf.dart';
import 'staff_profile_dialog.dart';
import 'store.dart';

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
  String category = 'Todas';
  String reportRange = 'Hoy';
  String reportMethod = 'Todos';
  String reportWaiterId = '';
  int? _focusedRequestId;
  bool _attendingAlert = false;
  String? _cashierId;
  Future<CashierShift>? _cashierShift;
  bool _changingCashierShift = false;

  RestaurantStore get store => widget.store;
  bool get managerOnly => widget.managerOnly;
  List<int> get _pages => widget.managerOnly
      ? const [0, 3, 4, 6, 5, 7]
      : const [0, 1, 2, 3, 4, 5, 6, 8];
  int get _activePage => _pages[page];

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
    return showDialog<(double, String)>(
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
    const groups = [
      'ABCDEFGHJKLMNPQRSTUVWXYZ',
      'abcdefghijkmnopqrstuvwxyz',
      '23456789',
      '!@#%',
    ];
    final random = math.Random.secure();
    String pick(String characters) =>
        characters[random.nextInt(characters.length)];
    final password = [
      ...groups.map(pick),
      ...List.generate(10, (_) => pick(groups.join())),
    ]..shuffle(random);
    return password.join();
  }

  Future<void> _editStaff([StaffMember? member]) async {
    final form = GlobalKey<FormState>();
    final validEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    var name = member?.name ?? '';
    var email = member?.email ?? '';
    var password = member == null ? _temporaryPassword() : '';
    var documentId = member?.documentId ?? '';
    var personalEmail = member?.personalEmail ?? '';
    var phone = member?.phone ?? '';
    var address = member?.address ?? '';
    var department = member?.department ?? '';
    var role = member?.role ?? StaffRole.waiter;
    var employmentStatus = member?.employmentStatus ?? 'ACTIVO';
    var saving = false;
    String? failure;

    final emailSent = await showDialog<bool>(
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
              final delivered = await showBlockingProgress<bool?>(
                dialogContext,
                label: member == null
                    ? 'Creando cuenta…'
                    : 'Guardando usuario…',
                action: () async {
                  if (member == null) {
                    return store.addStaffMember(
                      name: name.trim(),
                      email: email.trim(),
                      role: role,
                      password: password.trim(),
                      documentId: documentId,
                      personalEmail: personalEmail,
                      phone: phone,
                      address: address,
                      department: department,
                      employmentStatus: employmentStatus,
                    );
                  }
                  await store.updateStaffMember(
                    member: member,
                    name: name,
                    email: email,
                    role: role,
                    documentId: documentId,
                    personalEmail: personalEmail,
                    phone: phone,
                    address: address,
                    department: department,
                    employmentStatus: employmentStatus,
                  );
                  return null;
                },
              );
              if (mounted) setState(() {});
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext, delivered);
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
                        if (member == null) ...[
                          TextFormField(
                            initialValue: password,
                            onChanged: (value) => password = value,
                            validator: (value) =>
                                (value ?? '').trim().length < 8
                                ? 'Usa al menos 8 caracteres.'
                                : null,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Contraseña temporal',
                              helperText: 'Deberá cambiarse al iniciar sesión.',
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        DropdownButtonFormField<StaffRole>(
                          initialValue: role,
                          decoration: const InputDecoration(
                            labelText: 'Puesto',
                          ),
                          items: [
                            for (final value in StaffRole.values)
                              DropdownMenuItem(
                                value: value,
                                child: Text(value.label),
                              ),
                          ],
                          onChanged: (value) => role = value ?? role,
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
                              value: 'VACACIONES',
                              child: Text('De vacaciones'),
                            ),
                            DropdownMenuItem(
                              value: 'LICENCIA',
                              child: Text('Con licencia'),
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
                          initialValue: department,
                          onChanged: (value) => department = value,
                          decoration: const InputDecoration(
                            labelText: 'Departamento o área (opcional)',
                            hintText: 'Ej. Primer piso, caja, cocina',
                          ),
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
                          initialValue: personalEmail,
                          onChanged: (value) => personalEmail = value,
                          validator: (value) {
                            final address = (value ?? '').trim();
                            return address.isEmpty ||
                                    validEmail.hasMatch(address)
                                ? null
                                : 'Ingresa un correo personal válido.';
                          },
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Correo personal',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          initialValue: phone,
                          onChanged: (value) => phone = value,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Teléfono móvil',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          initialValue: address,
                          onChanged: (value) => address = value,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Dirección residencial',
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

    if (emailSent == null || !mounted) return;
    if (store.isDemo || emailSent) {
      await showResultDialog(
        context,
        success: true,
        title: 'Cuenta creada',
        message: store.isDemo
            ? 'El usuario se agregó a la demostración.'
            : 'La contraseña temporal se envió a ${email.trim()}.',
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cuenta creada'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No se confirmó el envío a ${email.trim()}. Entrega esta '
              'contraseña temporal al usuario por un canal privado.',
            ),
            const SizedBox(height: 12),
            SelectableText(password.trim()),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleStaff(StaffMember member) async {
    if (member.active) {
      final confirmed = await showDialog<bool>(
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
    final pendingAlerts = _pendingInventoryAlerts.toList();
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
              value: '${pendingAlerts.length}',
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
            final right = _dashboardAlerts(pendingAlerts);
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
                _countChip('Disponibles', available, luxuryPaletteGreen),
                _countChip('Ocupadas', occupied, luxuryPaletteGold),
                _countChip('Por cobrar', payment, luxuryPaletteRed),
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

  Widget _dashboardAlerts(
    List<(InventoryItem?, List<StockAlert>)> pendingAlerts,
  ) => Card(
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
          if (pendingAlerts.isEmpty)
            const EmptyState(
              message: 'No hay alertas pendientes.',
              icon: Icons.check_circle_outline,
            )
          else
            for (final (item, notices) in pendingAlerts)
              _inventoryAlertTile(item, notices, dense: true),
        ],
      ),
    ),
  );

  Widget _inventoryAlertTile(
    InventoryItem? item,
    List<StockAlert> notices, {
    bool dense = false,
  }) {
    final hasRequest = item != null && store.openStockRequestFor(item) != null;
    final title = item == null
        ? notices.single.message
        : item.lowStock
        ? 'Stock bajo: ${item.name}'
        : item.name;
    final details = [
      if (item != null)
        'Actual ${item.quantity} ${item.unit} · mínimo ${item.minimum}',
      if (item == null) 'Aviso de cocina · ${notices.single.priority}',
      if (item != null) ...notices.map((notice) => notice.message).toSet(),
      if (hasRequest) 'Reposición registrada',
    ];
    return ResponsiveListTile(
      dense: dense,
      contentPadding: dense ? EdgeInsets.zero : null,
      leading: Icon(
        item?.lowStock == true
            ? Icons.warning_amber
            : Icons.notifications_active_outlined,
        color: luxuryRed,
      ),
      title: Text(title),
      subtitle: Text(details.join('\n')),
      trailing: managerOnly
          ? null
          : TextButton(
              onPressed: _attendingAlert
                  ? null
                  : () => _attendInventoryAlert(item, notices),
              child: Text(
                hasRequest && notices.isEmpty ? 'Ver solicitud' : 'Atender',
              ),
            ),
    );
  }

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
          (request) => [
            request.itemName,
            request.status,
            request.note,
            ...request.items.map((line) => line.itemName),
          ].join(' ').toLowerCase().contains(query),
        )
        .toList();
    final focusedIndex = requests.indexWhere(
      (request) => request.id == _focusedRequestId,
    );
    if (focusedIndex > 0) requests.insert(0, requests.removeAt(focusedIndex));
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
            onSelectionChanged: (selection) => setState(() {
              inventoryTab = selection.first;
              _focusedRequestId = null;
              query = '';
            }),
          ),
        ),
        const SizedBox(height: 12),
        KeyedSubtree(key: ValueKey(inventoryTab), child: _searchField()),
        const SizedBox(height: 12),
        if (inventoryTab == 2) ...[
          const Text(
            'Atiende los avisos de cocina y los insumos con stock bajo.',
          ),
          const SizedBox(height: 8),
          for (final (item, notices) in _pendingInventoryAlerts)
            if ([
              item?.name,
              item?.unit,
              ...notices.expand((notice) => [notice.message, notice.priority]),
            ].join(' ').toLowerCase().contains(query))
              Card(child: _inventoryAlertTile(item, notices)),
          for (final alert in store.alerts.where(
            (alert) => alert.status != 'NUEVA',
          ))
            if ('${alert.message} ${alert.priority}'.toLowerCase().contains(
              query,
            ))
              Card(
                child: ResponsiveListTile(
                  leading: const Icon(
                    Icons.check_circle_outline,
                    color: luxuryGreen,
                  ),
                  title: Text(alert.message),
                  subtitle: Text(
                    '${alert.priority} · ${alert.createdAt.toLocal()}',
                  ),
                  trailing: const StatusBadge(
                    label: 'Revisada',
                    color: luxuryGreen,
                  ),
                ),
              ),
          if (store.alerts.isEmpty && _pendingInventoryAlerts.isEmpty)
            const EmptyState(
              message: 'No hay alertas de inventario.',
              icon: Icons.notifications_none,
            ),
        ] else if (inventoryTab == 1) ...[
          const Text(
            'Procesa las solicitudes y confirma la recepción cuando llegue el stock.',
          ),
          const SizedBox(height: 8),
          if (requests.isEmpty)
            const EmptyState(
              message: 'No hay solicitudes en esta vista.',
              icon: Icons.inventory_2_outlined,
            ),
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
                        onPressed: () => _run(
                          () => request.status == 'PENDIENTE'
                              ? store.advanceRequest(request)
                              : store.fulfillStockRequest(request),
                        ),
                        child: Text(
                          request.status == 'PENDIENTE'
                              ? 'Procesar'
                              : 'Confirmar recepción',
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cancelar solicitud',
                        onPressed: () => _cancelRestock(request),
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
          ),
        ] else
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
                      onChanged: (value) => _setInventoryActive(item, value),
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
                          : (value) => _toggleStaff(member),
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
              'Puedes crear la cuenta y entregar la contraseña temporal en privado si el correo de bienvenida no se confirma.',
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
    final waiters =
        store.staff.where((member) => member.role == StaffRole.waiter).toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    final waitersById = {for (final waiter in waiters) waiter.id: waiter};
    final waitersByName = <String, List<StaffMember>>{};
    for (final waiter in waiters) {
      waitersByName
          .putIfAbsent(waiter.name.trim().toLowerCase(), () => [])
          .add(waiter);
    }
    final selectedWaiterId = waitersById.containsKey(reportWaiterId)
        ? reportWaiterId
        : '';
    final ordersById = {for (final order in store.orders) order.id: order};

    StaffMember? waiterFor(RestaurantOrder? order) {
      if (order == null) return null;
      if (order.waiterId != null) return waitersById[order.waiterId];
      final name = order.waiterName.trim().toLowerCase();
      if (name.isEmpty || name == 'mesero' || name == 'equipo luxury') {
        return null;
      }
      final matches = waitersByName[name];
      return matches?.length == 1 ? matches!.single : null;
    }

    String waiterLabel(RestaurantOrder? order) {
      final waiter = waiterFor(order);
      if (waiter != null) return waiter.name;
      final name = order?.waiterName.trim() ?? '';
      return name.isEmpty ||
              name.toLowerCase() == 'mesero' ||
              name == 'Equipo Luxury'
          ? 'Sin mesero identificado'
          : name;
    }

    bool matchesWaiter(Map<String, dynamic> receipt) =>
        selectedWaiterId.isEmpty ||
        waiterFor(ordersById[receipt['orderId']])?.id == selectedWaiterId;

    final receiptHistory = store.receipts.where(matchesWaiter).toList();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final cutoff = switch (reportRange) {
      'Hoy' => today,
      '7 días' => today.subtract(const Duration(days: 6)),
      _ => DateTime.fromMillisecondsSinceEpoch(0),
    };
    final allValidReceipts = receiptHistory.where(
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
    String csvCell(Object? value) =>
        '"${(value ?? '').toString().replaceAll('"', '""')}"';
    final csvRows = [
      ['Nota', 'Fecha', 'Mesa', 'Mesero', 'Métodos de pago', 'Total'],
      ...receipts.map((receipt) {
        final order = ordersById[receipt['orderId']];
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
          waiterLabel(order),
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
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: DropdownButton<String>(
                key: const ValueKey('report-waiter'),
                isExpanded: true,
                value: selectedWaiterId,
                items: [
                  const DropdownMenuItem(value: '', child: Text('Todos')),
                  for (final waiter in waiters)
                    DropdownMenuItem(
                      value: waiter.id,
                      child: Text(
                        waitersByName[waiter.name.trim().toLowerCase()]!
                                    .length >
                                1
                            ? '${waiter.name} (${waiter.email})'
                            : waiter.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => reportWaiterId = value ?? ''),
              ),
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
            final order = ordersById[receipt['orderId']];
            return Card(
              child: ResponsiveListTile(
                title: Text(
                  '${receipt['code']} · ${receipt['locationLabel'] ?? 'Mesa ${receipt['tableNumber']}'}',
                ),
                subtitle: Text(
                  '${waiterLabel(order)} · ${receipt['createdAt']}',
                ),
                trailing: Text(money((receipt['total'] as num).toDouble())),
              ),
            );
          }),
        const SizedBox(height: 18),
        Text('Notas de venta', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (receiptHistory.isEmpty)
          const Text('No hay notas de venta para esta selección.')
        else
          ...receiptHistory.map(
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
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _incidentDetails(order),
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
                  trailing: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      StatusBadge(
                        label: order.incidentSolution.isEmpty
                            ? 'Pendiente'
                            : 'Solucionada',
                        color: order.incidentSolution.isEmpty
                            ? luxuryGold
                            : luxuryGreen,
                      ),
                      const SizedBox(height: 4),
                      const Text('Ver detalle'),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _incidentDetails(RestaurantOrder order) async {
    var solutionText = order.incidentSolution;
    final solution = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Incidencia · Pedido #${order.id}'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.locationLabel,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  '${order.createdAt.toLocal()} · ${order.status.label}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Reporte',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(order.incident),
                const SizedBox(height: 18),
                TextFormField(
                  key: const ValueKey('incident-solution-field'),
                  initialValue: solutionText,
                  autofocus: true,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 500,
                  onChanged: (value) => solutionText = value,
                  decoration: const InputDecoration(
                    labelText: 'Solución aplicada',
                    hintText: 'Detalla qué se hizo para resolver la incidencia',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, solutionText.trim()),
            icon: const Icon(Icons.check_circle_outline),
            label: Text(
              order.incidentSolution.isEmpty
                  ? 'Guardar solución'
                  : 'Actualizar solución',
            ),
          ),
        ],
      ),
    );
    if (solution != null) {
      await _run(() => store.resolveKitchenIncident(order, solution));
      if (mounted) setState(() {});
    }
  }

  Widget _auditPage() {
    final paymentIds = <String>{};
    final movements = [
      for (final entry in store.auditEntries)
        if (entry.movement case final movement?)
          if (entry.entity != 'pagos' ||
              movement.$1 != 'Pago registrado' ||
              entry.entityId.isEmpty ||
              paymentIds.add(entry.entityId))
            (entry, movement),
    ];
    final peopleById = {for (final member in store.staff) member.id: member};
    String timestamp(DateTime value) {
      final date = value.toLocal();
      String two(int number) => number.toString().padLeft(2, '0');
      return '${two(date.day)}/${two(date.month)}/${date.year} · '
          '${two(date.hour)}:${two(date.minute)}';
    }

    String? reference(AuditEntry entry) {
      if (entry.entityId.isEmpty) return null;
      if (entry.entity == 'usuarios') {
        final member = peopleById[entry.entityId];
        if (member == null) return null;
        final name = AuditEntry.isGenericName(member.name)
            ? member.email
            : member.name;
        return name.isEmpty ? null : 'Cuenta de $name';
      }
      if (int.tryParse(entry.entityId) == null) return null;
      final label = switch (entry.entity) {
        'pedidos' => 'Pedido',
        'pagos' => 'Pago',
        'notas_venta' => 'Nota de venta',
        'turnos_caja' || 'caja_diaria' => 'Turno',
        'solicitudes_reabastecimiento' => 'Solicitud de reposición',
        'alertas_cocina' => 'Alerta',
        'insumos' => 'Insumo',
        _ => null,
      };
      return label == null ? null : '$label #${entry.entityId}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(
          title: 'Auditoría de movimientos',
          subtitle: 'Movimientos importantes y quién los realizó',
        ),
        if (movements.isEmpty)
          const EmptyState(
            message: 'Todavía no hay movimientos importantes registrados.',
            icon: Icons.history,
          )
        else
          for (final (entry, (title, category)) in movements)
            Card(
              child: ResponsiveListTile(
                leading: Icon(switch (category) {
                  'Caja' => Icons.point_of_sale_outlined,
                  'Cocina' => Icons.restaurant_outlined,
                  'Inventario' => Icons.inventory_2_outlined,
                  'Usuarios' => Icons.manage_accounts_outlined,
                  _ => Icons.receipt_long_outlined,
                }),
                title: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  [
                    ?reference(entry),
                    'Realizado por ${entry.actorLabel}${entry.actorRoleLabel.isEmpty || entry.actorRoleLabel == entry.actorLabel ? '' : ' · ${entry.actorRoleLabel}'}',
                    timestamp(entry.createdAt),
                  ].join('\n'),
                ),
                trailing: Chip(label: Text(category)),
              ),
            ),
      ],
    );
  }

  Future<void> _consultCashierShift(String cashierId) => _run(() async {
    final shift = store.cashierShift(cashierId);
    setState(() {
      _cashierId = cashierId;
      _cashierShift = shift;
    });
    await shift;
  }, label: 'Consultando turno…');

  Widget _cashAdministration() {
    final cashiers = store.staff
        .where((member) => member.active && member.role == StaffRole.cashier)
        .toList();
    final cashier = cashiers
        .where((member) => member.id == _cashierId)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(
          title: 'Control de caja',
          subtitle: 'Apertura y cierre de turnos de los cajeros',
        ),
        if (cashiers.isEmpty)
          const EmptyState(
            message: 'No hay cajeros activos.',
            icon: Icons.point_of_sale,
          )
        else
          DropdownButtonFormField<String>(
            key: ValueKey(cashier?.id),
            initialValue: cashier?.id,
            decoration: const InputDecoration(labelText: 'Cajero'),
            isExpanded: true,
            items: [
              for (final member in cashiers)
                DropdownMenuItem(
                  value: member.id,
                  child: Text(member.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: _changingCashierShift
                ? null
                : (id) {
                    if (id != null) _consultCashierShift(id);
                  },
          ),
        if (cashier != null) ...[
          const SizedBox(height: 12),
          FutureBuilder<CashierShift>(
            future: _cashierShift,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LinearProgressIndicator();
              }
              final shift = snapshot.data;
              if (shift == null) {
                return OutlinedButton.icon(
                  onPressed: () => _consultCashierShift(cashier.id),
                  icon: const Icon(Icons.refresh),
                  label: const Text(
                    'No se pudo consultar el turno. Reintentar',
                  ),
                );
              }
              final openedAt = shift.openedAt;
              final previousOpen =
                  shift.open &&
                  (openedAt == null ||
                      !isSameLimaBusinessDay(openedAt, DateTime.now()));
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StatusBadge(
                        label: previousOpen
                            ? 'Turno anterior pendiente de cierre'
                            : shift.open
                            ? 'Turno abierto'
                            : 'Turno cerrado',
                        color: shift.open ? luxuryGreen : luxuryRed,
                      ),
                      ResponsiveListTile(
                        title: const Text('Monto de apertura'),
                        trailing: Text(money(shift.openingCash)),
                      ),
                      if (!shift.open && shift.id != null)
                        ResponsiveListTile(
                          title: const Text('Monto de cierre'),
                          trailing: Text(money(shift.closingCash)),
                        ),
                      FilledButton.icon(
                        onPressed: _changingCashierShift
                            ? null
                            : () => _changeCashierShift(cashier, shift),
                        icon: Icon(
                          shift.open ? Icons.lock_outline : Icons.lock_open,
                        ),
                        label: Text(
                          previousOpen
                              ? 'Cerrar turno anterior'
                              : shift.open
                              ? 'Cerrar caja'
                              : 'Abrir caja',
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  Future<void> _changeCashierShift(
    StaffMember cashier,
    CashierShift shift,
  ) async {
    final formKey = GlobalKey<FormState>();
    var input = '';
    double? parseAmount() {
      final value = input.trim();
      if (!RegExp(r'^\d+(?:[.,]\d{1,2})?$').hasMatch(value)) return null;
      final amount = double.tryParse(value.replaceAll(',', '.'));
      return amount == null || !amount.isFinite ? null : amount;
    }

    final counted = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(
          '${shift.open ? 'Cerrar caja' : 'Abrir caja'} · ${cashier.name}',
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            autofocus: true,
            onChanged: (value) => input = value,
            validator: (_) =>
                parseAmount() == null ? 'Ingresa un importe válido.' : null,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Efectivo contado',
              prefixText: 'S/ ',
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
                Navigator.pop(context, parseAmount());
              }
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (counted == null || !mounted) return;
    setState(() => _changingCashierShift = true);
    try {
      await _run(() async {
        await store.setShiftOpen(
          !shift.open,
          cashierId: cashier.id,
          countedCash: counted,
          shiftId: shift.id,
        );
        if (!mounted) return;
        final updatedShift = store.cashierShift(cashier.id);
        setState(() => _cashierShift = updatedShift);
        await updatedShift;
      }, label: shift.open ? 'Cerrando turno…' : 'Abriendo turno…');
    } finally {
      if (mounted) setState(() => _changingCashierShift = false);
    }
  }

  Widget _pageContent() => switch (_activePage) {
    _ when _activePage == 0 => _dashboard(),
    _ when _activePage == 1 => _menuPage(),
    _ when _activePage == 2 => _inventoryPage(),
    _ when _activePage == 3 => _staffPage(),
    _ when _activePage == 4 => _tablesPage(),
    _ when _activePage == 5 => _reportsPage(),
    _ when _activePage == 6 => _incidentsPage(),
    _ when _activePage == 8 => _cashAdministration(),
    _ => _auditPage(),
  };

  Widget _content() => Column(
    children: [
      Expanded(
        child: SingleChildScrollView(
          key: ValueKey(_activePage == 2 ? (page, inventoryTab) : page),
          padding: EdgeInsets.fromLTRB(
            MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
            22,
            MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
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
              'Control de caja',
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
            LuxuryMenuEntry(label: 'Usuarios', icon: Icons.groups_outlined),
            LuxuryMenuEntry(label: 'Mesas', icon: Icons.table_restaurant),
            LuxuryMenuEntry(
              label: 'Incidencias',
              icon: Icons.report_problem_outlined,
            ),
            LuxuryMenuEntry(label: 'Reportes', icon: Icons.bar_chart),
            LuxuryMenuEntry(label: 'Auditoría', icon: Icons.history),
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
      userName: store.displayName,
      userRole:
          store.role?.label ?? (managerOnly ? 'Gerente' : 'Administrador'),
      onProfileTap: () => showOwnStaffProfile(context, store),
      onDestinationSelected: (value) => setState(() {
        page = value;
        query = '';
      }),
    );
  }
}
