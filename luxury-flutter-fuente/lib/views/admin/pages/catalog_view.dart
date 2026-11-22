part of '../dashboard_screen.dart';

extension _AdminCatalogView on _AdminScreenState {
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
                    _setState(() => category = 'Todas');
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
                  onSelected: (_) => _setState(() => category = value),
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
                leading: CatalogThumbnail(
                  url: item.imageUrl,
                  icon: Icons.restaurant,
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
}
