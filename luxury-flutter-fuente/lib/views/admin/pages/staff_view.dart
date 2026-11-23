part of '../dashboard_screen.dart';

extension _AdminStaffView on _AdminScreenState {
  Widget _staffPage() {
    final members = store.staff
        .where(
          (member) => '${member.name} ${member.email} ${member.role.label}'
              .toLowerCase()
              .contains(query),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          title: 'Usuarios y roles',
          subtitle: store.isDemo
              ? 'Personal de la demostración'
              : 'Perfiles activos de Supabase Auth',
        ),
        if (!managerOnly)
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _editStaff,
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Nuevo usuario'),
            ),
          ),
        const SizedBox(height: 12),
        _searchField(),
        const SizedBox(height: 12),
        if (members.isEmpty)
          const EmptyState(message: 'No se encontraron usuarios.')
        else
          ...members.map(
            (member) => Card(
              child: ResponsiveListTile(
                leading: _staffAvatar(member),
                title: Text(member.name),
                subtitle: Text(member.email),
                trailing: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Chip(label: Text(member.role.label)),
                    if (!managerOnly &&
                        member.role != StaffRole.manager &&
                        (member.role != StaffRole.administrator ||
                            member.id == store.userId))
                      IconButton(
                        tooltip: 'Editar usuario',
                        onPressed: () => _editStaff(member),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    if (!managerOnly &&
                        store.isConnected &&
                        member.role != StaffRole.administrator &&
                        member.role != StaffRole.manager)
                      IconButton(
                        tooltip: 'Cambiar contraseña',
                        onPressed: () => _resetStaffPassword(member),
                        icon: const Icon(Icons.lock_reset),
                      ),
                    Switch(
                      value: member.active,
                      onChanged: managerOnly
                          ? null
                          : (value) => _toggleStaff(member),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _staffAvatar(StaffMember member) {
    final photoUrl = store.profilePhotoUrl(member.photoPath);
    return CircleAvatar(
      radius: 25,
      backgroundColor: luxuryGold.withValues(alpha: .18),
      foregroundImage: photoUrl.isEmpty ? null : NetworkImage(photoUrl),
      onForegroundImageError: photoUrl.isEmpty ? null : (_, _) {},
      child: Text(
        member.name.isEmpty ? '?' : member.name[0].toUpperCase(),
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}
