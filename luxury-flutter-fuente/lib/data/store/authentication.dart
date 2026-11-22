part of '../restaurant_store.dart';
extension RestaurantStoreAuthentication on RestaurantStore {
  Future<void> initialize() async {
    try {
      if (_client == null) {
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getString(RestaurantStore._storageKey);
        if (saved != null) _restore(jsonDecode(saved) as Map<String, dynamic>);
      } else {
        final user = _client.auth.currentUser;
        if (user != null) {
          try {
            await _loadProfile(user.id);
          } catch (error) {
            if (!_connectionInterrupted(error) ||
                !await _restoreRemoteCache(user.id)) {
              if (_client.auth.currentUser?.id == user.id) await signOut();
              rethrow;
            }
            errorMessage =
                'Sin conexión con Supabase. Los datos guardados se muestran en modo local.';
            if (pendingOrders.isNotEmpty) {
              errorMessage =
                  '$errorMessage Hay pedidos pendientes de sincronización.';
            }
          }
        }
      }
    } catch (_) {
      errorMessage =
          'No se pudo restaurar la sesión. Intenta iniciar sesión de nuevo.';
    } finally {
      loading = false;
      _publish();
    }
  }

  Future<void> loginDemo(StaffRole selectedRole) async {
    if (!isDemo) {
      throw StateError(
        'El acceso por roles de demostración está desactivado al conectar Supabase.',
      );
    }
    role = selectedRole;
    displayName = switch (selectedRole) {
      StaffRole.administrator => 'Administración Luxury',
      StaffRole.manager => 'Gerencia Luxury',
      StaffRole.kitchen => 'Equipo de cocina',
      StaffRole.headChef => 'Jefatura de cocina',
      StaffRole.waiter => 'Mesero de turno',
      StaffRole.cashier => 'Caja Luxury',
    };
    userId = 'demo-${selectedRole.databaseValue.toLowerCase()}';
    errorMessage = null;
    _publish();
  }

  Future<void> signIn(String email, String password) async {
    final client = _client;
    if (client == null) {
      throw StateError('No hay conexión de Supabase configurada.');
    }
    if (_signInInProgress) return;
    _signInInProgress = true;
    String? authenticatedId;
    try {
      final response = await client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      final user = response.user;
      if (user == null) {
        throw StateError('Supabase no devolvió un usuario autenticado.');
      }
      authenticatedId = user.id;
      await _loadProfile(user.id);
      errorMessage = null;
      _publish();
    } catch (_) {
      if (authenticatedId != null &&
          client.auth.currentUser?.id == authenticatedId) {
        await signOut();
      }
      rethrow;
    } finally {
      _signInInProgress = false;
    }
  }

  Future<void> _loadProfile(String id) async {
    final client = _client!;
    final version = _sessionVersion;
    final profile = await client
        .from('usuarios')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (profile == null || profile['activo'] != true) {
      throw StateError(
        'No existe un perfil activo para esta cuenta. Solicita acceso al administrador.',
      );
    }
    final profileRole = StaffRole.fromDatabase(profile['rol'] as String);
    final queued = await _readPendingOrderQueue(id);
    if (!_sameSession(version, id)) return;
    await _loadRemoteData(profileId: id, profileRole: profileRole);
    if (!_sameSession(version, id)) return;
    userId = id;
    role = profileRole;
    displayName = profile['nombre_completo'] as String;
    mustChangePassword =
        _passwordRecoveryPending ||
        _client.auth.currentUser?.appMetadata['must_change_password'] == true;
    pendingOrders
      ..clear()
      ..addAll(queued);
    _showPendingOrderQueue(queued);
    await _saveRemoteCache();
    if (_sameSession(version, id)) _subscribeRealtime();
  }

  Future<bool> _restoreRemoteCache(String id) async {
    final version = _sessionVersion;
    final prefs = await SharedPreferences.getInstance();
    if (!_sameSession(version, id)) return false;
    final saved = prefs.getString('${RestaurantStore._remoteCachePrefix}$id');
    if (saved == null) return false;
    final data = jsonDecode(saved) as Map<String, dynamic>;
    if (data['userId'] != id) return false;
    final savedRole = data['role'] as String?;
    final syncedAt = DateTime.tryParse(
      data['lastOnlineSyncAt'] as String? ?? '',
    );
    if (savedRole == null ||
        syncedAt == null ||
        DateTime.now().difference(syncedAt) > const Duration(hours: 12)) {
      return false;
    }
    _restore(data);
    userId = id;
    role = StaffRole.fromDatabase(savedRole);
    displayName = data['displayName'] as String? ?? 'Equipo Luxury';
    lastOnlineSyncAt = syncedAt;
    mustChangePassword =
        _passwordRecoveryPending ||
        _client?.auth.currentUser?.appMetadata['must_change_password'] == true;
    _showPendingOrderQueue(pendingOrders);
    _subscribeRealtime();
    return true;
  }

  Future<List<RestaurantOrder>> _readPendingOrderQueue(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('${RestaurantStore._remoteCachePrefix}$id');
    if (saved == null) return [];
    final data = jsonDecode(saved) as Map<String, dynamic>;
    if (data['userId'] != id) return [];
    return [
      for (final row in data['pendingOrders'] as List<dynamic>? ?? [])
        RestaurantOrder.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }

  Future<void> signOut() async {
    _clearConnectedState();
    _publish();
    final client = _client;
    if (client != null) {
      try {
        await client.auth.signOut();
      } on AuthException {
        // Supabase Auth clears the local session before revoking the token.
        if (client.auth.currentSession != null) rethrow;
      }
    }
  }

  bool _sameSession(int version, String? id) =>
      _sessionVersion == version &&
      (id == null || _client?.auth.currentUser?.id == id);

  bool _connectionInterrupted(Object error) =>
      error is TimeoutException ||
      error is ClientException ||
      error is AuthRetryableFetchException ||
      (error is PostgrestException &&
          const {'502', '503', '504', 'PGRST002'}.contains(error.code));

  void _clearConnectedState() {
    _sessionVersion++;
    _realtimeRefreshTimer?.cancel();
    _realtimeRefreshTimer = null;
    _orderRetryTimer?.cancel();
    _orderRetryTimer = null;
    _realtimeRefreshRunning = false;
    _realtimeRefreshPending = false;
    final channel = _realtime;
    _realtime = null;
    if (channel != null) unawaited(_client?.removeChannel(channel));
    _remoteLoad = null;
    _orderSync = null;
    _paymentsToVerify.clear();
    role = null;
    userId = null;
    mustChangePassword = false;
    _passwordRecoveryPending = false;
    displayName = 'Equipo Luxury';
    errorMessage = null;
    if (isConnected) {
      tables.clear();
      menu.clear();
      orders.clear();
      inventory.clear();
      staff.clear();
      requests.clear();
      alerts.clear();
      categories.clear();
      receipts.clear();
      auditEntries.clear();
      pendingOrders.clear();
      _remoteSupportsTableGroups = false;
      _shift = _noCashierShift;
      lastOnlineSyncAt = null;
    }
  }

  Future<void> _handleExternalSignIn(String id) async {
    _clearConnectedState();
    final version = _sessionVersion;
    _publish();
    try {
      await _loadProfile(id);
      if (!_sameSession(version, id)) return;
      errorMessage = null;
      _publish();
    } catch (_) {
      if (!_sameSession(version, id)) return;
      await signOut();
      errorMessage = 'No se pudo validar la sesión abierta en otra pestaña.';
      _publish();
    }
  }


}
