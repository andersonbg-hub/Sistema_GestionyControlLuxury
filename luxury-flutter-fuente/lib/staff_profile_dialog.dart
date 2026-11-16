import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'app_widgets.dart';
import 'models.dart';
import 'store.dart';

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
  await showDialog<void>(
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
    child: photoUrl.isNotEmpty
        ? null
        : Text(
            name.isEmpty ? '?' : name[0].toUpperCase(),
            style: TextStyle(
              fontSize: radius * .8,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF593D26),
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
    final photoUrl = widget.store.profilePhotoUrl(photoPath);
    return AlertDialog(
      title: const Text('Mi perfil'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 42,
                      backgroundColor: const Color(0xFFE9D9BD),
                      foregroundImage: photoUrl.isEmpty
                          ? null
                          : NetworkImage(photoUrl),
                      child: photoUrl.isNotEmpty
                          ? null
                          : Text(
                              member.name.isEmpty
                                  ? '?'
                                  : member.name.trim()[0].toUpperCase(),
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF593D26),
                              ),
                            ),
                    ),
                    TextButton.icon(
                      onPressed: busy || widget.store.isDemo
                          ? null
                          : _selectPhoto,
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Cambiar fotografía'),
                    ),
                  ],
                ),
              ),
              if (widget.store.isDemo)
                const Text(
                  'La carga de fotografías requiere una cuenta conectada a Supabase.',
                  style: TextStyle(color: Colors.black54),
                ),
              const SizedBox(height: 8),
              ResponsiveListTile(
                title: Text(member.name),
                subtitle: Text(
                  '${member.role.label} · ${staffEmploymentLabel(member.employmentStatus)}',
                ),
              ),
              _readOnly('Código de empleado', member.employeeCode),
              _readOnly('Documento de identidad', member.documentId),
              _readOnly('Correo de acceso', member.email),
              const SizedBox(height: 12),
              TextField(
                controller: personalEmail,
                enabled: !busy,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Correo personal'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phone,
                enabled: !busy,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Teléfono'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: address,
                enabled: !busy,
                decoration: const InputDecoration(labelText: 'Dirección'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: department,
                enabled: !busy,
                decoration: const InputDecoration(labelText: 'Área de trabajo'),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!, style: const TextStyle(color: Colors.red)),
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

  Widget _readOnly(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text.rich(
      TextSpan(
        text: '$label  ',
        style: const TextStyle(fontWeight: FontWeight.w700),
        children: [
          TextSpan(
            text: value.isEmpty ? 'Sin registrar' : value,
            style: const TextStyle(fontWeight: FontWeight.normal),
          ),
        ],
      ),
    ),
  );
}
