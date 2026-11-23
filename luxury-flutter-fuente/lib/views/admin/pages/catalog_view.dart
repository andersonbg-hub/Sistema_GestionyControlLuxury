part of '../dashboard_screen.dart';

extension _AdminCatalogView on _AdminScreenState {
  Widget _menuPage() {
    final categories = ['Todas', ...store.categories];
    final items = store.menu.where((item) {
      final matchesText =
          query.isEmpty ||
          '${item.name} ${item.description}'.toLowerCase().contains(query);
      return matchesText && (category == 'Todas' || item.category == category);
    }).toList();
    final filters = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
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
        const SizedBox(height: 8),
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
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = math.max(
          constraints.maxWidth < 600 ? 16.0 : 24.0,
          (constraints.maxWidth - 1320) / 2,
        );
        return Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: padding),
              child: const SectionTitle(
                title: 'Menú y catálogo',
                subtitle: 'Categorías, disponibilidad y precios',
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.fromLTRB(padding, 22, padding, 32),
                itemCount: items.isEmpty ? 2 : items.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) return filters;
                  if (items.isEmpty) {
                    return const EmptyState(
                      message:
                          'No hay platillos que coincidan con la búsqueda.',
                    );
                  }
                  return _catalogItem(items[index - 1]);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _catalogItem(MenuItem item) {
    return Card(
      child: ResponsiveListTile(
        leading: CatalogThumbnail(url: item.imageUrl, icon: Icons.restaurant),
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
    );
  }
}
