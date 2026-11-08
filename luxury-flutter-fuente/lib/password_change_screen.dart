import 'dart:async';

import 'package:flutter/material.dart';

import 'app_widgets.dart';
import 'store.dart';

Future<void> showPasswordChangeDialog(
  BuildContext context,
  RestaurantStore store,
) async {
  final password = TextEditingController();
  final confirmation = TextEditingController();
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Cambiar contraseña'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Nueva contraseña (mínimo 8 caracteres)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmation,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirmar contraseña',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () async {
            if (password.text.length < 8 ||
                password.text != confirmation.text) {
              await showResultDialog(
                context,
                success: false,
                message:
                    'Verifica que ambas contraseñas coincidan y tengan al menos 8 caracteres.',
              );
              return;
            }
            Navigator.pop(context, true);
          },
          child: const Text('Guardar contraseña'),
        ),
      ],
    ),
  );
  if (result == true) {
    try {
      await store.changeOwnPassword(password.text);
      if (context.mounted) {
        await showResultDialog(
          context,
          success: true,
          message: 'Contraseña actualizada.',
        );
      }
    } catch (error) {
      if (context.mounted) {
        await showResultDialog(context, success: false, message: '$error');
      }
    }
  }
  password.dispose();
  confirmation.dispose();
}

class PasswordChangeScreen extends StatefulWidget {
  const PasswordChangeScreen({
    super.key,
    required this.store,
    required this.requiredChange,
  });

  final RestaurantStore store;
  final bool requiredChange;

  @override
  State<PasswordChangeScreen> createState() => _PasswordChangeScreenState();
}

class _PasswordChangeScreenState extends State<PasswordChangeScreen> {
  final password = TextEditingController();
  final confirmation = TextEditingController();
  bool busy = false;

  @override
  void dispose() {
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (password.text.length < 8 || password.text != confirmation.text) {
      await showResultDialog(
        context,
        success: false,
        message:
            'Verifica que ambas contraseñas coincidan y tengan al menos 8 caracteres.',
      );
      return;
    }
    setState(() => busy = true);
    try {
      await widget.store.changeOwnPassword(password.text);
      if (mounted) {
        await showResultDialog(
          context,
          success: true,
          message: 'Contraseña actualizada.',
        );
      }
    } catch (exception) {
      if (mounted) {
        await showResultDialog(context, success: false, message: '$exception');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Cambiar contraseña'),
      actions: [
        TextButton(
          onPressed: busy ? null : () => unawaited(widget.store.signOut()),
          child: const Text('Cerrar sesión'),
        ),
      ],
    ),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.requiredChange
                    ? 'Crea una contraseña personal para continuar.'
                    : 'Actualiza la contraseña de tu cuenta.',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 20),
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Nueva contraseña (mínimo 8 caracteres)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmation,
                obscureText: true,
                onSubmitted: (_) => _save(),
                decoration: const InputDecoration(
                  labelText: 'Confirmar contraseña',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: busy ? null : _save,
                child: Text(busy ? 'Guardando…' : 'Guardar contraseña'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
