part of '../restaurant_store.dart';

const maxMenuItemPrice = 999999.99;

extension RestaurantStoreCatalog on RestaurantStore {
  Future<void> setMenuAvailability(MenuItem item, bool available) async {
    if (_client != null) {
      await _client.rpc(
        'alternar_plato_agotado',
        params: {'p_platillo': item.id, 'p_agotado': !available},
      );
      await _loadRemoteData();
    } else {
      _replaceMenu(item.copyWith(available: available));
      await _persist();
    }
    _recordLocalAudit(
      available ? 'Habilitar platillo' : 'Marcar platillo agotado',
      'platillos',
      item.id.toString(),
    );
    _publish();
  }

  Future<void> saveMenuItem({
    int? id,
    required String name,
    required String category,
    required double price,
    required String description,
    String? imageUrl,
  }) async {
    if (name.trim().isEmpty || price < 0 || price > maxMenuItemPrice) {
      if (price > maxMenuItemPrice) {
        throw StateError('El precio máximo permitido es S/ 999,999.99.');
      }
      throw StateError('Indica un nombre y un precio válido.');
    }
    final previous = menu.where((item) => item.id == id).firstOrNull;
    final image = imageUrl?.trim() == (previous?.imageUrl.trim() ?? '')
        ? null
        : _catalogImageUrl(imageUrl);
    if (_client != null) {
      final categoryRows = await _client
          .from('categorias')
          .select('id')
          .eq('nombre', category)
          .limit(1);
      if (categoryRows.isEmpty) {
        final inserted = await _client
            .from('categorias')
            .insert({'nombre': category})
            .select('id')
            .single();
        final categoryId = inserted['id'] as int;
        await _writeMenuItem(
          id: id,
          categoryId: categoryId,
          name: name,
          price: price,
          description: description,
          imageUrl: image,
        );
      } else {
        await _writeMenuItem(
          id: id,
          categoryId: categoryRows.first['id'] as int,
          name: name,
          price: price,
          description: description,
          imageUrl: image,
        );
      }
      await _loadRemoteData();
    } else {
      if (id == null) {
        final newId = _nextId++;
        menu.add(
          MenuItem(
            id: newId,
            name: name.trim(),
            category: category,
            price: price,
            description: description.trim(),
            imageUrl: image ?? '',
          ),
        );
      } else {
        final old = menu.firstWhere((item) => item.id == id);
        _replaceMenu(
          old.copyWith(
            name: name.trim(),
            category: category,
            price: price,
            description: description.trim(),
            imageUrl: image,
          ),
        );
      }
      if (!categories.contains(category)) categories.add(category);
      await _persist();
    }
    _recordLocalAudit(
      id == null ? 'Crear platillo' : 'Editar platillo',
      'platillos',
      id?.toString() ?? menu.last.id.toString(),
    );
    _publish();
  }

  Future<void> saveCategory({
    String? previousName,
    required String name,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw StateError('El nombre de la categoría es obligatorio.');
    }
    if (_client != null) {
      final existing = await _client
          .from('categorias')
          .select('id')
          .eq('nombre', trimmed)
          .limit(1);
      if (existing.isNotEmpty &&
          (previousName == null ||
              existing.first['id'] !=
                  (await _client
                      .from('categorias')
                      .select('id')
                      .eq('nombre', previousName)
                      .single())['id'])) {
        throw StateError('Ya existe una categoría con ese nombre.');
      }
      if (previousName == null) {
        await _client.from('categorias').insert({'nombre': trimmed});
      } else {
        await _client
            .from('categorias')
            .update({'nombre': trimmed})
            .eq('nombre', previousName);
      }
      await _loadRemoteData();
    } else {
      if (categories.any(
        (value) =>
            value.toLowerCase() == trimmed.toLowerCase() &&
            value != previousName,
      )) {
        throw StateError('Ya existe una categoría con ese nombre.');
      }
      if (previousName == null) {
        categories.add(trimmed);
      } else {
        final index = categories.indexOf(previousName);
        categories[index] = trimmed;
        for (var i = 0; i < menu.length; i++) {
          if (menu[i].category == previousName) {
            menu[i] = menu[i].copyWith(category: trimmed);
          }
        }
      }
      await _persist();
    }
    _recordLocalAudit(
      previousName == null ? 'Crear categoría' : 'Editar categoría',
      'categorias',
      trimmed,
    );
    _publish();
  }

  Future<void> removeCategory(String name) async {
    if (menu.any((item) => item.category == name)) {
      throw StateError(
        'No se puede eliminar la categoría porque todavía contiene platillos.',
      );
    }
    if (_client != null) {
      final category = await _client
          .from('categorias')
          .select('id')
          .eq('nombre', name)
          .single();
      await _client.from('categorias').delete().eq('id', category['id']);
      await _loadRemoteData();
    } else {
      categories.remove(name);
      await _persist();
    }
    _recordLocalAudit('Eliminar categoría', 'categorias', name);
    _publish();
  }

  Future<void> _writeMenuItem({
    int? id,
    required int categoryId,
    required String name,
    required double price,
    required String description,
    String? imageUrl,
  }) async {
    final values = {
      'categoria_id': categoryId,
      'nombre': name.trim(),
      'precio': price,
      'descripcion': description.trim(),
      if (imageUrl != null) 'foto_url': imageUrl.isEmpty ? null : imageUrl,
    };
    if (id == null) {
      await _client!.from('platillos').insert(values);
    } else {
      await _client!.from('platillos').update(values).eq('id', id);
    }
  }

  Future<void> saveTable({
    int? id,
    required int number,
    required int capacity,
  }) async {
    final previous = _tableById(id);
    if (number < 1 ||
        capacity < 1 ||
        (capacity > 8 && capacity != previous?.capacity)) {
      throw StateError(
        'Usa un número de mesa positivo y una capacidad de 1 a 8 asientos.',
      );
    }
    if (id != null && previous == null) {
      throw StateError('La mesa ya no está disponible para editar.');
    }
    if (tables.any((table) => table.id != id && table.number == number)) {
      throw StateError('La mesa $number ya está creada.');
    }
    if (previous != null &&
        (previous.groupOrderId != null ||
            previous.status != TableStatus.available ||
            _hasOpenOrderAtTable(previous.id))) {
      throw StateError('Libera la mesa antes de editar su número o capacidad.');
    }
    if (_client != null) {
      final values = {'numero': number, 'capacidad': capacity};
      try {
        if (id == null) {
          await _client.from('mesas').insert(values);
        } else {
          final updated = await _client
              .from('mesas')
              .update(values)
              .eq('id', id)
              .eq('estado', 'DISPONIBLE')
              .select('id')
              .maybeSingle();
          if (updated == null) {
            throw StateError(
              'La mesa cambió de estado. Actualiza las mesas antes de editar.',
            );
          }
        }
      } on PostgrestException catch (error) {
        if (error.code == '23505') {
          throw StateError('La mesa $number ya está creada.');
        }
        rethrow;
      }
      await _loadRemoteData();
    } else {
      if (id == null) {
        tables.add(
          RestaurantTable(id: _nextId++, number: number, capacity: capacity),
        );
      } else {
        final index = tables.indexWhere((table) => table.id == id);
        tables[index] = tables[index].copyWith(
          number: number,
          capacity: capacity,
        );
      }
      await _persist();
    }
    _recordLocalAudit(
      id == null ? 'Crear mesa' : 'Editar mesa',
      'mesas',
      number.toString(),
    );
    _publish();
  }

  Future<void> removeTable(RestaurantTable table) async {
    if (_tableById(table.id)?.groupOrderId != null) {
      throw StateError('Libera las mesas unidas antes de eliminar esta mesa.');
    }
    final hasOpenOrder = orders.any(
      (order) =>
          order.tableId == table.id &&
          order.status != OrderStatus.paid &&
          order.status != OrderStatus.cancelled &&
          order.status != OrderStatus.delivered,
    );
    if (table.status != TableStatus.available || hasOpenOrder) {
      throw StateError(
        'La mesa ${table.number} tiene un pedido abierto y no se puede eliminar.',
      );
    }
    if (_client != null) {
      await _client.from('mesas').delete().eq('id', table.id);
      await _loadRemoteData();
    } else {
      tables.removeWhere((item) => item.id == table.id);
      await _persist();
    }
    _recordLocalAudit('Eliminar mesa', 'mesas', table.number.toString());
    _publish();
  }
}
