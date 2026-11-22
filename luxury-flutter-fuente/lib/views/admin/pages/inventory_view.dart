part of '../dashboard_screen.dart';

extension _AdminInventoryView on _AdminScreenState {
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
            onSelectionChanged: (selection) => _setState(() {
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
                    '${alert.priority} · ${limaDateTime(alert.createdAt)}',
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
                        onPressed: () async {
                          if (request.status == 'PENDIENTE') {
                            await _run(() => store.advanceRequest(request));
                            return;
                          }
                          final received = await runOperation(
                            () => store.fulfillStockRequest(request),
                            label: 'Confirmando recepción…',
                          );
                          if (received && mounted) {
                            await showResultDialog(
                              context,
                              success: true,
                              message:
                                  'Recepción registrada y stock actualizado.',
                            );
                          }
                        },
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
                leading: CatalogThumbnail(
                  url: item.imageUrl,
                  icon: item.lowStock
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
}
