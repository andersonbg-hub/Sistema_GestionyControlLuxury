import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import '../../core/app_widgets.dart';
import '../../data/restaurant_store.dart';
import '../../models/models.dart';

part 'pages/orders_view.dart';
part 'pages/inventory_view.dart';
part 'pages/order_board_view.dart';
part 'pages/history_view.dart';

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
  Timer? _clock;
  final ValueNotifier<DateTime> clock = ValueNotifier(DateTime.now());

  @override
  void initState() {
    super.initState();
    _navigate(0);
  }

  void _navigate(int page) {
    _clock?.cancel();
    if (page == 0) {
      clock.value = DateTime.now();
      _clock = Timer.periodic(const Duration(minutes: 1), (_) {
        clock.value = DateTime.now();
      });
    }
    setState(() => this.page = page);
  }

  DateTimeRange? historyRange;
  final _search = TextEditingController();
  String query = '';
  bool notesOnly = false;
  OrderStatus? stageFilter;
  RestaurantStore get store => widget.store;
  static const _labels = ['Comandas', 'Insumos y carta', 'Historial'];
  static const _icons = [
    Icons.soup_kitchen_outlined,
    Icons.inventory_2_outlined,
    Icons.history,
  ];
  void _setState(VoidCallback update) => setState(update);

  @override
  void dispose() {
    _clock?.cancel();
    clock.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<bool> _run(
    Future<void> Function() action, {
    String label = 'Procesando…',
  }) => runOperation(action, label: label);

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
                showBrand: true,
                onDestinationSelected: _navigate,
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
                onDestinationSelected: _navigate,
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
