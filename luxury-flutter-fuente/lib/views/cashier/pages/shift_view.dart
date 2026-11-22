part of '../cashier_screen.dart';
extension _CashierShiftView on _CashierScreenState {
  Widget _shift(DateTime businessDay) {
    var collected = 0.0;
    var cash = 0.0;
    for (final payment in store.cashierPaymentsForDay(businessDay)) {
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
                    title: const Text('Efectivo recaudado al cierre'),
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


}
