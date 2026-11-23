import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/models.dart';
import 'app_widgets.dart' show limaDateTime;

Future<void> printPreAccountPdf({required RestaurantOrder order}) async {
  final document = pw.Document();
  document.addPage(
    pw.Page(
      pageFormat: PdfPageFormat(
        80 * PdfPageFormat.mm,
        260 * PdfPageFormat.mm,
        marginAll: 5 * PdfPageFormat.mm,
      ),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Center(
            child: pw.Column(
              children: [
                pw.Text(
                  'LUXURY',
                  style: pw.TextStyle(
                    fontSize: 19,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text('Restaurante Oriental · Chincha'),
              ],
            ),
          ),
          pw.SizedBox(height: 14),
          pw.Center(
            child: pw.Text(
              'PRECUENTA · NO ES COMPROBANTE DE PAGO',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text('${order.locationLabel} · Pedido #${order.id}'),
          pw.Text(limaDateTime(order.createdAt)),
          if (order.customerName.isNotEmpty)
            pw.Text('Cliente: ${order.customerName} · ${order.customerPhone}'),
          if (order.deliveryAddress.isNotEmpty)
            pw.Text('Dirección: ${order.deliveryAddress}'),
          pw.Divider(),
          ...order.lines.map(
            (line) => pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Text('${line.quantity} × ${line.name}'),
                  ),
                  pw.Text('S/ ${line.subtotal.toStringAsFixed(2)}'),
                ],
              ),
            ),
          ),
          pw.Divider(),
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  'TOTAL',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.Text(
                'S/ ${order.total.toStringAsFixed(2)}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
          if (order.paid > 0) ...[
            pw.SizedBox(height: 4),
            pw.Row(
              children: [
                pw.Expanded(child: pw.Text('Abonado')),
                pw.Text('S/ ${order.paid.toStringAsFixed(2)}'),
              ],
            ),
            pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    'Saldo pendiente',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.Text(
                  'S/ ${order.balance.toStringAsFixed(2)}',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
              ],
            ),
          ],
          pw.SizedBox(height: 12),
          pw.Center(
            child: pw.Text(
              'Documento informativo. El pago se registra por separado.',
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 8),
            ),
          ),
        ],
      ),
    ),
  );
  await Printing.layoutPdf(
    name: 'precuenta-pedido-${order.id}.pdf',
    onLayout: (_) async => document.save(),
  );
}

Future<void> printReceiptPdf({
  required RestaurantOrder order,
  required String code,
  String status = 'VIGENTE',
  DateTime? issuedAt,
}) async {
  final bytes = await buildReceiptPdf(
    order: order,
    code: code,
    status: status,
    issuedAt: issuedAt,
  );
  await Printing.layoutPdf(
    name: '$code.pdf',
    format: PdfPageFormat.roll80,
    onLayout: (_) async => bytes,
  );
}

Future<Uint8List> buildReceiptPdf({
  required RestaurantOrder order,
  required String code,
  String status = 'VIGENTE',
  DateTime? issuedAt,
}) {
  final products = <(int, String, double), int>{};
  for (final line in order.lines) {
    final key = (line.menuItemId, line.name, line.unitPrice);
    products.update(
      key,
      (quantity) => quantity + line.quantity,
      ifAbsent: () => line.quantity,
    );
  }

  final payments = <String, double>{};
  var hasCash = false;
  var tendered = 0.0;
  var change = 0.0;
  for (final payment in order.payments) {
    payments.update(
      payment.method,
      (amount) => amount + payment.amount,
      ifAbsent: () => payment.amount,
    );
    final received = payment.cashReceived;
    if (received != null) {
      hasCash = true;
      tendered += received;
      change += payment.change;
    }
  }

  const ink = PdfColors.grey900;
  const muted = PdfColors.grey700;
  const rule = PdfColors.grey400;
  const paper = PdfColors.grey100;
  final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold);
  final small = const pw.TextStyle(fontSize: 8, color: muted);
  final section = bold.copyWith(fontSize: 8, letterSpacing: .75);
  String amount(double value) => 'S/ ${value.toStringAsFixed(2)}';

  pw.Widget fields(String label, String value, {pw.TextStyle? style}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(width: 62, child: pw.Text(label, style: small)),
            pw.Expanded(child: pw.Text(value, style: style)),
          ],
        ),
      );

  pw.Widget itemRow(
    String quantity,
    String product,
    String price, {
    pw.TextStyle? style,
  }) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 3),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(width: 27, child: pw.Text(quantity, style: style)),
        pw.Expanded(child: pw.Text(product, style: style)),
        pw.SizedBox(
          width: 62,
          child: pw.Text(price, textAlign: pw.TextAlign.right, style: style),
        ),
      ],
    ),
  );

  pw.Widget amountRow(String label, double value, {pw.TextStyle? style}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          children: [
            pw.Expanded(child: pw.Text(label, style: style)),
            pw.Text(amount(value), style: style),
          ],
        ),
      );

  final document = pw.Document(title: 'Nota de venta interna $code');
  document.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.roll80,
      margin: const pw.EdgeInsets.symmetric(
        horizontal: 5 * PdfPageFormat.mm,
        vertical: 6 * PdfPageFormat.mm,
      ),
      theme:
          pw.ThemeData.withFont(
            base: pw.Font.helvetica(),
            bold: pw.Font.helveticaBold(),
          ).copyWith(
            defaultTextStyle: const pw.TextStyle(fontSize: 9.5, color: ink),
          ),
      build: (context) => pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            'LUXURY',
            textAlign: pw.TextAlign.center,
            style: bold.copyWith(fontSize: 21, letterSpacing: 2),
          ),
          pw.Text(
            'Restaurante Oriental · Chincha',
            textAlign: pw.TextAlign.center,
            style: small,
          ),
          pw.SizedBox(height: 12),
          pw.Divider(color: rule, height: 1),
          pw.SizedBox(height: 9),
          pw.Text(
            'NOTA DE VENTA INTERNA',
            style: section,
            textAlign: pw.TextAlign.center,
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            code,
            style: bold.copyWith(fontSize: 14),
            textAlign: pw.TextAlign.center,
          ),
          pw.SizedBox(height: 10),
          if (issuedAt != null) fields('Emisión', limaDateTime(issuedAt)),
          fields(
            'Pedido',
            '#${order.id} · ${order.locationLabel}',
            style: bold,
          ),
          fields('Fecha pedido', limaDateTime(order.createdAt)),
          if (order.customerName.isNotEmpty)
            fields('Cliente', order.customerName),
          if (order.customerPhone.isNotEmpty)
            fields('Teléfono', order.customerPhone),
          if (order.deliveryAddress.isNotEmpty)
            fields('Dirección', order.deliveryAddress),
          pw.SizedBox(height: 9),
          pw.Divider(color: rule, height: 1),
          itemRow('Cant.', 'Producto', 'Importe', style: section),
          pw.Divider(color: rule, height: 1),
          for (final product in products.entries)
            itemRow(
              '${product.value}',
              product.key.$2,
              amount(product.value * product.key.$3),
            ),
          pw.SizedBox(height: 7),
          pw.Container(
            color: paper,
            padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 5),
            child: amountRow(
              'TOTAL',
              order.total,
              style: bold.copyWith(fontSize: 12),
            ),
          ),
          if (payments.isNotEmpty) ...[
            pw.SizedBox(height: 11),
            pw.Text('PAGOS', style: section),
            pw.SizedBox(height: 3),
            for (final payment in payments.entries)
              amountRow(payment.key, payment.value),
            if (hasCash &&
                (tendered - (payments['Efectivo'] ?? 0)).abs() > .001) ...[
              amountRow('Efectivo recibido', tendered),
              amountRow('Vuelto', change),
            ],
          ],
          pw.SizedBox(height: 10),
          pw.Divider(color: rule, height: 1),
          pw.SizedBox(height: 8),
          pw.Text(
            status == 'ANULADO'
                ? 'ANULADA · EXTORNO REGISTRADO'
                : 'PAGADO · Gracias por su visita',
            textAlign: pw.TextAlign.center,
            style: bold,
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Documento de control interno.\nNo es un comprobante electrónico SUNAT.',
            textAlign: pw.TextAlign.center,
            style: small,
          ),
        ],
      ),
    ),
  );
  return document.save();
}
