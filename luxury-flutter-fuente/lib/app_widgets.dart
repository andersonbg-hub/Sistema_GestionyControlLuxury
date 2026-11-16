import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

const luxuryBrown = Color(0xFF2A0F0D);
const luxuryGold = Color(0xFFE48424);
const luxuryRed = Color(0xFFC81D25);
const luxuryGreen = Color(0xFF7FB519);
const luxuryBone = Color(0xFFF5F0EB);
const luxuryInk = Color(0xFF1D1E23);
const luxuryMuted = Color(0xFF77716D);
const luxuryBorder = Color(0xFFE9E1DA);

const luxuryPaletteRed = Color(0xFFF20530);
const luxuryPaletteGreen = Color(0xFF93D92B);
const luxuryPaletteGold = Color(0xFFF2BD1D);
const luxuryPaletteOrange = Color(0xFFF28907);
const luxuryPaletteDark = Color(0xFF261603);
const luxuryPaletteGreenText = Color(0xFF527A18);

class LuxuryMenuEntry {
  const LuxuryMenuEntry({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

class LuxurySideMenu extends StatelessWidget {
  const LuxurySideMenu({
    super.key,
    required this.entries,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.userName,
    required this.userRole,
    this.onProfileTap,
    this.sectionBreakIndices = const {},
  });

  final List<LuxuryMenuEntry> entries;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final String userName;
  final String userRole;
  final VoidCallback? onProfileTap;
  final Set<int> sectionBreakIndices;

  static const _background = Color(0xFF382217);
  static const _headerBackground = Color(0xFF2D1A11);
  static const _mutedText = Color(0xFFE4C9B0);

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 258,
    child: Material(
      color: _background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 100,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: const BoxDecoration(
              color: _headerBackground,
              border: Border(bottom: BorderSide(color: Color(0xFF65402B))),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF130D09),
                    shape: BoxShape.circle,
                    border: Border.all(color: luxuryGold, width: 2),
                  ),
                  child: const Icon(
                    Icons.restaurant_menu,
                    color: luxuryGold,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'LUXURY',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .5,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'RESTAURANTE ORIENTAL',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Color(0xFFF2A447),
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: .7,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 16, 16, 8),
            child: Text(
              'MENÚ PRINCIPAL',
              style: TextStyle(
                color: _mutedText,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                final selected = selectedIndex == index;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (sectionBreakIndices.contains(index))
                      const Padding(
                        padding: EdgeInsets.fromLTRB(0, 8, 0, 8),
                        child: Divider(color: Color(0xFF65402B), height: 1),
                      ),
                    Semantics(
                      button: true,
                      selected: selected,
                      child: InkWell(
                        key: ValueKey('luxury-side-menu-$index'),
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => onDestinationSelected(index),
                        child: SizedBox(
                          height: 44,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                Icon(
                                  entry.icon,
                                  size: 20,
                                  color: selected
                                      ? const Color(0xFFFFC46B)
                                      : _mutedText,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    entry.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: selected ? 1 : .9,
                                      ),
                                      fontSize: 13,
                                      fontWeight: selected
                                          ? FontWeight.w800
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (onProfileTap != null)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFF65402B))),
              ),
              child: Material(
                color: const Color(0xFF654033),
                borderRadius: BorderRadius.circular(15),
                child: InkWell(
                  key: const ValueKey('luxury-side-menu-profile'),
                  onTap: onProfileTap,
                  borderRadius: BorderRadius.circular(15),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 15,
                          backgroundColor: const Color(0xFF44362B),
                          child: Text(
                            userName.trim().isEmpty
                                ? 'L'
                                : userName.trim()[0].toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                userName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                userRole,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _mutedText,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: _mutedText,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

String money(num value) => 'S/ ${value.toStringAsFixed(2)}';

String formatErrorMessage(Object? error) {
  if (error == null) return '';
  if (error is TimeoutException ||
      error is ClientException ||
      error is AuthRetryableFetchException) {
    return 'La conexión no respondió a tiempo. Revisa la red y vuelve a intentarlo.';
  }
  if (error is FunctionException && error.status == 404) {
    return 'Falta publicar la función de cuentas en Supabase.';
  }
  if (error is AuthException) {
    final msg = error.message.toLowerCase();
    final code = error.code?.toLowerCase() ?? '';
    if (code == 'invalid_credentials' ||
        msg.contains('invalid login credentials') ||
        msg.contains('invalid_credentials')) {
      return 'Correo o contraseña incorrectos.';
    }
    if (code == 'email_not_confirmed' || msg.contains('email not confirmed')) {
      return 'El correo no ha sido confirmado. Revisa tu bandeja de entrada.';
    }
    if (code == 'user_not_found' || msg.contains('user not found')) {
      return 'No existe una cuenta registrada con este correo.';
    }
    if (code == 'over_request_rate_limit' ||
        error.statusCode == '429' ||
        msg.contains('rate limit')) {
      return 'Demasiados intentos fallidos. Inténtalo de nuevo en unos minutos.';
    }
    if (code == 'same_password' || msg.contains('same password')) {
      return 'La nueva contraseña no puede ser igual a la anterior.';
    }
    if (error.message.trim().isNotEmpty) {
      return error.message;
    }
  }
  if (error is PostgrestException) {
    if (error.code == 'PGRST116') {
      return 'No se encontró el registro solicitado o no tienes permiso.';
    }
    if (error.message.trim().isNotEmpty) {
      return error.message;
    }
  }
  if (error is StateError) {
    return error.message;
  }
  final str = error.toString();
  if (str.contains('invalid_credentials') ||
      str.contains('Invalid login credentials')) {
    return 'Correo o contraseña incorrectos.';
  }
  if (str.contains('Email not confirmed') ||
      str.contains('email_not_confirmed')) {
    return 'El correo no ha sido confirmado. Revisa tu bandeja de entrada.';
  }
  if (str.startsWith('Exception: ')) {
    return str.substring(11);
  }
  if (str.startsWith('StateError: ')) {
    return str.substring(12);
  }
  final match = RegExp(r'message:\s*([^,]+)').firstMatch(str);
  if (match != null) {
    final extracted = match.group(1)?.trim();
    if (extracted != null && extracted.isNotEmpty) {
      if (extracted.toLowerCase().contains('invalid login credentials')) {
        return 'Correo o contraseña incorrectos.';
      }
      return extracted;
    }
  }
  return str;
}

Color statusColor(String status) => switch (status) {
  'DISPONIBLE' || 'LISTO' || 'PAGADO' || 'ATENDIDO' => luxuryPaletteGreen,
  'POR_COBRAR' || 'CANCELADO' => luxuryPaletteRed,
  _ => luxuryPaletteOrange,
};

Color orderColor(OrderStatus status) => statusColor(status.databaseValue);

Future<void> showResultDialog(
  BuildContext context, {
  required String message,
  required bool success,
  String? title,
  String actionLabel = 'Continuar',
}) => showDialog<void>(
  context: context,
  barrierColor: const Color(0xB317181D),
  builder: (context) => Dialog(
    backgroundColor: Colors.transparent,
    elevation: 0,
    child: Container(
      width: 340,
      padding: const EdgeInsets.fromLTRB(28, 30, 28, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33404B48),
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (success ? luxuryGreen : luxuryRed).withValues(alpha: .14),
            ),
            child: Icon(
              success ? Icons.check_rounded : Icons.priority_high_rounded,
              color: success ? luxuryGreen : luxuryRed,
              size: 42,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            title ?? (success ? '¡Listo!' : 'No se pudo completar'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.black54,
              height: 1.45,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 22),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: success ? luxuryGreen : luxuryRed,
              side: BorderSide(
                color: (success ? luxuryGreen : luxuryRed).withValues(
                  alpha: .55,
                ),
              ),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            ),
            child: Text(actionLabel),
          ),
        ],
      ),
    ),
  ),
);

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String actionLabel,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Volver'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(actionLabel),
            ),
          ],
        ),
      ) ??
      false;
}

class OperationLabel extends StatelessWidget {
  const OperationLabel({super.key, required this.label, this.loading = false});

  final String label;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (!loading) return Text(label);
    return Semantics(
      liveRegion: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(
              color: DefaultTextStyle.of(context).style.color,
              strokeWidth: 2,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(child: Text(label)),
        ],
      ),
    );
  }
}

Future<T> showBlockingProgress<T>(
  BuildContext context, {
  required String label,
  required Future<T> Function() action,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black54,
    requestFocus: true,
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
    builder: (context) => PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 368),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 26),
            child: Semantics(
              liveRegion: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  const Text('Espera un momento.', textAlign: TextAlign.center),
                  const SizedBox(height: 18),
                  const LinearProgressIndicator(
                    color: luxuryGold,
                    backgroundColor: Color(0xFFF0E2D3),
                    minHeight: 5,
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  unawaited(navigator.push(route));
  try {
    return await action();
  } finally {
    if (navigator.mounted && route.isActive) navigator.removeRoute(route);
  }
}

mixin OperationProgress<T extends StatefulWidget> on State<T> {
  bool _operationPending = false;
  bool get operationPending => _operationPending;

  Future<bool> runOperation(
    Future<void> Function() action, {
    String label = 'Procesando…',
  }) async {
    if (operationPending || !mounted) return false;
    _operationPending = true;
    try {
      await showBlockingProgress(context, label: label, action: action);
      return true;
    } catch (error) {
      if (mounted) {
        await showResultDialog(
          context,
          success: false,
          message: formatErrorMessage(error),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _operationPending = false);
    }
  }
}

class SectionTransition extends StatelessWidget {
  const SectionTransition({
    super.key,
    required this.section,
    required this.child,
  });

  final Object section;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      key: ValueKey(section),
      tween: Tween(begin: .65, end: 1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      builder: (context, progress, child) => Opacity(
        opacity: progress,
        child: Transform.translate(
          offset: Offset(0, (1 - progress) * 8),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  factory StatusBadge.order(OrderStatus status) =>
      StatusBadge(label: status.label, color: orderColor(status));

  factory StatusBadge.table(TableStatus status) => StatusBadge(
    label: status.label,
    color: statusColor(status.databaseValue),
  );

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: .13),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: .18)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Text(
        label,
        style: TextStyle(
          color: color == luxuryPaletteGreen ? luxuryPaletteGreenText : color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final heading = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 4,
              height: 34,
              margin: const EdgeInsets.only(top: 3, right: 12),
              decoration: BoxDecoration(
                color: luxuryPaletteGold,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontFamily: 'Georgia',
                      fontSize: 26,
                      letterSpacing: -.45,
                    ),
                  ),
                  if (subtitle case final value?) ...[
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: luxuryMuted),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
        if (trailing == null) return heading;
        if (constraints.maxWidth < 760 && trailing is! IconButton) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [heading, const SizedBox(height: 14), trailing!],
          );
        }
        return Row(
          children: [
            Expanded(child: heading),
            const SizedBox(width: 20),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth * .5),
              child: trailing!,
            ),
          ],
        );
      },
    ),
  );
}

/// Gives record details their own row before the actions on smaller screens.
class ResponsiveListTile extends StatelessWidget {
  const ResponsiveListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.dense = false,
    this.isThreeLine = false,
    this.contentPadding,
    this.onTap,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final bool dense;
  final bool isThreeLine;
  final EdgeInsetsGeometry? contentPadding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth >= 760 || trailing == null) {
        return ListTile(
          title: title,
          subtitle: subtitle,
          leading: leading,
          trailing: trailing == null
              ? null
              : ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * .5,
                  ),
                  child: trailing,
                ),
          dense: dense,
          isThreeLine: isThreeLine,
          contentPadding: contentPadding,
          onTap: onTap,
        );
      }
      final theme = Theme.of(context).textTheme;
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: contentPadding ?? EdgeInsets.all(dense ? 12 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 12)],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DefaultTextStyle(
                          style: theme.titleMedium!,
                          child: title,
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 4),
                          DefaultTextStyle(
                            style: theme.bodyMedium!.copyWith(
                              color: Colors.black54,
                            ),
                            child: subtitle!,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DefaultTextStyle(style: theme.bodyMedium!, child: trailing!),
            ],
          ),
        ),
      );
    },
  );
}

/// Natural card heights keep statistics readable with enlarged text as well.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children, this.maxColumns = 4});
  final List<Widget> children;
  final int maxColumns;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = ((constraints.maxWidth + 12) / 272).floor().clamp(
        1,
        maxColumns,
      );
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color = luxuryBrown,
    this.caption,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? caption;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: (color == luxuryBrown ? luxuryPaletteOrange : color)
                  .withValues(alpha: .14),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              icon,
              color: color == luxuryBrown ? luxuryPaletteOrange : color,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (caption != null)
                  Text(caption!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
  });

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: Colors.black38),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          ),
        ],
      ),
    ),
  );
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: luxuryPaletteRed.withValues(alpha: .08),
      border: Border.all(color: luxuryPaletteRed.withValues(alpha: .18)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(message, style: const TextStyle(color: luxuryPaletteRed)),
  );
}

class LoginFieldError extends StatelessWidget {
  const LoginFieldError({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 7),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF1F2),
      border: Border.all(color: const Color(0xFFFFD6DC)),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Text(
      message,
      style: const TextStyle(
        color: Color(0xFFCF334B),
        fontSize: 12,
        height: 1.35,
      ),
    ),
  );
}
