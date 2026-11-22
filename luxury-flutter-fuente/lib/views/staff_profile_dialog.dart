import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_widgets.dart';
import '../data/restaurant_store.dart';
import '../models/models.dart';

Future<void> showOwnStaffProfile(
  BuildContext context,
  RestaurantStore store,
) async {
  final member = store.currentStaffMember;
  if (member == null) {
    await showResultDialog(
      context,
      success: false,
      message: 'No se encontró el perfil de este usuario.',
    );
    return;
  }
  await showLuxuryDialog<void>(
    context: context,
    builder: (context) => _OwnStaffProfileDialog(store: store, member: member),
  );
}

String staffEmploymentLabel(String value) => switch (value) {
  'VACACIONES' => 'De vacaciones',
  'LICENCIA' => 'Con licencia',
  'INACTIVO' => 'Inactivo',
  _ => 'Activo',
};

Widget staffProfileAvatar(
  RestaurantStore store,
  StaffMember member, {
  double radius = 30,
}) {
  final photoUrl = store.profilePhotoUrl(member.photoPath);
  final name = member.name.trim();
  return CircleAvatar(
    radius: radius,
    backgroundColor: const Color(0xFFE9D9BD),
    foregroundImage: photoUrl.isEmpty ? null : NetworkImage(photoUrl),
    onForegroundImageError: photoUrl.isEmpty ? null : (_, _) {},
    child: Text(
      name.isEmpty ? '?' : name.characters.first.toUpperCase(),
      style: TextStyle(
        fontSize: radius * .8,
        fontWeight: FontWeight.w800,
        color: luxuryBrown,
      ),
    ),
  );
}

class _OwnStaffProfileDialog extends StatefulWidget {
  const _OwnStaffProfileDialog({required this.store, required this.member});

  final RestaurantStore store;
  final StaffMember member;

  @override
  State<_OwnStaffProfileDialog> createState() => _OwnStaffProfileDialogState();
}

class _OwnStaffProfileDialogState extends State<_OwnStaffProfileDialog> {
  late final TextEditingController personalEmail;
  late final TextEditingController phone;
  late final TextEditingController address;
  late final TextEditingController department;
  late String photoPath;
  String? error;
  String? progress;
  bool get busy => progress != null;

  @override
  void initState() {
    super.initState();
    personalEmail = TextEditingController(text: widget.member.personalEmail);
    phone = TextEditingController(text: widget.member.phone);
    address = TextEditingController(text: widget.member.address);
    department = TextEditingController(text: widget.member.department);
    photoPath = widget.member.photoPath;
  }

  @override
  void dispose() {
    personalEmail.dispose();
    phone.dispose();
    address.dispose();
    department.dispose();
    super.dispose();
  }

  Future<void> _selectPhoto() async {
    if (busy) return;
    setState(() {
      progress = 'Subiendo foto…';
      error = null;
    });
    try {
      final photo = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        imageQuality: 85,
      );
      if (!mounted || photo == null) return;
      final dot = photo.name.lastIndexOf('.');
      final extension = dot < 0 ? '' : photo.name.substring(dot + 1);
      await showBlockingProgress(
        context,
        label: 'Subiendo foto…',
        action: () async {
          await widget.store.uploadStaffPhoto(
            member: widget.member,
            bytes: await photo.readAsBytes(),
            extension: extension,
          );
        },
      );
      if (mounted) {
        setState(
          () => photoPath =
              widget.store.currentStaffMember?.photoPath ??
              widget.member.photoPath,
        );
      }
    } catch (exception) {
      if (mounted) setState(() => error = formatErrorMessage(exception));
    } finally {
      if (mounted) setState(() => progress = null);
    }
  }

  Future<void> _save() async {
    if (busy) return;
    setState(() {
      progress = 'Guardando perfil…';
      error = null;
    });
    try {
      await showBlockingProgress(
        context,
        label: 'Guardando perfil…',
        action: () => widget.store.updateOwnStaffProfile(
          personalEmail: personalEmail.text,
          phone: phone.text,
          address: address.text,
          department: department.text,
          photoPath: photoPath,
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (exception) {
      if (mounted) {
        setState(() {
          error = formatErrorMessage(exception);
          progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final member = widget.member;
    final canEdit = widget.store.canEditOwnStaffProfile;
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Mi perfil'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LuxuryReveal(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFCF6EB), luxuryBone],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: luxuryBorder),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            AnimatedSwitcher(
                              duration: luxuryDuration(context, 240),
                              child: KeyedSubtree(
                                key: ValueKey(photoPath),
                                child: staffProfileAvatar(
                                  widget.store,
                                  member.copyWith(photoPath: photoPath),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    member.name,
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    member.role.label,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        StatusBadge(
                          label: staffEmploymentLabel(member.employmentStatus),
                          color: member.employmentStatus == 'ACTIVO'
                              ? luxuryPaletteGreenText
                              : luxuryMuted,
                        ),
                        if (canEdit && !widget.store.isDemo)
                          TextButton.icon(
                            onPressed: busy ? null : _selectPhoto,
                            icon: const Icon(
                              Icons.photo_camera_outlined,
                              size: 18,
                            ),
                            label: const Text('Cambiar fotografía'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (canEdit && widget.store.isDemo)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'La carga de fotografías requiere una cuenta conectada a Supabase.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 16),
              LuxuryReveal(
                index: 1,
                child: _profileSection('Identificación', [
                  _readOnly('Código de empleado', member.employeeCode),
                  _readOnly('Documento de identidad', member.documentId),
                  _readOnly('Correo de acceso', member.email),
                ]),
              ),
              const SizedBox(height: 12),
              LuxuryReveal(
                index: 2,
                child: _profileSection('Contacto y área', [
                  if (!canEdit) ...[
                    _readOnly('Correo personal', member.personalEmail),
                    _readOnly('Teléfono', member.phone),
                    _readOnly('Dirección', member.address),
                    _readOnly('Área de trabajo', member.department),
                  ] else ...[
                    TextField(
                      controller: personalEmail,
                      enabled: !busy,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Correo personal',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: phone,
                      enabled: !busy,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Teléfono'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: address,
                      enabled: !busy,
                      decoration: const InputDecoration(labelText: 'Dirección'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: department,
                      enabled: !busy,
                      decoration: const InputDecoration(
                        labelText: 'Área de trabajo',
                      ),
                    ),
                  ],
                ]),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
        if (canEdit)
          FilledButton(
            onPressed: busy ? null : _save,
            child: OperationLabel(
              label: progress ?? 'Guardar perfil',
              loading: busy,
            ),
          ),
      ],
    );
  }

  Widget _profileSection(String title, List<Widget> children) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      border: Border.all(color: luxuryBorder),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 10),
        ...children,
      ],
    ),
  );

  Widget _readOnly(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(
          value.isEmpty ? 'Sin registrar' : value,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}
