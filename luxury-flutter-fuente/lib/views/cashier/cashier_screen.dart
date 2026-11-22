import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_widgets.dart';
import '../../core/receipt_pdf.dart';
import '../../data/restaurant_store.dart';
import '../../models/models.dart';

part 'pages/outstanding_accounts_view.dart';
part 'pages/receipts_view.dart';
part 'pages/shift_view.dart';
part 'pages/activity_view.dart';

class CashierScreen extends StatefulWidget {
  const CashierScreen({super.key, required this.store});
  final RestaurantStore store;

  @override
  State<CashierScreen> createState() => _CashierScreenState();
}

typedef _PaymentConfirmation = ({double amount, double change, String method});

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
  String? confirmedAbono;

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
        Navigator.pop(context, (
          amount: applied / 100,
          change: isCash ? (tendered - applied) / 100 : 0.0,
          method: selectedMethod,
        ));
        return;
      }
      setState(() {
        order = updated;
        confirmedAbono =
            'Abono registrado · ${money(applied / 100)} · $selectedMethod';
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
                inputFormatters: [
                  TextInputFormatter.withFunction(
                    (oldValue, newValue) =>
                        RegExp(
                          r'^\d{0,10}(?:[.,]\d{0,2})?$',
                        ).hasMatch(newValue.text)
                        ? newValue
                        : oldValue,
                  ),
                ],
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
                  onChanged: (_) => setState(() => paymentError = null),
                  enabled: !saving,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'N.º de operación / referencia',
                  ),
                ),
              ],
              const SizedBox(height: 8),
              if (isCash)
                AnimatedSwitcher(
                  duration: luxuryDuration(context, 200),
                  child: Text(
                    'Vuelto: ${money(change / 100)}',
                    key: ValueKey(change),
                  ),
                ),
              Text('Saldo después del pago: ${money(outstanding / 100)}'),
              AnimatedSize(
                duration: luxuryDuration(context, 190),
                alignment: Alignment.topLeft,
                child: confirmedAbono == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle_outline,
                              size: 19,
                              color: luxuryPaletteGreenText,
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(confirmedAbono!)),
                          ],
                        ),
                      ),
              ),
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
                    (isCash || reference.text.trim().isNotEmpty) &&
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
  String _accountQuery = '';
  final _reviewedAccounts = <int>{};
  DateTimeRange? activityRange;
  DateTimeRange? receiptRange;
  static const _labels = [
    'Cuentas por cobrar',
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
  RestaurantStore get store => widget.store;
  void _setState(VoidCallback update) => setState(update);

  Future<void> _run(
    Future<void> Function() action, {
    String label = 'Procesando…',
  }) => runOperation(action, label: label);

  Future<void> _collect(RestaurantOrder order) async {
    if (_reviewedAccounts.add(order.id)) setState(() {});
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
    final payment = await showLuxuryDialog<_PaymentConfirmation>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _PaymentDialog(order: order, store: store),
    );
    if (!mounted) return;
    setState(() {});
    if (payment != null) {
      await showResultDialog(
        context,
        success: true,
        title: 'Cuenta pagada',
        message:
            '${money(payment.amount)} · ${payment.method}'
            '${payment.change > 0 ? '\nVuelto: ${money(payment.change)}' : ''}',
      );
    }
  }

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
                    label: 'Cuentas por cobrar',
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
                showBrand: true,
                onDestinationSelected: (value) => setState(() => page = value),
              ),
            ],
            Expanded(
              child: PinnedHeaderHost(
                section: page,
                child: SectionTransition(section: page, child: body),
              ),
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
