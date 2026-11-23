part of '../restaurant_store.dart';

extension RestaurantStoreStaff on RestaurantStore {
  Future<void> addStaffMember({
    required String name,
    required String email,
    required StaffRole role,
    String? password,
    String documentId = '',
    String personalEmail = '',
    String phone = '',
    String address = '',
    String department = '',
    String employmentStatus = 'ACTIVO',
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (staff.any((member) => member.email.toLowerCase() == normalizedEmail)) {
      throw StateError('Ya existe una cuenta con ese correo.');
    }
    final String id;
    if (_client != null) {
      final initialPassword = password ?? '';
      if (initialPassword.trim().length < 8 ||
          utf8.encode(initialPassword).length > 72) {
        throw StateError('Usa al menos 8 caracteres y hasta 72 bytes.');
      }
      final FunctionResponse result;
      try {
        result = await _client.functions.invoke(
          'manage-staff',
          body: {
            'action': 'create',
            'name': name.trim(),
            'email': normalizedEmail,
            'role': role.databaseValue,
            'password': initialPassword,
            'documentId': documentId.trim(),
            'personalEmail': personalEmail.trim(),
            'phone': phone.trim(),
            'address': address.trim(),
            'department': department.trim(),
            'employmentStatus': employmentStatus,
          },
        );
      } on FunctionException catch (error) {
        final details = error.details;
        final message = details is Map ? details['error'] : null;
        throw StateError(
          message is String
              ? message
              : switch (error.status) {
                  401 => 'Vuelve a iniciar sesión para crear la cuenta.',
                  403 => 'Solo un administrador activo puede crear cuentas.',
                  404 => 'Falta publicar la función de cuentas en Supabase.',
                  409 => 'Ya existe una cuenta con ese correo.',
                  _ => 'No se pudo crear la cuenta. Inténtalo de nuevo.',
                },
        );
      } on Exception {
        throw StateError(
          'No se pudo confirmar el alta. Actualiza la lista antes de volver a intentarlo.',
        );
      }
      final response = result.data;
      if (response is! Map || response['id'] is! String) {
        throw StateError('Supabase no confirmó la creación de la cuenta.');
      }
      id = response['id'] as String;
      try {
        await _loadRemoteData();
      } on Exception {
        // The function already confirmed the account. Keep it visible if refresh fails.
      }
    } else {
      id = 'local-${_nextId++}';
    }
    if (!staff.any((member) => member.id == id)) {
      staff.add(
        StaffMember(
          id: id,
          name: name.trim(),
          email: normalizedEmail,
          role: role,
          active: employmentStatus != 'INACTIVO',
          documentId: documentId.trim(),
          personalEmail: personalEmail.trim(),
          phone: phone.trim(),
          address: address.trim(),
          department: department.trim(),
          employmentStatus: employmentStatus,
        ),
      );
    }
    if (_client == null) await _persist();
    _recordLocalAudit('Crear usuario', 'usuarios', id);
    _publish();
  }

  Future<void> updateStaffMember({
    required StaffMember member,
    required String name,
    required String email,
    required StaffRole role,
    String? documentId,
    String? personalEmail,
    String? phone,
    String? address,
    String? department,
    String? employmentStatus,
  }) async {
    final currentRole = this.role ?? StaffRole.waiter;
    if (staffRank(currentRole) < staffRank(member.role)) {
      throw StateError(
        'No tienes permisos para modificar a un usuario de mayor rango (${member.role.label}).',
      );
    }
    if (member.role == StaffRole.manager && currentRole != StaffRole.manager) {
      throw StateError(
        'Solo un Gerente puede gestionar la cuenta de otro Gerente.',
      );
    }
    final nextStatus = employmentStatus ?? member.employmentStatus;
    final profile = member.copyWith(
      name: name.trim(),
      email: email.trim().toLowerCase(),
      role: role,
      active: employmentStatus == null
          ? member.active
          : nextStatus != 'INACTIVO',
      employmentStatus: nextStatus,
      documentId: documentId?.trim() ?? member.documentId,
      personalEmail: personalEmail?.trim() ?? member.personalEmail,
      phone: phone?.trim() ?? member.phone,
      address: address?.trim() ?? member.address,
      department: department?.trim() ?? member.department,
    );
    if (profile.name.isEmpty) {
      throw StateError('Indica el nombre completo.');
    }
    if (profile.personalEmail.isNotEmpty &&
        !RegExp(
          r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
        ).hasMatch(profile.personalEmail)) {
      throw StateError('Indica un correo personal válido.');
    }

    final client = _client;
    final sessionVersion = _sessionVersion;
    if (client == null) {
      final index = staff.indexWhere((item) => item.id == member.id);
      if (index < 0) throw StateError('No se encontró el usuario.');
      staff[index] = profile;
      await _persist();
    } else if (profile.email == member.email.trim().toLowerCase() &&
        profile.role == member.role &&
        profile.employmentStatus == member.employmentStatus) {
      final changes = <String, String>{
        if (profile.name != member.name) 'nombre_completo': profile.name,
        if (profile.documentId != member.documentId)
          'documento_identidad': profile.documentId,
        if (profile.personalEmail != member.personalEmail)
          'correo_personal': profile.personalEmail,
        if (profile.phone != member.phone) 'telefono': profile.phone,
        if (profile.address != member.address) 'direccion': profile.address,
        if (profile.department != member.department)
          'departamento': profile.department,
      };
      if (changes.isEmpty) return;
      final updated = await client
          .from('usuarios')
          .update(changes)
          .eq('id', member.id)
          .eq('rol', member.role.databaseValue)
          .select('id')
          .maybeSingle();
      if (updated == null) {
        throw StateError(
          'No se pudo guardar el perfil con tus permisos actuales.',
        );
      }
      await _refreshAfterWrite(sessionVersion);
    } else {
      try {
        final result = await client.functions.invoke(
          'manage-staff',
          body: {
            'action': 'update',
            'id': member.id,
            'name': profile.name,
            'email': profile.email,
            'role': profile.role.databaseValue,
            'documentId': profile.documentId,
            'personalEmail': profile.personalEmail,
            'phone': profile.phone,
            'address': profile.address,
            'department': profile.department,
            'employmentStatus': profile.employmentStatus,
          },
        );
        _throwFunctionError(result, 'No se pudo actualizar la cuenta.');
      } on FunctionException catch (error) {
        if (error.status == 0 || error.status == 404) {
          throw StateError(
            'El servicio para cambiar el acceso no está disponible. Puedes guardar los datos personales conservando el correo de acceso, el rol y el estado actuales.',
          );
        }
        rethrow;
      }
      await _refreshAfterWrite(sessionVersion);
    }
    _publish();
  }

  StaffMember? get currentStaffMember =>
      staff.where((member) => member.id == userId).firstOrNull ??
      (isDemo
          ? staff.where((member) => member.role == role).firstOrNull
          : null);

  String get currentUserEmail =>
      _client?.auth.currentUser?.email ?? currentStaffMember?.email ?? '';

  String waiterDisplayLabel(RestaurantOrder? order) {
    if (order == null) return 'Mesero 1';
    final waiters = staff.where((s) => s.role == StaffRole.waiter).toList();
    if (order.waiterId != null) {
      final index = waiters.indexWhere((s) => s.id == order.waiterId);
      if (index >= 0) {
        final w = waiters[index];
        final num = index + 1;
        if (w.name.isEmpty ||
            w.name == 'Mesero' ||
            w.name.startsWith('Mesero $num')) {
          return 'Mesero $num';
        }
        return 'Mesero $num (${w.name})';
      }
    }
    final nameIndex = waiters.indexWhere((s) => s.name == order.waiterName);
    if (nameIndex >= 0) {
      final w = waiters[nameIndex];
      final num = nameIndex + 1;
      if (w.name.startsWith('Mesero $num')) return w.name;
      return 'Mesero $num (${w.name})';
    }
    if (order.waiterName.isNotEmpty && order.waiterName != 'Equipo Luxury') {
      return order.waiterName;
    }
    return 'Mesero 1';
  }

  String profilePhotoUrl(String path) {
    final client = _client;
    if (client == null || path.isEmpty) return '';
    return client.storage.from('employee-profiles').getPublicUrl(path);
  }

  bool get canEditOwnStaffProfile =>
      role == StaffRole.administrator ||
      role == StaffRole.manager ||
      role == StaffRole.headChef;

  Future<void> updateOwnStaffProfile({
    required String personalEmail,
    required String phone,
    required String address,
    required String department,
    String? photoPath,
  }) async {
    if (!canEditOwnStaffProfile) {
      throw StateError('Tu perfil es de solo lectura.');
    }
    if (personalEmail.isNotEmpty &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(personalEmail.trim())) {
      throw StateError('Indica un correo personal válido.');
    }
    if (_client != null) {
      await _client.rpc(
        'actualizar_perfil_propio',
        params: {
          'p_correo_personal': personalEmail.trim(),
          'p_telefono': phone.trim(),
          'p_direccion': address.trim(),
          'p_departamento': department.trim(),
          'p_foto_path': photoPath,
        },
      );
      await _loadRemoteData();
    } else {
      final member = currentStaffMember;
      if (member == null) throw StateError('No se encontró el perfil propio.');
      final index = staff.indexWhere((item) => item.id == member.id);
      staff[index] = member.copyWith(
        personalEmail: personalEmail.trim(),
        phone: phone.trim(),
        address: address.trim(),
        department: department.trim(),
        photoPath: photoPath,
      );
      await _persist();
    }
    _publish();
  }

  Future<void> uploadStaffPhoto({
    required StaffMember member,
    required Uint8List bytes,
    required String extension,
  }) async {
    if (member.id == userId && !canEditOwnStaffProfile) {
      throw StateError('Tu perfil es de solo lectura.');
    }
    final client = _client;
    if (client == null) {
      throw StateError('La carga de fotos requiere conexión con Supabase.');
    }
    if (bytes.isEmpty || bytes.length > 2 * 1024 * 1024) {
      throw StateError('La foto debe tener un tamaño máximo de 2 MB.');
    }
    final format = extension.toLowerCase();
    final contentType = switch (format) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => throw StateError('Usa una foto JPG, PNG o WebP.'),
    };
    final path = '${member.id}/perfil.$format';
    await client.storage
        .from('employee-profiles')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: contentType),
        );
    if (member.id == userId) {
      await updateOwnStaffProfile(
        personalEmail: member.personalEmail,
        phone: member.phone,
        address: member.address,
        department: member.department,
        photoPath: path,
      );
    } else {
      await client
          .from('usuarios')
          .update({'foto_path': path})
          .eq('id', member.id);
      await _loadRemoteData();
      _publish();
    }
  }

  Future<void> resetStaffPassword({
    required StaffMember member,
    required String password,
  }) async {
    if (role != StaffRole.administrator ||
        member.role == StaffRole.administrator ||
        member.role == StaffRole.manager) {
      throw StateError(
        'Solo Administración puede cambiar contraseñas del personal operativo.',
      );
    }
    final client = _client;
    if (client == null) {
      throw StateError('El cambio de contraseña requiere Supabase.');
    }
    if (password.trim().length < 8 || utf8.encode(password).length > 72) {
      throw StateError('Usa al menos 8 caracteres y hasta 72 bytes.');
    }
    final result = await client.functions.invoke(
      'manage-staff',
      body: {'action': 'reset_password', 'id': member.id, 'password': password},
    );
    final payload = result.data;
    if (payload is! Map || payload['id'] != member.id) {
      throw StateError('Supabase no confirmó el cambio de contraseña.');
    }
  }

  Future<void> changeOwnPassword(String password) async {
    final client = _client;
    if (client == null) {
      throw StateError('El cambio de contraseña requiere Supabase.');
    }
    if (password.trim().length < 8) {
      throw StateError('La contraseña debe tener al menos 8 caracteres.');
    }
    final currentUser = client.auth.currentUser;
    if (currentUser?.appMetadata['must_change_password'] == true) {
      final email = currentUser?.email;
      if (email == null) throw StateError('Vuelve a iniciar sesión.');
      final result = await client.functions.invoke(
        'manage-staff',
        body: {'action': 'complete_password_change', 'password': password},
      );
      _throwFunctionError(
        result,
        'No se pudo completar el cambio de contraseña.',
      );
      _passwordRecoveryPending = false;
      // Obtain a session with the updated password and account flag.
      await signIn(email, password);
      return;
    }
    await client.auth.updateUser(UserAttributes(password: password));
    mustChangePassword = false;
    _passwordRecoveryPending = false;
    _publish();
  }

  void _throwFunctionError(FunctionResponse result, String fallback) {
    if (result.status >= 400) {
      final body = result.data;
      final message = body is Map ? body['error'] : null;
      throw StateError(message is String ? message : fallback);
    }
  }

  Future<void> toggleStaff(StaffMember member) async {
    final currentRole = role ?? StaffRole.waiter;
    if (staffRank(currentRole) < staffRank(member.role)) {
      throw StateError(
        'No tienes permisos para cambiar el estado de un usuario de mayor rango (${member.role.label}).',
      );
    }
    if (member.role == StaffRole.manager && currentRole != StaffRole.manager) {
      throw StateError(
        'Solo un Gerente puede cambiar el estado de un Gerente.',
      );
    }
    if (member.role == StaffRole.administrator &&
        member.active &&
        staff
                .where(
                  (item) => item.role == StaffRole.administrator && item.active,
                )
                .length <
            2) {
      throw StateError('Debe quedar al menos un administrador activo.');
    }
    if (member.role == StaffRole.manager &&
        member.active &&
        staff
                .where((item) => item.role == StaffRole.manager && item.active)
                .length <
            2) {
      throw StateError('Debe quedar al menos un gerente activo.');
    }
    if (_client != null) {
      await _client
          .from('usuarios')
          .update({
            'activo': !member.active,
            'estado_laboral': member.active ? 'INACTIVO' : 'ACTIVO',
          })
          .eq('id', member.id);
      await _loadRemoteData();
    } else {
      final index = staff.indexWhere((item) => item.id == member.id);
      final active = !member.active;
      staff[index] = member.copyWith(
        active: active,
        employmentStatus: active ? 'ACTIVO' : 'INACTIVO',
      );
      await _persist();
    }
    _recordLocalAudit(
      member.active ? 'Desactivar usuario' : 'Activar usuario',
      'usuarios',
      member.id,
    );
    _publish();
  }
}
