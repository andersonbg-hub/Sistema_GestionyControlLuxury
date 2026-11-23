part of '../dashboard_screen.dart';

extension _AdminIncidentsView on _AdminScreenState {
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
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  leading: const Icon(
                    Icons.report_problem_outlined,
                    color: luxuryRed,
                  ),
                  title: Text('Pedido #${order.id} · ${order.locationLabel}'),
                  subtitle: Text(
                    '${order.incident}\n${limaDateTime(order.createdAt)} · ${order.status.label}',
                  ),
                  isThreeLine: true,
                  trailing: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      StatusBadge(
                        label: order.incidentSolution.isEmpty
                            ? 'Pendiente'
                            : 'Solucionada',
                        color: order.incidentSolution.isEmpty
                            ? luxuryGold
                            : luxuryGreen,
                      ),
                      TextButton.icon(
                        onPressed: () => _incidentDetails(order),
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text('Ver detalle'),
                      ),
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
    final solution = await showLuxuryDialog<String>(
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
                  '${limaDateTime(order.createdAt)} · ${order.status.label}',
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
      if (mounted) _setState(() {});
    }
  }
}
