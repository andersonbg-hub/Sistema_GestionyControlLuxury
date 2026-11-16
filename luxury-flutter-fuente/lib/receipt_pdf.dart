import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'models.dart';

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
          pw.Text(order.createdAt.toLocal().toString()),
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
}) async {
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
              'NOTA DE VENTA INTERNA\n$code',
              textAlign: pw.TextAlign.center,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text('${order.locationLabel} · Pedido #${order.id}'),
          pw.Text(order.createdAt.toLocal().toString()),
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
          pw.SizedBox(height: 8),
          ...order.payments.map(
            (payment) => pw.Column(
              children: [
                pw.Row(
                  children: [
                    pw.Expanded(child: pw.Text(payment.method)),
                    pw.Text('S/ ${payment.amount.toStringAsFixed(2)}'),
                  ],
                ),
                if (payment.cashReceived != null) ...[
                  pw.Row(
                    children: [
                      pw.Expanded(child: pw.Text('Efectivo recibido')),
                      pw.Text('S/ ${payment.cashReceived!.toStringAsFixed(2)}'),
                    ],
                  ),
                  pw.Row(
                    children: [
                      pw.Expanded(child: pw.Text('Vuelto')),
                      pw.Text('S/ ${payment.change.toStringAsFixed(2)}'),
                    ],
                  ),
                ],
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Center(
            child: pw.Text(
              status == 'ANULADO'
                  ? 'ANULADA · EXTORNO REGISTRADO'
                  : 'PAGADO · Gracias por su visita',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.Text(
              'Documento de control interno.\nNo es un comprobante electrónico SUNAT.',
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 8),
            ),
          ),
        ],
      ),
    ),
  );
  await Printing.layoutPdf(
    name: '$code.pdf',
    onLayout: (_) async => document.save(),
  );
}
